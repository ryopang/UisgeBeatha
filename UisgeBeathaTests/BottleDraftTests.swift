import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 1: the form's staged state, validation and label merging, with no
/// view involved.
@MainActor
struct BottleDraftTests {
    private let store = DistilleryStore(distilleries: [
        Distillery(
            name: "Lagavulin", aliases: [], region: "islay",
            lat: 55.6365, lon: -6.1268, founded: 1816, owner: "Diageo",
            wikipediaTitle: "Lagavulin_distillery"
        ),
        Distillery(
            name: "Laphroaig", aliases: [], region: "islay",
            lat: 55.6277, lon: -6.1517, founded: 1815, owner: "Beam Suntory",
            wikipediaTitle: "Laphroaig_distillery"
        ),
        Distillery(
            name: "Glenfarclas", aliases: [], region: "speyside",
            lat: 57.4, lon: -3.3, founded: 1836, owner: "J&G Grant",
            wikipediaTitle: "Glenfarclas_distillery"
        ),
    ])

    private func validDraft() -> BottleDraft {
        let draft = BottleDraft()
        draft.name = "Lagavulin 16"
        draft.distilleryName = "Lagavulin"
        draft.region = "islay"
        return draft
    }

    // MARK: - Validation

    @Test func freshDraftCannotSave() {
        #expect(!BottleDraft().canSave)
    }

    @Test func nameDistilleryAndRegionAreRequired() {
        let draft = validDraft()
        #expect(draft.canSave)

        draft.name = "   "
        #expect(!draft.canSave)
        draft.name = "Lagavulin 16"

        draft.distilleryName = ""
        #expect(!draft.canSave)
        draft.distilleryName = "Lagavulin"

        draft.region = "narnia"
        #expect(!draft.canSave)
    }

    @Test func outOfRangeNumbersBlockSave() {
        let draft = validDraft()
        draft.abv = 430
        #expect(!draft.canSave)
        draft.abv = 43
        #expect(draft.canSave)

        draft.age = 400
        #expect(!draft.canSave)
        draft.isNAS = true
        #expect(draft.canSave, "An age is irrelevant once the bottle is marked NAS")

        draft.price = -1
        #expect(!draft.canSave)
    }

    // MARK: - Init

    @Test func editingStartsFromTheBottle() {
        let bottle = Bottle(
            name: "Ardbeg 10", distilleryName: "Ardbeg", region: "islay",
            barcode: "5000281005416", abv: 46, ageStatement: 10,
            caskType: "Ex-bourbon", status: .open
        )
        let draft = BottleDraft(bottle: bottle)
        #expect(!draft.isNewBottle)
        #expect(draft.name == "Ardbeg 10")
        #expect(draft.age == 10)
        #expect(!draft.isNAS)
        #expect(draft.status == .open)
        #expect(draft.barcode == "5000281005416")
    }

    @Test func aBottleWithNoAgeEditsAsNAS() {
        let draft = BottleDraft(bottle: Bottle(name: "Talisker Storm", ageStatement: nil))
        #expect(draft.isNAS)
    }

    @Test func prefillSeedsANewDraft() {
        let prefill = LookupPrefill(
            name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay",
            abv: 43, age: 16, barcode: "5000281005416", stockPhotoURL: "https://example.com/a.jpg"
        )
        let draft = BottleDraft(prefill: prefill)
        #expect(draft.isNewBottle)
        #expect(draft.abv == 43)
        #expect(draft.age == 16)
        #expect(draft.barcode == "5000281005416")
        #expect(draft.prefillStockPhotoURL == "https://example.com/a.jpg")
    }

    // MARK: - Autocomplete

    @Test func suggestionsPutPrefixMatchesFirstAndCapAtSix() {
        let draft = BottleDraft()
        draft.distilleryName = "la"
        let names = draft.distillerySuggestions(in: store).map(\.name)
        // "Glenfarclas" contains "la" mid-word, so it matches but sorts after
        // the two names that start with it.
        #expect(names == ["Lagavulin", "Laphroaig", "Glenfarclas"])
    }

