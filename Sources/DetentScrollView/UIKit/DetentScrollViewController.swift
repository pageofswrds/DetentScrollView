//
//  DetentScrollViewController.swift
//  DetentScrollView
//
//  UIKit-based detent scroll view controller.
//  Provides immediate visual feedback during gestures by updating view transforms directly.
//

import UIKit
import SwiftUI
import QuartzCore
import Mercurial

// MARK: - Section Height Anchor

/// Specifies how scroll position should be preserved when section heights change.
public enum SectionHeightAnchor {
    /// Anchor to the top of the current section.
    /// Content changes cause the view to grow/shrink downward.
    /// Use for: tab switching, expanding/collapsing content in place.
    case sectionTop

    /// Preserve the currently visible content by adjusting for insertions/removals.
    /// - Parameter insertedAbove: Height added (positive) or removed (negative) above the current scroll position.
    /// Use for: adding/removing cards above current view, dynamic content loading.
    case preserveVisibleContent(insertedAbove: CGFloat)
}

/// Core UIKit implementation of detent scrolling.
///
/// This view controller hosts SwiftUI content via UIHostingController and handles
/// scroll gestures with UIKit's UIPanGestureRecognizer. This approach provides
/// immediate visual feedback during drag (unlike SwiftUI DragGesture which can
/// have update delays when nested with other gesture recognizers).
@MainActor
public class DetentScrollViewController: UIViewController {

    // MARK: - Configuration

    /// Height of each section in points.
    public var sectionHeights: [CGFloat] = [] {
        didSet { updateSectionOffsets() }
    }

    /// How far from viewport top each section starts when snapped.
    public var sectionSnapInsets: [CGFloat] = []

    /// Configuration for threshold and resistance behavior.
    public var configuration: DetentScrollConfiguration = .default

    /// External signal to disable scrolling (e.g., when content is zoomed).
    public var isScrollDisabled: Bool = false

    // MARK: - State

    /// Current section index.
    public private(set) var currentSection: Int = 0

    /// Internal scroll offset within the current section.
    private var internalOffset: CGFloat = 0

    /// Raw drag offset (before rubber-band is applied).
    private var rawDragOffset: CGFloat = 0

    /// Whether a drag gesture is currently active.
    private var isDragging: Bool = false

    /// Last pan translation for computing deltas.
    private var lastPanTranslation: CGFloat = 0

    /// Cached section start offsets.
    private var cachedSectionOffsets: [CGFloat] = []

    // MARK: - Momentum State

    /// Display link for momentum animation.
    private var displayLink: CADisplayLink?

    /// Current momentum velocity for internalOffset.
    private var momentumVelocity: CGFloat = 0

    /// Current spring velocity for rawDragOffset snap-back.
    /// This is integrated into the momentum display link to avoid conflicts
    /// between UIView animations and display link frame updates.
    private var snapBackVelocity: CGFloat = 0

    /// Whether a section transition animation is in progress.
    private var isSectionAnimating: Bool = false

    /// Property animator for section transitions (supports interruption).
    private var sectionAnimator: UIViewPropertyAnimator?

    /// Start state for section transition (for interpolation on interruption).
    private var sectionAnimationStartState: (section: Int, internalOffset: CGFloat, rawDragOffset: CGFloat, frameY: CGFloat)?

    /// End state for section transition.
    private var sectionAnimationEndState: (section: Int, internalOffset: CGFloat, frameY: CGFloat)?

    /// Whether any animation is active (momentum or section transition).
    public var isAnimating: Bool {
        displayLink != nil || isSectionAnimating || sectionAnimator?.isRunning == true || progressDisplayLink != nil
    }

    /// Last momentum update timestamp.
    private var lastMomentumTime: CFTimeInterval = 0

    // MARK: - Progress Animation State

    /// Display link for animating scroll progress during snap-back.
    private var progressDisplayLink: CADisplayLink?

    /// Start time for progress animation.
    private var progressAnimationStartTime: CFTimeInterval = 0

    /// Starting progress value for animation.
    private var progressAnimationStartValue: CGFloat = 0

    /// Target progress value for animation.
    private var progressAnimationEndValue: CGFloat = 0

    /// Duration of progress animation.
    private var progressAnimationDuration: CFTimeInterval = 0.3

    // MARK: - Callbacks

    /// Called when current section changes.
    public var onSectionChanged: ((Int) -> Void)?

    /// Called during drag to report transition progress (0.0 = section 0, 1.0 = section 1+).
    /// This enables scroll-driven animations like collapsing headers.
    public var onScrollProgress: ((CGFloat) -> Void)?

    // MARK: - Views

    /// Container view that gets transformed for scrolling.
    private var contentContainerView: UIView!

    /// Hosting controller for SwiftUI content.
    private var hostingController: UIHostingController<AnyView>?

