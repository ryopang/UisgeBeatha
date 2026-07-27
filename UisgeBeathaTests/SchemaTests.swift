import Foundation
import SwiftData
import Testing
@testable import UisgeBeatha

/// Smoke tests that the SwiftData schema is valid and behaves per the
/// CloudKit-forward rules (cascade delete, no unique constraints).
struct SchemaTests {
    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Bottle.self, TastingNote.self,
            configurations: configuration
        )
    }

    @Test func containerCreatesWithValidSchema() throws {
        _ = try makeInMemoryContainer()
    }

    @Test func deletingBottleCascadesToNotes() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let bottle = Bottle(name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay")
        context.insert(bottle)
        let note = TastingNote(nose: "Peat smoke", palate: "Sherry", finish: "Long", conclusion: "A classic")
        note.bottle = bottle
        context.insert(note)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TastingNote>()) == 1)
        context.delete(bottle)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TastingNote>()) == 0)
    }

    @Test func duplicateBarcodesAreAllowedByTheSchema() throws {
        // Duplicate detection is a fetch, never a constraint (PRD section 5).
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        context.insert(Bottle(name: "A", distilleryName: "Oban", region: "highland", barcode: "5000281005416"))
        context.insert(Bottle(name: "B", distilleryName: "Oban", region: "highland", barcode: "5000281005416"))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Bottle>()) == 2)
    }

    @Test func newBottleDefaultsMatchPRD() {
        let bottle = Bottle()
        #expect(bottle.country == "Scotland")
        #expect(bottle.currencyCode == "USD")
        // A new bottle has no status until someone sets one — defaulting
        // every scan to Sealed asserted something the app can't know.
        #expect(bottle.status == nil)
        #expect(bottle.rating == nil)
        #expect(bottle.ageStatement == nil)
        #expect(bottle.notes?.isEmpty == true)
    }

    /// Cycling starts at sealed from unset and never returns to unset —
    /// a stray extra tap shouldn't silently blank a status.
    @Test func statusCyclingFromUnsetStartsAtSealedAndNeverReturnsToUnset() {
        #expect(BottleStatus.next(after: nil) == .sealed)
        #expect(BottleStatus.next(after: .sealed) == .open)
        #expect(BottleStatus.next(after: .open) == .finished)
        #expect(BottleStatus.next(after: .finished) == .sealed)
    }
}
