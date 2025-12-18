//
//  DetentSection.swift
//  DetentScrollView
//
//  Wrapper view that measures section content and reports height via PreferenceKey.
//

import SwiftUI

/// Wraps section content and reports its measured height to the parent DetentScrollContainer.
///
/// Use this view to wrap each section when using dynamic height measurement:
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
/// The measured height is reported via `SectionHeightPreferenceKey` and collected
/// by the container to update the scroll view controller.
public struct DetentSection<Content: View>: View {
    /// The section index (0-based).
    let index: Int

    /// The section content.
    let content: Content

    /// Creates a detent section with the specified index and content.
    ///
    /// - Parameters:
    ///   - index: The section index (0-based). Must match the order in the container.
    ///   - content: The section content to display and measure.
    public init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    public var body: some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SectionHeightPreferenceKey.self,
                            value: [index: geometry.size.height]
                        )
                }
            )
    }
}
