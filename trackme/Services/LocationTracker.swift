import CoreLocation
import Foundation
import Observation

@MainActor
protocol LocationManagerClient: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
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
    @ObservationIgnored private let activeDraftStore: ActiveWorkoutDraftStoring
    var lastAcceptedLocation: CLLocation?
    var lastReadyLocation: CLLocation?
    var lastRawLocationUpdateAt: Date?
    var lastUsableLocationUpdateAt: Date?
    var routeAnchorNotBefore: Date?
    var startDate: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauses: [WorkoutPause] = []
    var gpsStatus: GPSStatus = .finding
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored var readinessTask: Task<Void, Never>?

    var state: State = .idle
    var activity: ActivityKind = .walk
    var elapsed: TimeInterval = 0
    var distance: Double = 0
    var route: [RoutePoint] = []
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var hasPreciseLocation = true
    var isRequestingAuthorization = false
    var errorMessage: String?

    init(
        manager: LocationManagerClient = CLLocationManager(),
        activeDraftStore: ActiveWorkoutDraftStoring = FileActiveWorkoutDraftStore()
    ) {
        self.manager = manager
        self.activeDraftStore = activeDraftStore
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
        hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
    }

    var averagePace: TimeInterval {
        guard distance > 0 else { return 0 }
        return elapsed / (distance / 1_609.344)
    }

    func prepareForWorkout() {
        guard state == .idle else { return }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard hasPreciseLocation else {
                errorMessage = Self.preciseLocationMessage
                return
            }
            expireIdleReadinessIfNeeded()
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
        guard authorizationStatus == .notDetermined else {
            prepareForWorkout()
            return
        }
        guard !isRequestingAuthorization else { return }
        errorMessage = nil
        gpsStatus = .finding
        isRequestingAuthorization = true
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard state == .idle else { return }
        guard isReadyToStart else {
            requestStartupLocationAccess()
            return
        }
        clearSession()
        errorMessage = nil
        let now = Date.now
        startDate = now
        lastUsableLocationUpdateAt = now
        // Use the same recent fix that enabled Start so the first leg is recorded.
        if let lastReadyLocation, now.timeIntervalSince(lastReadyLocation.timestamp) <= 5 {
            append(lastReadyLocation, timestamp: now)
        }
        beginTracking()
    }

    func pause(now: Date = .now) {
        guard state == .tracking else { return }
        updateElapsed(at: now)
        state = .paused
        pausedAt = now
        breakRouteForSignalGap()
        stopUpdates()
        saveActiveDraft()
    }

    func resume() {
        guard state == .paused else { return }
        guard canRecordLocation else {
            errorMessage = locationPermissionMessage
            return
        }
        errorMessage = nil
        let resumedAt = Date.now
        if let pausedAt {
            pausedDuration += resumedAt.timeIntervalSince(pausedAt)
            pauses.append(WorkoutPause(startDate: pausedAt, endDate: resumedAt))
        }
        self.pausedAt = nil
        breakRouteForSignalGap(notBefore: resumedAt)
        lastUsableLocationUpdateAt = resumedAt
        beginTracking()
    }

    private func beginTracking() {
        state = .tracking
        gpsStatus = .finding
        beginLocationUpdatesIfAuthorized(background: true)
        startClock()
        saveActiveDraft()
    }

    func finish(save: (WorkoutSnapshot) throws -> Void) rethrows -> WorkoutSnapshot? {
        guard let startDate, state != .idle, hasMeaningfulWorkout else { return nil }
        let endDate = Date.now
        var pauses = pauses
        if let pausedAt {
            pauses.append(WorkoutPause(startDate: pausedAt, endDate: endDate))
        }

        let snapshot = WorkoutSnapshot(
            activity: activity,
            startDate: startDate,
            endDate: endDate,
            duration: activeDuration(at: endDate),
            distance: distance,
            elevationGain: ElevationGainCalculator.totalGain(from: route),
            route: route,
            pauses: pauses
        )
        try save(snapshot)
        discard()
        return snapshot
    }

    func discard() {
        stopUpdates()
        state = .idle
        clearSession()
        activeDraftStore.clear()
        errorMessage = nil
        restoreIdleReadiness()
        prepareForWorkout()
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
                let now = Date.now
                self.updateElapsed(at: now)
                self.refreshSignalTimeout(now: now)
            }
        }
    }

    private func updateElapsed(at date: Date) {
        elapsed = activeDuration(at: date)
    }

    private func activeDuration(at date: Date) -> TimeInterval {
        guard let startDate else { return 0 }
        return max(0, (pausedAt ?? date).timeIntervalSince(startDate) - pausedDuration)
    }

    private func clearSession() {
        stopTimers()
        lastAcceptedLocation = nil
        startDate = nil
        pausedAt = nil
        pausedDuration = 0
        pauses = []
        routeAnchorNotBefore = nil
        lastRawLocationUpdateAt = nil
        lastUsableLocationUpdateAt = nil
        elapsed = 0
        distance = 0
        route = []
    }

    private func stopTimers() {
        clockTask?.cancel()
        clockTask = nil
        readinessTask?.cancel()
        readinessTask = nil
    }

    private func stopUpdates() {
        stopTimers()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    static let locationAccessMessage =
        "Location access is off. Allow it in iPhone Settings to map and measure your workout."
    static let preciseLocationMessage =
        "Turn on Precise Location in iPhone Settings to map and measure your workout."
}

