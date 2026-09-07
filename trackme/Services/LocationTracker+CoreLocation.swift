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

        guard let startDate else { return }
        if lastUsableLocationUpdateAt == nil {
            lastUsableLocationUpdateAt = lastRawLocationUpdateAt ?? startDate
        }
        for location in locations {
            guard GPSPointFilter.isValidSample(location, since: startDate, now: receivedAt),
                  location.timestamp > (lastRawLocationUpdateAt ?? .distantPast),
                  location.timestamp >= (routeAnchorNotBefore ?? startDate) else { continue }

            // Check measurement times before advancing the signal clock so delayed
            // batches preserve continuous routes without bridging missing fixes.
            updateSignalTimeout(at: location.timestamp)
            lastRawLocationUpdateAt = location.timestamp
            if GPSPointFilter.hasTrackingAccuracy(location) {
                lastUsableLocationUpdateAt = location.timestamp
            }
            if isUsable(location, receivedAt: receivedAt) {
                append(location)
            }
            if GPSPointFilter.isCurrentSignalSample(location, now: receivedAt) {
                errorMessage = nil
                if GPSPointFilter.hasReadyAccuracy(location) {
                    lastReadyLocation = location
                    gpsStatus = .ready
                } else {
                    markSignalWeak()
                }
            }
        }
        updateSignalTimeout(at: receivedAt)
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
            lastUsableLocationUpdateAt = now
            lastStationaryAt = nil
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
        guard state == .tracking else { return }
        updateSignalTimeout(at: now)
        if gpsStatus == .lost {
            saveActiveDraft()
        }
    }

    func runSignalMonitor() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            refreshSignalTimeout()
        }
    }

    private func updateSignalTimeout(at date: Date) {
        let lastUsable = lastUsableLocationUpdateAt ?? lastRawLocationUpdateAt ?? startDate
        // Stationary silence is expected with a distance filter. Explicitly poor
        // fixes still time out, even when motion reports stationary.
        if motionActivity.state(at: date) == .stationary,
           (lastRawLocationUpdateAt ?? .distantPast) <= (lastUsable ?? .distantPast) {
            lastStationaryAt = max(lastStationaryAt ?? date, date)
            return
        }
        let timeoutReference = max(lastUsable ?? .distantPast, lastStationaryAt ?? .distantPast)
        if GPSPointFilter.signalTimedOut(since: timeoutReference, now: date) {
            markSignalLost(at: date)
        }
    }

    private func updateReadiness(from locations: [CLLocation], now: Date) {
        if let readyLocation = locations.last(where: { GPSPointFilter.isReadyFix($0, now: now) }) {
            lastReadyLocation = readyLocation
            gpsStatus = .ready
            scheduleReadinessExpiry(for: readyLocation)
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

    private func scheduleReadinessExpiry(for location: CLLocation) {
        readinessTask?.cancel()
        let expiresAt = GPSPointFilter.readyFixExpiration(for: location)
        readinessTask = Task { [weak self] in
            do {
                // Cached fixes have only the remainder of their lifetime left.
                try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.state == .idle,
                  self.gpsStatus == .ready, !self.hasRecentReadyFix else { return }
            self.gpsStatus = .finding
        }
    }

    private func cancelReadinessExpiry() {
        readinessTask?.cancel()
        readinessTask = nil
    }
}
