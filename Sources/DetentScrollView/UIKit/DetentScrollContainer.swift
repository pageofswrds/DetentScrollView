//
//  DetentScrollContainer.swift
//  DetentScrollView
//
//  UIViewControllerRepresentable wrapper for DetentScrollViewController.
//  Provides a SwiftUI-friendly interface to the UIKit-based scroll view.
//

import SwiftUI

// MARK: - Drag Injection Handler

/// Handler for injecting vertical drag events into the DetentScrollView.
///
/// Use this when a SwiftUI child view captures a gesture but wants to forward
/// vertical movement to the parent scroll view.
public class DetentScrollDragHandler: ObservableObject {
    weak var controller: DetentScrollViewController?

    public init() {}

    /// Injects a vertical drag translation into the scroll view.
    /// Call this from your gesture's `onChanged` with the vertical translation.
    @MainActor
    public func injectDrag(translation: CGFloat) {
        controller?.injectDrag(translation: translation)
    }

    /// Ends the injected drag gesture.
    /// Call this from your gesture's `onEnded` with the vertical velocity.
    @MainActor
    public func injectDragEnd(velocity: CGFloat) {
        controller?.injectDragEnd(velocity: velocity)
    }
}

// MARK: - Environment Key

private struct DetentScrollDragHandlerKey: EnvironmentKey {
    static let defaultValue: DetentScrollDragHandler? = nil
}

public extension EnvironmentValues {
    /// Handler for injecting drag events into the parent DetentScrollContainer.
    var detentScrollDragHandler: DetentScrollDragHandler? {
        get { self[DetentScrollDragHandlerKey.self] }
        set { self[DetentScrollDragHandlerKey.self] = newValue }
    }
}

/// A UIKit-based detent scroll view wrapped for SwiftUI.
///
/// This is an alternative to `DetentScrollView` that uses UIKit's `UIPanGestureRecognizer`
/// instead of SwiftUI's `DragGesture`. The UIKit approach provides immediate visual feedback
/// during drag gestures, even when child views have their own gesture recognizers.
///
/// ## Usage
/// ```swift
/// @State private var section = 0
///
/// DetentScrollContainer(
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
public struct DetentScrollContainer<Content: View>: UIViewControllerRepresentable {

    // MARK: - Configuration

    /// Fixed section heights (nil when using dynamic measurement).
    private let fixedSectionHeights: [CGFloat]?

    /// Number of sections for dynamic height mode.
    private let sectionCount: Int?

    /// How far from viewport top each section starts when snapped.
    public let sectionSnapInsets: [CGFloat]

    /// Configuration for threshold and resistance behavior.
    public let configuration: DetentScrollConfiguration

    /// External signal to disable scrolling (e.g., when content is zoomed).
    public let isScrollDisabled: Bool

    /// Whether using dynamic height measurement.
    private var usesDynamicHeights: Bool {
        sectionCount != nil
    }

    // MARK: - Bindings

    /// Binding to observe/control current section externally.
    @Binding private var currentSection: Int

    /// Whether external binding is being used.
    private let usesExternalBinding: Bool

    /// Binding to observe scroll progress (0.0 = section 0, 1.0 = section 1+).
    /// Enables scroll-driven animations like collapsing headers.
    @Binding private var scrollProgress: CGFloat

    /// Whether scroll progress binding is being used.
    private let usesScrollProgressBinding: Bool

    // MARK: - Content

    /// The SwiftUI content to display.
    public let content: Content

    // MARK: - Initializers

