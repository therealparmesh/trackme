import CoreLocation
import XCTest
@testable import trackme

final class TrackMapCameraTests: XCTestCase {
    func testFocusesKnownLocationIn2D() throws {
        let location = CLLocation(latitude: 41.881_832, longitude: -87.623_177)
        let position = TrackMapCamera.position(focusing: location)
        let camera = try XCTUnwrap(position.camera)

        XCTAssertEqual(camera.centerCoordinate.latitude, location.coordinate.latitude, accuracy: 0.000_001)
        XCTAssertEqual(camera.centerCoordinate.longitude, location.coordinate.longitude, accuracy: 0.000_001)
        XCTAssertEqual(camera.distance, TrackMapCamera.focusDistance, accuracy: 0.001)
        XCTAssertEqual(camera.heading, 0, accuracy: 0.001)
        XCTAssertEqual(camera.pitch, 0, accuracy: 0.001)
    }

    func testFallsBackToNativeUserLocationFollowing() {
        let position = TrackMapCamera.position(focusing: nil)

        XCTAssertTrue(position.followsUserLocation)
        XCTAssertFalse(position.followsUserHeading)
    }
}
