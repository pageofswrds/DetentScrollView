//
//  DetentScrollConfiguration.swift
//  DetentScrollView
//
//  Configuration options for detent scroll view behavior.
//

import Foundation

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
