import Foundation
import SwiftData
import Testing
@testable import UisgeBeatha

/// Phase 3: two devices adding the same barcode offline leave two records.
/// The merge must converge, lose nothing, and be safe to run repeatedly.
@MainActor
struct BottleDeduplicatorTests {
    private let barcode = "5000281005416"

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try AppContainer.make(inMemory: true)
        return (container, ModelContext(container))
    }

    private func insert(
        _ context: ModelContext, name: String = "Lagavulin 16", barcode: String?, added: TimeInterval
    ) -> Bottle {
        let bottle = Bottle(
            name: name, distilleryName: "Lagavulin", region: "islay", barcode: barcode,
            dateAdded: Date(timeIntervalSince1970: added)
        )
        context.insert(bottle)
        return bottle
    }

    @Test func twoBottlesWithTheSameBarcodeMergeIntoTheOlderOne() throws {
        let (container, context) = try makeContext()
        _ = container
        let older = insert(context, barcode: barcode, added: 1000)
        let newer = insert(context, barcode: barcode, added: 2000)
        try context.save()

        let removed = try BottleDeduplicator.mergeDuplicates(in: context)

        #expect(removed == 1)
        let remaining = try context.fetch(FetchDescriptor<Bottle>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == older.id)
        #expect(remaining.first?.id != newer.id)
    }

    @Test func notesAndPhotosMoveToTheSurvivor() async throws {
        let (container, context) = try makeContext()
        _ = container
        let older = insert(context, barcode: barcode, added: 1000)
        let newer = insert(context, barcode: barcode, added: 2000)
        let oldNote = TastingNote(date: Date(timeIntervalSince1970: 5000), nose: "From the older")
        let newNote = TastingNote(date: Date(timeIntervalSince1970: 9000), nose: "From the newer")
        context.insert(oldNote)
        context.insert(newNote)
        oldNote.bottle = older
        newNote.bottle = newer
        try context.save()
        try await BottlePhotos.set(TestImages.jpeg(), kind: .stock, for: newer, in: context)

        try BottleDeduplicator.mergeDuplicates(in: context)

        #expect(older.notes?.count == 2, "Both notes survive")
        #expect(try context.fetchCount(FetchDescriptor<TastingNote>()) == 2)
        #expect(older.photo(of: .stock) != nil, "The duplicate's photo moves over")
        #expect(older.lastTastedDate == Date(timeIntervalSince1970: 9000))
    }

    @Test func theSurvivorKeepsItsValuesAndGapsAreFilledFromTheDuplicate() throws {
        let (container, context) = try makeContext()
        _ = container
        let older = insert(context, barcode: barcode, added: 1000)
        older.abv = 43
        let newer = insert(context, barcode: barcode, added: 2000)
        newer.abv = 46
        newer.rating = 4.5
        newer.status = .open
        newer.caskType = "Sherry"
        try context.save()

        try BottleDeduplicator.mergeDuplicates(in: context)

        #expect(older.abv == 43, "The survivor's own value wins")
        #expect(older.rating == 4.5)
        #expect(older.status == .open)
        #expect(older.caskType == "Sherry")
    }

    @Test func aLegacyTwelveDigitBarcodeMatchesItsThirteenDigitForm() throws {
        let (container, context) = try makeContext()
        _ = container
        _ = insert(context, barcode: "0088076161863", added: 1000)
        let legacy = insert(context, barcode: "088076161863", added: 2000)
        try context.save()

        let removed = try BottleDeduplicator.mergeDuplicates(in: context)

        #expect(removed == 1)
        let remaining = try context.fetch(FetchDescriptor<Bottle>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.barcode == "0088076161863", "The survivor ends up canonical")
        #expect(remaining.first?.id != legacy.id)
    }

    @Test func bottlesWithoutBarcodesOrWithDifferentOnesAreLeftAlone() throws {
        let (container, context) = try makeContext()
        _ = container
        _ = insert(context, name: "A", barcode: nil, added: 1)
        _ = insert(context, name: "B", barcode: nil, added: 2)
        _ = insert(context, name: "C", barcode: "5000281005416", added: 3)
        _ = insert(context, name: "D", barcode: "5010314302409", added: 4)
        _ = insert(context, name: "E", barcode: "not a barcode", added: 5)
        _ = insert(context, name: "F", barcode: "not a barcode", added: 6)
        try context.save()

        #expect(try BottleDeduplicator.mergeDuplicates(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Bottle>()) == 6)
    }

    @Test func runningTwiceChangesNothingTheSecondTime() throws {
        let (container, context) = try makeContext()
        _ = container
        _ = insert(context, barcode: barcode, added: 1000)
        _ = insert(context, barcode: barcode, added: 2000)
        _ = insert(context, barcode: barcode, added: 3000)
        try context.save()

        #expect(try BottleDeduplicator.mergeDuplicates(in: context) == 2)
        #expect(try BottleDeduplicator.mergeDuplicates(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Bottle>()) == 1)
    }

    @Test func identicalTimestampsStillPickOneDeterministicSurvivor() throws {
        let (container, context) = try makeContext()
        _ = container
        let first = insert(context, barcode: barcode, added: 1000)
        let second = insert(context, barcode: barcode, added: 1000)
        try context.save()

        try BottleDeduplicator.mergeDuplicates(in: context)

        let expected = [first, second].min { $0.id.uuidString < $1.id.uuidString }
        let remaining = try context.fetch(FetchDescriptor<Bottle>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == expected?.id,
                "Every device must choose the same survivor so merges converge")
    }

    @Test func mergingTwoUserPhotosKeepsTheNewest() async throws {
        let (container, context) = try makeContext()
        _ = container
        let older = insert(context, barcode: barcode, added: 1000)
        let newer = insert(context, barcode: barcode, added: 2000)
        try context.save()
        try await BottlePhotos.set(TestImages.jpeg(color: .red), kind: .user, for: older, in: context)
        let newest = try await BottlePhotos.set(TestImages.jpeg(color: .blue), kind: .user, for: newer, in: context)

        try BottleDeduplicator.mergeDuplicates(in: context)

        #expect(older.photos?.count == 1)
        #expect(older.photo(of: .user)?.id == newest.id)
        #expect(try context.fetchCount(FetchDescriptor<BottlePhoto>()) == 1)
    }
}
