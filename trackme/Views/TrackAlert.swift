import Foundation

enum TrackAlert: Identifiable {
    case tooShortToSave
    case saveFailure(WorkoutSnapshot)

    var id: String {
        switch self {
        case .tooShortToSave:
            return "too-short-to-save"
        case .saveFailure(let snapshot):
            return "save-failure-\(snapshot.id.uuidString)"
        }
    }
}