    /// Scroll bar indicator view.
    private var scrollBarView: UIView!

    /// Task for hiding scroll bar after delay.
    private var scrollBarHideTask: Task<Void, Never>?

    // MARK: - Gestures

    /// Pan gesture recognizer for scrolling.
    private var panGesture: UIPanGestureRecognizer!

    /// Touch-down gesture to stop momentum immediately when finger contacts screen.
    private var touchDownGesture: UILongPressGestureRecognizer!

    // MARK: - External Drag State

    /// Whether an external drag (injected from SwiftUI child) is active.
    private var isExternalDragActive: Bool = false

    /// Last translation for external drag delta calculation.
    private var lastExternalTranslation: CGFloat = 0

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        setupGestures()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Clean up scroll bar state when view disappears (e.g., switching tabs)
        scrollBarHideTask?.cancel()
        scrollBarHideTask = nil
        scrollBarView.alpha = 0
        stopMomentum()
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear
        view.clipsToBounds = true

        // Content container - this view gets transformed
        contentContainerView = UIView()
        contentContainerView.backgroundColor = .clear
        view.addSubview(contentContainerView)

        // Scroll bar
        scrollBarView = UIView()
        scrollBarView.backgroundColor = UIColor.label.withAlphaComponent(0.4)
        scrollBarView.layer.cornerRadius = 2
        scrollBarView.alpha = 0
        view.addSubview(scrollBarView)
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.delaysTouchesBegan = false
        panGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(panGesture)

        // Touch-down gesture fires immediately when finger touches screen.
        // This stops momentum scrolling even before the pan gesture begins (which requires movement).
        touchDownGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTouchDown(_:)))
        touchDownGesture.minimumPressDuration = 0
        touchDownGesture.cancelsTouchesInView = false
        touchDownGesture.delegate = self
        view.addGestureRecognizer(touchDownGesture)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update content container size while preserving y position during drag
        let newWidth = view.bounds.width
        let newHeight = totalContentHeight
        var frame = contentContainerView.frame

        // Only update if size actually changed
        if frame.size.width != newWidth || frame.size.height != newHeight {
            frame.size.width = newWidth
            frame.size.height = newHeight
            frame.origin.x = 0  // Keep x at 0
            // Preserve y position - it's controlled by updateContentOffset
            contentContainerView.frame = frame
        }

        // Update hosting controller frame to match container bounds
        let hostingFrame = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
        if hostingController?.view.frame != hostingFrame {
            hostingController?.view.frame = hostingFrame
        }

        // Update scroll bar frame
        updateScrollBarFrame()

        // Apply current offset (this sets frame.origin.y)
        updateContentOffset()
    }

    // MARK: - Content

    /// Sets the SwiftUI content to display.
    ///
    /// - Parameter content: The SwiftUI view to embed.
    public func setContent<V: View>(_ content: V) {
        // Ensure view is loaded before setting content
        loadViewIfNeeded()

        // Wrap content to ignore safe area (prevents hosting controller safe area interference)
        let wrappedContent = AnyView(
            content
                .ignoresSafeArea()
        )

        // Update existing hosting controller if available (preserves @State in child views)
        if let existingHC = hostingController {
            existingHC.rootView = wrappedContent
            view.setNeedsLayout()
            return
        }

        // Create new hosting controller only if one doesn't exist
        let hc = UIHostingController(rootView: wrappedContent)
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = true
        hc.view.clipsToBounds = false  // Don't clip - we handle clipping at container level

        // Add as child
        addChild(hc)
        contentContainerView.addSubview(hc.view)
        hc.didMove(toParent: self)

        // Set initial frame immediately
        let contentSize = CGSize(width: view.bounds.width, height: totalContentHeight)
        hc.view.frame = CGRect(origin: .zero, size: contentSize)

        hostingController = hc

        // Trigger layout update
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    // MARK: - Section Geometry

    /// Pre-compute section offsets.
    private func updateSectionOffsets() {
        var offsets: [CGFloat] = [0]
        var cumulative: CGFloat = 0
        for height in sectionHeights.dropLast() {
            cumulative += height
            offsets.append(cumulative)
        }
        cachedSectionOffsets = offsets
    }

    /// Y offset for the start of each section.
    private var sectionOffsets: [CGFloat] {
        cachedSectionOffsets
    }

    /// Current section's starting offset.
    private var currentSectionOffset: CGFloat {
        guard currentSection < sectionOffsets.count else { return 0 }
        return sectionOffsets[currentSection]
    }

    /// Height of the current section.
    private var currentSectionHeight: CGFloat {
        guard currentSection < sectionHeights.count else { return 0 }
        return sectionHeights[currentSection]
    }

    /// Total height of all sections combined.
    private var totalContentHeight: CGFloat {
        sectionHeights.reduce(0, +)
    }

    /// Current section's snap inset.
    private var currentSnapInset: CGFloat {
        guard currentSection < sectionSnapInsets.count else { return 0 }
        return sectionSnapInsets[currentSection]
    }

    /// Snap inset for a specific section.
    private func snapInset(for section: Int) -> CGFloat {
        guard section < sectionSnapInsets.count else { return 0 }
        return sectionSnapInsets[section]
    }

    /// Maximum internal scroll for current section.
    private var maxInternalScroll: CGFloat {
        maxInternalScroll(for: currentSection)
    }

    /// Maximum internal scroll for a specific section.
    private func maxInternalScroll(for section: Int) -> CGFloat {
        guard section < sectionHeights.count else { return 0 }
        let inset = snapInset(for: section)
        return max(0, sectionHeights[section] - view.bounds.height + inset)
    }

    // MARK: - Scroll Position

    /// Whether scroll position is at the top of current section.
    private var isAtSectionTop: Bool {
        internalOffset <= 0
    }

    /// Whether scroll position is at the bottom of current section.
    private var isAtSectionBottom: Bool {
        internalOffset >= maxInternalScroll
    }

    /// Visual drag offset with rubber-band applied.
    private var dragOffset: CGFloat {
        Physics.rubberBand(
            offset: rawDragOffset,
            limit: configuration.threshold * 2,
            coefficient: configuration.resistanceCoefficient
        )
    }

    /// The visual offset applied to content.
    private var visualOffset: CGFloat {
        let baseOffset = -currentSectionOffset + currentSnapInset - internalOffset
        return baseOffset + dragOffset
    }

    // MARK: - Offset Updates

    /// Updates the content container's position to reflect current offset.
    private func updateContentOffset() {
        // Use frame.origin instead of transform - UIHostingController doesn't respond well to transforms
        contentContainerView.frame.origin.y = visualOffset
    }
}

