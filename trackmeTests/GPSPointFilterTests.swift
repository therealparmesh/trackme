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

    func testTrackingRejectsVeryPoorAccuracySamples() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let poorFix = location(
            latitude: 41.000_25,
            horizontalAccuracy: 100,
            timestamp: sessionStart.addingTimeInterval(13)
        )

        XCTAssertFalse(
            GPSPointFilter.shouldAccept(
                poorFix,
                after: nil,
                sessionStart: sessionStart,
                now: poorFix.timestamp
            )
        )
    }

    private func location(
        latitude: Double,
        horizontalAccuracy: CLLocationAccuracy,
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
