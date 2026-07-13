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
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore()
        )
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

    func testStationaryIndoorDriftDoesNotAccumulateDistance() {
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

        let locations = [
            location(
                latitude: 41,
                horizontalAccuracy: 10,
                timestamp: sessionStart.addingTimeInterval(1)
            ),
            location(
                latitude: 41.000_25,
                horizontalAccuracy: 10,
                timestamp: sessionStart.addingTimeInterval(13)
            ),
            location(
                latitude: 40.999_75,
                horizontalAccuracy: 10,
                timestamp: sessionStart.addingTimeInterval(25)
            )
        ]

        tracker.locationManager(CLLocationManager(), didUpdateLocations: locations)

        XCTAssertEqual(tracker.distance, 0, accuracy: 0.001)
        XCTAssertEqual(tracker.route.count, 1)
        XCTAssertTrue(tracker.route[0].startsNewSegment)
        XCTAssertEqual(tracker.gpsStatus, .ready)
    }

    func testTooShortWorkoutCanBeDetectedWithoutStopping() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager)
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart
        tracker.distance = 12

        XCTAssertFalse(tracker.hasMeaningfulWorkout)
        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertNotNil(tracker.startDate)
    }

    func testDiscardStopsAndClearsActiveWorkout() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        let draftStore = InMemoryActiveWorkoutDraftStore()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager, activeDraftStore: draftStore)
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart
        tracker.elapsed = 30
        tracker.distance = 12
        tracker.errorMessage = "Temporary"
        tracker.route = [RoutePoint(location: location(latitude: 41, timestamp: sessionStart), startsNewSegment: true)]

        tracker.saveActiveDraft()
        tracker.discard()

        XCTAssertEqual(tracker.state, .idle)
        XCTAssertNil(tracker.startDate)
        XCTAssertEqual(tracker.elapsed, 0)
        XCTAssertEqual(tracker.distance, 0)
        XCTAssertTrue(tracker.route.isEmpty)
        XCTAssertNil(tracker.errorMessage)
        XCTAssertNil(draftStore.draft)
        XCTAssertTrue(draftStore.didClear)
        XCTAssertEqual(manager.stopUpdatingLocationCalls, 1)
    }

    func testActiveWorkoutDraftPersistsLocationProgress() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        let draftStore = InMemoryActiveWorkoutDraftStore()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager, activeDraftStore: draftStore)
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart

        let first = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(1))
        let second = location(latitude: 41.000_2, timestamp: sessionStart.addingTimeInterval(15))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [first, second])

        let draft = draftStore.draft
        XCTAssertEqual(draft?.state, .tracking)
        XCTAssertEqual(draft?.route.count, 2)
        XCTAssertEqual(draft?.distance ?? 0, tracker.distance, accuracy: 0.001)
        XCTAssertEqual(draft?.lastAcceptedLocation?.latitude, second.coordinate.latitude)
    }

    func testRestoresActiveWorkoutDraftAndRestartsBackgroundUpdates() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        let motionActivity = SignalTestMotionActivityClient()
        let draftStore = InMemoryActiveWorkoutDraftStore()
        let lastPoint = RoutePoint(
            location: location(latitude: 41.000_2, timestamp: sessionStart.addingTimeInterval(60)),
            startsNewSegment: false
        )
        draftStore.draft = ActiveWorkoutDraft(
            state: .tracking,
            activity: .walk,
            startDate: sessionStart,
            pausedAt: nil,
            pausedDuration: 0,
            pauses: [],
            startsNewSegment: false,
            elapsed: 60,
            distance: 42,
            route: [lastPoint],
            lastAcceptedLocation: lastPoint,
            lastReadyLocation: lastPoint,
            lastRawLocationUpdateAt: sessionStart.addingTimeInterval(60)
        )
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: draftStore,
            motionActivity: motionActivity
        )
        tracker.authorizationStatus = .authorizedWhenInUse

        let restored = tracker.restoreActiveWorkoutIfAvailable(now: sessionStart.addingTimeInterval(120))

        XCTAssertTrue(restored)
        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertEqual(tracker.activity, .walk)
        XCTAssertEqual(tracker.distance, 42)
        XCTAssertEqual(tracker.route.count, 1)
        XCTAssertEqual(tracker.route.first?.latitude, lastPoint.latitude)
        XCTAssertEqual(tracker.route.first?.longitude, lastPoint.longitude)
        XCTAssertEqual(tracker.elapsed, 120, accuracy: 0.001)
        XCTAssertEqual(manager.startUpdatingLocationCalls, 1)
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        XCTAssertEqual(motionActivity.startCalls, 1)

        tracker.discard()
        XCTAssertEqual(motionActivity.stopCalls, 1)
    }

    func testRestoredStaleWorkoutStartsNewRouteSegmentWithoutGuessingDistance() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = SignalTestLocationManager()
        let motionActivity = SignalTestMotionActivityClient(state: .moving)
        let draftStore = InMemoryActiveWorkoutDraftStore()
        let lastPoint = RoutePoint(
            location: location(latitude: 41, timestamp: sessionStart.addingTimeInterval(10)),
            startsNewSegment: true
        )
        draftStore.draft = ActiveWorkoutDraft(
            state: .tracking,
            activity: .walk,
            startDate: sessionStart,
            pausedAt: nil,
            pausedDuration: 0,
            pauses: [],
            startsNewSegment: false,
            elapsed: 10,
            distance: 42,
            route: [lastPoint],
            lastAcceptedLocation: lastPoint,
            lastReadyLocation: lastPoint,
            lastRawLocationUpdateAt: sessionStart.addingTimeInterval(10)
        )
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: draftStore,
            motionActivity: motionActivity
        )
        tracker.authorizationStatus = .authorizedWhenInUse

        tracker.restoreActiveWorkoutIfAvailable(now: sessionStart.addingTimeInterval(90))
        let resumedPoint = location(latitude: 41.01, timestamp: sessionStart.addingTimeInterval(95))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [resumedPoint])

        XCTAssertEqual(tracker.distance, 42, accuracy: 0.001)
        XCTAssertEqual(tracker.route.count, 2)
        XCTAssertTrue(tracker.route[1].startsNewSegment)

        tracker.discard()
    }

    private func location(
        latitude: Double,
        horizontalAccuracy: CLLocationAccuracy = 5,
        speed: CLLocationSpeed = 1.2,
        speedAccuracy: CLLocationSpeedAccuracy = 0.2,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -87),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 5,
            course: -1,
            courseAccuracy: -1,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }
}