// MARK: - Gesture Handling

extension DetentScrollViewController {

    @objc private func handleTouchDown(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard !isScrollDisabled else { return }

        // Stop momentum immediately when finger touches screen during scrolling.
        // This provides the expected "catch" behavior where touching stops deceleration.
        if displayLink != nil {
            stopMomentum()
            showScrollBar()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isScrollDisabled else { return }

        // If multi-touch detected, cancel scroll and let pinch handle it
        if gesture.numberOfTouches > 1 {
            if isDragging {
                handleDragCancelled()
            }
            return
        }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            handleDragBegan()

        case .changed:
            // Only handle primarily vertical drags
            let isVertical = abs(translation.y) > abs(translation.x)
            if isVertical {
                handleDragChanged(translation: translation.y)
            }

        case .ended:
            handleDragEnded(translation: translation.y, velocity: velocity.y)

        case .cancelled, .failed:
            handleDragCancelled()

        default:
            break
        }
    }

    private func handleDragBegan() {
        // Cancel any in-flight animations
        stopMomentum()
        stopProgressAnimation()

        // Handle UIViewPropertyAnimator interruption
        if let animator = sectionAnimator, animator.isRunning,
           let endState = sectionAnimationEndState {

            // Stop the animator first
            animator.stopAnimation(true)

            // Get the ACTUAL visual position from the presentation layer
            let actualFrameY = contentContainerView.layer.presentation()?.frame.origin.y
                ?? contentContainerView.frame.origin.y

            // User committed to target section by passing threshold and releasing.
            // Always use target section, even if animation just started.
            currentSection = endState.section

            // Calculate internalOffset from actual frame position.
            // DON'T CLAMP - allow negative values (past top) or values > maxInternalScroll (past bottom).
            // The momentum system handles out-of-bounds values with spring physics.
            let targetSectionOffset = sectionOffsets[currentSection]
            let targetSnapInset = snapInset(for: currentSection)
            internalOffset = -targetSectionOffset + targetSnapInset - actualFrameY

            rawDragOffset = 0

            // Set frame to match actual position (no visual jump)
            contentContainerView.frame.origin.y = actualFrameY

            // Notify binding that we're now in the target section
            // This prevents updateUIViewController from snapping us back to the old section
            onSectionChanged?(currentSection)

            sectionAnimator = nil
            sectionAnimationStartState = nil
            sectionAnimationEndState = nil
        }

        // Clean up any remaining animation state
        contentContainerView.layer.removeAllAnimations()
        isSectionAnimating = false

        isDragging = true
        lastPanTranslation = 0

        showScrollBar()
    }

