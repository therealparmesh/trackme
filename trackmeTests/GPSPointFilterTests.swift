import CoreLocation
import XCTest
@testable import trackme

final class GPSPointFilterTests: XCTestCase {
    func testTrackingAcceptsModeratelyAccurateOutdoorMovement() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(
            latitude: 41,
            horizontalAccuracy: 40,
            timestamp: sessionStart.addingTimeInterval(1)
        )
        let next = location(
            latitude: 41.000_25,
            horizontalAccuracy: 45,
            timestamp: sessionStart.addingTimeInterval(13)
        )

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                next,
                after: previous,
                sessionStart: sessionStart,
                now: next.timestamp
            )
        )
    }

    func testTrackingUsesTheSameAccuracyLimitForANewSegment() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let weakAnchor = location(
            latitude: 41,
            horizontalAccuracy: 40,
            timestamp: sessionStart.addingTimeInterval(1)
        )

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                weakAnchor,
                after: nil,
                sessionStart: sessionStart,
                now: weakAnchor.timestamp
            )
        )
    }

    func testTrackingAcceptsAnAccurateStationaryAnchorWithoutPreviousLocation() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let anchor = location(
            latitude: 41,
            horizontalAccuracy: 10,
            speed: 0,
            timestamp: sessionStart.addingTimeInterval(1)
        )

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                anchor,
                after: nil,
                sessionStart: sessionStart,
                now: anchor.timestamp
            )
        )
    }

    func testTrackingRejectsLocationsAboveWorkoutRouteAccuracyLimit() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(
            latitude: 41,
            horizontalAccuracy: 10,
            timestamp: sessionStart.addingTimeInterval(1)
        )
        let inaccurate = location(
            latitude: 41.000_25,
            horizontalAccuracy: 55,
            timestamp: sessionStart.addingTimeInterval(13)
        )

        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                inaccurate,
                after: previous,
                sessionStart: sessionStart,
                now: inaccurate.timestamp
            )
        )
    }

    func testSamplingDoesNotDependOnReportedSpeed() {
        let start = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 41, horizontalAccuracy: 10, timestamp: start)
        // Slow, stationary, uncertain and missing speed must not override the recorded path.
        for (speed, accuracy) in [(0.2, 0.05), (0.0, 0.0), (1.2, 2.0), (-1.0, -1.0)] {
            let next = location(
                latitude: 41.000_1, horizontalAccuracy: 10,
                speed: speed, speedAccuracy: accuracy, timestamp: start.addingTimeInterval(10)
            )
            XCTAssertTrue(GPSPointFilter.shouldAccept(
                next, after: previous, sessionStart: start, now: next.timestamp
            ))
        }
    }

    func testSpatialSamplingAccumulatesFromLastRecordedPoint() {
        let start = Date(timeIntervalSince1970: 1_000)
        let anchor = location(latitude: 41, horizontalAccuracy: 5, timestamp: start)
        let near = location(latitude: 41.000_03, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(10))
        let far = location(latitude: 41.000_06, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(20))

        XCTAssertFalse(GPSPointFilter.shouldAccept(near, after: anchor, sessionStart: start, now: near.timestamp))
        XCTAssertTrue(GPSPointFilter.shouldAccept(far, after: anchor, sessionStart: start, now: far.timestamp))
    }

    private func location(
        latitude: Double,
        horizontalAccuracy: CLLocationAccuracy,
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
