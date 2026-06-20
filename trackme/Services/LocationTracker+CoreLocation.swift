import CoreLocation

extension LocationTracker {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isRequestingAuthorization = false

        if isAuthorized {
            errorMessage = nil
            if state == .tracking {
                beginLocationUpdatesIfAuthorized(background: true)
            } else if state == .idle {
                prepareForWorkout()
            }
        } else if state == .tracking {
            pause()
            errorMessage = "Location access was turned off, so your workout is paused. "
                + "Allow access in iPhone Settings to continue."
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            gpsStatus = .lost
            errorMessage = Self.locationAccessMessage
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state != .paused else { return }
        lastRawLocationUpdateAt = .now

        if state == .idle {
            updateReadiness(from: locations)
            return
        }

        var acceptedLocation = false
        for location in locations where isUsable(location) {
            append(location)
            acceptedLocation = true
        }
        acceptedLocation ? (gpsStatus = .ready) : markSignalWeak()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationError = error as? CLError else {
            errorMessage = "Your location could not be updated. Try again."
            return
        }
        switch locationError.code {
        case .locationUnknown:
            markSignalWeak()
        case .denied:
            markSignalLost()
            errorMessage = Self.locationAccessMessage
        case .network:
            markSignalLost()
            errorMessage = "Your location could not be updated. Check your connection and try again."
        default:
            markSignalWeak()
            errorMessage = "Your location could not be updated. Try again."
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        markSignalLost()
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        if state == .tracking {
            startsNewSegment = true
            gpsStatus = .finding
        }
    }

    func beginLocationUpdatesIfAuthorized(background: Bool) {
        guard isAuthorized else {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                errorMessage = Self.locationAccessMessage
            }
            return
        }
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        manager.startUpdatingLocation()
    }

    func refreshSignalTimeout() {
        guard state == .tracking,
              GPSPointFilter.signalTimedOut(since: lastRawLocationUpdateAt) else {
            return
        }
        markSignalLost()
    }

    private func updateReadiness(from locations: [CLLocation]) {
        if let readyLocation = locations.last(where: { GPSPointFilter.isReadyFix($0) }) {
            lastReadyLocation = readyLocation
            gpsStatus = .ready
            scheduleReadinessExpiry()
        } else if locations.isEmpty {
            gpsStatus = .finding
            cancelReadinessExpiry()
        } else {
            gpsStatus = .weak
            cancelReadinessExpiry()
        }
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
            distance += HorizontalDistanceCalculator.distance(from: previous, to: location)
        }
        lastReadyLocation = location
        lastAcceptedLocation = location
        route.append(RoutePoint(location: location, startsNewSegment: startsNewSegment))
        startsNewSegment = false
    }

    private func markSignalWeak() {
        guard state != .paused else { return }
        gpsStatus = .weak
    }

    private func markSignalLost() {
        guard state != .paused else { return }
        if state == .tracking {
            breakRouteForSignalGap()
        }
        gpsStatus = .lost
    }

    private func breakRouteForSignalGap() {
        lastAcceptedLocation = nil
        startsNewSegment = true
    }

    private func scheduleReadinessExpiry() {
        readinessTask?.cancel()
        readinessTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(GPSPointFilter.readyFixLifetimeSeconds))
            } catch {
                return
            }
            guard let self, self.state == .idle, !self.hasRecentReadyFix else { return }
            self.gpsStatus = .finding
        }
    }

    private func cancelReadinessExpiry() {
        readinessTask?.cancel()
        readinessTask = nil
    }
}
