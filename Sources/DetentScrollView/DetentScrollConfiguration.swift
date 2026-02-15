//
//  DetentScrollConfiguration.swift
//  DetentScrollView
//
//  Configuration options for detent scroll view behavior.
//

import Foundation

/// Configuration options for DetentScrollView behavior.
public struct DetentScrollConfiguration {
    /// Drag distance required to trigger a section transition (default: 120pt).
    /// Also scales the rubber-band limit (limit = threshold * 2).
    ///
    /// **Tuning resistance at the detent boundary:**
    /// - Increase `threshold` → user must drag further to break through
    /// - Decrease `resistanceCoefficient` → less visual movement per unit of drag (feels stiffer)
    /// - Both together produce a "heavier" barrier feel
    public var threshold: CGFloat

    /// Rubber-band coefficient — higher values = less resistance (more visual movement).
    /// Range 0.0–1.0. At 0.3 the barrier feels stiff; at 0.7 it feels loose. (default: 0.55)
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
