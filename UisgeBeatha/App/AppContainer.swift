import Foundation
import SwiftData

/// Builds the app's `ModelContainer` and owns the recovery operations for
/// when that fails.
///
/// A collection app that crash-loops on launch (`fatalError` on a store it
/// can't open) is the worst failure mode there is, so the app treats
/// container creation as something that can fail and shows
/// `ContainerRecoveryView` instead.
enum AppContainer {
    /// The schema every new build opens. Phase 3 points this at `SchemaV2`.
    static var currentSchema: Schema {
        Schema(versionedSchema: SchemaV1.self)
    }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: currentSchema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: currentSchema,
            migrationPlan: UisgeMigrationPlan.self,
            configurations: configuration
        )
    }

    /// Where SwiftData keeps the default store.
    static var storeURL: URL {
        ModelConfiguration().url
    }

    /// The store file plus its SQLite sidecars.
    static func storeFiles(at url: URL = storeURL) -> [URL] {
        ["", "-shm", "-wal"].map { suffix in
            suffix.isEmpty ? url : URL(fileURLWithPath: url.path + suffix)
        }
    }

    /// Deletes the store and its sidecars. Destructive: callers must have
    /// confirmed with the person and offered the file for sharing first.
    static func resetStore(at url: URL = storeURL) throws {
        let fileManager = FileManager.default
        for file in storeFiles(at: url) where fileManager.fileExists(atPath: file.path) {
            try fileManager.removeItem(at: file)
        }
    }
}
