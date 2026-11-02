import Foundation
import SwiftData
import Testing
import UIKit
@testable import UisgeBeatha

/// Phase 3: photos as synced model rows, the v1 file migration and the
/// stock photo importer.
@MainActor
struct PhotoSyncTests {
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try AppContainer.make(inMemory: true)
        return (container, ModelContext(container))
    }

    private func makeBottle(in context: ModelContext, name: String = "Lagavulin 16") throws -> Bottle {
        let bottle = Bottle(name: name, distilleryName: "Lagavulin", region: "islay")
        context.insert(bottle)
        try context.save()
        return bottle
    }

    // MARK: - BottlePhotos

    @Test func settingAUserPhotoStoresBothSizes() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)

        let photo = try await BottlePhotos.set(TestImages.jpeg(width: 3000, height: 1200), kind: .user, for: bottle, in: context)

        #expect(photo.kind == "user")
        #expect(photo.imageData?.isEmpty == false)
        #expect(photo.thumbnailData?.isEmpty == false)
        #expect((photo.thumbnailData?.count ?? 0) < (photo.imageData?.count ?? 0))
        #expect(bottle.photos?.count == 1)
    }

    @Test func replacingAPhotoRemovesTheOldRow() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)

        let first = try await BottlePhotos.set(TestImages.jpeg(color: .red), kind: .user, for: bottle, in: context)
        let second = try await BottlePhotos.set(TestImages.jpeg(color: .blue), kind: .user, for: bottle, in: context)

        #expect(first.id != second.id)
        #expect(bottle.photos?.count == 1)
        #expect(bottle.photo(of: .user)?.id == second.id)
        #expect(try context.fetchCount(FetchDescriptor<BottlePhoto>()) == 1, "The old row must not be orphaned")
    }

    @Test func aFailedEncodeKeepsTheExistingPhoto() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)
        let original = try await BottlePhotos.set(TestImages.jpeg(), kind: .user, for: bottle, in: context)

        await #expect(throws: (any Error).self) {
            try await BottlePhotos.set(Data("not an image".utf8), kind: .user, for: bottle, in: context)
        }
        #expect(bottle.photo(of: .user)?.id == original.id)
    }

    @Test func theUsersPhotoOutranksAStockPhoto() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)

        try await BottlePhotos.set(TestImages.jpeg(), kind: .stock, for: bottle, in: context)
        #expect(bottle.primaryPhoto?.kind == "stock")

        try await BottlePhotos.set(TestImages.jpeg(), kind: .user, for: bottle, in: context)
        #expect(bottle.primaryPhoto?.kind == "user")
        #expect(bottle.photos?.count == 2, "Both coexist; the user photo just wins")
    }

    @Test func removingTheUserPhotoFallsBackToTheStockPhoto() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)
        try await BottlePhotos.set(TestImages.jpeg(), kind: .stock, for: bottle, in: context)
        try await BottlePhotos.set(TestImages.jpeg(), kind: .user, for: bottle, in: context)

        try BottlePhotos.remove(.user, from: bottle, in: context)

        #expect(bottle.primaryPhoto?.kind == "stock")
    }

    @Test func deletingABottleDeletesItsPhotos() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)
        try await BottlePhotos.set(TestImages.jpeg(), kind: .user, for: bottle, in: context)

        context.delete(bottle)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<BottlePhoto>()) == 0)
    }

    // MARK: - PhotoMigrator

    private func makeStore() -> (LocalImageStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoMigratorTests-\(UUID().uuidString)", isDirectory: true)
        return (LocalImageStore(directory: directory), directory)
    }

    @Test func migratorMovesAFileIntoARowByteForByteThenDeletesTheFiles() async throws {
        let (container, context) = try makeContext()
        _ = container
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let filename = try await store.save(imageData: TestImages.jpeg(width: 1200, height: 800))
        let originalBytes = try Data(contentsOf: store.imageURL(for: filename))
        let thumbnailBytes = try Data(contentsOf: store.thumbnailURL(for: filename))

        let bottle = try makeBottle(in: context)
        bottle.userPhotoFilename = filename
        try context.save()

        let moved = await PhotoMigrator(store: store).migrate(in: context)

        #expect(moved == 1)
        let photo = try #require(bottle.photo(of: .user))
        #expect(photo.imageData == originalBytes, "No re-encoding: the bytes must be identical")
        #expect(photo.thumbnailData == thumbnailBytes)
        #expect(bottle.userPhotoFilename == nil)
        #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: filename).path))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(for: filename).path))
    }

    @Test func migratorRegeneratesAMissingThumbnail() async throws {
        let (container, context) = try makeContext()
        _ = container
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let filename = try await store.save(imageData: TestImages.jpeg(width: 1200, height: 800))
        try FileManager.default.removeItem(at: store.thumbnailURL(for: filename))
        let bottle = try makeBottle(in: context)
        bottle.userPhotoFilename = filename
        try context.save()

        await PhotoMigrator(store: store).migrate(in: context)

        #expect(bottle.photo(of: .user)?.thumbnailData?.isEmpty == false)
    }

    @Test func migratorClearsAFilenameWhoseFileIsGone() async throws {
        let (container, context) = try makeContext()
        _ = container
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bottle = try makeBottle(in: context)
        bottle.userPhotoFilename = "never-existed.jpg"
        try context.save()

        let moved = await PhotoMigrator(store: store).migrate(in: context)

        #expect(moved == 0)
        #expect(bottle.userPhotoFilename == nil, "A dead filename must not be retried forever")
        #expect(bottle.photos?.isEmpty == true)
    }

    @Test func migratorRunsTwiceWithoutDuplicating() async throws {
        let (container, context) = try makeContext()
        _ = container
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let filename = try await store.save(imageData: TestImages.jpeg())
        let bottle = try makeBottle(in: context)
        bottle.userPhotoFilename = filename
        try context.save()

        await PhotoMigrator(store: store).migrate(in: context)
        let second = await PhotoMigrator(store: store).migrate(in: context)

        #expect(second == 0)
        #expect(bottle.photos?.count == 1)
    }

    @Test func migratorDoesNotOverwriteAPhotoAlreadySynced() async throws {
        let (container, context) = try makeContext()
        _ = container
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let filename = try await store.save(imageData: TestImages.jpeg(color: .red))
        let bottle = try makeBottle(in: context)
        let synced = try await BottlePhotos.set(TestImages.jpeg(color: .blue), kind: .user, for: bottle, in: context)
        bottle.userPhotoFilename = filename
        try context.save()

        await PhotoMigrator(store: store).migrate(in: context)

        #expect(bottle.photos?.count == 1)
        #expect(bottle.photo(of: .user)?.id == synced.id)
        #expect(bottle.userPhotoFilename == nil)
    }

    // MARK: - StockPhotoImporter

    private func importer(
        data: Data = TestImages.jpeg(), mime: String? = "image/jpeg", error: Error? = nil
    ) -> StockPhotoImporter {
        StockPhotoImporter(fetch: { _ in
            if let error { throw error }
            return (data, mime)
        })
    }

    @Test func importerStoresAStockPhotoWithAttribution() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)

        let ok = await importer().importPhoto(
            from: "https://upload.wikimedia.org/thumb/a.jpg", for: bottle, in: context
        )

        #expect(ok)
        #expect(bottle.photo(of: .stock) != nil)
        #expect(bottle.stockPhotoURL == "https://upload.wikimedia.org/thumb/a.jpg")
        #expect(bottle.stockPhotoAttribution == Strings.Detail.photoViaCommons)
    }

    @Test func importerNeverTouchesTheUsersOwnPhoto() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)
        let own = try await BottlePhotos.set(TestImages.jpeg(color: .red), kind: .user, for: bottle, in: context)

        await importer().importPhoto(from: "https://example.com/a.jpg", for: bottle, in: context)

        #expect(bottle.photo(of: .user)?.id == own.id)
        #expect(bottle.primaryPhoto?.id == own.id)
        #expect(bottle.photo(of: .stock) != nil)
    }

    @Test func importerRejectsNonImagesAndOversizedFiles() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)

        let html = await importer(data: Data("<html>".utf8), mime: "text/html")
            .importPhoto(from: "https://example.com/a", for: bottle, in: context)
        #expect(!html)

        let huge = Data(count: StockPhotoImporter.maxBytes + 1)
        let tooBig = await importer(data: huge, mime: "image/jpeg")
            .importPhoto(from: "https://example.com/a.jpg", for: bottle, in: context)
        #expect(!tooBig)

        #expect(bottle.photos?.isEmpty == true)
    }

    @Test func importerSurvivesANetworkFailure() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)

        let ok = await importer(error: URLError(.notConnectedToInternet))
            .importPhoto(from: "https://example.com/a.jpg", for: bottle, in: context)

        #expect(!ok)
        #expect(bottle.photos?.isEmpty == true)
    }

    @Test func importerRefusesAURLThatIsNotHTTPS() {
        #expect(StockPhotoImporter.secureURL(from: "ftp://example.com/a.jpg") == nil)
        #expect(StockPhotoImporter.secureURL(from: "not a url") == nil)
        #expect(StockPhotoImporter.secureURL(from: "http://example.com/a.jpg")?.scheme == "https")
        #expect(StockPhotoImporter.secureURL(from: "https://example.com/a.jpg")?.scheme == "https")
    }

    @Test func attributionNamesTheSource() throws {
        func credit(_ string: String) throws -> String? {
            StockPhotoImporter.attribution(for: try #require(URL(string: string)))
        }
        #expect(try credit("https://upload.wikimedia.org/x.jpg") == Strings.Detail.photoViaCommons)
        #expect(try credit("https://en.wikipedia.org/x.jpg") == Strings.Detail.photoViaCommons)
        #expect(try credit("https://images.openfoodfacts.org/x.jpg") == Strings.Detail.photoViaOpenFoodFacts)
        #expect(try credit("https://www.thewhiskyexchange.com/x.jpg") == "Photo via thewhiskyexchange.com")
    }

    // MARK: - Maintenance

    @Test func needsStockPhotoOnlyWhenAURLIsRememberedAndNoPhotoExists() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)
        #expect(!StoreMaintenance.needsStockPhoto(bottle), "No URL, nothing to fetch")

        bottle.stockPhotoURL = "https://example.com/a.jpg"
        #expect(StoreMaintenance.needsStockPhoto(bottle))

        try await BottlePhotos.set(TestImages.jpeg(), kind: .user, for: bottle, in: context)
        #expect(!StoreMaintenance.needsStockPhoto(bottle), "Already has a photo")
    }

    @Test func retryDownloadsOncePerDay() async throws {
        let (container, context) = try makeContext()
        _ = container
        let bottle = try makeBottle(in: context)
        bottle.stockPhotoURL = "https://example.com/a.jpg"
        try context.save()

        let suiteName = "StoreMaintenanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let failing = StockPhotoImporter(fetch: { _ in throw URLError(.timedOut) })
        let maintenance = StoreMaintenance(importer: failing, defaults: defaults)

        let start = Date.now
        await maintenance.retryStockPhotoImports(in: context, now: start)
        let attemptsAfterFirst = (defaults.dictionary(forKey: "stockPhotoImportAttempts") as? [String: Date])?.count
        #expect(attemptsAfterFirst == 1)

        // A second pass an hour later must not try again.
        await maintenance.retryStockPhotoImports(in: context, now: start.addingTimeInterval(3600))
        let stored = defaults.dictionary(forKey: "stockPhotoImportAttempts") as? [String: Date]
        #expect(stored?[bottle.id.uuidString] == start, "The attempt time must not move forward on a skipped bottle")
    }
}