    private func handleDragChanged(translation: CGFloat) {
        // Compute incremental delta from last frame
        let delta = translation - lastPanTranslation
        lastPanTranslation = translation

        if delta > 0 {
            // User is dragging DOWN (wants to scroll up or go to previous section)
            applyScrollUp(delta: delta)
        } else if delta < 0 {
            // User is dragging UP (wants to scroll down or go to next section)
            applyScrollDown(delta: delta)
        }

        updateContentOffset()
        updateScrollBarFrame()
        reportScrollProgress()
    }

    /// Reports scroll progress for scroll-driven animations.
    /// Progress is 0.0 at section 0, 1.0 at section 1+, with smooth interpolation during drag.
    private func reportScrollProgress() {
        let threshold = configuration.threshold

        let progress: CGFloat
        if currentSection == 0 {
            // At section 0: progress increases as user drags up (negative rawDragOffset)
            if rawDragOffset < 0 {
                progress = min(1.0, -rawDragOffset / threshold)
            } else {
                progress = 0.0
            }
        } else {
            // At section 1+: progress decreases as user drags down (positive rawDragOffset)
            if rawDragOffset > 0 {
                progress = max(0.0, 1.0 - rawDragOffset / threshold)
            } else {
                progress = 1.0
            }
        }

        onScrollProgress?(progress)
    }

    private func handleDragEnded(translation: CGFloat, velocity: CGFloat) {
        let threshold = configuration.threshold

        // Velocity-based triggering thresholds
        let velocityThreshold: CGFloat = 800  // points per second
        let minDistanceForVelocity: CGFloat = 30  // minimum drag to consider velocity

        // Check raw drag offset against threshold, or use velocity for quick flicks
        let distanceAdvance = -rawDragOffset > threshold
        let velocityAdvance = -rawDragOffset > minDistanceForVelocity && -velocity > velocityThreshold
        let shouldAdvance = (distanceAdvance || velocityAdvance) && currentSection < sectionHeights.count - 1

        let distanceRetreat = rawDragOffset > threshold
        let velocityRetreat = rawDragOffset > minDistanceForVelocity && velocity > velocityThreshold
        let shouldRetreat = (distanceRetreat || velocityRetreat) && currentSection > 0

        if shouldAdvance {
            animateToSection(currentSection + 1, fromBottom: false, velocity: velocity)
        } else if shouldRetreat {
            animateToSection(currentSection - 1, fromBottom: true, velocity: velocity)
        } else {
            // No section transition - snap back and apply momentum
            animateSnapBack(velocity: velocity)
            applyMomentum(velocity: velocity)
        }

        isDragging = false
        lastPanTranslation = 0

        // Always schedule scroll bar hide when drag ends.
        //
        // Why unconditional: There are multiple code paths that should hide the scroll bar
        // (stopMomentum, animateToSection completion, etc.), but edge cases at scroll
        // boundaries - particularly at the bottom of the last section - can cause the
        // hide to not trigger. Rather than chase down every edge case, we always schedule
        // a hide here as a safeguard. The hide task self-deduplicates (calling it multiple
        // times just resets the 1-second timer), so there's no harm in redundant calls.
        hideScrollBarAfterDelay()
    }

    private func handleDragCancelled() {
        isDragging = false
        lastPanTranslation = 0
        animateSnapBack(velocity: 0)
        hideScrollBarAfterDelay()
    }

    // MARK: - Scroll Application

    private func applyScrollUp(delta: CGFloat) {
        // First, drain any negative rawDragOffset
        if rawDragOffset < 0 {
            rawDragOffset += delta
            if rawDragOffset > 0 {
                let remainder = rawDragOffset
                rawDragOffset = 0
                applyScrollUpInternal(delta: remainder)
            }
            return
        }

        applyScrollUpInternal(delta: delta)
    }

    private func applyScrollUpInternal(delta: CGFloat) {
        if isAtSectionTop {
            rawDragOffset += delta
        } else {
            let newInternal = internalOffset - delta
            if newInternal < 0 {
                let overflow = -newInternal
                internalOffset = 0
                rawDragOffset += overflow
            } else {
                internalOffset = newInternal
            }
        }
    }

    private func applyScrollDown(delta: CGFloat) {
        // First, drain any positive rawDragOffset
        if rawDragOffset > 0 {
            rawDragOffset += delta
            if rawDragOffset < 0 {
                let remainder = rawDragOffset
                rawDragOffset = 0
                applyScrollDownInternal(delta: remainder)
            }
            return
        }

        applyScrollDownInternal(delta: delta)
    }

    private func applyScrollDownInternal(delta: CGFloat) {
        if isAtSectionBottom {
            rawDragOffset += delta
        } else {
            let newInternal = internalOffset - delta
            if newInternal > maxInternalScroll {
                let overflow = newInternal - maxInternalScroll
                internalOffset = maxInternalScroll
                rawDragOffset -= overflow
            } else {
                internalOffset = newInternal
            }
        }
    }
}

// MARK: - Animations

extension DetentScrollViewController {

