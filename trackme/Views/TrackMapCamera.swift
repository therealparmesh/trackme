import CoreLocation
import MapKit
import SwiftUI

enum TrackMapCamera {
    static let focusDistance: CLLocationDistance = 750

    static func position(focusing location: CLLocation?) -> MapCameraPosition {
        guard let location else {
            return .userLocation(followsHeading: false, fallback: .automatic)
        }

        return .camera(
            MapCamera(
                centerCoordinate: location.coordinate,
                distance: focusDistance,
                heading: 0,
                pitch: 0
            )
        )
    }
}
