//
//  DetentScrollView.swift
//  DetentScrollView
//
//  A scroll view with detent-based resistance and snapping between sections.
//

import SwiftUI
import QuartzCore

// MARK: - Physics

/// Pure physics functions for DetentScrollView, exposed for testing.
public enum DetentScrollPhysics {
    /// Apply rubber-band resistance to a drag offset.
    /// - Parameters:
    ///   - offset: The raw drag offset (can be positive or negative)
    ///   - limit: The maximum visual offset (asymptotic limit)
    ///   - coefficient: Resistance strength (higher = more resistance)
    /// - Returns: The visually dampened offset
    public static func rubberBand(offset: CGFloat, limit: CGFloat, coefficient: CGFloat) -> CGFloat {
        let absOffset = abs(offset)
        let sign: CGFloat = offset >= 0 ? 1 : -1
        let resisted = (1 - (1 / (absOffset * coefficient / limit + 1))) * limit
        return sign * resisted
    }

    /// Calculate spring force for boundary bounce.
    /// Uses over-damped spring formula: F = -kx - cv
    /// - Parameters:
    ///   - displacement: Distance from boundary (positive = past boundary)
    ///   - velocity: Current velocity
    ///   - stiffness: Spring constant (k)
    ///   - damping: Damping coefficient (c)
    /// - Returns: The spring force to apply
    public static func springForce(
        displacement: CGFloat,
        velocity: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat
    ) -> CGFloat {
        return -stiffness * displacement - damping * velocity
    }

    /// Apply friction to velocity for one frame.
    /// - Parameters:
    ///   - velocity: Current velocity
    ///   - friction: Friction coefficient (0-1, e.g., 0.95)
    /// - Returns: New velocity after friction applied
    public static func applyFriction(velocity: CGFloat, friction: CGFloat) -> CGFloat {
        return velocity * friction
    }

    /// Calculate new position from velocity over a time step.
    /// - Parameters:
    ///   - position: Current position
    ///   - velocity: Current velocity
    ///   - deltaTime: Time step in seconds
    /// - Returns: New position
    public static func integrate(position: CGFloat, velocity: CGFloat, deltaTime: CGFloat) -> CGFloat {
        return position + velocity * deltaTime
    }
}

// MARK: - Configuration

/// Configuration options for DetentScrollView behavior.
public struct DetentScrollConfiguration {
    /// Drag distance required to trigger a section transition (default: 120pt)
    public var threshold: CGFloat

    /// Rubber-band resistance coefficient - higher values produce more resistance (default: 0.55)
    public var resistanceCoefficient: CGFloat

    /// Minimum drag distance before scroll gesture activates (default: 10pt).
    /// Increase this value if child views need to capture vertical drags.
    public var minimumDragDistance: CGFloat

    /// Creates a configuration with the specified parameters.
    public init(
        threshold: CGFloat = 120,
        resistanceCoefficient: CGFloat = 0.55,
        minimumDragDistance: CGFloat = 10
    ) {
        self.threshold = threshold
        self.resistanceCoefficient = resistanceCoefficient
        self.minimumDragDistance = minimumDragDistance
    }

    /// Default configuration with standard threshold and resistance values.
    public static let `default` = DetentScrollConfiguration()
}

// MARK: - DetentScrollView

/// A scroll view with detent-based resistance and snapping between sections.
///
/// Unlike standard ScrollView (free-flowing) or paged ScrollView (binary snap),
/// DetentScrollView creates a physical "detent" feel where users must overcome
/// resistance to transition between sections.
///
/// ## Features
/// - Rubber-band resistance at section boundaries
/// - Threshold-based snapping between sections
/// - Free scrolling within sections that exceed viewport height
/// - Natural momentum with instant catch on touch
/// - Over-damped bounce at section edges
/// - Auto-hiding scrollbar
/// - Section snap insets for "peek" behavior
///
/// ## Example
/// ```swift
/// @State private var section = 0
///
/// DetentScrollView(
///     sectionHeights: [screenHeight, 600, screenHeight],
///     sectionSnapInsets: [0, 100, 0],
///     currentSection: $section
/// ) {
///     VStack(spacing: 0) {
///         Section1().frame(height: screenHeight)
///         Section2().frame(height: 600)
///         Section3().frame(height: screenHeight)
///     }
/// }
/// ```
public struct DetentScrollView<Content: View>: View {
    // MARK: - Public Properties

