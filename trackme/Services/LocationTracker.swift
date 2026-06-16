import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationTracker: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum State {
        case idle
        case tracking
        case paused
    }

    private let manager = CLLocationManager()
    private var lastAcceptedLocation: CLLocation?
    private var startDate: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauses: [WorkoutPause] = []
    private var startsNewSegment = true
    private var pendingStart = false
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    var state: State = .idle
    var activity: ActivityKind = .walk
    var elapsed: TimeInterval = 0
    var distance: Double = 0
    var route: [RoutePoint] = []
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isRequestingAuthorization = false
    var errorMessage: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    var averagePace: TimeInterval {
        guard distance > 0 else { return 0 }
        return elapsed / (distance / 1_609.344)
    }

    func start() {
        errorMessage = nil
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginSession()
        case .notDetermined:
            guard !pendingStart else { return }
            pendingStart = true
            isRequestingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = Self.locationAccessMessage
        @unknown default:
            errorMessage = "Your location is temporarily unavailable. Try again in a moment."
        }
    }

    private func beginSession() {
        clearSession()
        startDate = Date()
        state = .tracking

        beginLocationUpdatesIfAuthorized()
        startClock()
    }

    func pause() {
        guard state == .tracking else { return }
        let now = Date()
        updateElapsed(at: now)
        state = .paused
        pausedAt = now
        lastAcceptedLocation = nil
        clockTask?.cancel()
        clockTask = nil
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard state == .paused else { return }
        errorMessage = nil
        if let pausedAt {
            let resumedAt = Date()
            pausedDuration += resumedAt.timeIntervalSince(pausedAt)
            pauses.append(WorkoutPause(startDate: pausedAt, endDate: resumedAt))
        }
        self.pausedAt = nil
        startsNewSegment = true
        state = .tracking
        beginLocationUpdatesIfAuthorized()
        startClock()
    }

    func stop() -> WorkoutSnapshot? {
        guard let startDate, state != .idle else { return nil }
        let endDate = Date()
        if state == .paused, let pausedAt {
            pausedDuration += endDate.timeIntervalSince(pausedAt)
            pauses.append(WorkoutPause(startDate: pausedAt, endDate: endDate))
            self.pausedAt = nil
        }
        updateElapsed(at: endDate)
        manager.stopUpdatingLocation()
        clockTask?.cancel()
        clockTask = nil

        let path = WorkoutPathFilter.finalized(distance: distance, route: route)
        let elevationGain = ElevationGainCalculator.totalGain(from: path.route)
        let snapshot = WorkoutSnapshot(
            activity: activity,
            startDate: startDate,
            endDate: endDate,
            duration: elapsed,
            distance: path.distance,
            elevationGain: elevationGain,
            route: path.route,
            pauses: pauses
        )
        state = .idle
        return snapshot
    }

    func reset() {
        guard state == .idle else { return }
        clearSession()
        errorMessage = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isRequestingAuthorization = false

        if pendingStart {
            pendingStart = false
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                beginSession()
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                errorMessage = Self.locationAccessMessage
            }
        } else if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            errorMessage = nil
            if state == .tracking {
                beginLocationUpdatesIfAuthorized()
            }
        } else if state == .tracking {
            pause()
            errorMessage = "Location access was turned off, so your workout is paused. "
                + "Allow access in iPhone Settings to continue."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .tracking else { return }
        for location in locations where isUsable(location) {
            append(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationError = error as? CLError else {
            errorMessage = "Your location could not be updated. Try again."
            return
        }
        switch locationError.code {
        case .locationUnknown:
            return
        case .denied:
            errorMessage = Self.locationAccessMessage
        case .network:
            errorMessage = "Your location could not be updated. Check your connection and try again."
        default:
            errorMessage = "Your location could not be updated. Try again."
        }
    }

    private func beginLocationUpdatesIfAuthorized() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                errorMessage = Self.locationAccessMessage
            }
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        guard let startDate else { return false }
        return GPSPointFilter.shouldAccept(
            location,
            after: lastAcceptedLocation,
            sessionStart: startDate
        )
    }

    private func append(_ location: CLLocation) {
        if let previous = lastAcceptedLocation {
            distance += HorizontalDistanceCalculator.distance(
                from: previous,
                to: location
            )
        }

        lastAcceptedLocation = location
        route.append(RoutePoint(location: location, startsNewSegment: startsNewSegment))
        startsNewSegment = false
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                self.updateElapsed(at: .now)
            }
        }
    }

    private func updateElapsed(at date: Date) {
        guard let startDate else { return }
        let activePause = pausedAt.map { date.timeIntervalSince($0) } ?? 0
        elapsed = max(0, date.timeIntervalSince(startDate) - pausedDuration - activePause)
    }

    private func clearSession() {
        clockTask?.cancel()
        clockTask = nil
        lastAcceptedLocation = nil
        startDate = nil
        pausedAt = nil
        pausedDuration = 0
        pauses = []
        startsNewSegment = true
        elapsed = 0
        distance = 0
        route = []
    }

    private static let locationAccessMessage =
        "Location access is off. Allow it in iPhone Settings to map and measure your workout."
}
