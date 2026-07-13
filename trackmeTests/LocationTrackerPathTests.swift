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
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [anchor])
        motionActivity.state = .moving
        let walking = location(latitude: 41.000_1, timestamp: sessionStart.addingTimeInterval(11))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [walking])

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

    func testSystemLocationResumeStartsANewDistanceSegment() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
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
        let resumed = location(latitude: 41.01, timestamp: sessionStart.addingTimeInterval(31))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [resumed])

        XCTAssertEqual(tracker.distance, 20, accuracy: 0.001)
        XCTAssertEqual(tracker.route.count, 2)
        XCTAssertTrue(tracker.route[1].startsNewSegment)
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
