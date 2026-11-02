import Foundation
import SwiftData
import Testing
@testable import UisgeBeatha

/// Phase 1: versioned schema, migration plan and store recovery.
struct AppContainerTests {
    @Test func containerOpensThroughTheMigrationPlan() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Bottle(name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Bottle>()) == 1)
    }

    @Test func schemaVersionsAreOrderedOldestFirst() {
        let versions = UisgeMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == versions.sorted())
        #expect(versions.first == Schema.Version(1, 0, 0))
    }

    @Test func currentSchemaIsTheNewestVersion() {
        #expect(UisgeMigrationPlan.schemas.last?.versionIdentifier == AppContainer.currentSchema.version)
    }

    @Test func storeFilesIncludeSQLiteSidecars() {
        let url = URL(fileURLWithPath: "/tmp/test.store")
        let paths = AppContainer.storeFiles(at: url).map(\.path)
        #expect(paths == ["/tmp/test.store", "/tmp/test.store-shm", "/tmp/test.store-wal"])
    }

    @Test func resetRemovesTheStoreAndSidecars() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppContainerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("default.store")
        for file in AppContainer.storeFiles(at: url) {
            try Data("x".utf8).write(to: file)
        }
        try AppContainer.resetStore(at: url)
        for file in AppContainer.storeFiles(at: url) {
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func resettingAMissingStoreIsHarmless() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("never-existed-\(UUID().uuidString).store")
        try AppContainer.resetStore(at: url)
    }
}
