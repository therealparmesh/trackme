import CoreLocation
import Foundation
import Observation

@MainActor
protocol LocationManagerClient: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var delegate: CLLocationManagerDelegate? { get set }
    var activityType: CLActivityType { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var showsBackgroundLocationIndicator: Bool { get set }

    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: LocationManagerClient {}

enum LocationDisplayStatus: Equatable {
    case locationNeeded, locationOff, finding, ready, live, paused, weakSignal, signalLost
}

enum GPSStatus: Equatable {
    case finding, ready, weak, lost
}

@MainActor
@Observable
final class LocationTracker: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum State {
        case idle
        case tracking
        case paused
    }

    @ObservationIgnored let manager: LocationManagerClient
    var lastAcceptedLocation: CLLocation?
    var lastReadyLocation: CLLocation?
    var lastRawLocationUpdateAt: Date?
    var startDate: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauses: [WorkoutPause] = []
    var startsNewSegment = true
    var gpsStatus: GPSStatus = .finding
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var signalTask: Task<Void, Never>?
    @ObservationIgnored var readinessTask: Task<Void, Never>?

    var state: State = .idle
    var activity: ActivityKind = .walk
    var elapsed: TimeInterval = 0
    var distance: Double = 0
    var route: [RoutePoint] = []
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isRequestingAuthorization = false
    var errorMessage: String?

    init(manager: LocationManagerClient = CLLocationManager()) {
        self.manager = manager
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

    func prepareForWorkout() {
        guard state == .idle else { return }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
            if !hasRecentReadyFix {
                gpsStatus = .finding
            }
            beginLocationUpdatesIfAuthorized(background: false)
        case .notDetermined:
            gpsStatus = .finding
        case .denied, .restricted:
            gpsStatus = .lost
            errorMessage = Self.locationAccessMessage
        @unknown default:
            gpsStatus = .finding
            errorMessage = "Your location is temporarily unavailable. Try again in a moment."
        }
    }

    func requestStartupLocationAccess() {
        guard state == .idle else { return }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            prepareForWorkout()
        case .notDetermined:
            guard !isRequestingAuthorization else { return }
            errorMessage = nil
            gpsStatus = .finding
            isRequestingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            gpsStatus = .lost
            errorMessage = Self.locationAccessMessage
        @unknown default:
            gpsStatus = .finding
            errorMessage = "Your location is temporarily unavailable. Try again in a moment."
        }
    }

    func start() {
        errorMessage = nil
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard isReadyToStart else {
                prepareForWorkout()
                return
            }
            guard hasRecentReadyFix else {
                gpsStatus = .finding
                prepareForWorkout()
                return
            }
            beginSession()
        case .notDetermined:
            requestStartupLocationAccess()
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
        gpsStatus = .finding
        lastRawLocationUpdateAt = .now
        beginLocationUpdatesIfAuthorized(background: true)
        startClock()
        startSignalMonitor()
    }

    func pause() {
        guard state == .tracking else { return }
        let now = Date()
        updateElapsed(at: now)
        state = .paused
        pausedAt = now
        lastAcceptedLocation = nil
        stopTimers()
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
        gpsStatus = .finding
        lastRawLocationUpdateAt = .now
        state = .tracking
        beginLocationUpdatesIfAuthorized(background: true)
        startClock()
        startSignalMonitor()
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
        stopTimers()

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

    private func startSignalMonitor() {
        signalTask?.cancel()
        signalTask = Task { [weak self] in
            await self?.runSignalMonitor()
        }
    }

    private func runSignalMonitor() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            refreshSignalTimeout()
        }
    }

    private func clearSession() {
        stopTimers()
        lastAcceptedLocation = nil
        startDate = nil
        pausedAt = nil
        pausedDuration = 0
        pauses = []
        startsNewSegment = true
        lastRawLocationUpdateAt = nil
        elapsed = 0
        distance = 0
        route = []
    }

    private func stopTimers() {
        clockTask?.cancel()
        clockTask = nil
        signalTask?.cancel()
        signalTask = nil
        readinessTask?.cancel()
        readinessTask = nil
    }

    static let locationAccessMessage =
        "Location access is off. Allow it in iPhone Settings to map and measure your workout."
}
