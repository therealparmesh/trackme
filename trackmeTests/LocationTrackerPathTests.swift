import CoreLocation
import XCTest
@testable import trackme

@MainActor
final class LocationTrackerPathTests: XCTestCase {
    func testWalkingAfterStationaryTrackingContinuesFromTheAccurateAnchor() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        let motionActivity = SignalTestMotionActivityClient(state: .stationary)
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: motionActivity
        )
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart

        let anchor = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(1))
        tracker.processLocationUpdates([anchor], receivedAt: anchor.timestamp)
        motionActivity.state = .moving
        let walking = location(latitude: 41.000_1, timestamp: sessionStart.addingTimeInterval(11))
        tracker.processLocationUpdates([walking], receivedAt: walking.timestamp)

        XCTAssertEqual(tracker.route.count, 2)
        XCTAssertGreaterThan(tracker.distance, 0)
        XCTAssertEqual(tracker.route.routeSegments.count, 1)
    }

    func testStationaryWorkoutDoesNotReportSignalLostWhenDistanceFilterSuppressesUpdates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        let motionActivity = SignalTestMotionActivityClient(state: .stationary)
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: motionActivity
        )
        tracker.state = .tracking
        tracker.gpsStatus = .ready
        tracker.lastRawLocationUpdateAt = now.addingTimeInterval(-30)
        tracker.lastAcceptedLocation = location(latitude: 41, timestamp: now.addingTimeInterval(-30))

        tracker.refreshSignalTimeout(now: now)

        XCTAssertEqual(tracker.gpsStatus, .ready)
        XCTAssertNotNil(tracker.lastAcceptedLocation)
    }

    func testUnknownMotionStillDetectsSilentSignalLoss() {
        let now = Date(timeIntervalSince1970: 1_000)
        let tracker = LocationTracker(
            manager: SignalTestLocationManager(),
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: SignalTestMotionActivityClient(state: .unknown)
        )
        tracker.state = .tracking
        tracker.gpsStatus = .ready
        tracker.lastRawLocationUpdateAt = now.addingTimeInterval(-30)

        tracker.refreshSignalTimeout(now: now)

        XCTAssertEqual(tracker.gpsStatus, .lost)
    }

    func testSystemLocationResumeStartsANewDistanceSegment() {
        let sessionStart = Date.now.addingTimeInterval(-60)
        let manager = SignalTestLocationManager()
        let motionActivity = SignalTestMotionActivityClient(state: .moving)
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: motionActivity
        )
        tracker.state = .tracking
        tracker.startDate = sessionStart
        let previous = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(1))
        tracker.lastAcceptedLocation = previous
        tracker.route = [RoutePoint(location: previous, startsNewSegment: true)]
        tracker.distance = 20

        tracker.locationManagerDidResumeLocationUpdates(CLLocationManager())
        let resumed = location(latitude: 41.01, timestamp: .now.addingTimeInterval(1))
        tracker.processLocationUpdates([resumed], receivedAt: resumed.timestamp)

        XCTAssertEqual(tracker.distance, 20, accuracy: 0.001)
        XCTAssertEqual(tracker.route.count, 2)
        XCTAssertTrue(tracker.route[1].startsNewSegment)
    }

    func testManualResumeIgnoresLocationsCapturedDuringThePause() throws {
        let tracker = LocationTracker(
            manager: SignalTestLocationManager(),
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: SignalTestMotionActivityClient(state: .moving)
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
