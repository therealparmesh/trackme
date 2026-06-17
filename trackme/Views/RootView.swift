import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tracker = LocationTracker()
    @State private var health = HealthKitService()
    @State private var selectedTab: AppTab = .track

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TrackView {
                    selectedTab = .history
                }
            }
            .tabItem { AppTab.track.label }
            .tag(AppTab.track)

            NavigationStack {
                InsightsView()
            }
            .tabItem { AppTab.history.label }
            .tag(AppTab.history)

            NavigationStack {
                SettingsView()
            }
            .tabItem { AppTab.settings.label }
            .tag(AppTab.settings)
        }
        .tint(TokyoTheme.cyan)
        .environment(tracker)
        .environment(health)
        .task {
            guard !AppEnvironment.isRunningTests else { return }
            await health.requestAccess(showsIncompleteMessage: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                health.refreshAuthorizationStatus()
            }
        }
    }
}