    private func animateToSection(_ section: Int, fromBottom: Bool, velocity: CGFloat = 0) {
        let newSection = max(0, min(section, sectionHeights.count - 1))

        // Haptic feedback when crossing a detent
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Cancel any existing section animator
        sectionAnimator?.stopAnimation(true)
        sectionAnimator = nil

        isSectionAnimating = true

        // Store start state for interpolation on interruption
        let startFrameY = contentContainerView.frame.origin.y
        sectionAnimationStartState = (
            section: currentSection,
            internalOffset: internalOffset,
            rawDragOffset: rawDragOffset,
            frameY: startFrameY
        )

        // Calculate end state
        let endInternalOffset: CGFloat = fromBottom ? maxInternalScroll(for: newSection) : 0
        let endFrameY = -sectionOffsets[newSection] + snapInset(for: newSection) - endInternalOffset
        sectionAnimationEndState = (
            section: newSection,
            internalOffset: endInternalOffset,
            frameY: endFrameY
        )

        // Calculate current and target progress for smooth animation
        let currentProgress = calculateCurrentProgress()
        let targetProgress: CGFloat = newSection > 0 ? 1.0 : 0.0

        // Start progress animation (longer duration to match section animation)
        progressAnimationDuration = 0.4
        startProgressAnimation(from: currentProgress, to: targetProgress)

        // Create interruptible property animator
        // Using spring timing for natural feel
        let springTiming = UISpringTimingParameters(dampingRatio: 0.8)
        let animator = UIViewPropertyAnimator(duration: 0.4, timingParameters: springTiming)

        animator.addAnimations {
            self.currentSection = newSection
            self.internalOffset = endInternalOffset
            self.rawDragOffset = 0
            self.updateContentOffset()
            self.updateScrollBarFrame()
        }

        animator.addCompletion { [weak self] position in
            guard let self = self else { return }

            // Only handle completion if animation finished normally
            guard position == .end else { return }

            if self.currentSection == newSection {
                self.isSectionAnimating = false
                self.sectionAnimator = nil
                self.sectionAnimationStartState = nil
                self.sectionAnimationEndState = nil
                self.onSectionChanged?(newSection)
            }
            self.hideScrollBarAfterDelay()
        }

        sectionAnimator = animator
        animator.startAnimation()
    }