    /// The content to display within the scroll view.
    public let content: Content

    /// Height of each section in points.
    public let sectionHeights: [CGFloat]

    /// How far from viewport top each section starts when snapped.
    /// This allows the previous section to "peek" above the current section.
    public let sectionSnapInsets: [CGFloat]

    /// Configuration for threshold and resistance behavior.
    public let configuration: DetentScrollConfiguration

    /// External signal to disable scrolling (e.g., when content is zoomed).
    /// When true, all scroll gestures are ignored.
    public let isScrollDisabled: Bool

    // MARK: - Bindings

    /// Optional binding to observe/control current section externally.
    /// When provided, changes to this binding will be reflected in the scroll view.
    @Binding private var currentSectionBinding: Int

    /// Whether external binding is being used (vs internal state only).
    private let usesExternalBinding: Bool

    /// Cached Y offset for the start of each section (computed once at init).
    private let cachedSectionOffsets: [CGFloat]

    // MARK: - Private State

    @State private var currentSectionInternal: Int = 0
    @State private var internalOffset: CGFloat = 0
    @State private var rawDragOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var momentumVelocity: CGFloat = 0
    @State private var isMomentumActive: Bool = false
    @State private var isScrollBarVisible: Bool = false
    @State private var scrollBarHideTask: Task<Void, Never>?
    @State private var lastMomentumUpdateTime: CFTimeInterval = 0

    // MARK: - Computed Properties

    /// Current section index (from binding or internal state).
    private var currentSection: Int {
        get { usesExternalBinding ? currentSectionBinding : currentSectionInternal }
        nonmutating set {
            if usesExternalBinding {
                currentSectionBinding = newValue
            } else {
                currentSectionInternal = newValue
            }
        }
    }

    /// Whether the user has scrolled past the first section.
    /// Use this to coordinate with other gesture systems (e.g., disable zoom when scrolled).
    public var isScrolled: Bool {
        currentSection > 0
    }

    /// Visual drag offset with rubber-band applied.
    private var dragOffset: CGFloat {
        rubberBand(offset: rawDragOffset, limit: configuration.threshold * 2)
    }

    // MARK: - Initializers

    /// Creates a detent scroll view with the specified sections and configuration.
    ///
    /// - Parameters:
    ///   - sectionHeights: Height of each section in points.
    ///   - sectionSnapInsets: Optional insets for each section (default: all zeros).
    ///   - configuration: Threshold and resistance configuration.
    ///   - currentSection: Optional binding to observe/control current section.
    ///   - isScrollDisabled: External signal to disable scrolling (e.g., when content is zoomed).
    ///   - content: The content to display.
    public init(
        sectionHeights: [CGFloat],
        sectionSnapInsets: [CGFloat]? = nil,
        configuration: DetentScrollConfiguration = .default,
        currentSection: Binding<Int>? = nil,
        isScrollDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.sectionHeights = sectionHeights

        // Ensure snap insets array matches section count (pad with zeros if shorter)
        let insets = sectionSnapInsets ?? []
        if insets.count < sectionHeights.count {
            self.sectionSnapInsets = insets + Array(repeating: 0, count: sectionHeights.count - insets.count)
        } else {
            self.sectionSnapInsets = Array(insets.prefix(sectionHeights.count))
        }
        self.configuration = configuration
        self.isScrollDisabled = isScrollDisabled
        self.content = content()

        // Pre-compute section offsets once (avoids recalculation during animation)
        var offsets: [CGFloat] = [0]
        var cumulative: CGFloat = 0
        for height in sectionHeights.dropLast() {
            cumulative += height
            offsets.append(cumulative)
        }
        self.cachedSectionOffsets = offsets

        if let binding = currentSection {
            self._currentSectionBinding = binding
            self.usesExternalBinding = true
        } else {
            self._currentSectionBinding = .constant(0)
            self.usesExternalBinding = false
        }
    }


