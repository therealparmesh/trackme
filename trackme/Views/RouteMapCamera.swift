import MapKit
import SwiftUI

enum RouteMapCamera {
    private static let minimumSpan = 0.005
    private static let paddingMultiplier = 1.45

    static func position(fitting route: [RoutePoint]) -> MapCameraPosition {
        guard let first = route.first else { return .automatic }

        let bounds = route.reduce(
            (
                minimumLatitude: first.latitude,
                maximumLatitude: first.latitude,
                minimumLongitude: first.longitude,
                maximumLongitude: first.longitude
            )
        ) { bounds, point in
            (
                minimumLatitude: min(bounds.minimumLatitude, point.latitude),
                maximumLatitude: max(bounds.maximumLatitude, point.latitude),
                minimumLongitude: min(bounds.minimumLongitude, point.longitude),
                maximumLongitude: max(bounds.maximumLongitude, point.longitude)
            )
        }

        let center = CLLocationCoordinate2D(
            latitude: (bounds.minimumLatitude + bounds.maximumLatitude) / 2,
            longitude: (bounds.minimumLongitude + bounds.maximumLongitude) / 2
        )
        let latitudeDelta = max(
            minimumSpan,
            (bounds.maximumLatitude - bounds.minimumLatitude) * paddingMultiplier
        )
        let longitudeDelta = max(
            minimumSpan,
            (bounds.maximumLongitude - bounds.minimumLongitude) * paddingMultiplier
        )

        return .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }
}
