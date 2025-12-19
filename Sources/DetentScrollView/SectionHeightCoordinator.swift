//
//  SectionHeightCoordinator.swift
//  DetentScrollView
//
//  Coordinates section height measurements and applies them safely,
//  with deferral during animations to prevent visual glitches.
//

import SwiftUI

/// Coordinates section height measurements and applies them to the scroll view controller.
///
/// This class handles:
/// - Collecting height measurements from DetentSection views
/// - Deferring updates during animations to prevent visual jumps
/// - Filtering out insignificant height changes (< 1pt) to avoid layout thrashing
/// - Flushing pending updates when animations complete
public class SectionHeightCoordinator: ObservableObject {

    // MARK: - Published State

    /// Current measured heights for each section.
    @Published public private(set) var measuredHeights: [CGFloat]

    // MARK: - Internal State

    /// Pending height updates that were deferred during animation.
    private var pendingHeights: [Int: CGFloat] = [:]

    /// Minimum height change to consider significant (avoids micro-updates).
    private let changeThreshold: CGFloat = 1.0

    /// Maximum time to defer updates before forcing a flush.
    /// Prevents indefinite blocking if animation state gets stuck.
    private let maxDeferralDuration: TimeInterval = 0.5

    /// When deferral started (nil if not deferring).
    private var deferralStartTime: Date?

    /// Whether updates should be deferred (set true when controller is animating).
    public var shouldDeferUpdates: Bool = false {
        didSet {
            if shouldDeferUpdates && !oldValue {
                // Started deferring - record start time
                deferralStartTime = Date()
            } else if !shouldDeferUpdates && oldValue {
                // Stopped deferring - clear start time
                deferralStartTime = nil
            }
        }
    }

    /// Callback invoked when heights change and should be applied.
    public var onHeightsChanged: (([CGFloat]) -> Void)?

    // MARK: - Initialization

    /// Creates a coordinator for the specified number of sections.
    ///
    /// - Parameters:
    ///   - sectionCount: The number of sections to track.
    ///   - defaultHeight: The initial height for each section before measurement (default: 800).
    public init(sectionCount: Int, defaultHeight: CGFloat = 800) {
        self.measuredHeights = Array(repeating: defaultHeight, count: sectionCount)
    }

    // MARK: - Height Updates

    /// Updates the height for a specific section.
    ///
    /// If `shouldDeferUpdates` is true, the update is stored in `pendingHeights`
    /// and applied later via `flushPendingUpdates()`.
    ///
    /// - Parameters:
    ///   - section: The section index.
    ///   - height: The measured height.
    public func updateHeight(for section: Int, height: CGFloat) {
        guard section >= 0 && section < measuredHeights.count else { return }

        // Check if change is significant
        let currentHeight = measuredHeights[section]
        guard abs(height - currentHeight) > changeThreshold else { return }

        // Check for deferral timeout - if we've been deferring too long, force flush
        // This prevents indefinite blocking if animation state gets stuck
        if shouldDeferUpdates, let startTime = deferralStartTime {
            if Date().timeIntervalSince(startTime) > maxDeferralDuration {
                // Deferral timed out - flush pending updates and apply this one directly
                flushPendingUpdates()
                shouldDeferUpdates = false
                applyHeight(section: section, height: height)
                return
            }
        }

        if shouldDeferUpdates {
            pendingHeights[section] = height
        } else {
            applyHeight(section: section, height: height)
        }
    }

    /// Applies all pending height updates that were deferred during animation.
    ///
    /// Call this when `shouldDeferUpdates` becomes false (animation completed).
    public func flushPendingUpdates() {
        guard !pendingHeights.isEmpty else { return }

        for (section, height) in pendingHeights {
            measuredHeights[section] = height
        }
        pendingHeights.removeAll()

        onHeightsChanged?(measuredHeights)
    }

    /// Receives a batch of height measurements from PreferenceKey.
    ///
    /// - Parameter heights: Dictionary mapping section index to measured height.
    public func receiveHeights(_ heights: [Int: CGFloat]) {
        for (section, height) in heights {
            updateHeight(for: section, height: height)
        }
    }

    // MARK: - Private

    private func applyHeight(section: Int, height: CGFloat) {
        measuredHeights[section] = height
        onHeightsChanged?(measuredHeights)
    }
}
