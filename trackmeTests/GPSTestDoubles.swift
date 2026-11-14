import CoreLocation
@testable import trackme

@MainActor
final class SignalTestLocationManager: LocationManagerClient {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    weak var delegate: CLLocationManagerDelegate?
    var activityType: CLActivityType = .other
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var authorizationRequests = 0
    var startUpdatingLocationCalls = 0
    var stopUpdatingLocationCalls = 0

    func requestWhenInUseAuthorization() {
        authorizationRequests += 1
    }

    func startUpdatingLocation() {
        startUpdatingLocationCalls += 1
    }
    func stopUpdatingLocation() {
        stopUpdatingLocationCalls += 1
    }
}

final class InMemoryActiveWorkoutDraftStore: ActiveWorkoutDraftStoring {
    var draft: ActiveWorkoutDraft?
    var didClear = false

    func load() -> ActiveWorkoutDraft? {
        draft
    }

    func save(_ draft: ActiveWorkoutDraft) {
        self.draft = draft
        didClear = false
    }

    func clear() {
        draft = nil
        didClear = true
    }
}
