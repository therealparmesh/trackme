import SwiftUI

enum AppTab: Hashable {
    case track
    case history
    case settings

    var label: some View {
        switch self {
        case .track:
            Label("Track", systemImage: "location.north.line.fill")
        case .history:
            Label("History", systemImage: "chart.bar.xaxis")
        case .settings:
            Label("Settings", systemImage: "gearshape.fill")
        }
    }
}
