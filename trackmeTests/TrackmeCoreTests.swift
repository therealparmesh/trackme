import CoreLocation
import HealthKit
import SwiftData
import XCTest
@testable import trackme

final class TrackmeCoreTests: XCTestCase {
    func testDistanceUsesMiles() {
        XCTAssertEqual(MetricFormatter.distance(1_609.344), "1.00")
    }

    func testDurationFormatting() {
        XCTAssertEqual(MetricFormatter.duration(3_661), "1:01:01")
        XCTAssertEqual(MetricFormatter.duration(65), "01:05")
    }

    func testPaceFormatting() {
        XCTAssertEqual(MetricFormatter.pace(615), "10:15")
        XCTAssertEqual(MetricFormatter.pace(0), "--:--")
    }

    func testRouteSegmentsSplitAfterPause() {
        let first = routePoint(latitude: 41.0, startsNewSegment: true)
        let second = routePoint(latitude: 41.1, startsNewSegment: false)
        let third = routePoint(latitude: 41.2, startsNewSegment: true)

        let segments = [first, second, third].routeSegments

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.map(\.count), [2, 1])
    }

    func testSnapshotAveragePaceUsesMovingDuration() {
        let snapshot = WorkoutSnapshot(
            activity: .walk,
            startDate: .now,
            endDate: .now.addingTimeInterval(1_000),
            duration: 600,
            distance: 1_609.344,
            elevationGain: 0,
            route: [],
            pauses: []
        )

        XCTAssertEqual(snapshot.averagePace, 600, accuracy: 0.001)
    }

    func testZeroDistanceSnapshotIsNotMeaningful() {
        XCTAssertFalse(snapshot(distance: 0).hasMeaningfulDistance)
        XCTAssertTrue(snapshot(distance: 25).hasMeaningfulDistance)
    }

    @MainActor
    func testStartupLocationAccessRequestsPermissionGreedily() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .notDetermined
        let tracker = LocationTracker(manager: manager)

        tracker.requestStartupLocationAccess()
        tracker.requestStartupLocationAccess()

        XCTAssertEqual(manager.authorizationRequests, 1)
        XCTAssertTrue(tracker.isRequestingAuthorization)
        XCTAssertEqual(tracker.gpsStatus, .finding)
        XCTAssertEqual(tracker.state, .idle)
    }

    @MainActor
    func testStartupLocationAccessWarmsGPSWhenAlreadyAuthorized() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager)

        tracker.requestStartupLocationAccess()

        XCTAssertEqual(manager.authorizationRequests, 0)
        XCTAssertEqual(manager.startUpdatingLocationCalls, 1)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
        XCTAssertEqual(tracker.gpsStatus, .finding)
    }

    @MainActor
    func testStartupLocationAccessShowsErrorWhenDenied() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let tracker = LocationTracker(manager: manager)

        tracker.requestStartupLocationAccess()

        XCTAssertEqual(manager.authorizationRequests, 0)
        XCTAssertEqual(manager.startUpdatingLocationCalls, 0)
        XCTAssertEqual(tracker.gpsStatus, .lost)
        XCTAssertEqual(tracker.errorMessage, LocationTracker.locationAccessMessage)
    }

    @MainActor
    func testMapFocusIgnoresStaleReadyFix() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager)
        tracker.lastReadyLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41, longitude: -87),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: .now.addingTimeInterval(-120)
        )

        XCTAssertNil(tracker.mapFocusLocation)
    }

    @MainActor
    func testSignalGapBreaksRouteAndPreventsDistanceJump() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let manager = FakeLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        let tracker = LocationTracker(manager: manager)
        tracker.authorizationStatus = .authorizedWhenInUse
        tracker.state = .tracking
        tracker.startDate = sessionStart

        let first = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(1))
        let second = location(latitude: 41.000_1, timestamp: sessionStart.addingTimeInterval(11))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [first, second])
        let distanceBeforeGap = tracker.distance

        tracker.lastRawLocationUpdateAt = sessionStart.addingTimeInterval(-30)
        tracker.refreshSignalTimeout()
        let afterGap = location(latitude: 41.01, timestamp: sessionStart.addingTimeInterval(40))
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [afterGap])

        XCTAssertEqual(tracker.distance, distanceBeforeGap, accuracy: 0.001)
        XCTAssertEqual(tracker.route.routeSegments.count, 2)
        XCTAssertEqual(tracker.gpsStatus, .ready)
    }

    @MainActor
    func testHealthSyncSavesAndReturnsWorkoutIdentifier() async {
        let client = FakeHealthStoreClient()
        let expectedID = UUID()
        client.authorizationStatus = .sharingAuthorized
        client.nextSaveID = expectedID
        let health = HealthKitService(client: client)

        let id = await health.save(snapshot())

        XCTAssertEqual(id, expectedID)
        XCTAssertEqual(client.savedWorkoutCount, 1)
        XCTAssertNil(health.message)
    }

    @MainActor
    func testHealthSyncSkipsZeroDistanceWorkout() async {
        let client = FakeHealthStoreClient()
        client.authorizationStatus = .sharingAuthorized
        let health = HealthKitService(client: client)

        let id = await health.save(snapshot(distance: 0))

        XCTAssertNil(id)
        XCTAssertEqual(client.savedWorkoutCount, 0)
        XCTAssertNil(health.message)
    }

    @MainActor
    func testHealthSyncDeleteUsesWorkoutIdentifier() async {
        let client = FakeHealthStoreClient()
        client.authorizationStatus = .sharingAuthorized
        let health = HealthKitService(client: client)
        let id = UUID()

        let deleted = await health.deleteWorkout(id: id)

        XCTAssertTrue(deleted)
        XCTAssertEqual(client.deletedWorkoutIDs, [id])
        XCTAssertNil(health.message)
    }

    @MainActor
    func testHealthSyncDeleteFailsClosedWhenDisconnected() async {
        let client = FakeHealthStoreClient()
        client.authorizationStatus = .notDetermined
        let health = HealthKitService(client: client)

        let deleted = await health.deleteWorkout(id: UUID())

        XCTAssertFalse(deleted)
        XCTAssertTrue(client.deletedWorkoutIDs.isEmpty)
        XCTAssertEqual(health.message, "Reconnect Apple Health to remove this synced workout from Health.")
    }

    func testWorkoutRecordStoresHealthWorkoutIdentifier() throws {
        let id = UUID()
        let workout = try WorkoutRecord(snapshot: snapshot(), healthKitWorkoutID: id)

        XCTAssertEqual(workout.healthKitWorkoutID, id)

        workout.healthKitWorkoutID = nil
        XCTAssertNil(workout.healthKitWorkoutUUIDString)
        XCTAssertNil(workout.healthKitWorkoutID)
    }

    @MainActor
    func testWorkoutCanBeDeletedFromHistory() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let workout = try WorkoutRecord(snapshot: snapshot())

        context.insert(workout)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutRecord>()), 1)

        context.delete(workout)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutRecord>()), 0)
    }

    func testInsightRangesIncludeCurrentPeriod() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 14,
            hour: 12
        )))

        XCTAssertEqual(
            InsightsView.Range.week.cutoffDate(relativeTo: date, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))
        )
        XCTAssertEqual(
            InsightsView.Range.month.cutoffDate(relativeTo: date, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 16))
        )
        XCTAssertEqual(
            InsightsView.Range.quarter.cutoffDate(relativeTo: date, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))
        )
    }

    func testInsightRangesGenerateCompleteTimelines() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 1
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 14,
            hour: 12
        )))

        let week = InsightsView.Range.week.bucketStarts(relativeTo: date, calendar: calendar)
        let month = InsightsView.Range.month.bucketStarts(relativeTo: date, calendar: calendar)
        let quarter = InsightsView.Range.quarter.bucketStarts(relativeTo: date, calendar: calendar)

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(month.count, 6)
        XCTAssertEqual(quarter.count, 3)
        XCTAssertEqual(
            quarter.first,
            calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))
        )
        XCTAssertEqual(
            quarter.last,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))
        )
    }

    private func routePoint(latitude: Double, startsNewSegment: Bool) -> RoutePoint {
        RoutePoint(
            location: CLLocation(latitude: latitude, longitude: -87),
            startsNewSegment: startsNewSegment
        )
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

    private func snapshot(distance: Double = 100) -> WorkoutSnapshot {
        WorkoutSnapshot(
            activity: .walk,
            startDate: .now,
            endDate: .now.addingTimeInterval(60),
            duration: 60,
            distance: distance,
            elevationGain: 2,
            route: [],
            pauses: []
        )
    }
}

@MainActor
private final class FakeLocationManager: LocationManagerClient {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    weak var delegate: CLLocationManagerDelegate?
    var activityType: CLActivityType = .other
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var authorizationRequests = 0
    var startUpdatingLocationCalls = 0
    var stopUpdatingLocationCalls = 0

    func requestWhenInUseAuthorization() {
        authorizationRequests += 1
    }

    func startUpdatingLocation() {
        startUpdatingLocationCalls += 1
    }

    func stopUpdatingLocation() {
        stopUpdatingLocationCalls += 1
    }
}

@MainActor
private final class FakeHealthStoreClient: HealthStoreClient {
    var isHealthDataAvailable = true
    var authorizationStatus: HKAuthorizationStatus = .notDetermined
    var nextSaveID = UUID()
    var savedWorkoutCount = 0
    var deletedWorkoutIDs: [UUID] = []

    func authorizationStatus(for type: HKSampleType) -> HKAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        authorizationStatus = .sharingAuthorized
    }

    func save(_ snapshot: WorkoutSnapshot) async throws -> UUID {
        savedWorkoutCount += 1
        return nextSaveID
    }

    func deleteWorkout(id: UUID) async throws {
        deletedWorkoutIDs.append(id)
    }
}
