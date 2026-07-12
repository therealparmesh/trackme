import CoreMotion
import Foundation

enum MotionState: Equatable {
    case unknown, stationary, moving
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
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            self?.currentStateStartedAt = activity.startDate
            if activity.stationary, activity.confidence != .low {
                self?.currentState = .stationary
            } else if activity.walking || activity.running {
                self?.currentState = .moving
            } else {
                self?.currentState = .unknown
            }
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
