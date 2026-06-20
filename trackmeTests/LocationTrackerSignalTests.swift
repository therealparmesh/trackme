import CoreLocation
import XCTest
@testable import trackme

@MainActor
final class LocationTrackerSignalTests: XCTestCase {
    func testPrepareForWorkoutDoesNotResetActiveTrackingState() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager)
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart
        tracker.elapsed = 30
        tracker.distance = 42
        tracker.route = [RoutePoint(location: location(latitude: 41, timestamp: sessionStart), startsNewSegment: true)]

        tracker.prepareForWorkout()

        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertEqual(tracker.elapsed, 30)
        XCTAssertEqual(tracker.distance, 42)
        XCTAssertEqual(tracker.route.count, 1)
        XCTAssertEqual(manager.startUpdatingLocationCalls, 0)
    }

    func testWeakSampleDoesNotBreakDistanceContinuity() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager)
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart

        let first = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(1))
        let second = location(latitude: 41.000_2, timestamp: sessionStart.addingTimeInterval(15))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [first, second])
        let distanceBeforeWeakSample = tracker.distance

        let weak = location(
            latitude: 41.000_25,
            horizontalAccuracy: 100,
            timestamp: sessionStart.addingTimeInterval(18)
        )
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [weak])

        XCTAssertEqual(tracker.gpsStatus, .weak)
        XCTAssertEqual(tracker.distance, distanceBeforeWeakSample, accuracy: 0.001)

        let third = location(latitude: 41.000_4, timestamp: sessionStart.addingTimeInterval(30))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [third])

        XCTAssertEqual(tracker.gpsStatus, .ready)
        XCTAssertGreaterThan(tracker.distance, distanceBeforeWeakSample)
        XCTAssertEqual(tracker.route.routeSegments.count, 1)
    }

    private func location(
        latitude: Double,
        horizontalAccuracy: CLLocationAccuracy = 5,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -87),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 5,
            course: -1,
            courseAccuracy: -1,
            speed: 1.2,
            speedAccuracy: 0.2,
            timestamp: timestamp
        )
    }
}

@MainActor
private final class SignalTestLocationManager: LocationManagerClient {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    weak var delegate: CLLocationManagerDelegate?
    var activityType: CLActivityType = .other
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var startUpdatingLocationCalls = 0

    func requestWhenInUseAuthorization() {}
    func startUpdatingLocation() {
        startUpdatingLocationCalls += 1
    }
    func stopUpdatingLocation() {}
}
