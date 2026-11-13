import Foundation

enum TrackAlert: Identifiable {
    case tooShortToSave
    case saveFailure

    var id: String {
        switch self {
        case .tooShortToSave:
            return "too-short-to-save"
        case .saveFailure:
            return "save-failure"
        }
    }
}