    // MARK: - Section Geometry

    /// Current section's snap inset (how far from top it should start).
    private var currentSnapInset: CGFloat {
        guard currentSection < sectionSnapInsets.count else { return 0 }
        return sectionSnapInsets[currentSection]
    }

    /// Snap inset for a specific section.
    private func snapInset(for section: Int) -> CGFloat {
        guard section < sectionSnapInsets.count else { return 0 }
        return sectionSnapInsets[section]
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

    /// Maximum internal scroll for current section (0 means section fits in viewport).
    private var maxInternalScroll: CGFloat {
        maxInternalScroll(for: currentSection)
    }

    /// Maximum internal scroll for a specific section.
    /// Includes snap inset so user can scroll away the margin from previous section.
    private func maxInternalScroll(for section: Int) -> CGFloat {
        guard section < sectionHeights.count else { return 0 }
        let inset = snapInset(for: section)
        return max(0, sectionHeights[section] - viewportHeight + inset)
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

    /// The visual offset applied to content.
    private var visualOffset: CGFloat {
        let baseOffset = -currentSectionOffset + currentSnapInset - internalOffset
        return baseOffset + dragOffset
    }

    // MARK: - Rubber Band

    /// Apply rubber-band resistance to drag offset.
    private func rubberBand(offset: CGFloat, limit: CGFloat) -> CGFloat {
        DetentScrollPhysics.rubberBand(
            offset: offset,
            limit: limit,
            coefficient: configuration.resistanceCoefficient
        )
    }

    // MARK: - Scroll Bar

    /// Total height of all sections combined.
    private var totalContentHeight: CGFloat {
        sectionHeights.reduce(0, +)
    }

    /// Current absolute scroll position across all sections.
    private var currentAbsoluteOffset: CGFloat {
        currentSectionOffset + internalOffset
    }

    /// Total scrollable distance (content height minus viewport).
    private var totalScrollableDistance: CGFloat {
        max(0, totalContentHeight - viewportHeight)
    }

    /// Height of the scroll bar indicator.
    private var scrollBarHeight: CGFloat {
        guard totalScrollableDistance > 0 else { return 0 }
        let contentRatio = viewportHeight / totalContentHeight
        // 40pt minimum ensures scroll bar is always visible/tappable
        let baseHeight = max(40, viewportHeight * contentRatio)

        // Shrink when overscrolling (bounce or detent resistance)
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

        // 300pt divisor controls how quickly scroll bar shrinks during overscroll
        // 0.3 minimum prevents scroll bar from disappearing completely
        // 20pt absolute minimum for visibility
        let shrinkFactor = max(0.3, 1 - (overscrollAmount / 300))
        return max(20, baseHeight * shrinkFactor)
    }

    /// Y offset of the scroll bar indicator.
    private var scrollBarOffset: CGFloat {
        guard totalScrollableDistance > 0 else { return 0 }
        let progress = currentAbsoluteOffset / totalScrollableDistance
        let clampedProgress = max(0, min(1, progress))
        let trackHeight = viewportHeight - scrollBarHeight - 16
        return 8 + (clampedProgress * trackHeight)
    }

    /// Whether the scroll bar should be visible.
    private var showScrollBar: Bool {
        totalScrollableDistance > 0 && isScrollBarVisible
    }

    /// Show the scroll bar immediately.
    private func showScrollBarNow() {
        scrollBarHideTask?.cancel()
        scrollBarHideTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            isScrollBarVisible = true
        }
    }

    /// Hide the scroll bar after a delay.
    private func hideScrollBarAfterDelay() {
        scrollBarHideTask?.cancel()
        scrollBarHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isScrollBarVisible = false
                    }
                }
            }
        }
    }

    // MARK: - Body

    public var body: some View {
        TimelineView(.animation(paused: !isMomentumActive)) { timeline in
            GeometryReader { geometry in
                content
                    .offset(y: visualOffset)
                    .gesture(
                        DragGesture(minimumDistance: configuration.minimumDragDistance)
                            .onChanged { value in
                                // Ignore if scrolling is disabled (e.g., content is zoomed)
                                guard !isScrollDisabled else { return }

                                // Only handle primarily vertical drags
                                let isVertical = abs(value.translation.height) > abs(value.translation.width)
                                if isVertical {
                                    handleDragChanged(translation: value.translation.height)
                                }
                            }
                            .onEnded { value in
                                // Ignore if scrolling is disabled
                                guard !isScrollDisabled else { return }
                                handleDragEnd(translation: value.translation.height, velocity: value.velocity.height)
                            }
                    )
                    .onAppear {
                        viewportHeight = geometry.size.height
                    }
                    .onDisappear {
                        scrollBarHideTask?.cancel()
                        scrollBarHideTask = nil
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        viewportHeight = newHeight
                    }
                    .onChange(of: timeline.date) { _, _ in
                        if isMomentumActive {
                            updateMomentum()
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        // Scroll bar for entire content
                        if showScrollBar {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.4))
                                .frame(width: 4, height: scrollBarHeight)
                                .offset(y: scrollBarOffset)
                                .padding(.trailing, 4)
                        }
                    }
            }
        }
    }

    // MARK: - Gesture Handling

    /// Process incremental drag delta during a drag gesture.
    private func handleDragChanged(translation: CGFloat) {
        // On first touch of a new drag, cancel any in-flight momentum animation
        if !isDragging {
            isDragging = true
            catchMomentum()
            showScrollBarNow()
        }

        // Compute incremental delta from last frame
        let delta = translation - lastDragTranslation
        lastDragTranslation = translation

        // Dragging down (positive delta) = scrolling up / going to previous
        // Dragging up (negative delta) = scrolling down / going to next

        if delta > 0 {
            // User is dragging DOWN (wants to scroll up or go to previous section)

            // First, drain any negative rawDragOffset (from previous "next section" attempt)
            if rawDragOffset < 0 {
                rawDragOffset += delta
                if rawDragOffset > 0 {
                    // Overshot zero - use remainder for normal scroll
                    let remainder = rawDragOffset
                    rawDragOffset = 0
                    applyScrollUp(delta: remainder)
                }
                return
            }

            applyScrollUp(delta: delta)

        } else if delta < 0 {
            // User is dragging UP (wants to scroll down or go to next section)

            // First, drain any positive rawDragOffset (from previous "previous section" attempt)
            if rawDragOffset > 0 {
                rawDragOffset += delta
                if rawDragOffset < 0 {
                    // Overshot zero - use remainder for normal scroll
                    let remainder = rawDragOffset
                    rawDragOffset = 0
                    applyScrollDown(delta: remainder)
                }
                return
            }

            applyScrollDown(delta: delta)
        }
    }

    /// Apply scroll up movement (drag down, positive delta).
    private func applyScrollUp(delta: CGFloat) {
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

    /// Apply scroll down movement (drag up, negative delta).
    private func applyScrollDown(delta: CGFloat) {
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

    private func handleDragEnd(translation: CGFloat, velocity: CGFloat) {
        let threshold = configuration.threshold

        // Check raw drag offset against threshold (not the rubber-banded visual offset)
        let shouldAdvance = -rawDragOffset > threshold && currentSection < sectionHeights.count - 1
        let shouldRetreat = rawDragOffset > threshold && currentSection > 0

        if shouldAdvance {
            let newSection = currentSection + 1
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                setCurrentSection(newSection)
                internalOffset = 0
                rawDragOffset = 0
            }
        } else if shouldRetreat {
            let newSection = currentSection - 1
            let previousSectionMaxScroll = maxInternalScroll(for: newSection)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                setCurrentSection(newSection)
                internalOffset = previousSectionMaxScroll
                rawDragOffset = 0
            }
        } else {
            // No section transition - apply momentum to internal scroll
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                rawDragOffset = 0
            }
            applyMomentum(velocity: velocity)
        }

        // Reset drag tracking
        lastDragTranslation = 0
        isDragging = false

        // Hide scrollbar after delay if no momentum
        if !isMomentumActive {
            hideScrollBarAfterDelay()
        }
    }

    /// Update current section (handles both internal state and external binding).
    private func setCurrentSection(_ section: Int) {
        currentSectionInternal = section
        if usesExternalBinding {
            currentSectionBinding = section
        }
    }

    // MARK: - Momentum Physics

    /// Immediately stop any in-progress momentum animation.
    private func catchMomentum() {
        isMomentumActive = false
        momentumVelocity = 0
    }

    /// Start momentum animation with the given velocity.
    /// - Parameter velocity: Gesture velocity in points per second.
    private func applyMomentum(velocity: CGFloat) {
        // 50 pt/s minimum prevents micro-momentum from tiny flicks
        let minVelocity: CGFloat = 50
        if abs(velocity) > minVelocity {
            // Flip sign: positive velocity = content moves up = offset increases
            momentumVelocity = -velocity
            lastMomentumUpdateTime = CACurrentMediaTime()
            isMomentumActive = true
        }
    }

    /// Update momentum physics each frame (called by TimelineView).
    ///
    /// Uses friction-based deceleration for normal scrolling and
    /// over-damped spring physics for boundary bounce.
    private func updateMomentum() {
        // Calculate actual frame time for correct physics on all refresh rates
        let currentTime = CACurrentMediaTime()
        let rawDelta = currentTime - lastMomentumUpdateTime
        let frameTime = CGFloat(min(rawDelta, 1.0 / 30.0))  // Clamp to prevent jumps on frame drops
        lastMomentumUpdateTime = currentTime

        // Physics constants tuned for natural iOS feel:
        // - friction: 0.95 = velocity decays to ~5% after 60 frames (~1 second)
        // - bounceStiffness: 200 = firm spring, quick return to boundary
        // - bounceDamping: 30 = over-damped (no oscillation), smooth settle
        let friction: CGFloat = 0.95
        let bounceStiffness: CGFloat = 200
        let bounceDamping: CGFloat = 30

        let isPastTop = internalOffset < 0
        let isPastBottom = internalOffset > maxInternalScroll

        if isPastTop || isPastBottom {
            // Over-damped spring bounce (no oscillation)
            let boundary: CGFloat = isPastTop ? 0 : maxInternalScroll
            let displacement = internalOffset - boundary

            let force = DetentScrollPhysics.springForce(
                displacement: displacement,
                velocity: momentumVelocity,
                stiffness: bounceStiffness,
                damping: bounceDamping
            )
            momentumVelocity += force * frameTime
            internalOffset = DetentScrollPhysics.integrate(
                position: internalOffset,
                velocity: momentumVelocity,
                deltaTime: frameTime
            )

            // Stop when reaching boundary
            let reachedTop = isPastTop && internalOffset >= 0
            let reachedBottom = isPastBottom && internalOffset <= maxInternalScroll

            if reachedTop || reachedBottom {
                internalOffset = boundary
                momentumVelocity = 0
                isMomentumActive = false
                hideScrollBarAfterDelay()
            }
        } else {
            // Normal friction-based momentum
            internalOffset = DetentScrollPhysics.integrate(
                position: internalOffset,
                velocity: momentumVelocity,
                deltaTime: frameTime
            )
            momentumVelocity = DetentScrollPhysics.applyFriction(
                velocity: momentumVelocity,
                friction: friction
            )

            if abs(momentumVelocity) < 1 {
                momentumVelocity = 0
                isMomentumActive = false
                hideScrollBarAfterDelay()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DetentScrollView(sectionHeights: [800, 600, 800]) {
        VStack(spacing: 0) {
            Color.blue.opacity(0.3)
                .frame(height: 800)
                .overlay(Text("Section 1").font(.largeTitle))

            Color.green.opacity(0.3)
                .frame(height: 600)
                .overlay(Text("Section 2").font(.largeTitle))

            Color.purple.opacity(0.3)
                .frame(height: 800)
                .overlay(Text("Section 3").font(.largeTitle))
        }
    }
}
