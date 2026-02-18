//
//  StickyHeader.swift
//  DetentScrollView
//
//  A header that pins at the top of the viewport during specific sections.
//

import SwiftUI

/// A header that pins at the top of the viewport during specific content sections,
/// then scrolls away naturally when leaving those sections.
///
/// Sticky headers are rendered as independent UIView overlays positioned by the
/// controller. Multiple sticky headers stack in declaration order.
///
/// ## Usage
///
/// ```swift
/// DetentScrollContainer(
///     sectionHeights: [800, 600, 400],
///     stickyHeaders: [
///         StickyHeader(during: 0...0) { ToolbarView() },
///         StickyHeader(during: 0...1) { NavigationView() }
///     ]
/// ) {
///     // content sections
/// }
/// ```
public struct StickyHeader {
    /// The range of content section indices during which this header is pinned.
    public let during: ClosedRange<Int>

    /// The type-erased SwiftUI content for this header.
    let content: AnyView

    /// Creates a sticky header that pins during the specified section range.
    ///
    /// - Parameters:
    ///   - during: The content section indices during which this header stays pinned.
    ///     When the current section leaves this range, the header scrolls away.
    ///   - content: The SwiftUI view to display as the sticky header.
    public init<Content: View>(
        during: ClosedRange<Int>,
        @ViewBuilder content: () -> Content
    ) {
        precondition(during.lowerBound >= 0, "StickyHeader 'during' range must start at 0 or greater")
        self.during = during
        self.content = AnyView(content())
    }
}