extension LocationTracker {
    @discardableResult
    func restoreActiveWorkoutIfAvailable(now: Date = .now) -> Bool {
        guard state == .idle, let draft = activeDraftStore.load() else { return false }

        activity = draft.activity
        startDate = draft.startDate
        pausedAt = draft.pausedAt
        pausedDuration = draft.pausedDuration
        pauses = draft.pauses
        elapsed = draft.elapsed
        distance = draft.distance
        route = draft.route
        lastAcceptedLocation = draft.startsNewSegment ? nil : draft.lastAcceptedLocation?.location
        lastReadyLocation = draft.lastReadyLocation?.location ?? lastAcceptedLocation
        lastRawLocationUpdateAt = draft.lastRawLocationUpdateAt
        lastUsableLocationUpdateAt = draft.lastUsableLocationUpdateAt
            ?? lastAcceptedLocation?.timestamp ?? lastReadyLocation?.timestamp
        routeAnchorNotBefore = nil
        errorMessage = locationPermissionMessage

        switch draft.state {
        case .tracking:
            state = .tracking
            guard canRecordLocation else {
                pause(now: now)
                return true
            }
            if GPSPointFilter.signalTimedOut(since: lastUsableLocationUpdateAt, now: now) {
                breakRouteForSignalGap(notBefore: now)
                lastUsableLocationUpdateAt = now
            } else if lastAcceptedLocation == nil {
                routeAnchorNotBefore = now
            }
            updateElapsed(at: now)
            beginTracking()
            return true
        case .paused:
            stopUpdates()
            state = .paused
            gpsStatus = .weak
            updateElapsed(at: now)
        }

        saveActiveDraft()
        return true
    }

    func saveActiveDraft() {
        guard let draft = activeDraft else { return }
        activeDraftStore.save(draft)
    }

    private var activeDraft: ActiveWorkoutDraft? {
        guard let startDate, let draftState = activeDraftState else { return nil }
        return ActiveWorkoutDraft(
            state: draftState,
            activity: activity,
            startDate: startDate,
            pausedAt: pausedAt,
            pausedDuration: pausedDuration,
            pauses: pauses,
            startsNewSegment: lastAcceptedLocation == nil,
            elapsed: elapsed,
            distance: distance,
            route: route,
            lastAcceptedLocation: lastAcceptedLocation.map {
                RoutePoint(location: $0, startsNewSegment: false)
            },
            lastReadyLocation: lastReadyLocation.map {
                RoutePoint(location: $0, startsNewSegment: false)
            },
            lastRawLocationUpdateAt: lastRawLocationUpdateAt,
            lastUsableLocationUpdateAt: lastUsableLocationUpdateAt
        )
    }

    private var activeDraftState: ActiveWorkoutDraft.State? {
        switch state {
        case .idle:
            return nil
        case .tracking:
            return .tracking
        case .paused:
            return .paused
        }
    }
}
