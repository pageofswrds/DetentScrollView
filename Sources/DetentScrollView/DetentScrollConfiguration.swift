//
//  DetentScrollConfiguration.swift
//  DetentScrollView
//
//  Configuration options for detent scroll view behavior.
//

import Foundation

/// Controls how the scroll view handles section boundaries (detents).
public enum DetentCrossingMode: Sendable {
    /// Cross mid-drag when threshold exceeded. Haptic feedback fires at the crossing
    /// point and visual position is preserved seamlessly. (Default)
    case breakThrough

    /// Only cross on finger release. Shows rubber-band resistance during drag,
    /// then animates to the next section or snaps back based on distance/velocity.
    case rigid

    /// No detent boundary. Scroll flows seamlessly through section boundaries
    /// with no resistance or threshold.
    case free
}

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

    /// How the scroll view handles section boundaries.
    public var crossingMode: DetentCrossingMode

    /// Creates a configuration with the specified parameters.
    public init(
        threshold: CGFloat = 120,
        resistanceCoefficient: CGFloat = 0.55,
        minimumDragDistance: CGFloat = 10,
        crossingMode: DetentCrossingMode = .breakThrough
    ) {
        self.threshold = threshold
        self.resistanceCoefficient = resistanceCoefficient
        self.minimumDragDistance = minimumDragDistance
        self.crossingMode = crossingMode
    }

    /// Default configuration with standard threshold and resistance values.
    public static let `default` = DetentScrollConfiguration()
}
