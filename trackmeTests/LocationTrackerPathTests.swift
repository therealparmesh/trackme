import CoreLocation
import XCTest
@testable import trackme

@MainActor
final class LocationTrackerPathTests: XCTestCase {
    func testRecentReadyFixRecordsTheFirstLegFromTheStart() throws {
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(
            manager: manager, activeDraftStore: InMemoryActiveWorkoutDraftStore()
        )
        defer { tracker.discard() }
        let now = Date.now
        tracker.processLocationUpdates([location(latitude: 41, timestamp: now)], receivedAt: now)
        tracker.start()

        let start = try XCTUnwrap(tracker.startDate)
        let next = location(latitude: 41.000_1, timestamp: start.addingTimeInterval(8))
        tracker.processLocationUpdates([next], receivedAt: next.timestamp)

        XCTAssertEqual(tracker.route.first?.timestamp, start)
        XCTAssertEqual(tracker.route.count, 2)
        XCTAssertEqual(tracker.distance, 11.1, accuracy: 0.2)
    }

    func testManualResumeIgnoresLocationsCapturedDuringThePause() throws {
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore()
        )
        tracker.state = .paused
        tracker.startDate = .now.addingTimeInterval(-60)
        tracker.distance = 20
        tracker.route = [
            RoutePoint(
                location: location(latitude: 41, timestamp: .now.addingTimeInterval(-30)),
                startsNewSegment: true
            )
        ]

        tracker.resume()
        let resumedAt = try XCTUnwrap(tracker.routeAnchorNotBefore)
        let duringPause = location(latitude: 41.005, timestamp: resumedAt.addingTimeInterval(-1))
        let afterResume = location(latitude: 41.01, timestamp: resumedAt.addingTimeInterval(1))
        tracker.processLocationUpdates([duringPause, afterResume], receivedAt: afterResume.timestamp)

        XCTAssertEqual(tracker.distance, 20, accuracy: 0.001)
        XCTAssertEqual(tracker.route.count, 2)
        XCTAssertTrue(tracker.route[1].startsNewSegment)
        XCTAssertEqual(tracker.route[1].latitude, afterResume.coordinate.latitude)
        tracker.discard()
    }

    private func location(latitude: Double, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -87),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            courseAccuracy: -1,
            speed: 1.2,
            speedAccuracy: 0.2,
            timestamp: timestamp
        )
    }
}
