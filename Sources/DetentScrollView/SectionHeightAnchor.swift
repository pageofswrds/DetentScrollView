//
//  SectionHeightAnchor.swift
//  DetentScrollView
//
//  Specifies how scroll position should be preserved when section heights change.
//

import Foundation

/// Specifies how scroll position should be preserved when section heights change.
///
/// When section heights change dynamically (e.g., content added/removed), the scroll
/// position needs to be adjusted to maintain a good user experience. This enum controls
/// that behavior.
///
/// ## Usage
///
/// ```swift
/// // Tab switching - anchor to section top (default)
/// controller.updateSectionHeights(newHeights)
///
/// // Card inserted above current view - preserve visible content
/// controller.updateSectionHeights(newHeights, anchor: .preserveVisibleContent(insertedAbove: cardHeight))
/// ```
public enum SectionHeightAnchor {
    /// Anchor to the top of the current section.
    ///
    /// Content changes cause the view to grow/shrink downward from the section's
    /// top edge. The scroll position within the section is preserved.
    ///
    /// Use for:
    /// - Tab switching within a section
    /// - Expanding/collapsing content in place
    /// - Any change where the top of the section should stay fixed
    case sectionTop

    /// Preserve the currently visible content by adjusting for insertions/removals.
    ///
    /// - Parameter insertedAbove: Height added (positive) or removed (negative) above
    ///   the current scroll position.
    ///
    /// Use for:
    /// - Adding/removing cards above the current view
    /// - Dynamic content loading that inserts above
    /// - Chat-style interfaces where new content appears above
    case preserveVisibleContent(insertedAbove: CGFloat)
}
