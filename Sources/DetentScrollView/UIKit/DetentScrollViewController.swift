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

    /// Current momentum velocity.
    private var momentumVelocity: CGFloat = 0

    /// Whether a section transition animation is in progress.
    private var isSectionAnimating: Bool = false

    /// Whether any animation is active (momentum or section transition).
    public var isAnimating: Bool {
        displayLink != nil || isSectionAnimating
    }

    /// Last momentum update timestamp.
    private var lastMomentumTime: CFTimeInterval = 0

    // MARK: - Callbacks

    /// Called when current section changes.
    public var onSectionChanged: ((Int) -> Void)?

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

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        setupGestures()
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
    }

    private func handleDragEnded(translation: CGFloat, velocity: CGFloat) {
        let threshold = configuration.threshold

        // Check raw drag offset against threshold
        let shouldAdvance = -rawDragOffset > threshold && currentSection < sectionHeights.count - 1
        let shouldRetreat = rawDragOffset > threshold && currentSection > 0

        if shouldAdvance {
            animateToSection(currentSection + 1, fromBottom: false)
        } else if shouldRetreat {
            animateToSection(currentSection - 1, fromBottom: true)
        } else {
            // No section transition - snap back and apply momentum
            animateSnapBack()
            applyMomentum(velocity: velocity)
        }

        isDragging = false
        lastPanTranslation = 0

        // Hide scroll bar after delay if no momentum
        if !isAnimating {
            hideScrollBarAfterDelay()
        }
    }

    private func handleDragCancelled() {
        isDragging = false
        lastPanTranslation = 0
        animateSnapBack()
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

    private func animateToSection(_ section: Int, fromBottom: Bool) {
        let newSection = max(0, min(section, sectionHeights.count - 1))

        isSectionAnimating = true

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.currentSection = newSection
            if fromBottom {
                self.internalOffset = self.maxInternalScroll(for: newSection)
            } else {
                self.internalOffset = 0
            }
            self.rawDragOffset = 0
            self.updateContentOffset()
            self.updateScrollBarFrame()
        } completion: { _ in
            // Only clear animation flag and notify if we're actually at the target section
            // (animation wasn't overridden by another animation)
            if self.currentSection == newSection {
                self.isSectionAnimating = false
                self.onSectionChanged?(newSection)
            }
            self.hideScrollBarAfterDelay()
        }
    }

    private func animateSnapBack() {
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.rawDragOffset = 0
            self.updateContentOffset()
        }
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
}

// MARK: - Momentum Physics

extension DetentScrollViewController {

    private func applyMomentum(velocity: CGFloat) {
        let minVelocity: CGFloat = 50
        guard abs(velocity) > minVelocity else { return }

        // Flip sign: positive velocity = content moves up = offset increases
        momentumVelocity = -velocity
        lastMomentumTime = CACurrentMediaTime()

        displayLink = CADisplayLink(target: self, selector: #selector(updateMomentum))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateMomentum() {
        let currentTime = CACurrentMediaTime()
        let rawDelta = currentTime - lastMomentumTime
        let frameTime = CGFloat(min(rawDelta, 1.0 / 30.0))
        lastMomentumTime = currentTime

        let friction: CGFloat = 0.95
        let bounceStiffness: CGFloat = 200
        let bounceDamping: CGFloat = 30

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
                stopMomentum()
            }
        } else {
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
                stopMomentum()
            }
        }

        updateContentOffset()
        updateScrollBarFrame()
    }

    private func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        momentumVelocity = 0
        hideScrollBarAfterDelay()
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
        currentSectionOffset + internalOffset
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
        // Allow pinch gestures to work simultaneously
        if otherGestureRecognizer is UIPinchGestureRecognizer {
            return true
        }
        return false
    }
}
