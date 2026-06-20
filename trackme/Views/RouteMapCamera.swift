import MapKit
import SwiftUI

enum RouteMapCamera {
    private static let minimumMapSizeMeters: CLLocationDistance = 90
    private static let paddingRatio = 0.10

    static func position(fitting route: [RoutePoint]) -> MapCameraPosition {
        guard !route.isEmpty else { return .automatic }
        return .region(region(fitting: route))
    }

    static func region(fitting route: [RoutePoint]) -> MKCoordinateRegion {
        guard let first = route.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        let routeRect = route.dropFirst().reduce(
            MKMapRect(origin: MKMapPoint(first.coordinate), size: .init(width: 0, height: 0))
        ) { rect, point in
            rect.union(
                MKMapRect(
                    origin: MKMapPoint(point.coordinate),
                    size: .init(width: 0, height: 0)
                )
            )
        }

        let center = MKMapPoint(x: routeRect.midX, y: routeRect.midY)
        let coordinate = center.coordinate
        let minimumMapPoints = minimumMapSizeMeters * MKMapPointsPerMeterAtLatitude(coordinate.latitude)
        let width = max(routeRect.width, minimumMapPoints)
        let height = max(routeRect.height, minimumMapPoints)
        let fittedRect = MKMapRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        .insetBy(dx: -(width * paddingRatio), dy: -(height * paddingRatio))

        return MKCoordinateRegion(fittedRect)
    }
}
