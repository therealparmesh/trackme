import CoreLocation

extension LocationTracker {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        updateAuthorization(manager.authorizationStatus)
    }

    private func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        isRequestingAuthorization = false

        if canRecordLocation {
            errorMessage = nil
            if state == .tracking {
                beginLocationUpdatesIfAuthorized(background: true)
            } else if state == .idle {
                prepareForWorkout()
            }
        } else {
            if state == .tracking { pause() }
            gpsStatus = .lost
            lastReadyLocation = nil
            cancelReadinessExpiry()
            errorMessage = status == .notDetermined && state == .idle ? nil : locationPermissionMessage
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard canRecordLocation else { return }
        processLocationUpdates(locations, receivedAt: .now)
    }

    func processLocationUpdates(_ locations: [CLLocation], receivedAt: Date) {
        guard state != .paused else { return }

        if state == .idle {
            updateReadiness(from: locations, now: receivedAt)
            return
        }

        guard let startDate else { return }
        for location in locations {
            guard GPSPointFilter.isValidSample(location, since: startDate, now: receivedAt),
                  location.timestamp > (lastRawLocationUpdateAt ?? .distantPast),
                  location.timestamp >= (routeAnchorNotBefore ?? startDate) else { continue }

            // Decide route continuity from measurement time, even for delayed batches.
            if signalHasTimedOut(at: location.timestamp) {
                breakRouteForSignalGap()
            }
            lastRawLocationUpdateAt = location.timestamp
            if GPSPointFilter.hasTrackingAccuracy(location) {
                lastUsableLocationUpdateAt = location.timestamp
            }
            if GPSPointFilter.shouldAccept(
                location,
                after: lastAcceptedLocation,
                sessionStart: startDate,
                now: receivedAt
            ) {
                append(location)
            }
            updateLiveSignal(from: location, receivedAt: receivedAt)
        }
        refreshSignalTimeout(now: receivedAt)
        saveActiveDraft()
    }

    private func updateLiveSignal(from location: CLLocation, receivedAt: Date) {
        guard GPSPointFilter.isCurrentSignalSample(location, now: receivedAt) else { return }
        if GPSPointFilter.hasReadyAccuracy(location) {
            lastReadyLocation = location
            gpsStatus = .ready
            errorMessage = nil
        } else if gpsStatus != .lost || lastAcceptedLocation != nil {
            gpsStatus = .weak
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard state != .paused else { return }
        switch (error as? CLError)?.code {
        case .locationUnknown:
            markSignalWeak()
        case .denied:
            let status = manager.authorizationStatus
            updateAuthorization(status == .restricted ? .restricted : .denied)
        case .network:
            gpsStatus = .lost
            errorMessage = "Your location could not be updated. Check your connection and try again."
        default:
            markSignalWeak()
            errorMessage = "Your location could not be updated. Try again."
        }
    }

    func beginLocationUpdatesIfAuthorized(background: Bool) {
        guard canRecordLocation else { return }
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        manager.startUpdatingLocation()
    }

    func refreshSignalTimeout(now: Date = .now) {
        guard state == .tracking else { return }
        if signalHasTimedOut(at: now) {
            gpsStatus = .lost
        }
    }

    private func signalHasTimedOut(at date: Date) -> Bool {
        GPSPointFilter.signalTimedOut(
            since: lastUsableLocationUpdateAt ?? startDate,
            now: date
        )
    }

    private func updateReadiness(from locations: [CLLocation], now: Date) {
        if let readyLocation = locations.last(where: { GPSPointFilter.isReadyFix($0, now: now) }) {
            lastReadyLocation = readyLocation
            if canRecordLocation {
                errorMessage = nil
            }
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

    func append(_ location: CLLocation, timestamp: Date? = nil) {
        let previous = lastAcceptedLocation
        if let previous {
            distance += HorizontalDistanceCalculator.distance(from: previous, to: location)
        }
        let point = RoutePoint(location: location, startsNewSegment: previous == nil, timestamp: timestamp)
        lastAcceptedLocation = timestamp == nil ? location : point.location
        route.append(point)
        routeAnchorNotBefore = nil
    }

    private func markSignalWeak() {
        if gpsStatus != .lost { gpsStatus = .weak }
    }

    func breakRouteForSignalGap(notBefore date: Date? = nil) {
        routeAnchorNotBefore = date
        lastAcceptedLocation = nil
    }

    func restoreIdleReadiness() {
        if canRecordLocation, let lastReadyLocation, GPSPointFilter.isReadyFix(lastReadyLocation) {
            gpsStatus = .ready
            scheduleReadinessExpiry(for: lastReadyLocation)
        } else {
            gpsStatus = .finding
            cancelReadinessExpiry()
        }
    }

    func expireIdleReadinessIfNeeded() {
        if gpsStatus == .ready, !hasRecentReadyFix {
            gpsStatus = .finding
            cancelReadinessExpiry()
        }
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