    /// Creates a detent scroll container with fixed section heights.
    ///
    /// Use this initializer when you know the exact height of each section upfront.
    ///
    /// - Parameters:
    ///   - sectionHeights: Height of each section in points.
    ///   - sectionSnapInsets: Optional insets for each section (default: all zeros).
    ///   - configuration: Threshold and resistance configuration.
    ///   - currentSection: Optional binding to observe/control current section.
    ///   - scrollProgress: Optional binding to observe scroll progress (0.0-1.0) for scroll-driven animations.
    ///   - isScrollDisabled: External signal to disable scrolling.
    ///   - content: The content to display.
    public init(
        sectionHeights: [CGFloat],
        sectionSnapInsets: [CGFloat]? = nil,
        configuration: DetentScrollConfiguration = .default,
        currentSection: Binding<Int>? = nil,
        scrollProgress: Binding<CGFloat>? = nil,
        isScrollDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.fixedSectionHeights = sectionHeights
        self.sectionCount = nil

        // Ensure snap insets array matches section count
        let insets = sectionSnapInsets ?? []
        if insets.count < sectionHeights.count {
            self.sectionSnapInsets = insets + Array(repeating: 0, count: sectionHeights.count - insets.count)
        } else {
            self.sectionSnapInsets = Array(insets.prefix(sectionHeights.count))
        }

        self.configuration = configuration
        self.isScrollDisabled = isScrollDisabled
        self.content = content()

        if let binding = currentSection {
            self._currentSection = binding
            self.usesExternalBinding = true
        } else {
            self._currentSection = .constant(0)
            self.usesExternalBinding = false
        }

        if let binding = scrollProgress {
            self._scrollProgress = binding
            self.usesScrollProgressBinding = true
        } else {
            self._scrollProgress = .constant(0)
            self.usesScrollProgressBinding = false
        }
    }

    /// Creates a detent scroll container with dynamically measured section heights.
    ///
    /// Use this initializer when section heights should be determined by their content.
    /// Wrap each section in a `DetentSection` view to enable height measurement:
    ///
    /// ```swift
    /// DetentScrollContainer(sectionCount: 2) {
    ///     VStack(spacing: 0) {
    ///         DetentSection(index: 0) {
    ///             Section1Content()
    ///         }
    ///         DetentSection(index: 1) {
    ///             Section2Content()
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - sectionCount: The number of sections to track.
    ///   - sectionSnapInsets: Optional insets for each section (default: all zeros).
    ///   - configuration: Threshold and resistance configuration.
    ///   - currentSection: Optional binding to observe/control current section.
    ///   - scrollProgress: Optional binding to observe scroll progress (0.0-1.0) for scroll-driven animations.
    ///   - isScrollDisabled: External signal to disable scrolling.
    ///   - content: The content to display. Each section should be wrapped in `DetentSection`.
    public init(
        sectionCount: Int,
        sectionSnapInsets: [CGFloat]? = nil,
        configuration: DetentScrollConfiguration = .default,
        currentSection: Binding<Int>? = nil,
        scrollProgress: Binding<CGFloat>? = nil,
        isScrollDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.fixedSectionHeights = nil
        self.sectionCount = sectionCount

        // Ensure snap insets array matches section count
        let insets = sectionSnapInsets ?? []
        if insets.count < sectionCount {
            self.sectionSnapInsets = insets + Array(repeating: 0, count: sectionCount - insets.count)
        } else {
            self.sectionSnapInsets = Array(insets.prefix(sectionCount))
        }

        self.configuration = configuration
        self.isScrollDisabled = isScrollDisabled
        self.content = content()

        if let binding = currentSection {
            self._currentSection = binding
            self.usesExternalBinding = true
        } else {
            self._currentSection = .constant(0)
            self.usesExternalBinding = false
        }

        if let binding = scrollProgress {
            self._scrollProgress = binding
            self.usesScrollProgressBinding = true
        } else {
            self._scrollProgress = .constant(0)
            self.usesScrollProgressBinding = false
        }
    }

    // MARK: - UIViewControllerRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> DetentScrollViewController {
        let controller = DetentScrollViewController()

        // Determine initial heights
        let initialHeights: [CGFloat]
        if let fixed = fixedSectionHeights {
            initialHeights = fixed
        } else if let count = sectionCount {
            // Dynamic mode: use coordinator's measured heights or defaults
            initialHeights = context.coordinator.heightCoordinator?.measuredHeights
                ?? Array(repeating: 800, count: count)
        } else {
            initialHeights = []
        }

        // Set configuration
        controller.sectionHeights = initialHeights
        controller.sectionSnapInsets = sectionSnapInsets
        controller.configuration = configuration
        controller.isScrollDisabled = isScrollDisabled

        // Wire up drag handler to controller
        context.coordinator.dragHandler.controller = controller

        // Store controller reference in coordinator for height updates
        context.coordinator.controller = controller

