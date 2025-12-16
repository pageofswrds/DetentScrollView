//
//  DetentScrollContainer.swift
//  DetentScrollView
//
//  UIViewControllerRepresentable wrapper for DetentScrollViewController.
//  Provides a SwiftUI-friendly interface to the UIKit-based scroll view.
//

import SwiftUI

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

    /// Height of each section in points.
    public let sectionHeights: [CGFloat]

    /// How far from viewport top each section starts when snapped.
    public let sectionSnapInsets: [CGFloat]

    /// Configuration for threshold and resistance behavior.
    public let configuration: DetentScrollConfiguration

    /// External signal to disable scrolling (e.g., when content is zoomed).
    public let isScrollDisabled: Bool

    // MARK: - Bindings

    /// Binding to observe/control current section externally.
    @Binding private var currentSection: Int

    /// Whether external binding is being used.
    private let usesExternalBinding: Bool

    // MARK: - Content

    /// The SwiftUI content to display.
    public let content: Content

    // MARK: - Initializers

    /// Creates a detent scroll container with the specified sections and configuration.
    ///
    /// - Parameters:
    ///   - sectionHeights: Height of each section in points.
    ///   - sectionSnapInsets: Optional insets for each section (default: all zeros).
    ///   - configuration: Threshold and resistance configuration.
    ///   - currentSection: Optional binding to observe/control current section.
    ///   - isScrollDisabled: External signal to disable scrolling.
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
    }

    // MARK: - UIViewControllerRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> DetentScrollViewController {
        let controller = DetentScrollViewController()

        // Set configuration
        controller.sectionHeights = sectionHeights
        controller.sectionSnapInsets = sectionSnapInsets
        controller.configuration = configuration
        controller.isScrollDisabled = isScrollDisabled

        // Set content
        controller.setContent(content)

        // Set callback for section changes
        controller.onSectionChanged = { [weak coordinator = context.coordinator] section in
            coordinator?.sectionChanged(section)
        }

        return controller
    }

    public func updateUIViewController(_ controller: DetentScrollViewController, context: Context) {
        // Update configuration if changed
        controller.sectionHeights = sectionHeights
        controller.sectionSnapInsets = sectionSnapInsets
        controller.configuration = configuration
        controller.isScrollDisabled = isScrollDisabled

        // Update content
        controller.setContent(content)

        // Handle programmatic section changes from binding
        // Don't trigger during animations to avoid feedback loops with rapid swiping
        if usesExternalBinding && controller.currentSection != currentSection && !controller.isAnimating {
            controller.scrollToSection(currentSection, animated: true)
        }
    }

    // MARK: - Coordinator

    public class Coordinator {
        var parent: DetentScrollContainer

        init(_ parent: DetentScrollContainer) {
            self.parent = parent
        }

        func sectionChanged(_ section: Int) {
            if parent.usesExternalBinding {
                parent.currentSection = section
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
