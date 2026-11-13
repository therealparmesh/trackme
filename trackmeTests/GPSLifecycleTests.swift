import CoreLocation
import XCTest
@testable import trackme

@MainActor
final class GPSLifecycleTests: XCTestCase {
    func testRestoringPausedOrUnauthorizedWorkoutPreservesProgressWithoutTracking() {
        let now = Date.now
        let point = RoutePoint(location: location(at: now.addingTimeInterval(-10)), startsNewSegment: true)
        let cases: [(ActiveWorkoutDraft.State, CLAuthorizationStatus)] = [
            (.tracking, .denied), (.paused, .denied), (.paused, .authorizedWhenInUse)
        ]
        for (draftState, status) in cases {
            let manager = SignalTestLocationManager()
            manager.authorizationStatus = status
            let motion = SignalTestMotionActivityClient()
            let store = InMemoryActiveWorkoutDraftStore()
            let pausedAt = draftState == .paused ? now.addingTimeInterval(-20) : nil
            store.draft = ActiveWorkoutDraft(
                state: draftState, activity: .walk, startDate: now.addingTimeInterval(-60),
                pausedAt: pausedAt, pausedDuration: 0, pauses: [], startsNewSegment: false,
                elapsed: 40, distance: 25, route: [point], lastAcceptedLocation: point,
                lastReadyLocation: point, lastRawLocationUpdateAt: point.timestamp
            )
            let tracker = LocationTracker(manager: manager, activeDraftStore: store, motionActivity: motion)
            defer { tracker.discard() }
            tracker.prepareForWorkout()
            let updatesBeforeRestore = manager.startUpdatingLocationCalls

            XCTAssertTrue(tracker.restoreActiveWorkoutIfAvailable(now: now))

            XCTAssertEqual(tracker.state, .paused)
            XCTAssertEqual(tracker.elapsed, draftState == .paused ? 40 : 60, accuracy: 0.001)
            XCTAssertEqual(tracker.distance, 25)
            XCTAssertEqual(tracker.route.count, 1)
            XCTAssertEqual(tracker.errorMessage, tracker.isAuthorized ? nil : LocationTracker.locationAccessMessage)
            XCTAssertEqual(manager.startUpdatingLocationCalls, updatesBeforeRestore)
            XCTAssertEqual(manager.stopUpdatingLocationCalls, 1)
            XCTAssertEqual(motion.startCalls, 0)
            XCTAssertEqual(store.draft?.state, .paused)
            XCTAssertEqual(store.draft?.pausedAt, pausedAt ?? now)
        }
    }

    func testMonitoringDoesNotRetainTracker() async {
        weak var releasedTracker: LocationTracker?
        do {
            let tracker = makeTracker()
            releasedTracker = tracker
            let now = Date.now
            tracker.processLocationUpdates([location(at: now)], receivedAt: now)
            tracker.start()
            await Task.yield()
        }

        XCTAssertNil(releasedTracker)
        releasedTracker?.discard()
    }

