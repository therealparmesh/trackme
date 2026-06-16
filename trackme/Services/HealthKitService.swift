import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitService {
    private let store = HKHealthStore()

    var isConnected = false
    var isWorking = false
    var message: String?

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        let wasConnected = isConnected
        isConnected = shareTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingAuthorized }
        if isConnected != wasConnected {
            message = nil
        }
    }

    func requestAccess() async {
        guard !isWorking else { return }
        guard isAvailable else {
            message = "Apple Health is not available on this device."
            return
        }

        message = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
            refreshAuthorizationStatus()
            message = isConnected
                ? nil
                : "Some permissions are still off. Allow all requested access in the Health app to sync new workouts."
        } catch {
            message = "Apple Health could not be connected. Try again."
        }
    }

    func save(_ snapshot: WorkoutSnapshot) async {
        refreshAuthorizationStatus()
        guard isConnected else { return }
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

        do {
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
            guard let workout = try await builder.finishWorkout() else { return }
            guard snapshot.route.count > 1 else { return }
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await routeBuilder.insertRouteData(snapshot.route.map(\.location))
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
            message = nil
        } catch {
            message = "Your workout was saved in trackme, but it could not be added to Apple Health."
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
