import Foundation
import SwiftData
import Testing
@testable import UisgeBeatha

/// Phase 3: a store written by v1.0 must open under v2.0 with nothing lost.
@MainActor
struct SchemaMigrationTests {
    private func makeStoreURL() throws -> (url: URL, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory.appendingPathComponent("test.store"), { try? FileManager.default.removeItem(at: directory) })
    }

    @Test func aV1StoreOpensAsV2WithEveryFieldIntact() throws {
        let (url, cleanup) = try makeStoreURL()
        defer { cleanup() }

        let bottleID: UUID
        // Written exactly as v1.0 wrote it.
        do {
            let v1Schema = Schema(versionedSchema: SchemaV1.self)
            let v1 = try ModelContainer(
                for: v1Schema,
                configurations: ModelConfiguration(schema: v1Schema, url: url, cloudKitDatabase: .none)
            )
            let context = ModelContext(v1)
            let bottle = SchemaV1.Bottle(
                name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay",
                barcode: "5000281005416", abv: 43, ageStatement: 16, caskType: "Ex-bourbon",
                purchasePrice: Decimal(string: "89.99"), status: .open, rating: 4.5,
                stockPhotoURL: "https://example.com/stock.jpg", userPhotoFilename: "abc.jpg"
            )
            context.insert(bottle)
            let note = SchemaV1.TastingNote(nose: "Peat smoke", palate: "Sherry", finish: "Long", conclusion: "Classic")
            context.insert(note)
            note.bottle = bottle
            try context.save()
            bottleID = bottle.id
        }

        // Opened by v2.0.
        let v2Schema = AppContainer.currentSchema
        let v2 = try ModelContainer(
            for: v2Schema,
            migrationPlan: UisgeMigrationPlan.self,
            configurations: ModelConfiguration(schema: v2Schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(v2)
        let bottles = try context.fetch(FetchDescriptor<Bottle>())
        #expect(bottles.count == 1)
        let bottle = try #require(bottles.first)

        #expect(bottle.id == bottleID)
        #expect(bottle.name == "Lagavulin 16")
        #expect(bottle.region == "islay")
        #expect(bottle.barcode == "5000281005416")
        #expect(bottle.abv == 43)
        #expect(bottle.ageStatement == 16)
        #expect(bottle.caskType == "Ex-bourbon")
        #expect(bottle.purchasePrice == Decimal(string: "89.99"))
        #expect(bottle.status == .open)
        #expect(bottle.rating == 4.5)
        #expect(bottle.stockPhotoURL == "https://example.com/stock.jpg")
        #expect(bottle.userPhotoFilename == "abc.jpg", "The filename must survive so the photo migrator can find the file")
        #expect(bottle.notes?.count == 1)
        #expect(bottle.notes?.first?.nose == "Peat smoke")

        // The new fields start empty; the maintenance pass fills them.
        #expect(bottle.photos?.isEmpty == true)
        #expect(bottle.priceMinorUnits == nil)
        #expect(bottle.lastTastedDate == nil)
        #expect(bottle.stockPhotoAttribution == nil)
    }

    @Test func derivedFieldsAreBackfilledAfterMigration() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        let bottle = Bottle(name: "Ardbeg 10", purchasePrice: Decimal(string: "54.5"))
        let note = TastingNote(date: Date(timeIntervalSince1970: 1_700_000_000), nose: "Smoke")
        context.insert(bottle)
        context.insert(note)
        note.bottle = bottle
        try context.save()

        #expect(StoreMaintenance.backfillDerivedFields(in: context) == 1)
        #expect(bottle.priceMinorUnits == 5450)
        #expect(bottle.lastTastedDate == note.date)
        #expect(StoreMaintenance.backfillDerivedFields(in: context) == 0, "Idempotent")
    }
}
