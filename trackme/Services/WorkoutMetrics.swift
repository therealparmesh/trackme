import CoreLocation

enum HorizontalDistanceCalculator {
    static func distance(
        from start: CLLocation,
        to end: CLLocation
    ) -> CLLocationDistance {
        let startLocation = CLLocation(
            latitude: start.coordinate.latitude,
            longitude: start.coordinate.longitude
        )
        let endLocation = CLLocation(
            latitude: end.coordinate.latitude,
            longitude: end.coordinate.longitude
        )
        return startLocation.distance(from: endLocation)
    }
}

enum GPSPointFilter {
    private static let maximumReadyHorizontalAccuracy: CLLocationAccuracy = 25
    private static let maximumTrackingHorizontalAccuracy: CLLocationAccuracy = 50
    private static let maximumSpeed: CLLocationSpeed = 12
    private static let minimumMovementSpeed: CLLocationSpeed = 0.35
    private static let signalTimeout: TimeInterval = 20
    private static let readyFixLifetime: TimeInterval = 30
    private static let futureTimestampTolerance: TimeInterval = 5

    static func shouldAccept(
        _ location: CLLocation,
        after previous: CLLocation?,
        sessionStart: Date,
        motionState: MotionState,
        now: Date = .now
    ) -> Bool {
        guard isValidSample(location, since: sessionStart, now: now),
              hasTrackingAccuracy(location) else {
            return false
        }

        guard let previous else { return hasReadyAccuracy(location) }
        guard motionState != .stationary else { return false }
        let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return false }

        let distance = HorizontalDistanceCalculator.distance(from: previous, to: location)
        let accuracyFloor = min(25, max(previous.horizontalAccuracy, location.horizontalAccuracy) * 0.5)
        let hasReliableSpeed = location.speedAccuracy >= 0
            && location.speed - location.speedAccuracy >= minimumMovementSpeed
        return (motionState == .moving || hasReliableSpeed)
            && distance >= max(4, accuracyFloor)
            && distance / seconds < maximumSpeed
    }

    static func isReadyFix(_ location: CLLocation, now: Date = .now) -> Bool {
        hasReadyAccuracy(location)
            && now < readyFixExpiration(for: location)
            && location.timestamp <= now.addingTimeInterval(futureTimestampTolerance)
    }

    static func readyFixExpiration(for location: CLLocation) -> Date {
        location.timestamp.addingTimeInterval(readyFixLifetime)
    }

    static func hasReadyAccuracy(_ location: CLLocation) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumReadyHorizontalAccuracy
    }

    static func isCurrentSignalSample(_ location: CLLocation, now: Date = .now) -> Bool {
        isValidSample(location, since: now.addingTimeInterval(-signalTimeout), now: now)
    }

    static func hasTrackingAccuracy(_ location: CLLocation) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumTrackingHorizontalAccuracy
    }

    static func isValidSample(_ location: CLLocation, since date: Date, now: Date) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.timestamp >= date
            && location.timestamp <= now.addingTimeInterval(futureTimestampTolerance)
    }

    static func signalTimedOut(since lastUpdateAt: Date?, now: Date = .now) -> Bool {
        guard let lastUpdateAt else { return true }
        return now.timeIntervalSince(lastUpdateAt) > signalTimeout
    }
}

enum WorkoutPathFilter {
    private static let minimumMeaningfulDistance: CLLocationDistance = 20

    static func isMeaningful(distance: CLLocationDistance) -> Bool {
        distance >= minimumMeaningfulDistance
    }

    static func finalized(
        distance: CLLocationDistance,
        route: [RoutePoint]
    ) -> (distance: CLLocationDistance, route: [RoutePoint]) {
        guard isMeaningful(distance: distance) else {
            return (0, [])
        }
        return (distance, route)
    }
}

enum ElevationGainCalculator {
    private static let maximumVerticalAccuracy: CLLocationAccuracy = 20
    private static let minimumClimb: CLLocationDistance = 3
    private static let reversalThreshold: CLLocationDistance = 3

    static func totalGain(from route: [RoutePoint]) -> CLLocationDistance {
        route.routeSegments.reduce(0) { gain, segment in
            gain + gainForSegment(segment)
        }
    }

    private static func gainForSegment(_ segment: [RoutePoint]) -> CLLocationDistance {
        let accurateSamples = segment.filter {
            $0.verticalAccuracy >= 0 && $0.verticalAccuracy <= maximumVerticalAccuracy
        }
        let samples = removingAltitudeSpikes(from: accurateSamples)
        let altitudes = medianFilteredAltitudes(from: samples)
        guard altitudes.count > 1 else { return 0 }

        return gain(
            from: altitudes,
            minimumClimb: minimumClimb,
            reversalThreshold: reversalThreshold
        )
    }

    private static func removingAltitudeSpikes(from samples: [RoutePoint]) -> [RoutePoint] {
        guard let first = samples.first else { return [] }
        return samples.dropFirst().reduce(into: [first]) { accepted, sample in
            guard let previous = accepted.last else { return }
            let seconds = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { return }
            let maximumChange = max(8, seconds * 4)
            if abs(sample.altitude - previous.altitude) <= maximumChange {
                accepted.append(sample)
            }
        }
    }

    private static func medianFilteredAltitudes(from samples: [RoutePoint]) -> [CLLocationDistance] {
        guard samples.count > 2 else { return samples.map(\.altitude) }
        return samples.indices.map { index in
            if index == samples.startIndex || index == samples.index(before: samples.endIndex) {
                return samples[index].altitude
            }
            let lowerBound = max(samples.startIndex, index - 2)
            let upperBound = min(samples.index(before: samples.endIndex), index + 2)
            let values = samples[lowerBound...upperBound].map(\.altitude).sorted()
            return values[values.count / 2]
        }
    }

    static func gain(
        from altitudes: [CLLocationDistance],
        minimumClimb: CLLocationDistance,
        reversalThreshold: CLLocationDistance
    ) -> CLLocationDistance {
        guard let first = altitudes.first else { return 0 }
        var lowPoint = first
        var highPoint = first
        var isClimbing = false
        var gain: CLLocationDistance = 0

        for altitude in altitudes.dropFirst() {
            if isClimbing {
                highPoint = max(highPoint, altitude)
                if highPoint - altitude >= reversalThreshold {
                    gain += max(0, highPoint - lowPoint)
                    lowPoint = altitude
                    highPoint = altitude
                    isClimbing = false
                }
            } else {
                lowPoint = min(lowPoint, altitude)
                if altitude - lowPoint >= minimumClimb {
                    highPoint = altitude
                    isClimbing = true
                }
            }
        }

        if isClimbing {
            gain += max(0, highPoint - lowPoint)
        }
        return gain
    }
}
