import CoreLocation
import XCTest
@testable import trackme

@MainActor
final class GPSReadinessTimingTests: XCTestCase {
    func testReadinessExpiresAtMeasurementDeadline() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let fix = location(at: timestamp)
        let deadline = timestamp.addingTimeInterval(30)

        XCTAssertEqual(GPSPointFilter.readyFixExpiration(for: fix), deadline)
        XCTAssertTrue(GPSPointFilter.isReadyFix(fix, now: deadline.addingTimeInterval(-0.001)))
        XCTAssertFalse(GPSPointFilter.isReadyFix(fix, now: deadline))
        XCTAssertFalse(GPSPointFilter.isReadyFix(fix, now: deadline.addingTimeInterval(0.001)))
    }

    func testFutureTimestampToleranceMatchesForReadinessAndTracking() {
        let now = Date(timeIntervalSince1970: 1_000)
        for offset in [5.0, 5.001] {
            let fix = location(at: now.addingTimeInterval(offset))
            let expected = offset <= 5
            XCTAssertEqual(GPSPointFilter.isReadyFix(fix, now: now), expected)
            XCTAssertEqual(GPSPointFilter.isValidSample(fix, since: now, now: now), expected)
            XCTAssertEqual(GPSPointFilter.isCurrentSignalSample(fix, now: now), expected)
        }
        let futureFix = location(at: now.addingTimeInterval(5))
        XCTAssertEqual(GPSPointFilter.readyFixExpiration(for: futureFix), now.addingTimeInterval(35))
    }

    func testSignalFreshnessAndTimeoutAgreeAtBoundary() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let fix = location(at: timestamp)
        for age in [19.999, 20, 20.001] {
            let now = timestamp.addingTimeInterval(age)
            XCTAssertEqual(GPSPointFilter.isCurrentSignalSample(fix, now: now), age <= 20)
            XCTAssertEqual(GPSPointFilter.signalTimedOut(since: timestamp, now: now), age > 20)
        }
    }

    func testDelayedFixExpiresWithoutAnotherLocationCallback() async throws {
        let tracker = makeTracker()
        defer { tracker.readinessTask?.cancel() }
        let now = Date.now
        tracker.processLocationUpdates([location(at: now.addingTimeInterval(-29))], receivedAt: now)
        XCTAssertEqual(tracker.displayStatus, .ready)
        XCTAssertTrue(tracker.isReadyToStart)

        let expiryTask = try XCTUnwrap(tracker.readinessTask)
        let expired = expectation(description: "Cached fix expires within its remaining lifetime")
        let waiter = Task {
            await expiryTask.value
            expired.fulfill()
        }
        defer { waiter.cancel() }
        await fulfillment(of: [expired], timeout: 5)

        XCTAssertEqual(tracker.gpsStatus, .finding)
        XCTAssertEqual(tracker.displayStatus, .finding)
        XCTAssertFalse(tracker.isReadyToStart)
    }

    func testReplacementFixCancelsOldExpiry() async throws {
        let tracker = makeTracker()
        defer { tracker.readinessTask?.cancel() }
        let now = Date.now
        tracker.processLocationUpdates([location(at: now.addingTimeInterval(-29))], receivedAt: now)
        let oldTask = try XCTUnwrap(tracker.readinessTask)
        let replacement = location(at: now)
        tracker.processLocationUpdates([replacement], receivedAt: now)
        await oldTask.value

        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertEqual(tracker.lastReadyLocation?.timestamp, replacement.timestamp)
        XCTAssertEqual(tracker.gpsStatus, .ready)
        XCTAssertTrue(tracker.isReadyToStart)
    }

    func testExpiryDoesNotOverwriteSignalLoss() async throws {
        let tracker = makeTracker()
        defer { tracker.readinessTask?.cancel() }
        let now = Date.now
        tracker.processLocationUpdates([location(at: now.addingTimeInterval(-29))], receivedAt: now)
        let expiryTask = try XCTUnwrap(tracker.readinessTask)
        tracker.locationManager(CLLocationManager(), didFailWithError: CLError(.network))
        XCTAssertEqual(tracker.gpsStatus, .lost)
        let expired = expectation(description: "Readiness timer completes after signal loss")
        let waiter = Task {
            await expiryTask.value
            expired.fulfill()
        }
        defer { waiter.cancel() }
        await fulfillment(of: [expired], timeout: 5)

        XCTAssertEqual(tracker.gpsStatus, .lost)
        XCTAssertFalse(tracker.isReadyToStart)
    }

    func testWeakFixCancelsReadinessExpiry() async throws {
        let tracker = makeTracker()
        let now = Date.now
        tracker.processLocationUpdates([location(at: now.addingTimeInterval(-29))], receivedAt: now)
        let oldTask = try XCTUnwrap(tracker.readinessTask)
        tracker.processLocationUpdates([location(at: now, accuracy: 100)], receivedAt: now)
        await oldTask.value

        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertNil(tracker.readinessTask)
        XCTAssertEqual(tracker.gpsStatus, .weak)
        XCTAssertFalse(tracker.isReadyToStart)
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
