import XCTest
import SwiftUI
@testable import DetentScrollView

final class DetentScrollViewTests: XCTestCase {

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = DetentScrollConfiguration.default
        XCTAssertEqual(config.threshold, 120)
        XCTAssertEqual(config.resistanceCoefficient, 0.55)
        XCTAssertEqual(config.minimumDragDistance, 10)
    }

    func testCustomConfiguration() {
        let config = DetentScrollConfiguration(threshold: 200, resistanceCoefficient: 0.8)
        XCTAssertEqual(config.threshold, 200)
        XCTAssertEqual(config.resistanceCoefficient, 0.8)
        XCTAssertEqual(config.minimumDragDistance, 10)  // Uses default
    }

    func testCustomMinimumDragDistance() {
        let config = DetentScrollConfiguration(
            threshold: 120,
            resistanceCoefficient: 0.55,
            minimumDragDistance: 25
        )
        XCTAssertEqual(config.minimumDragDistance, 25)
    }

    // MARK: - View Instantiation Tests

    func testViewInstantiation() {
        let _ = DetentScrollContainer(sectionHeights: [800, 600]) {
            VStack {
                Color.blue.frame(height: 800)
                Color.green.frame(height: 600)
            }
        }
    }

    func testViewWithConfiguration() {
        let config = DetentScrollConfiguration(threshold: 150, resistanceCoefficient: 0.6)
        let _ = DetentScrollContainer(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: [0, 50, 0],
            configuration: config
        ) {
            VStack {
                Color.red.frame(height: 400)
                Color.green.frame(height: 400)
                Color.blue.frame(height: 400)
            }
        }
    }

    func testSingleSection() {
        let _ = DetentScrollContainer(sectionHeights: [800]) {
            Color.blue.frame(height: 800)
        }
    }

    // MARK: - Snap Insets Normalization Tests

    func testSnapInsetsNilDefaultsToZeros() {
        // When nil, should create array of zeros matching section count
        let _ = DetentScrollContainer(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: nil
        ) {
            Color.red
        }
        // View instantiation succeeds - internal array is padded
    }

    func testSnapInsetsShorterThanHeights() {
        // When fewer insets than heights, should pad with zeros
        let _ = DetentScrollContainer(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: [0, 50]  // Missing third inset
        ) {
            Color.red
        }
    }

    func testSnapInsetsLongerThanHeights() {
        // When more insets than heights, should truncate
        let _ = DetentScrollContainer(
            sectionHeights: [400, 400],
            sectionSnapInsets: [0, 50, 100, 150]  // Too many insets
        ) {
            Color.red
        }
    }

    func testEmptySnapInsets() {
        // Empty array should be padded to match heights
        let _ = DetentScrollContainer(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: []
        ) {
            Color.red
        }
    }

    // MARK: - SectionPinning Tests

    func testSectionPinningNone() {
        let pinning = SectionPinning.none
        if case .none = pinning {
            // Expected
        } else {
            XCTFail("Expected .none")
        }
    }

    func testSectionPinningFixedTop() {
        let pinning = SectionPinning.fixed(.top)
        if case .fixed(let edge) = pinning {
            XCTAssertEqual(edge, .top)
        } else {
            XCTFail("Expected .fixed(.top)")
        }
    }
}

// Note: Physics tests have been moved to Mercurial package.
// See Mercurial/Tests/MercurialTests/PhysicsTests.swift for comprehensive physics testing.
