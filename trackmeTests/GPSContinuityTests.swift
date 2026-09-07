import CoreLocation
import XCTest
@testable import trackme

@MainActor
final class GPSContinuityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testProlongedInaccurateFixesDoNotBridgeRecovery() {
        for motionState in [MotionState.moving, .stationary, .unknown] {
            let tracker = tracker(motion: SignalTestMotionActivityClient(state: motionState))
            send(tracker, latitude: 41, seconds: 1)
            let distanceBeforeGap = tracker.distance
            for seconds in stride(from: 6, through: 136, by: 5) {
                send(tracker, latitude: 41.001, seconds: Double(seconds), accuracy: 100)
                tracker.refreshSignalTimeout(now: start.addingTimeInterval(Double(seconds)))
            }
            XCTAssertEqual(tracker.gpsStatus, .lost)
            send(tracker, latitude: 41.002, seconds: 141)

            XCTAssertEqual(tracker.distance, distanceBeforeGap, accuracy: 0.001)
            XCTAssertEqual(tracker.route.routeSegments.count, 2)
            XCTAssertEqual(tracker.gpsStatus, .ready)
        }
    }

    func testRecoveryBeforeNextMonitorTickStillBreaksGap() {
        let tracker = tracker()
        send(tracker, latitude: 41, seconds: 1)
        send(tracker, latitude: 41.000_1, seconds: 11)
        let distanceBeforeGap = tracker.distance
        for seconds in stride(from: 16, through: 31, by: 5) {
            tracker.refreshSignalTimeout(now: start.addingTimeInterval(Double(seconds)))
        }
        // Recovery arrives after the timeout but before the next timer tick at 36.
        send(tracker, latitude: 41.000_5, seconds: 35)

        XCTAssertEqual(tracker.distance, distanceBeforeGap, accuracy: 0.001)
        XCTAssertEqual(tracker.route.routeSegments.count, 2)
    }

    func testStartingToWalkAfterStationaryDoesNotImmediatelyLoseSignal() {
        let motion = SignalTestMotionActivityClient(state: .stationary)
        let tracker = tracker(motion: motion)
        send(tracker, latitude: 41, seconds: 1)
        tracker.refreshSignalTimeout(now: start.addingTimeInterval(60))
        XCTAssertEqual(tracker.gpsStatus, .ready)

        // Motion can report walking before the next five-meter GPS update.
        motion.state = .moving
        tracker.refreshSignalTimeout(now: start.addingTimeInterval(61))
        XCTAssertNotEqual(tracker.gpsStatus, .lost)
        XCTAssertNotNil(tracker.lastAcceptedLocation)
        send(tracker, latitude: 41.000_1, seconds: 66)

        XCTAssertGreaterThan(tracker.distance, 0)
        XCTAssertEqual(tracker.route.routeSegments.count, 1)
    }

    func testStationaryGraceStillExpiresIfMovementGetsNoGPS() {
        for resumedMotion in [MotionState.moving, .unknown] {
            let motion = SignalTestMotionActivityClient(state: .stationary)
            let tracker = tracker(motion: motion)
            send(tracker, latitude: 41, seconds: 1)
            tracker.refreshSignalTimeout(now: start.addingTimeInterval(60))
            motion.state = resumedMotion
            tracker.refreshSignalTimeout(now: start.addingTimeInterval(61))
            XCTAssertEqual(tracker.gpsStatus, .ready)
            tracker.refreshSignalTimeout(now: start.addingTimeInterval(81))

            XCTAssertEqual(tracker.gpsStatus, .lost)
            XCTAssertNil(tracker.lastAcceptedLocation)
        }
    }

    func testContinuousBackgroundBatchPreservesRoute() {
        let tracker = tracker()
        send(tracker, latitude: 41, seconds: 1)
        let batch = (1...6).map { index in
            location(latitude: 41 + Double(index) * 0.000_1, seconds: Double(index * 10 + 1))
        }
        tracker.processLocationUpdates(batch, receivedAt: start.addingTimeInterval(61))

        XCTAssertEqual(tracker.route.count, 7)
        XCTAssertEqual(tracker.route.routeSegments.count, 1)
        XCTAssertGreaterThan(tracker.distance, 60)
        XCTAssertEqual(tracker.gpsStatus, .ready)
    }

    func testGapInsideBackgroundBatchStartsNewSegment() {
        let tracker = tracker()
        let batch = [
            location(latitude: 41, seconds: 1),
            location(latitude: 41.000_1, seconds: 11),
            location(latitude: 41.002, seconds: 61),
            location(latitude: 41.002_1, seconds: 71)
        ]
        tracker.processLocationUpdates(batch, receivedAt: start.addingTimeInterval(71))

        XCTAssertEqual(tracker.route.count, 4)
        XCTAssertEqual(tracker.route.routeSegments.count, 2)
        XCTAssertEqual(tracker.distance, 22.21, accuracy: 0.1)
    }

    func testStationaryAccurateUpdatesKeepSignalAliveWithoutAddingDistance() {
        let motion = SignalTestMotionActivityClient(state: .stationary)
        let tracker = tracker(motion: motion)
        send(tracker, latitude: 41, seconds: 1)
        for seconds in stride(from: 6, through: 61, by: 5) {
            send(tracker, latitude: 41.000_01, seconds: Double(seconds), accuracy: 45)
        }
        tracker.refreshSignalTimeout(now: start.addingTimeInterval(100))

        XCTAssertNotEqual(tracker.gpsStatus, .lost)
        XCTAssertEqual(tracker.distance, 0)
        XCTAssertEqual(tracker.route.count, 1)
    }

    func testDuplicateAndOutOfOrderSamplesCannotRenewSignal() {
        let tracker = tracker()
        send(tracker, latitude: 41, seconds: 1)
        send(tracker, latitude: 41.000_1, seconds: 11)
        tracker.processLocationUpdates([
            location(latitude: 41.000_1, seconds: 11),
            location(latitude: 41.001, seconds: 5)
        ], receivedAt: start.addingTimeInterval(30))

        XCTAssertEqual(tracker.lastRawLocationUpdateAt, start.addingTimeInterval(11))
        XCTAssertEqual(tracker.route.count, 2)
        tracker.refreshSignalTimeout(now: start.addingTimeInterval(32))
        XCTAssertEqual(tracker.gpsStatus, .lost)
    }

    func testStaleContinuousBatchRecordsHistoryWithoutClaimingCurrentSignal() {
        let tracker = tracker()
        send(tracker, latitude: 41, seconds: 1)
        tracker.processLocationUpdates([
            location(latitude: 41.000_1, seconds: 11),
            location(latitude: 41.000_2, seconds: 21)
        ], receivedAt: start.addingTimeInterval(100))

        XCTAssertEqual(tracker.route.count, 3)
        XCTAssertGreaterThan(tracker.distance, 20)
        XCTAssertEqual(tracker.gpsStatus, .lost)
        XCTAssertNil(tracker.lastAcceptedLocation)
    }

    func testWeakFixesCannotKeepInitialAcquisitionAliveForever() {
        let tracker = tracker()
        for seconds in stride(from: 5, through: 30, by: 5) {
            send(tracker, latitude: 41, seconds: Double(seconds), accuracy: 100)
        }
        XCTAssertEqual(tracker.gpsStatus, .lost)
        XCTAssertTrue(tracker.route.isEmpty)
        send(tracker, latitude: 41, seconds: 31, accuracy: 45)
        XCTAssertTrue(tracker.route.isEmpty)
        send(tracker, latitude: 41, seconds: 35)
        XCTAssertEqual(tracker.route.count, 1)
        XCTAssertEqual(tracker.distance, 0)
    }

    func testUsableSignalTimestampSurvivesDraftRoundTrip() throws {
        let store = InMemoryActiveWorkoutDraftStore()
        let tracker = LocationTracker(manager: SignalTestLocationManager(), activeDraftStore: store)
        tracker.state = .tracking
        tracker.startDate = start
        send(tracker, latitude: 41, seconds: 1)
        send(tracker, latitude: 41, seconds: 10, accuracy: 100)
        let draft = try XCTUnwrap(store.draft)
        let restored = try JSONDecoder().decode(ActiveWorkoutDraft.self, from: JSONEncoder().encode(draft))

        XCTAssertEqual(restored.lastRawLocationUpdateAt, start.addingTimeInterval(10))
        XCTAssertEqual(restored.lastUsableLocationUpdateAt, start.addingTimeInterval(1))
    }

    func testLegacyDraftWithOnlyPoorRecentFixesRestoresWithNewAnchor() throws {
        let store = InMemoryActiveWorkoutDraftStore()
        let point = RoutePoint(location: location(latitude: 41, seconds: 1), startsNewSegment: true)
        let legacy = ActiveWorkoutDraft(
            state: .tracking, activity: .walk, startDate: start, pausedAt: nil,
            pausedDuration: 0, pauses: [], startsNewSegment: false, elapsed: 60,
            distance: 20, route: [point], lastAcceptedLocation: point, lastReadyLocation: point,
            lastRawLocationUpdateAt: start.addingTimeInterval(60)
        )
        let encoded = try JSONEncoder().encode(legacy)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["lastUsableLocationUpdateAt"])
        store.draft = try JSONDecoder().decode(ActiveWorkoutDraft.self, from: encoded)
        let tracker = LocationTracker(
            manager: SignalTestLocationManager(), activeDraftStore: store,
            motionActivity: SignalTestMotionActivityClient(state: .moving)
        )
        defer { tracker.discard() }
        XCTAssertTrue(tracker.restoreActiveWorkoutIfAvailable(now: start.addingTimeInterval(65)))
        send(tracker, latitude: 41.002, seconds: 66)

        XCTAssertEqual(tracker.distance, 20)
        XCTAssertEqual(tracker.route.routeSegments.count, 2)
    }

    private func tracker(
        motion: SignalTestMotionActivityClient = SignalTestMotionActivityClient(state: .moving)
    ) -> LocationTracker {
        let tracker = LocationTracker(
            manager: SignalTestLocationManager(),
            activeDraftStore: InMemoryActiveWorkoutDraftStore(), motionActivity: motion
        )
        tracker.state = .tracking
        tracker.startDate = start
        return tracker
    }

    private func send(_ tracker: LocationTracker, latitude: Double, seconds: Double, accuracy: Double = 5) {
        let fix = location(latitude: latitude, seconds: seconds, accuracy: accuracy)
        tracker.processLocationUpdates([fix], receivedAt: fix.timestamp)
    }

    private func location(latitude: Double, seconds: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -87),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
            course: -1, courseAccuracy: -1, speed: 1.2, speedAccuracy: 0.2,
            timestamp: start.addingTimeInterval(seconds)
        )
    }
}