        // Set up height coordinator callback
        context.coordinator.heightCoordinator?.onHeightsChanged = { [weak controller] heights in
            controller?.updateSectionHeights(heights)
        }

        // Build content with environment and preference handling
        let contentWithEnvironment: AnyView
        if usesDynamicHeights {
            contentWithEnvironment = AnyView(
                content
                    .environment(\.detentScrollDragHandler, context.coordinator.dragHandler)
                    .onPreferenceChange(SectionHeightPreferenceKey.self) { heights in
                        context.coordinator.heightCoordinator?.receiveHeights(heights)
                    }
            )
        } else {
            contentWithEnvironment = AnyView(
                content
                    .environment(\.detentScrollDragHandler, context.coordinator.dragHandler)
            )
        }
        controller.setContent(contentWithEnvironment)

        // Set callback for section changes
        controller.onSectionChanged = { [weak coordinator = context.coordinator] section in
            coordinator?.sectionChanged(section)
        }

        // Set callback for scroll progress (scroll-driven animations)
        controller.onScrollProgress = { [weak coordinator = context.coordinator] progress in
            coordinator?.scrollProgressChanged(progress)
        }

        return controller
    }

    public func updateUIViewController(_ controller: DetentScrollViewController, context: Context) {
        // Update configuration
        controller.sectionSnapInsets = sectionSnapInsets
        controller.configuration = configuration
        controller.isScrollDisabled = isScrollDisabled

        // Ensure drag handler has current controller reference
        context.coordinator.dragHandler.controller = controller
        context.coordinator.controller = controller

        // Handle height updates based on mode
        if let fixed = fixedSectionHeights {
            // Fixed mode: directly set heights
            if controller.sectionHeights != fixed {
                controller.updateSectionHeights(fixed)
            }
        } else if let heightCoordinator = context.coordinator.heightCoordinator {
            // Dynamic mode: manage deferral based on animation state
            let wasDeferred = heightCoordinator.shouldDeferUpdates
            heightCoordinator.shouldDeferUpdates = controller.isAnimating

            // Flush pending updates when animation completes
            if wasDeferred && !controller.isAnimating {
                heightCoordinator.flushPendingUpdates()
            }

            // Sync measured heights to controller if different
            let measured = heightCoordinator.measuredHeights
            if controller.sectionHeights != measured {
                controller.updateSectionHeights(measured)
            }
        }

        // Build content with environment and preference handling
        let contentWithEnvironment: AnyView
        if usesDynamicHeights {
            contentWithEnvironment = AnyView(
                content
                    .environment(\.detentScrollDragHandler, context.coordinator.dragHandler)
                    .onPreferenceChange(SectionHeightPreferenceKey.self) { heights in
                        context.coordinator.heightCoordinator?.receiveHeights(heights)
                    }
            )
        } else {
            contentWithEnvironment = AnyView(
                content
                    .environment(\.detentScrollDragHandler, context.coordinator.dragHandler)
            )
        }
        controller.setContent(contentWithEnvironment)

        // Handle programmatic section changes from binding
        // Don't trigger during animations to avoid feedback loops with rapid swiping
        if usesExternalBinding && controller.currentSection != currentSection && !controller.isAnimating {
            controller.scrollToSection(currentSection, animated: true)
        }
    }

    // MARK: - Coordinator

    public class Coordinator {
        var parent: DetentScrollContainer
        let dragHandler = DetentScrollDragHandler()
        var heightCoordinator: SectionHeightCoordinator?
        weak var controller: DetentScrollViewController?

        init(_ parent: DetentScrollContainer) {
            self.parent = parent

            // Create height coordinator for dynamic mode
            if let count = parent.sectionCount {
                self.heightCoordinator = SectionHeightCoordinator(sectionCount: count)
            }
        }

        func sectionChanged(_ section: Int) {
            if parent.usesExternalBinding {
                parent.currentSection = section
            }
        }

        func scrollProgressChanged(_ progress: CGFloat) {
            if parent.usesScrollProgressBinding {
                parent.scrollProgress = progress
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DetentScrollContainer(
        sectionHeights: [800, 600, 800],
        sectionSnapInsets: [0, 100, 0]
    ) {
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
