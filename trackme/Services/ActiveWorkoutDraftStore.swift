import Foundation

protocol ActiveWorkoutDraftStoring {
    func load() -> ActiveWorkoutDraft?
    func save(_ draft: ActiveWorkoutDraft)
    func clear()
}

final class FileActiveWorkoutDraftStore: ActiveWorkoutDraftStoring {
    private let fileManager: FileManager
    private let fileURL: URL

    init(
        fileManager: FileManager = .default,
        fileURL: URL = FileActiveWorkoutDraftStore.defaultFileURL()
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
    }

    func load() -> ActiveWorkoutDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ActiveWorkoutDraft.self, from: data)
    }

    func save(_ draft: ActiveWorkoutDraft) {
        do {
            let data = try JSONEncoder().encode(draft)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to save active workout draft: \(error)")
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            assertionFailure("Unable to clear active workout draft: \(error)")
        }
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ActiveWorkoutDraft.json")
    }
}