    private func animateSnapBack(velocity: CGFloat = 0) {
        // Calculate current and target progress for smooth animation
        let currentProgress = calculateCurrentProgress()
        let targetProgress: CGFloat = currentSection > 0 ? 1.0 : 0.0

        // Start progress animation to smoothly interpolate from current to target
        startProgressAnimation(from: currentProgress, to: targetProgress)

        // If rawDragOffset is negligible, just zero it out
        guard abs(rawDragOffset) > 1 else {
            rawDragOffset = 0
            return
        }

        // Initialize snap-back spring velocity based on gesture velocity.
        // The spring will pull rawDragOffset back to 0.
        // Gesture velocity sign: positive = dragging down, negative = dragging up.
        // rawDragOffset sign: positive = pulled toward previous section, negative = pulled toward next.
        // We want the initial spring velocity to match the gesture direction.
        snapBackVelocity = -velocity * 0.5  // Dampen initial velocity for smoother feel

        // Ensure the display link is running to process the snap-back.
        // If momentum is already active, it will handle both. If not, start it.
        if displayLink == nil {
            lastMomentumTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(updateMomentum))
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    /// Calculates the current scroll progress based on section and drag offset.
    private func calculateCurrentProgress() -> CGFloat {
        let threshold = configuration.threshold

        if currentSection == 0 {
            if rawDragOffset < 0 {
                return min(1.0, -rawDragOffset / threshold)
            } else {
                return 0.0
            }
        } else {
            if rawDragOffset > 0 {
                return max(0.0, 1.0 - rawDragOffset / threshold)
            } else {
                return 1.0
            }
        }
    }

    /// Starts a smooth progress animation from one value to another.
    private func startProgressAnimation(from startValue: CGFloat, to endValue: CGFloat) {
        // Cancel any existing progress animation
        stopProgressAnimation()

        // Don't animate if values are the same
        guard abs(startValue - endValue) > 0.001 else {
            onScrollProgress?(endValue)
            return
        }

        progressAnimationStartValue = startValue
        progressAnimationEndValue = endValue
        progressAnimationStartTime = CACurrentMediaTime()

        progressDisplayLink = CADisplayLink(target: self, selector: #selector(updateProgressAnimation))
        progressDisplayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateProgressAnimation() {
        let elapsed = CACurrentMediaTime() - progressAnimationStartTime
        let normalizedTime = min(1.0, elapsed / progressAnimationDuration)

        // Use ease-out curve for natural deceleration
        let easedTime = 1.0 - pow(1.0 - normalizedTime, 3.0)

        let currentProgress = progressAnimationStartValue + (progressAnimationEndValue - progressAnimationStartValue) * CGFloat(easedTime)
        onScrollProgress?(currentProgress)

        if normalizedTime >= 1.0 {
            stopProgressAnimation()
        }
    }

    private func stopProgressAnimation() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

    /// Programmatically scrolls to a section.
    public func scrollToSection(_ section: Int, animated: Bool = true) {
        let clampedSection = max(0, min(section, sectionHeights.count - 1))

        if animated {
            animateToSection(clampedSection, fromBottom: clampedSection < currentSection)
        } else {
            currentSection = clampedSection
            internalOffset = 0
            rawDragOffset = 0
            updateContentOffset()
            onSectionChanged?(clampedSection)
        }
    }

    /// Updates section heights with configurable scroll position anchoring.
    ///
    /// Use this method when section heights change dynamically (e.g., content was added/removed).
    ///
    /// - Parameters:
    ///   - newHeights: The new heights for each section.
    ///   - anchor: How to preserve scroll position (default: `.sectionTop`).
    ///   - animated: Whether to animate the layout update (default: false).
    ///
    /// ## Anchor Modes
    ///
    /// - `.sectionTop`: The current section's top stays visually anchored. Content grows/shrinks
    ///   downward. Use for tab switching, expanding/collapsing content in place.
    ///
    /// - `.preserveVisibleContent(insertedAbove:)`: Adjusts scroll position to keep the same
    ///   content visible when content is inserted above. Pass the height of inserted content
    ///   (positive) or removed content (negative).
    ///
    /// ## Example
    /// ```swift
    /// // Tab switching - anchor to top (default)
    /// controller.updateSectionHeights(newHeights)
    ///
    /// // Card inserted above current view - preserve visible content
    /// controller.updateSectionHeights(newHeights, anchor: .preserveVisibleContent(insertedAbove: cardHeight))
    /// ```
    public func updateSectionHeights(
        _ newHeights: [CGFloat],
        anchor: SectionHeightAnchor = .sectionTop,
        animated: Bool = false
    ) {
        guard newHeights != sectionHeights else { return }

        // Capture the offset of the current section before changing heights
        // This is the sum of all preceding section heights
        let oldSectionOffset = currentSectionOffset

        // Apply new heights (this triggers updateSectionOffsets via didSet)
        sectionHeights = newHeights

        // Ensure snap insets array matches new section count
        if sectionSnapInsets.count < newHeights.count {
            sectionSnapInsets += Array(repeating: 0, count: newHeights.count - sectionSnapInsets.count)
        } else if sectionSnapInsets.count > newHeights.count {
            sectionSnapInsets = Array(sectionSnapInsets.prefix(newHeights.count))
        }

        // Clamp current section to valid range
        if currentSection >= newHeights.count {
            currentSection = max(0, newHeights.count - 1)
        }

        // Check if preceding sections changed (which shifts our section's start position)
        let newSectionOffset = currentSectionOffset
        let precedingDelta = newSectionOffset - oldSectionOffset

        // Always compensate for preceding section changes
        if precedingDelta != 0 {
            internalOffset -= precedingDelta
        }

        // Apply anchor-specific adjustments for current section changes
        switch anchor {
        case .sectionTop:
            // No additional adjustment - section top stays anchored
            break

        case .preserveVisibleContent(let insertedAbove):
            // Adjust scroll position by the amount of content inserted above
            // Positive = content added above, scroll down to keep viewing same content
            // Negative = content removed above, scroll up
            internalOffset += insertedAbove
        }

        // Clamp internalOffset to valid range for the (possibly new) section height
        internalOffset = max(0, min(internalOffset, maxInternalScroll))

        // Update display
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.updateContentOffset()
                self.updateScrollBarFrame()
            }
        } else {
            updateContentOffset()
            updateScrollBarFrame()
        }

        // Trigger layout update for hosting controller
        view.setNeedsLayout()
    }

    // MARK: - External Drag Injection

    /// Injects a drag event from an external source (e.g., a SwiftUI child view).
    ///
    /// This allows SwiftUI child views that detect vertical drag gestures to forward
    /// them to the scroll view, enabling scrolling even when the gesture started on
    /// a child view with its own gesture recognizer.
    ///
    /// - Parameter translation: The cumulative vertical translation of the drag.
    public func injectDrag(translation: CGFloat) {
        guard !isScrollDisabled else { return }

        // Start external drag if not already active
        if !isExternalDragActive {
            isExternalDragActive = true
            lastExternalTranslation = 0

            // Cancel any in-flight animations
            stopMomentum()
            stopProgressAnimation()

            // Handle UIViewPropertyAnimator interruption (same as handleDragBegan)
            if let animator = sectionAnimator, animator.isRunning,
               let endState = sectionAnimationEndState {

                // Stop the animator first
                animator.stopAnimation(true)

                // Get actual visual position from presentation layer
                let actualFrameY = contentContainerView.layer.presentation()?.frame.origin.y
                    ?? contentContainerView.frame.origin.y

                // User committed to target section - always use it
                currentSection = endState.section

                // Don't clamp internalOffset - allow out-of-bounds values
                let targetSectionOffset = sectionOffsets[currentSection]
                let targetSnapInset = snapInset(for: currentSection)
                internalOffset = -targetSectionOffset + targetSnapInset - actualFrameY

                rawDragOffset = 0
                contentContainerView.frame.origin.y = actualFrameY

                // Notify binding that we're now in the target section
                onSectionChanged?(currentSection)

                sectionAnimator = nil
                sectionAnimationStartState = nil
                sectionAnimationEndState = nil
            }

            contentContainerView.layer.removeAllAnimations()
            isSectionAnimating = false

            isDragging = true
            showScrollBar()
        }

        // Calculate delta from last translation
        let delta = translation - lastExternalTranslation
        lastExternalTranslation = translation

        // Apply the scroll (same as internal gesture handling)
        if delta > 0 {
            applyScrollUp(delta: delta)
        } else if delta < 0 {
            applyScrollDown(delta: delta)
        }

        updateContentOffset()
        updateScrollBarFrame()
        reportScrollProgress()
    }

    /// Ends an externally injected drag gesture.
    ///
    /// - Parameter velocity: The vertical velocity of the drag at release.
    public func injectDragEnd(velocity: CGFloat) {
        guard isExternalDragActive else { return }

        isExternalDragActive = false
        lastExternalTranslation = 0

        // Use the same logic as internal gesture end
        handleDragEnded(translation: 0, velocity: velocity)
    }
}

// MARK: - Momentum Physics

extension DetentScrollViewController {