    func testResumeWithoutPermissionPreservesPauseUntilPermissionReturns() throws {
        for status in [CLAuthorizationStatus.denied, .restricted, .notDetermined] {
            let manager = SignalTestLocationManager()
            manager.authorizationStatus = .authorizedWhenInUse
            let store = InMemoryActiveWorkoutDraftStore()
            let motion = SignalTestMotionActivityClient()
            let tracker = LocationTracker(manager: manager, activeDraftStore: store, motionActivity: motion)
            defer {
                tracker.discard()
                tracker.readinessTask?.cancel()
            }
            let now = Date.now
            tracker.processLocationUpdates([location(at: now)], receivedAt: now)
            tracker.start()
            tracker.pause()
            XCTAssertEqual(motion.stopCalls, 1)
            XCTAssertEqual(manager.stopUpdatingLocationCalls, 1)
            let paused = try XCTUnwrap(store.draft)
            let elapsed = tracker.elapsed

            manager.authorizationStatus = status
            tracker.authorizationStatus = status
            tracker.resume()

            XCTAssertEqual(tracker.state, .paused)
            XCTAssertEqual(tracker.elapsed, elapsed)
            XCTAssertEqual(tracker.errorMessage, LocationTracker.locationAccessMessage)
            XCTAssertEqual(manager.startUpdatingLocationCalls, 1)
            XCTAssertEqual(motion.startCalls, 1)
            XCTAssertEqual(store.draft?.state, .paused)
            XCTAssertEqual(store.draft?.pausedAt, paused.pausedAt)
            XCTAssertEqual(store.draft?.pauses.count, 0)

            manager.authorizationStatus = .authorizedWhenInUse
            tracker.authorizationStatus = .authorizedWhenInUse
            tracker.resume()

            XCTAssertEqual(tracker.state, .tracking)
            XCTAssertNil(tracker.errorMessage)
            XCTAssertEqual(manager.startUpdatingLocationCalls, 2)
            XCTAssertEqual(motion.startCalls, 2)
            XCTAssertNil(store.draft?.pausedAt)
            XCTAssertEqual(store.draft?.pauses.count, 1)
            XCTAssertEqual(store.draft?.pauses.first?.startDate, paused.pausedAt)

            tracker.discard()
            XCTAssertEqual(motion.stopCalls, 2)
            XCTAssertEqual(manager.stopUpdatingLocationCalls, 2)
        }
    }

    func testFinishRestoresReadinessExpiryWithoutAnotherFix() async throws {
        let tracker = trackingTracker(fixAge: 29)
        defer { tracker.readinessTask?.cancel() }
        XCTAssertNotNil(tracker.finish { _ in })
        try await assertReadinessExpires(tracker)
    }

    func testFinishRestartsForegroundUpdatesEvenWithoutAFreshFix() {
        let tracker = trackingTracker(fixAge: 31)
        let manager = tracker.manager as? SignalTestLocationManager
        defer { tracker.readinessTask?.cancel() }
        XCTAssertNotNil(tracker.finish { _ in })
        XCTAssertEqual(tracker.state, .idle)
        XCTAssertEqual(tracker.displayStatus, .finding)
        XCTAssertEqual(manager?.startUpdatingLocationCalls, 1)
        XCTAssertEqual(manager?.allowsBackgroundLocationUpdates, false)
        XCTAssertEqual(manager?.distanceFilter, kCLDistanceFilterNone)

        let now = Date.now
        tracker.processLocationUpdates([location(at: now)], receivedAt: now)
        XCTAssertTrue(tracker.isReadyToStart)
    }

