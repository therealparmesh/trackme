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
        processLocationUpdates(locations, receivedAt: .now)
    }

    func processLocationUpdates(_ locations: [CLLocation], receivedAt: Date) {
        guard state != .paused else { return }

        if state == .idle {
            updateReadiness(from: locations, now: receivedAt)
            return
        }

        for location in locations where isUsable(location, receivedAt: receivedAt) {
            append(location)
        }

        let latestCurrentLocation = locations.last {
            GPSPointFilter.isCurrentSignalSample($0, now: receivedAt)
        }
        let latestReadyLocation = locations.last {
            GPSPointFilter.isCurrentSignalSample($0, now: receivedAt)
                && GPSPointFilter.hasReadyAccuracy($0)
        }

        if let latestCurrentLocation {
            lastRawLocationUpdateAt = receivedAt
            errorMessage = nil
        }
        if let latestReadyLocation {
            lastReadyLocation = latestReadyLocation
        }
        if let latestCurrentLocation,
           GPSPointFilter.hasReadyAccuracy(latestCurrentLocation) {
            gpsStatus = .ready
        } else if latestCurrentLocation != nil {
            markSignalWeak()
        }
        saveActiveDraft()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationError = error as? CLError else {
            markSignalWeak()
            errorMessage = "Your location could not be updated. Try again."
            saveActiveDraft()
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
        saveActiveDraft()
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        if state == .tracking {
            let now = Date.now
            breakRouteForSignalGap()
            lastRawLocationUpdateAt = now
            gpsStatus = .finding
            saveActiveDraft()
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

    func refreshSignalTimeout(now: Date = .now) {
        guard state == .tracking,
              motionActivity.state(at: now) != .stationary,
              GPSPointFilter.signalTimedOut(since: lastRawLocationUpdateAt, now: now) else {
            return
        }
        markSignalLost(at: now)
        saveActiveDraft()
    }

    private func updateReadiness(from locations: [CLLocation], now: Date) {
        if let readyLocation = locations.last(where: { GPSPointFilter.isReadyFix($0, now: now) }) {
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

    private func isUsable(_ location: CLLocation, receivedAt: Date) -> Bool {
        guard let startDate else { return false }
        if let routeAnchorNotBefore, lastAcceptedLocation == nil,
           location.timestamp < routeAnchorNotBefore {
            return false
        }
        return GPSPointFilter.shouldAccept(
            location,
            after: lastAcceptedLocation,
            sessionStart: startDate,
            motionState: motionActivity.state(at: location.timestamp),
            now: receivedAt
        )
    }

    private func append(_ location: CLLocation) {
        if let previous = lastAcceptedLocation {
            distance += HorizontalDistanceCalculator.distance(from: previous, to: location)
        }
        lastAcceptedLocation = location
        route.append(RoutePoint(location: location, startsNewSegment: startsNewSegment))
        startsNewSegment = false
        routeAnchorNotBefore = nil
    }

    private func markSignalWeak() {
        guard state != .paused else { return }
        gpsStatus = .weak
    }

    private func markSignalLost(at date: Date = .now) {
        guard state != .paused else { return }
        if state == .tracking {
            breakRouteForSignalGap(notBefore: date)
        }
        gpsStatus = .lost
    }

    func breakRouteForSignalGap(notBefore date: Date? = nil) {
        if let date, routeAnchorNotBefore == nil {
            routeAnchorNotBefore = date
        }
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
