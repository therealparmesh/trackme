import CoreLocation
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

    @MainActor
    func testWorkoutCanBeDeletedFromHistory() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let snapshot = WorkoutSnapshot(
            activity: .walk,
            startDate: .now,
            endDate: .now.addingTimeInterval(60),
            duration: 60,
            distance: 100,
            elevationGain: 2,
            route: [],
            pauses: []
        )
        let workout = try WorkoutRecord(snapshot: snapshot)

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
}
