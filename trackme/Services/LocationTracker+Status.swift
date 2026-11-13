import CoreLocation

extension LocationTracker {
    var isReadyToStart: Bool {
        state == .idle && canRecordLocation && gpsStatus == .ready && hasRecentReadyFix && !isRequestingAuthorization
    }

    var hasMeaningfulWorkout: Bool {
        WorkoutPathFilter.isMeaningful(distance: distance)
    }

    var displayStatus: LocationDisplayStatus {
        if isRequestingAuthorization {
            return .finding
        }
        if authorizationStatus == .notDetermined {
            return .locationNeeded
        }
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return .locationOff
        }
        guard isAuthorized else { return .finding }
        guard hasPreciseLocation else { return .locationOff }

        switch state {
        case .idle:
            return idleSignalStatus
        case .tracking:
            return trackingSignalStatus
        case .paused:
            return .paused
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var canRecordLocation: Bool { isAuthorized && hasPreciseLocation }

    var locationPermissionMessage: String? {
        if isAuthorized {
            return hasPreciseLocation ? nil : Self.preciseLocationMessage
        }
        return Self.locationAccessMessage
    }

    var mapFocusLocation: CLLocation? {
        if let lastAcceptedLocation {
            return lastAcceptedLocation
        }
        guard canRecordLocation, hasRecentReadyFix else { return nil }
        return lastReadyLocation
    }

    var hasRecentReadyFix: Bool {
        guard let lastReadyLocation else { return false }
        return GPSPointFilter.isReadyFix(lastReadyLocation)
    }

    private var idleSignalStatus: LocationDisplayStatus {
        switch gpsStatus {
        case .finding:
            return .finding
        case .ready:
            return .ready
        case .weak:
            return .weakSignal
        case .lost:
            return .signalLost
        }
    }

    private var trackingSignalStatus: LocationDisplayStatus {
        switch gpsStatus {
        case .weak:
            return .weakSignal
        case .lost:
            return .signalLost
        case .finding, .ready:
            return .live
        }
    }
}