    private func applyMomentum(velocity: CGFloat) {
        let minVelocity: CGFloat = 50
        guard abs(velocity) > minVelocity else { return }

        // Flip sign: positive velocity = content moves up = offset increases
        momentumVelocity = -velocity

        // Only create display link if one doesn't already exist.
        // animateSnapBack may have already started one for the same updateMomentum loop.
        // Creating a duplicate link causes double-speed momentum (the acceleration bug).
        if displayLink == nil {
            lastMomentumTime = CACurrentMediaTime()
            displayLink = CADisplayLink(target: self, selector: #selector(updateMomentum))
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc private func updateMomentum() {
        // Safety: never run momentum physics during an active drag.
        // This prevents the snap-back spring from fighting with user input.
        guard !isDragging else {
            stopMomentum()
            return
        }

        let currentTime = CACurrentMediaTime()
        let rawDelta = currentTime - lastMomentumTime
        let frameTime = CGFloat(min(rawDelta, 1.0 / 30.0))
        lastMomentumTime = currentTime

        let friction: CGFloat = 0.95
        let bounceStiffness: CGFloat = 200
        let bounceDamping: CGFloat = 30

        // Spring constants for rawDragOffset snap-back (over-damped to prevent overshoot)
        let snapBackStiffness: CGFloat = 180
        let snapBackDamping: CGFloat = 28  // > 2*sqrt(180) ≈ 26.8 for over-damped

        // --- Update internalOffset momentum ---
        var momentumComplete = false

        let isPastTop = internalOffset < 0
        let isPastBottom = internalOffset > maxInternalScroll

        if isPastTop || isPastBottom {
            // Over-damped spring bounce
            let boundary: CGFloat = isPastTop ? 0 : maxInternalScroll
            let displacement = internalOffset - boundary

            let force = Physics.springForce(
                displacement: displacement,
                velocity: momentumVelocity,
                stiffness: bounceStiffness,
                damping: bounceDamping
            )
            momentumVelocity += force * frameTime
            internalOffset = Physics.integrate(
                position: internalOffset,
                velocity: momentumVelocity,
                deltaTime: frameTime
            )

            let reachedTop = isPastTop && internalOffset >= 0
            let reachedBottom = isPastBottom && internalOffset <= maxInternalScroll

            if reachedTop || reachedBottom {
                internalOffset = boundary
                momentumVelocity = 0
                momentumComplete = true
            }
        } else if abs(momentumVelocity) > 0 {
            // Normal friction-based momentum
            internalOffset = Physics.integrate(
                position: internalOffset,
                velocity: momentumVelocity,
                deltaTime: frameTime
            )
            momentumVelocity = Physics.applyFriction(
                velocity: momentumVelocity,
                friction: friction
            )

            if abs(momentumVelocity) < 1 {
                momentumVelocity = 0
                momentumComplete = true
            }
        } else {
            momentumComplete = true
        }

        // --- Update rawDragOffset snap-back spring ---
        var snapBackComplete = false

        if abs(rawDragOffset) > 0.5 || abs(snapBackVelocity) > 1 {
            // Apply spring physics to pull rawDragOffset back to 0
            let force = Physics.springForce(
                displacement: rawDragOffset,
                velocity: snapBackVelocity,
                stiffness: snapBackStiffness,
                damping: snapBackDamping
            )
            snapBackVelocity += force * frameTime
            rawDragOffset = Physics.integrate(
                position: rawDragOffset,
                velocity: snapBackVelocity,
                deltaTime: frameTime
            )

            // Check if settled
            if abs(rawDragOffset) < 0.5 && abs(snapBackVelocity) < 1 {
                rawDragOffset = 0
                snapBackVelocity = 0
                snapBackComplete = true
            }
        } else {
            rawDragOffset = 0
            snapBackVelocity = 0
            snapBackComplete = true
        }

        // --- Update visuals ---
        updateContentOffset()
        updateScrollBarFrame()

        // --- Check if all animations are complete ---
        if momentumComplete && snapBackComplete {
            stopMomentum()
        }
    }

    private func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        momentumVelocity = 0
        snapBackVelocity = 0

        // Hide scroll bar when momentum stops, unless we're mid-drag.
        // The isDragging check prevents hiding when stopMomentum is called from
        // handleDragBegan (which cancels any existing momentum before showing the bar).
        if !isDragging {
            hideScrollBarAfterDelay()
        }
    }

    /// Stops any active momentum animation.
    public func stopAnimation() {
        stopMomentum()
    }
}

// MARK: - Scroll Bar

extension DetentScrollViewController {

    private var totalScrollableDistance: CGFloat {
        max(0, totalContentHeight - view.bounds.height)
    }

    private var currentAbsoluteOffset: CGFloat {
        // Account for snap inset - this represents the visual scroll position
        currentSectionOffset - currentSnapInset + internalOffset
    }

    private var scrollBarHeight: CGFloat {
        guard totalScrollableDistance > 0 else { return 0 }
        let contentRatio = view.bounds.height / totalContentHeight
        let baseHeight = max(40, view.bounds.height * contentRatio)

        // Shrink when overscrolling
        let overscrollAmount: CGFloat
        if internalOffset < 0 {
            overscrollAmount = abs(internalOffset)
        } else if internalOffset > maxInternalScroll {
            overscrollAmount = internalOffset - maxInternalScroll
        } else if rawDragOffset != 0 {
            overscrollAmount = abs(rawDragOffset) * 0.5
        } else {
            overscrollAmount = 0
        }

        let shrinkFactor = max(0.3, 1 - (overscrollAmount / 300))
        return max(20, baseHeight * shrinkFactor)
    }

    private var scrollBarOffsetY: CGFloat {
        guard totalScrollableDistance > 0 else { return 8 }
        let progress = currentAbsoluteOffset / totalScrollableDistance
        let clampedProgress = max(0, min(1, progress))
        let trackHeight = view.bounds.height - scrollBarHeight - 16
        return 8 + (clampedProgress * trackHeight)
    }

    private func updateScrollBarFrame() {
        scrollBarView.frame = CGRect(
            x: view.bounds.width - 8,
            y: scrollBarOffsetY,
            width: 4,
            height: scrollBarHeight
        )
    }

    private func showScrollBar() {
        scrollBarHideTask?.cancel()
        scrollBarHideTask = nil

        UIView.animate(withDuration: 0.15) {
            self.scrollBarView.alpha = 1
        }
    }

    private func hideScrollBarAfterDelay() {
        scrollBarHideTask?.cancel()
        scrollBarHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    UIView.animate(withDuration: 0.3) {
                        self.scrollBarView.alpha = 0
                    }
                }
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DetentScrollViewController: UIGestureRecognizerDelegate {

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        guard !isScrollDisabled else { return false }

        // Don't begin if multiple touches (likely a pinch gesture)
        if panGesture.numberOfTouches > 1 {
            return false
        }

        // Only handle primarily vertical drags
        let velocity = panGesture.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Always allow our touch-down gesture to work with everything.
        // It only stops momentum on touch and doesn't interfere with other gestures.
        if gestureRecognizer === touchDownGesture || otherGestureRecognizer === touchDownGesture {
            return true
        }

        // Allow pinch gestures to work simultaneously
        if otherGestureRecognizer is UIPinchGestureRecognizer {
            return true
        }

        // Allow pan gestures to work simultaneously with other pan gestures.
        // This enables child views (like TimeStepper) to handle horizontal drags
        // while we handle vertical drags. Each gesture filters by direction.
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return true
        }

        return false
    }
}
