import Foundation
import SwiftData

/// How the store is running.
nonisolated enum SyncMode: Equatable, Sendable {
    /// Mirrored to the person's private iCloud database.
    case cloud
    /// Local only. `reason` says why, for Settings.
    case localOnly(reason: LocalOnlyReason)

    nonisolated enum LocalOnlyReason: Equatable, Sendable {
        /// Turned off with a launch argument (tests, previews, debugging).
        case disabled
        /// The container couldn't be created with CloudKit, usually
        /// because the iCloud capability or entitlement is missing from
        /// this build. The app keeps working on the same data.
        case cloudKitUnavailable(String)
    }
}

/// Builds the app's `ModelContainer` and owns the recovery operations for
/// when that fails.
///
/// A collection app that crash-loops on launch (`fatalError` on a store it
/// can't open) is the worst failure mode there is, so the app treats
/// container creation as something that can fail and shows
/// `ContainerRecoveryView` instead.
enum AppContainer {
    /// The CloudKit container for the person's private database.
    static let cloudKitContainerID = "iCloud.com.ryo.UisgeBeatha"

    /// The schema every new build opens.
    static var currentSchema: Schema {
        Schema(versionedSchema: SchemaV2.self)
    }

    /// Launch argument that forces a local-only store.
    static let disableSyncArgument = "-disableCloudSync"

    /// Opens the store, with CloudKit sync if it can, and without if not.
    ///
    /// CloudKit-backed creation fails when the build has no iCloud
    /// entitlement. That must not strand the person's collection, so it
    /// falls back to the same store without mirroring and reports why.
    /// Only if that also fails does the caller see an error.
    static func open(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> (container: ModelContainer, mode: SyncMode) {
        if arguments.contains(disableSyncArgument) {
            return (try make(syncing: false), .localOnly(reason: .disabled))
        }
        do {
            return (try make(syncing: true), .cloud)
        } catch {
            let container = try make(syncing: false)
            return (container, .localOnly(reason: .cloudKitUnavailable(String(describing: error))))
        }
    }

    /// `inMemory` stores never sync.
    static func make(inMemory: Bool = false, syncing: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: currentSchema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: (syncing && !inMemory) ? .private(cloudKitContainerID) : .none
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
