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

    func testSingleSection() {
        let _ = DetentScrollView(sectionHeights: [800]) {
            Color.blue.frame(height: 800)
        }
    }

    // MARK: - Snap Insets Normalization Tests

    func testSnapInsetsNilDefaultsToZeros() {
        // When nil, should create array of zeros matching section count
        let _ = DetentScrollView(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: nil
        ) {
            Color.red
        }
        // View instantiation succeeds - internal array is padded
    }

    func testSnapInsetsShorterThanHeights() {
        // When fewer insets than heights, should pad with zeros
        let _ = DetentScrollView(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: [0, 50]  // Missing third inset
        ) {
            Color.red
        }
    }

    func testSnapInsetsLongerThanHeights() {
        // When more insets than heights, should truncate
        let _ = DetentScrollView(
            sectionHeights: [400, 400],
            sectionSnapInsets: [0, 50, 100, 150]  // Too many insets
        ) {
            Color.red
        }
    }

    func testEmptySnapInsets() {
        // Empty array should be padded to match heights
        let _ = DetentScrollView(
            sectionHeights: [400, 400, 400],
            sectionSnapInsets: []
        ) {
            Color.red
        }
    }
}

// MARK: - Physics Tests

final class DetentScrollPhysicsTests: XCTestCase {

    // MARK: - Rubber Band Tests

