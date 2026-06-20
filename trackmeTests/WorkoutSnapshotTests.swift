import XCTest
@testable import trackme

final class WorkoutSnapshotTests: XCTestCase {
    func testDistanceMustBeMeaningfulToSave() {
        XCTAssertFalse(snapshot(distance: 0).hasMeaningfulDistance)
        XCTAssertFalse(snapshot(distance: 12).hasMeaningfulDistance)
        XCTAssertTrue(snapshot(distance: 25).hasMeaningfulDistance)
    }

    func testAveragePaceUsesMovingDuration() {
        XCTAssertEqual(snapshot(duration: 600, distance: 1_609.344).averagePace, 600, accuracy: 0.001)
    }

    private func snapshot(
        duration: TimeInterval = 60,
        distance: Double = 100
    ) -> WorkoutSnapshot {
        WorkoutSnapshot(
            activity: .walk,
            startDate: .now,
            endDate: .now.addingTimeInterval(duration),
            duration: duration,
            distance: distance,
            elevationGain: 2,
            route: [],
            pauses: []
        )
    }
}
