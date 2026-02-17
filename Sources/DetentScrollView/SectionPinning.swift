//
//  SectionPinning.swift
//  DetentScrollView
//
//  Defines pinning behavior for sections within a detent scroll view.
//

import SwiftUI

/// Pinning behavior for a section within a DetentScrollContainer.
///
/// Controls whether a section stays fixed at an edge or scrolls normally.
///
/// ## Current Support
/// - `.none` — default, section scrolls with content
/// - `.fixed(.top)` — section is pinned at the top edge, never scrolls
///
/// ## Future
/// - `.sticky` — section scrolls normally until reaching an edge, then pins
///   during a specified section range
public enum SectionPinning: Sendable {
    /// Section scrolls normally with content (default).
    case none

    /// Section is fixed at the specified edge and never scrolls.
    /// The scroll content is positioned below (for `.top`) or above (for `.bottom`) the fixed section.
    case fixed(Edge)

    // Future:
    // case sticky(Edge, during: ClosedRange<Int>)
}