    func testRubberBandZeroOffset() {
        let result = DetentScrollPhysics.rubberBand(offset: 0, limit: 100, coefficient: 0.55)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func testRubberBandPositiveOffset() {
        let result = DetentScrollPhysics.rubberBand(offset: 100, limit: 100, coefficient: 0.55)
        // Should be less than limit but greater than 0
        XCTAssertGreaterThan(result, 0)
        XCTAssertLessThan(result, 100)
    }

    func testRubberBandNegativeOffset() {
        let result = DetentScrollPhysics.rubberBand(offset: -100, limit: 100, coefficient: 0.55)
        // Should preserve sign
        XCTAssertLessThan(result, 0)
        XCTAssertGreaterThan(result, -100)
    }

    func testRubberBandSymmetry() {
        let positive = DetentScrollPhysics.rubberBand(offset: 50, limit: 100, coefficient: 0.55)
        let negative = DetentScrollPhysics.rubberBand(offset: -50, limit: 100, coefficient: 0.55)
        XCTAssertEqual(positive, -negative, accuracy: 0.001)
    }

    func testRubberBandAsymptoticLimit() {
        // Very large offset should approach but never exceed limit
        let result = DetentScrollPhysics.rubberBand(offset: 10000, limit: 100, coefficient: 0.55)
        XCTAssertLessThan(result, 100)
        XCTAssertGreaterThan(result, 90)  // Should be close to limit
    }

    func testRubberBandHigherCoefficientLessResistance() {
        let lowCoeff = DetentScrollPhysics.rubberBand(offset: 100, limit: 100, coefficient: 0.3)
        let highCoeff = DetentScrollPhysics.rubberBand(offset: 100, limit: 100, coefficient: 0.8)
        // Higher coefficient = less resistance = larger visual offset (approaches limit faster)
        XCTAssertGreaterThan(highCoeff, lowCoeff)
    }

    func testRubberBandMonotonicallyIncreasing() {
        // Larger offsets should always produce larger (or equal) visual offsets
        var previousResult: CGFloat = 0
        for offset in stride(from: 0.0, through: 500.0, by: 50.0) {
            let result = DetentScrollPhysics.rubberBand(offset: CGFloat(offset), limit: 100, coefficient: 0.55)
            XCTAssertGreaterThanOrEqual(result, previousResult)
            previousResult = result
        }
    }

    // MARK: - Spring Force Tests

    func testSpringForceAtRest() {
        // At boundary with no velocity = no force
        let force = DetentScrollPhysics.springForce(
            displacement: 0,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        XCTAssertEqual(force, 0, accuracy: 0.001)
    }

    func testSpringForcePositiveDisplacement() {
        // Past boundary = force pushes back (negative)
        let force = DetentScrollPhysics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        XCTAssertLessThan(force, 0)
    }

    func testSpringForceNegativeDisplacement() {
        // Before boundary = force pushes forward (positive)
        let force = DetentScrollPhysics.springForce(
            displacement: -10,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        XCTAssertGreaterThan(force, 0)
    }

    func testSpringForceDampingReducesVelocity() {
        // Moving away from boundary = damping opposes motion
        let forceStill = DetentScrollPhysics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 200,
            damping: 30
        )
        let forceMoving = DetentScrollPhysics.springForce(
            displacement: 10,
            velocity: 100,  // Moving away from boundary
            stiffness: 200,
            damping: 30
        )
        // With positive velocity (moving away), force should be more negative
        XCTAssertLessThan(forceMoving, forceStill)
    }

    func testSpringForceHigherStiffnessStrongerForce() {
        let lowStiffness = DetentScrollPhysics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 100,
            damping: 30
        )
        let highStiffness = DetentScrollPhysics.springForce(
            displacement: 10,
            velocity: 0,
            stiffness: 300,
            damping: 30
        )
        XCTAssertLessThan(highStiffness, lowStiffness)  // More negative = stronger
    }

    // MARK: - Friction Tests

    func testFrictionReducesVelocity() {
        let initial: CGFloat = 100
        let result = DetentScrollPhysics.applyFriction(velocity: initial, friction: 0.95)
        XCTAssertEqual(result, 95, accuracy: 0.001)
    }

    func testFrictionZeroVelocity() {
        let result = DetentScrollPhysics.applyFriction(velocity: 0, friction: 0.95)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func testFrictionNegativeVelocity() {
        let result = DetentScrollPhysics.applyFriction(velocity: -100, friction: 0.95)
        XCTAssertEqual(result, -95, accuracy: 0.001)
    }

    func testFrictionDecayOverTime() {
        // After 60 frames at 0.95 friction, velocity should be ~5% of original
        var velocity: CGFloat = 100
        for _ in 0..<60 {
            velocity = DetentScrollPhysics.applyFriction(velocity: velocity, friction: 0.95)
        }
        XCTAssertLessThan(velocity, 6)  // Should be around 4.6
        XCTAssertGreaterThan(velocity, 4)
    }

    // MARK: - Integration Tests

    func testIntegratePositiveVelocity() {
        let result = DetentScrollPhysics.integrate(
            position: 100,
            velocity: 50,
            deltaTime: 1.0 / 60.0
        )
        let expected = 100 + 50 * (1.0 / 60.0)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testIntegrateNegativeVelocity() {
        let result = DetentScrollPhysics.integrate(
            position: 100,
            velocity: -50,
            deltaTime: 1.0 / 60.0
        )
        let expected = 100 - 50 * (1.0 / 60.0)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func testIntegrateZeroVelocity() {
        let result = DetentScrollPhysics.integrate(
            position: 100,
            velocity: 0,
            deltaTime: 1.0 / 60.0
        )
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    func testIntegrateZeroDeltaTime() {
        let result = DetentScrollPhysics.integrate(
            position: 100,
            velocity: 1000,
            deltaTime: 0
        )
        XCTAssertEqual(result, 100, accuracy: 0.001)
    }

    // MARK: - Combined Physics Simulation Tests

    func testMomentumDecaySimulation() {
        // Simulate momentum decay over 1 second (60 frames at 60fps)
        var position: CGFloat = 0
        var velocity: CGFloat = 500
        let friction: CGFloat = 0.95
        let frameTime: CGFloat = 1.0 / 60.0

        for _ in 0..<60 {
            position = DetentScrollPhysics.integrate(
                position: position,
                velocity: velocity,
                deltaTime: frameTime
            )
            velocity = DetentScrollPhysics.applyFriction(velocity: velocity, friction: friction)
        }

        // Position should have moved significantly
        XCTAssertGreaterThan(position, 100)
        // Velocity should be nearly stopped
        XCTAssertLessThan(abs(velocity), 30)
    }

    func testBounceSimulation() {
        // Simulate bouncing back from overscroll
        var position: CGFloat = 50  // 50pt past boundary
        var velocity: CGFloat = 0
        let stiffness: CGFloat = 200
        let damping: CGFloat = 30
        let frameTime: CGFloat = 1.0 / 60.0

        // Run simulation until settled
        for _ in 0..<120 {  // 2 seconds
            let force = DetentScrollPhysics.springForce(
                displacement: position,
                velocity: velocity,
                stiffness: stiffness,
                damping: damping
            )
            velocity += force * frameTime
            position = DetentScrollPhysics.integrate(
                position: position,
                velocity: velocity,
                deltaTime: frameTime
            )
        }

        // Should have returned close to boundary (0)
        XCTAssertLessThan(abs(position), 1)
        XCTAssertLessThan(abs(velocity), 1)
    }
}
