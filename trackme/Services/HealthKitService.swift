import HealthKit
import Observation

@MainActor
protocol HealthStoreClient: AnyObject {
    var isHealthDataAvailable: Bool { get }

    func authorizationStatus(for type: HKSampleType) -> HKAuthorizationStatus
    func requestAuthorization(toShare types: Set<HKSampleType>) async throws
    func save(_ snapshot: WorkoutSnapshot) async throws -> UUID
    func deleteWorkout(id: UUID) async throws
}

@MainActor
final class LiveHealthStoreClient: HealthStoreClient {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationStatus(for type: HKSampleType) -> HKAuthorizationStatus {
        store.authorizationStatus(for: type)
    }

    func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        try await store.requestAuthorization(toShare: types, read: [])
    }

    func save(_ snapshot: WorkoutSnapshot) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = snapshot.activity == .run ? .running : .walking
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        let distance = HKQuantitySample(
            type: HKQuantityType(.distanceWalkingRunning),
            quantity: HKQuantity(unit: .meter(), doubleValue: snapshot.distance),
            start: snapshot.startDate,
            end: snapshot.endDate
        )

        try await builder.beginCollection(at: snapshot.startDate)
        try await builder.addSamples([distance])
        let pauseEvents = snapshot.pauses.flatMap { pause in
            [
                HKWorkoutEvent(
                    type: .pause,
                    dateInterval: DateInterval(start: pause.startDate, duration: 0),
                    metadata: nil
                ),
                HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(start: pause.endDate, duration: 0),
                    metadata: nil
                )
            ]
        }
        if !pauseEvents.isEmpty {
            try await builder.addWorkoutEvents(pauseEvents)
        }
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: false])
        try await builder.endCollection(at: snapshot.endDate)
        guard let workout = try await builder.finishWorkout() else {
            throw HealthSyncError.workoutCreationFailed
        }
        if snapshot.route.count > 1 {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await routeBuilder.insertRouteData(snapshot.route.map(\.location))
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
        return workout.uuid
    }

    func deleteWorkout(id: UUID) async throws {
        guard let workout = try await workout(id: id) else { return }
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let distanceSamples = try await samples(
            of: HKQuantityType(.distanceWalkingRunning),
            predicate: workoutPredicate
        )
        let routes = try await samples(
            of: HKSeriesType.workoutRoute(),
            predicate: workoutPredicate
        )
        try await delete(distanceSamples)
        try await delete(routes)
        try await delete([workout])
    }

    private func workout(id: UUID) async throws -> HKWorkout? {
        try await samples(
            of: HKObjectType.workoutType(),
            predicate: HKQuery.predicateForObject(with: id),
            limit: 1
        )
        .compactMap { $0 as? HKWorkout }
        .first
    }

    private func samples(
        of type: HKSampleType,
        predicate: NSPredicate,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    private func delete(_ objects: [HKObject]) async throws {
        guard !objects.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(objects) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthSyncError.deleteFailed)
                }
            }
        }
    }
}

enum HealthSyncError: Error {
    case workoutCreationFailed
    case deleteFailed
}

@MainActor
@Observable
final class HealthKitService {
    @ObservationIgnored private let client: HealthStoreClient

    var isConnected = false
    var isWorking = false
    var message: String?

    var isAvailable: Bool {
        client.isHealthDataAvailable
    }

    convenience init() {
        self.init(client: LiveHealthStoreClient())
    }

    init(client: HealthStoreClient) {
        self.client = client
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        let wasConnected = isConnected
        isConnected = shareTypes.allSatisfy { client.authorizationStatus(for: $0) == .sharingAuthorized }
        if isConnected != wasConnected {
            message = nil
        }
    }

    func requestAccess(showsIncompleteMessage: Bool = true) async {
        guard !isWorking else { return }
        guard isAvailable else {
            message = "Apple Health is not available on this device."
            return
        }

        message = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await client.requestAuthorization(toShare: shareTypes)
            refreshAuthorizationStatus()
            if isConnected {
                message = nil
            } else if showsIncompleteMessage {
                message = "Allow all requested Health permissions to sync new workouts."
            }
        } catch {
            message = "Apple Health could not be connected. Try again."
        }
    }

    @discardableResult
    func save(_ snapshot: WorkoutSnapshot) async -> UUID? {
        guard snapshot.distance > 0 else {
            message = nil
            return nil
        }

        refreshAuthorizationStatus()
        guard isConnected else { return nil }

        do {
            let id = try await client.save(snapshot)
            message = nil
            return id
        } catch {
            message = "Your workout was saved in trackme, but it could not be added to Apple Health."
            return nil
        }
    }

    @discardableResult
    func deleteWorkout(id: UUID) async -> Bool {
        refreshAuthorizationStatus()
        guard isConnected else {
            message = "Reconnect Apple Health to remove this synced workout from Health."
            return false
        }

        do {
            try await client.deleteWorkout(id: id)
            message = nil
            return true
        } catch {
            message = "The workout could not be removed from Apple Health. Try again."
            return false
        }
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKSeriesType.workoutRoute()
        ]
    }
}
