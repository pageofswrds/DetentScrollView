import XCTest
import SwiftUI
@testable import DetentScrollView

final class DetentScrollViewTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = DetentScrollConfiguration.default
        XCTAssertEqual(config.threshold, 120)
        XCTAssertEqual(config.resistanceCoefficient, 0.55)
    }

    func testCustomConfiguration() {
        let config = DetentScrollConfiguration(threshold: 200, resistanceCoefficient: 0.8)
        XCTAssertEqual(config.threshold, 200)
        XCTAssertEqual(config.resistanceCoefficient, 0.8)
    }

    func testViewInstantiation() {
        // Verify the view can be created without errors
        let _ = DetentScrollView(sectionHeights: [800, 600]) {
            VStack {
                Color.blue.frame(height: 800)
                Color.green.frame(height: 600)
            }
        }
    }

    func testViewWithConfiguration() {
        let config = DetentScrollConfiguration(threshold: 150, resistanceCoefficient: 0.6)
        let _ = DetentScrollView(
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
}
