import CoreMotion
import XCTest
@testable import trackme

final class MotionActivityTests: XCTestCase {
    func testWalkingTakesPriorityWhenMotionFlagsOverlap() {
        XCTAssertEqual(
            MotionState.classify(
                stationary: true,
                walking: true,
                running: false,
                confidence: .medium
            ),
            .moving
        )
    }

    func testStationaryRequiresReliableConfidence() {
        XCTAssertEqual(
            MotionState.classify(
                stationary: true,
                walking: false,
                running: false,
                confidence: .medium
            ),
            .stationary
        )
        XCTAssertEqual(
            MotionState.classify(
                stationary: true,
                walking: false,
                running: false,
                confidence: .low
            ),
            .unknown
        )
    }
}
