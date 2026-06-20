import CoreLocation
import XCTest
@testable import trackme

final class WorkoutMetricsTests: XCTestCase {
    func testMileageIgnoresAltitude() {
        let coordinate = CLLocationCoordinate2D(latitude: 41.881_832, longitude: -87.623_177)
        let ground = location(coordinate: coordinate, altitude: 0, timestamp: .now)
        let highAltitude = location(
            coordinate: coordinate,
            altitude: 2_000,
            timestamp: .now.addingTimeInterval(1)
        )

        XCTAssertEqual(
            HorizontalDistanceCalculator.distance(from: ground, to: highAltitude),
            0,
            accuracy: 0.001
        )
    }

    func testGPSFilterRejectsPreWorkoutAndPoorAccuracySamples() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let stale = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(-1))
        let inaccurate = location(
            latitude: 41,
            horizontalAccuracy: 100,
            timestamp: sessionStart
        )

        XCTAssertFalse(GPSPointFilter.shouldAccept(stale, after: nil, sessionStart: sessionStart, now: sessionStart))
        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                inaccurate,
                after: nil,
                sessionStart: sessionStart,
                now: sessionStart
            )
        )
    }

    func testGPSFilterAcceptsValidBackgroundBatch() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 41, timestamp: sessionStart.addingTimeInterval(120))
        let next = location(latitude: 41.000_1, timestamp: sessionStart.addingTimeInterval(123))

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                next,
                after: previous,
                sessionStart: sessionStart,
                now: sessionStart.addingTimeInterval(600)
            )
        )
    }

    func testGPSFilterRejectsReliablyStationaryDrift() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 41, timestamp: sessionStart)
        let drift = location(
            latitude: 41.000_05,
            speed: 0,
            speedAccuracy: 0.2,
            timestamp: sessionStart.addingTimeInterval(3)
        )

        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                drift,
                after: previous,
                sessionStart: sessionStart,
                now: drift.timestamp
            )
        )
    }

    func testGPSFilterAcceptsWalkingMovement() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 41, timestamp: sessionStart)
        let walking = location(
            latitude: 41.000_05,
            speed: 1.2,
            speedAccuracy: 0.2,
            timestamp: sessionStart.addingTimeInterval(4)
        )

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                walking,
                after: previous,
                sessionStart: sessionStart,
                now: walking.timestamp
            )
        )
    }

    func testReadyFixRequiresRecentAccurateLocation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let recent = location(latitude: 41, timestamp: now.addingTimeInterval(-2))
        let stale = location(latitude: 41, timestamp: now.addingTimeInterval(-40))
        let inaccurate = location(
            latitude: 41,
            horizontalAccuracy: 50,
            timestamp: now.addingTimeInterval(-2)
        )

        XCTAssertTrue(GPSPointFilter.isReadyFix(recent, now: now))
        XCTAssertFalse(GPSPointFilter.isReadyFix(stale, now: now))
        XCTAssertFalse(GPSPointFilter.isReadyFix(inaccurate, now: now))
    }

    func testSignalTimeoutStartsANewTrustWindow() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(
            GPSPointFilter.signalTimedOut(
                since: now.addingTimeInterval(-10),
                now: now
            )
        )
        XCTAssertTrue(
            GPSPointFilter.signalTimedOut(
                since: now.addingTimeInterval(-25),
                now: now
            )
        )
    }

    func testTinyGPSOnlyWorkoutFinalizesAtZero() {
        let route = [
            routePoint(latitude: 41, startsNewSegment: true),
            routePoint(latitude: 41.000_05, startsNewSegment: false)
        ]

        let result = WorkoutPathFilter.finalized(distance: 12, route: route)

        XCTAssertEqual(result.distance, 0)
        XCTAssertTrue(result.route.isEmpty)
    }

    func testMeaningfulWorkoutThreshold() {
        XCTAssertFalse(WorkoutPathFilter.isMeaningful(distance: 19.99))
        XCTAssertTrue(WorkoutPathFilter.isMeaningful(distance: 20))
    }

    func testMeaningfulWorkoutKeepsDistanceAndRoute() {
        let route = [
            routePoint(latitude: 41, startsNewSegment: true),
            routePoint(latitude: 41.000_2, startsNewSegment: false)
        ]

        let result = WorkoutPathFilter.finalized(distance: 25, route: route)

        XCTAssertEqual(result.distance, 25)
        XCTAssertEqual(result.route.count, 2)
    }

    func testElevationGainCountsClimbingButNotDescent() {
        let route = [100, 102, 106, 111, 116, 116, 116, 113, 108].enumerated().map { index, altitude in
            routePoint(
                latitude: 41.0 + (Double(index) * 0.000_1),
                altitude: Double(altitude),
                timestamp: Date(timeIntervalSince1970: Double(index) * 2),
                startsNewSegment: index == 0
            )
        }

        XCTAssertEqual(ElevationGainCalculator.totalGain(from: route), 16, accuracy: 0.001)
    }

    func testElevationGainIgnoresSmallJitterAndPauseGap() {
        let route = [
            routePoint(
                latitude: 41,
                altitude: 100,
                timestamp: .init(timeIntervalSince1970: 0),
                startsNewSegment: true
            ),
            routePoint(
                latitude: 41.1,
                altitude: 101,
                timestamp: .init(timeIntervalSince1970: 2),
                startsNewSegment: false
            ),
            routePoint(
                latitude: 41.2,
                altitude: 99,
                timestamp: .init(timeIntervalSince1970: 4),
                startsNewSegment: false
            ),
            routePoint(
                latitude: 42,
                altitude: 140,
                timestamp: .init(timeIntervalSince1970: 30),
                startsNewSegment: true
            ),
            routePoint(
                latitude: 42.1,
                altitude: 142,
                timestamp: .init(timeIntervalSince1970: 32),
                startsNewSegment: false
            )
        ]

        XCTAssertEqual(ElevationGainCalculator.totalGain(from: route), 0, accuracy: 0.001)
    }

    private func routePoint(
        latitude: Double,
        altitude: Double = 180,
        timestamp: Date = .now,
        startsNewSegment: Bool
    ) -> RoutePoint {
        RoutePoint(
            location: location(latitude: latitude, altitude: altitude, timestamp: timestamp),
            startsNewSegment: startsNewSegment
        )
    }

    private func location(
        latitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 5,
        speed: Double = -1,
        speedAccuracy: Double = -1,
        timestamp: Date
    ) -> CLLocation {
        location(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -87),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }

    private func location(
        coordinate: CLLocationCoordinate2D,
        altitude: Double,
        horizontalAccuracy: Double = 5,
        speed: Double = -1,
        speedAccuracy: Double = -1,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
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
