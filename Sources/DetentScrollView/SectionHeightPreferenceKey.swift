//
//  SectionHeightPreferenceKey.swift
//  DetentScrollView
//
//  PreferenceKey for sections to report their measured heights.
//

import SwiftUI

/// PreferenceKey for reporting individual section heights from DetentSection to DetentScrollContainer.
///
/// Each section reports its index and measured height. The container collects all reports
/// and updates the scroll view controller with the new heights.
struct SectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