extension LocationTrackerSignalTests {
    func testMotionActivityFollowsWorkoutLifecycle() {
        let manager = SignalTestLocationManager()
        let motionActivity = SignalTestMotionActivityClient()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: motionActivity
        )
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.gpsStatus = .ready
        tracker.lastReadyLocation = location(latitude: 41, timestamp: .now)

        tracker.start()
        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertEqual(motionActivity.startCalls, 1)

        tracker.pause()
        XCTAssertEqual(tracker.state, .paused)
        XCTAssertEqual(motionActivity.stopCalls, 1)

        tracker.resume()
        XCTAssertEqual(tracker.state, .tracking)
        XCTAssertEqual(motionActivity.startCalls, 2)

        tracker.discard()
        XCTAssertEqual(motionActivity.stopCalls, 2)
    }
}

@MainActor
final class SignalTestLocationManager: LocationManagerClient {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    weak var delegate: CLLocationManagerDelegate?
    var activityType: CLActivityType = .other
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var startUpdatingLocationCalls = 0
    var stopUpdatingLocationCalls = 0

    func requestWhenInUseAuthorization() {}
    func startUpdatingLocation() {
        startUpdatingLocationCalls += 1
    }
    func stopUpdatingLocation() {
        stopUpdatingLocationCalls += 1
    }
}

final class InMemoryActiveWorkoutDraftStore: ActiveWorkoutDraftStoring {
    var draft: ActiveWorkoutDraft?
    var didClear = false

    func load() -> ActiveWorkoutDraft? {
        draft
    }

    func save(_ draft: ActiveWorkoutDraft) {
        self.draft = draft
        didClear = false
    }

    func clear() {
        draft = nil
        didClear = true
    }
}

final class SignalTestMotionActivityClient: MotionActivityClient {
    var state: MotionState
    var startCalls = 0
    var stopCalls = 0

    init(state: MotionState = .unknown) {
        self.state = state
    }

    func start() {
        startCalls += 1
    }

    func stop() {
        stopCalls += 1
    }

    func state(at date: Date) -> MotionState {
        state
    }
}
