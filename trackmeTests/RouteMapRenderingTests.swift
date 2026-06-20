import CoreLocation
import XCTest
@testable import trackme

final class RouteMapRenderingTests: XCTestCase {
    func testRainbowTrailDoesNotConnectSeparateRouteSegments() throws {
        let route = [
            routePoint(latitude: 41, startsNewSegment: true),
            routePoint(latitude: 41.001, startsNewSegment: false),
            routePoint(latitude: 41.01, startsNewSegment: true),
            routePoint(latitude: 41.011, startsNewSegment: false)
        ]

        let lines = RouteTrailStyle.lines(from: route)
        let firstLine = try XCTUnwrap(lines.first)
        let lastLine = try XCTUnwrap(lines.last)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(try XCTUnwrap(firstLine.coordinates.first).latitude, 41, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(firstLine.coordinates.last).latitude, 41.001, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(lastLine.coordinates.first).latitude, 41.01, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(lastLine.coordinates.last).latitude, 41.011, accuracy: 0.000_001)
    }

    func testRouteMapCameraFitsSavedRoute() throws {
        let route = [
            routePoint(latitude: 41, longitude: -87.01, startsNewSegment: true),
            routePoint(latitude: 41.01, longitude: -87, startsNewSegment: false)
        ]

        let position = RouteMapCamera.position(fitting: route)
        let region = try XCTUnwrap(position.region)

        XCTAssertEqual(region.center.latitude, 41.005, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, -87.005, accuracy: 0.000_001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0.01)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0.01)
    }

    private func routePoint(
        latitude: Double,
        longitude: Double = -87,
        startsNewSegment: Bool
    ) -> RoutePoint {
        RoutePoint(
            location: CLLocation(latitude: latitude, longitude: longitude),
            startsNewSegment: startsNewSegment
        )
    }
}