    @Test func suggestionsHideOnceTheFieldNamesTheOnlyMatch() {
        let draft = BottleDraft()
        draft.distilleryName = "Glenfarclas"
        #expect(draft.distillerySuggestions(in: store).isEmpty)
    }

    @Test func selectingASuggestionFillsTheRegion() throws {
        let draft = BottleDraft()
        let lagavulin = try #require(store.exactMatch("Lagavulin"))
        draft.select(lagavulin)
        #expect(draft.distilleryName == "Lagavulin")
        #expect(draft.region == "islay")
    }

    @Test func caskSuggestionsComeFromTheCollection() {
        let draft = BottleDraft()
        draft.caskType = "sherry"
        let suggestions = draft.caskTypeSuggestions(
            from: ["Oloroso Sherry", "Ex-bourbon", nil, "  ", "PX Sherry finish"]
        )
        #expect(suggestions == ["Oloroso Sherry", "PX Sherry finish"])
    }

    @Test func typingAKnownDistilleryResolvesTheRegionOnSave() {
        let draft = BottleDraft()
        draft.name = "Glenfarclas 15"
        draft.distilleryName = "glenfarclas"
        #expect(!draft.canSave)
        draft.resolveRegionIfNeeded(using: store)
        #expect(draft.region == "speyside")
        #expect(draft.canSave)
    }

    // MARK: - Label scan merge

    @Test func labelScanFillsOnlyWhatItRead() {
        let draft = validDraft()
        draft.abv = 40
        draft.caskType = "Refill"

        var result = LabelScanResult()
        result.name = "Lagavulin 16"
        result.distilleryName = "Lagavulin"
        result.distilleryProvenance = .confident
        result.region = "islay"
        result.age = 16
        result.ageProvenance = .confident
        draft.apply(result)

        #expect(draft.abv == 40, "A label with no ABV must not blank a typed one")
        #expect(draft.caskType == "Refill")
        #expect(draft.age == 16)
        #expect(draft.labelScanBanner == Strings.Form.labelScanSuccess)
    }

    @Test func aGuessedDistilleryAsksForConfirmation() {
        let draft = BottleDraft()
        var result = LabelScanResult()
        result.distilleryName = "Laphroaig"
        result.distilleryProvenance = .guessed
        draft.apply(result)
        #expect(draft.labelScanBanner == Strings.Form.labelScanUncertain)
    }

    @Test func anAgeOnTheLabelClearsNAS() {
        let draft = BottleDraft()
        draft.isNAS = true
        var result = LabelScanResult()
        result.age = 12
        draft.apply(result)
        #expect(!draft.isNAS)
        #expect(draft.age == 12)
    }

    @Test func unreadableLinesReportAFailure() {
        let draft = BottleDraft()
        draft.applyLabelScan(
            lines: [], distilleryStore: store, expressionStore: ExpressionStore(expressions: [])
        )
        #expect(draft.labelScanBanner == Strings.Form.labelScanFailure)
    }

    // MARK: - Commit

    @Test func applyWritesTrimmedValuesAndCanonicalBarcode() {
        let draft = validDraft()
        draft.name = "  Lagavulin 16  "
        draft.caskType = "   "
        draft.isNAS = true
        draft.age = 16
        draft.barcode = "088076161863"
        draft.hasPurchaseDate = false
        draft.status = .sealed

        let bottle = Bottle()
        draft.apply(to: bottle)

        #expect(bottle.name == "Lagavulin 16")
        #expect(bottle.caskType == nil)
        #expect(bottle.ageStatement == nil, "NAS wins over a stale age")
        #expect(bottle.barcode == "0088076161863")
        #expect(bottle.purchaseDate == nil)
        #expect(bottle.status == .sealed)
    }

    @Test func aNonGTINBarcodeIsKeptAsTyped() {
        let draft = validDraft()
        draft.barcode = "ABC-123"
        let bottle = Bottle()
        draft.apply(to: bottle)
        #expect(bottle.barcode == "ABC-123")
    }

    @Test func aBlankBarcodeIsStoredAsNil() {
        let draft = validDraft()
        draft.barcode = "  "
        let bottle = Bottle()
        draft.apply(to: bottle)
        #expect(bottle.barcode == nil)
    }
}
