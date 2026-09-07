import CoreLocation
@testable import trackme

@MainActor
final class SignalTestLocationManager: LocationManagerClient {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    weak var delegate: CLLocationManagerDelegate?
    var activityType: CLActivityType = .other
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var startUpdatingLocationCalls = 0
    var stopUpdatingLocationCalls = 0

    func requestWhenInUseAuthorization() {}
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

final class SignalTestMotionActivityClient: MotionActivityClient {
    var state: MotionState
    var startCalls = 0
    var stopCalls = 0

    init(state: MotionState = .unknown) {
        self.state = state
    }

    func start() {
        startCalls += 1
    }

    func stop() {
        stopCalls += 1
    }

    func state(at date: Date) -> MotionState {
        state
    }
}