    func testFailedLocalSaveKeepsPausedWorkoutAndDraftForRetry() throws {
        let now = Date.now
        let store = InMemoryActiveWorkoutDraftStore()
        let tracker = LocationTracker(
            manager: SignalTestLocationManager(), activeDraftStore: store,
            motionActivity: SignalTestMotionActivityClient()
        )
        tracker.state = .tracking
        tracker.startDate = now.addingTimeInterval(-60)
        tracker.distance = 100
        tracker.pause(now: now.addingTimeInterval(-10))

        XCTAssertThrowsError(try tracker.finish { _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertEqual(tracker.state, .paused)
        XCTAssertEqual(tracker.distance, 100)
        XCTAssertEqual(store.draft?.pausedAt, now.addingTimeInterval(-10))

        let snapshot = try XCTUnwrap(tracker.finish { _ in })
        XCTAssertEqual(snapshot.duration, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.pauses.count, 1)
        XCTAssertEqual(tracker.state, .idle)
        XCTAssertNil(store.draft)
    }

    func testApproximateLocationShowsSettingsInsteadOfWaitingForGPS() {
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        manager.accuracyAuthorization = .reducedAccuracy
        let tracker = LocationTracker(manager: manager, activeDraftStore: InMemoryActiveWorkoutDraftStore())

        tracker.prepareForWorkout()
        XCTAssertEqual(tracker.displayStatus, .locationOff)
        XCTAssertFalse(tracker.isReadyToStart)
        XCTAssertEqual(tracker.errorMessage, LocationTracker.preciseLocationMessage)
        XCTAssertEqual(manager.startUpdatingLocationCalls, 0)
    }

    func testDiscardRestoresReadinessExpiryWithoutAnotherFix() async throws {
        let tracker = trackingTracker(fixAge: 29)
        defer { tracker.readinessTask?.cancel() }
        tracker.discard()
        try await assertReadinessExpires(tracker)
    }

    func testReturningToIdleDoesNotReviveExpiredReadyFix() {
        let transitions: [(LocationTracker) -> Void] = [
            { _ = $0.finish { _ in } },
            { $0.discard() }
        ]
        for transition in transitions {
            let tracker = trackingTracker(fixAge: 31)
            transition(tracker)

            XCTAssertEqual(tracker.state, .idle)
            XCTAssertEqual(tracker.displayStatus, .finding)
            XCTAssertFalse(tracker.isReadyToStart)
            XCTAssertNil(tracker.readinessTask)
        }
    }

    func testIdleRecoveryClearsTransientLocationError() {
        for code in [CLError.Code.network, .deferredFailed] {
            let tracker = makeTracker()
            defer { tracker.readinessTask?.cancel() }
            tracker.locationManager(CLLocationManager(), didFailWithError: CLError(code))
            XCTAssertNotNil(tracker.errorMessage)
            let now = Date.now
            tracker.processLocationUpdates([location(at: now)], receivedAt: now)

            XCTAssertEqual(tracker.displayStatus, .ready)
            XCTAssertTrue(tracker.isReadyToStart)
            XCTAssertNil(tracker.errorMessage)
        }
    }

    func testIdlePoorOrStaleFixDoesNotClearLocationError() {
        let tracker = makeTracker()
        let now = Date.now
        tracker.locationManager(CLLocationManager(), didFailWithError: CLError(.network))
        let error = tracker.errorMessage
        for fix in [location(at: now, accuracy: 100), location(at: now.addingTimeInterval(-31))] {
            tracker.processLocationUpdates([fix], receivedAt: now)

            XCTAssertEqual(tracker.errorMessage, error)
            XCTAssertFalse(tracker.isReadyToStart)
        }
    }

    func testIdleLateFixDoesNotClearRevokedPermissionError() {
        let tracker = makeTracker()
        defer { tracker.readinessTask?.cancel() }
        tracker.authorizationStatus = .denied
        tracker.errorMessage = LocationTracker.locationAccessMessage
        let now = Date.now
        tracker.processLocationUpdates([location(at: now)], receivedAt: now)

        XCTAssertEqual(tracker.errorMessage, LocationTracker.locationAccessMessage)
        XCTAssertEqual(tracker.displayStatus, .locationOff)
        XCTAssertFalse(tracker.isReadyToStart)
    }

    private func assertReadinessExpires(_ tracker: LocationTracker) async throws {
        XCTAssertEqual(tracker.state, .idle)
        XCTAssertEqual(tracker.displayStatus, .ready)
        XCTAssertTrue(tracker.isReadyToStart)
        let expiryTask = try XCTUnwrap(tracker.readinessTask)
        let expired = expectation(description: "Retained location reaches its original expiry")
        let waiter = Task {
            await expiryTask.value
            expired.fulfill()
        }
        defer { waiter.cancel() }
        await fulfillment(of: [expired], timeout: 5)

        XCTAssertEqual(tracker.displayStatus, .finding)
        XCTAssertFalse(tracker.isReadyToStart)
    }

    private func trackingTracker(fixAge: TimeInterval) -> LocationTracker {
        let tracker = makeTracker()
        tracker.state = .tracking
        tracker.startDate = .now.addingTimeInterval(-60)
        tracker.distance = 25
        tracker.gpsStatus = .ready
        tracker.lastReadyLocation = location(at: .now.addingTimeInterval(-fixAge))
        return tracker
    }

    private func makeTracker() -> LocationTracker {
        let manager = SignalTestLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        return LocationTracker(
            manager: manager,
            activeDraftStore: InMemoryActiveWorkoutDraftStore(),
            motionActivity: SignalTestMotionActivityClient()
        )
    }

    private func location(at timestamp: Date, accuracy: CLLocationAccuracy = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41, longitude: -87),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: timestamp
        )
    }
}
