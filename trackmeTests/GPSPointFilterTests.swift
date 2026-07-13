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
                motionState: .unknown,
                now: next.timestamp
            )
        )
    }

    func testTrackingRequiresAnAccurateAnchorForANewRouteSegment() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let weakAnchor = location(
            latitude: 41,
            horizontalAccuracy: 40,
            timestamp: sessionStart.addingTimeInterval(1)
        )

        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                weakAnchor,
                after: nil,
                sessionStart: sessionStart,
                motionState: .moving,
                now: weakAnchor.timestamp
            )
        )
    }

    func testTrackingAcceptsAnAccurateStationaryAnchorWithoutPreviousLocation() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let anchor = location(
            latitude: 41,
            horizontalAccuracy: 10,
            timestamp: sessionStart.addingTimeInterval(1)
        )

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                anchor,
                after: nil,
                sessionStart: sessionStart,
                motionState: .stationary,
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
                motionState: .moving,
                now: inaccurate.timestamp
            )
        )
    }

    func testTrackingRejectsAccurateFixWhenSpeedCouldBeStationary() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(
            latitude: 41,
            horizontalAccuracy: 10,
            speed: 0.4,
            speedAccuracy: 0.1,
            timestamp: sessionStart.addingTimeInterval(1)
        )
        let drift = location(
            latitude: 41.000_25,
            horizontalAccuracy: 10,
            speed: 0.4,
            speedAccuracy: 0.1,
            timestamp: sessionStart.addingTimeInterval(13)
        )

        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                drift,
                after: previous,
                sessionStart: sessionStart,
                motionState: .unknown,
                now: drift.timestamp
            )
        )
    }

    func testTrackingRejectsStationaryMotionDespitePlausibleGPSSpeed() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(
            latitude: 41,
            horizontalAccuracy: 10,
            timestamp: sessionStart.addingTimeInterval(1)
        )
        let drift = location(
            latitude: 41.000_25,
            horizontalAccuracy: 10,
            timestamp: sessionStart.addingTimeInterval(13)
        )

        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                drift,
                after: previous,
                sessionStart: sessionStart,
                motionState: .stationary,
                now: drift.timestamp
            )
        )
    }

    func testTrackingAcceptsMotionConfirmedMovementWithoutGPSSpeed() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let previous = location(
            latitude: 41,
            horizontalAccuracy: 10,
            timestamp: sessionStart.addingTimeInterval(1)
        )
        let next = location(
            latitude: 41.000_1,
            horizontalAccuracy: 10,
            speed: -1,
            speedAccuracy: -1,
            timestamp: sessionStart.addingTimeInterval(8)
        )

        XCTAssertTrue(
            GPSPointFilter.shouldAccept(
                next,
                after: previous,
                sessionStart: sessionStart,
                motionState: .moving,
                now: next.timestamp
            )
        )
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
