import CoreMotion
import Foundation

enum MotionState: Equatable {
    case unknown, stationary, moving

    static func classify(
        stationary: Bool,
        walking: Bool,
        running: Bool,
        confidence: CMMotionActivityConfidence
    ) -> MotionState {
        if walking || running {
            return .moving
        }
        if stationary, confidence != .low {
            return .stationary
        }
        return .unknown
    }
}

protocol MotionActivityClient: AnyObject {
    func start()
    func stop()
    func state(at date: Date) -> MotionState
}

final class CoreMotionActivityClient: MotionActivityClient {
    private var manager: CMMotionActivityManager?
    private var currentState: MotionState = .unknown
    private var currentStateStartedAt = Date.distantPast

    func start() {
        stop()
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let manager = CMMotionActivityManager()
        self.manager = manager
        manager.startActivityUpdates(to: .main) { [weak self, weak manager] activity in
            guard let self, let manager, self.manager === manager, let activity else { return }
            currentStateStartedAt = activity.startDate
            currentState = MotionState.classify(
                stationary: activity.stationary,
                walking: activity.walking,
                running: activity.running,
                confidence: activity.confidence
            )
        }
    }

    func stop() {
        manager?.stopActivityUpdates()
        manager = nil
        currentState = .unknown
        currentStateStartedAt = .distantPast
    }

    func state(at date: Date) -> MotionState {
        date >= currentStateStartedAt ? currentState : .unknown
    }
}
