import Foundation
import SwiftData
import SwiftUI

enum AppEnvironment {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

@main
struct TrackmeApp: App {
    private let modelContainer: ModelContainer = {
        do {
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: AppEnvironment.isRunningTests
            )
            return try ModelContainer(
                for: WorkoutRecord.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to create workout store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
