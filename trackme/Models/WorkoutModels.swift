import CoreLocation
import Foundation
import SwiftData

enum ActivityKind: String, CaseIterable, Identifiable {
    case walk
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: "Walk"
        case .run: "Run"
        }
    }

    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .run: "figure.run"
        }
    }
}

struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let course: Double
    let courseAccuracy: Double
    let speed: Double
    let speedAccuracy: Double
    let startsNewSegment: Bool

    init(location: CLLocation, startsNewSegment: Bool) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        course = location.course
        courseAccuracy = location.courseAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        self.startsNewSegment = startsNewSegment
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }
}

extension Array where Element == RoutePoint {
    var routeSegments: [[RoutePoint]] {
        reduce(into: []) { segments, point in
            if segments.isEmpty || point.startsNewSegment {
                segments.append([point])
            } else {
                segments[segments.count - 1].append(point)
            }
        }
    }
}

struct WorkoutPause {
    let startDate: Date
    let endDate: Date
}

struct WorkoutSnapshot: Identifiable {
    let id = UUID()
    let activity: ActivityKind
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double
    let elevationGain: Double
    let route: [RoutePoint]
    let pauses: [WorkoutPause]

    var averagePace: TimeInterval {
        guard distance > 0 else { return 0 }
        return duration / (distance / 1_609.344)
    }
}

@Model
final class WorkoutRecord {
    var id: UUID
    var activityRawValue: String
    var startDate: Date
    var duration: TimeInterval
    var distance: Double
    var elevationGain: Double
    var healthKitWorkoutUUIDString: String?
    @Attribute(.externalStorage) var routeData: Data

    init(snapshot: WorkoutSnapshot, healthKitWorkoutID: UUID? = nil) throws {
        id = UUID()
        activityRawValue = snapshot.activity.rawValue
        startDate = snapshot.startDate
        duration = snapshot.duration
        distance = snapshot.distance
        elevationGain = snapshot.elevationGain
        healthKitWorkoutUUIDString = healthKitWorkoutID?.uuidString
        routeData = try JSONEncoder().encode(snapshot.route)
    }

    var activity: ActivityKind {
        ActivityKind(rawValue: activityRawValue) ?? .walk
    }

    var route: [RoutePoint] {
        do {
            return try JSONDecoder().decode([RoutePoint].self, from: routeData)
        } catch {
            assertionFailure("Unable to decode workout route: \(error)")
            return []
        }
    }

    var averagePace: TimeInterval {
        guard distance > 0 else { return 0 }
        return duration / (distance / 1_609.344)
    }

    var healthKitWorkoutID: UUID? {
        get {
            healthKitWorkoutUUIDString.flatMap(UUID.init(uuidString:))
        }
        set {
            healthKitWorkoutUUIDString = newValue?.uuidString
        }
    }
}
