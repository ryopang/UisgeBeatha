import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 4: what the app will and won't believe from an on-device model,
/// tested with scripted model answers (no model needed).
@MainActor
struct ExtractionMergerTests {
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
            name: "Macallan", aliases: ["The Macallan"], region: "speyside",
            lat: 57.48, lon: -3.2, founded: 1824, owner: "Edrington",
            wikipediaTitle: "Macallan_distillery"
        ),
    ])
    private let expressions = ExpressionStore(expressions: [])

    private func merge(
        _ base: LabelScanResult?, _ fields: ExtractedFields, lines: [String]
    ) -> LabelScanResult? {
        ExtractionMerger.merge(
            base, with: fields, lines: lines,
            distilleryStore: store, expressionStore: expressions
        )
    }

    private func confidentLagavulin() -> LabelScanResult {
        var result = LabelScanResult()
        result.distilleryName = "Lagavulin"
        result.region = "islay"
        result.distilleryProvenance = .confident
        return result
    }

    // MARK: - Confident heuristics always win

    @Test func aConfidentDistilleryIsNeverOverridden() {
        let result = merge(
            confidentLagavulin(),
            ExtractedFields(distillery: "Laphroaig"),
            lines: ["LAGAVULIN", "LAPHROAIG"]
        )
        #expect(result?.distilleryName == "Lagavulin")
    }

    @Test func aConfidentAgeAndABVAreNeverOverridden() {
        var base = confidentLagavulin()
        base.age = 16
        base.ageProvenance = .confident
        base.abv = 43
        base.abvProvenance = .confident
        let result = merge(
            base, ExtractedFields(ageYears: 12, abvPercent: 46),
            lines: ["LAGAVULIN", "16 YEARS", "12", "43%", "46%"]
        )
        #expect(result?.age == 16)
        #expect(result?.abv == 43)
    }

    // MARK: - Filling gaps

    @Test func fillsAMissingAgeAndMarksItGuessed() {
        let result = merge(
            confidentLagavulin(), ExtractedFields(ageYears: 16),
            lines: ["LAGAVULIN", "SIXTEEN", "16 YRS"]
        )
        #expect(result?.age == 16)
        #expect(result?.ageProvenance == .guessed)
        #expect(result?.isNAS == false)
    }

    @Test func fillsAMissingABVFromAnyPrintedForm() {
        let european = merge(
            confidentLagavulin(), ExtractedFields(abvPercent: 46.3),
            lines: ["LAGAVULIN", "46,3 % vol"]
        )
        #expect(european?.abv == 46.3)
        #expect(european?.abvProvenance == .guessed)

        let whole = merge(
            confidentLagavulin(), ExtractedFields(abvPercent: 43),
            lines: ["LAGAVULIN", "ALC 43 VOL"]
        )
        #expect(whole?.abv == 43)
    }

    @Test func fillsAMissingDistilleryOnlyWhenItIsInTheText() {
        let evidenced = merge(
            LabelScanResult(), ExtractedFields(distillery: "Lagavulin"),
            lines: ["LAGAVULIN", "ISLAY"]
        )
        #expect(evidenced?.distilleryName == "Lagavulin")
        #expect(evidenced?.region == "islay")
        #expect(evidenced?.distilleryProvenance == .guessed)

        // Plausible for the text ("ISLAY") but not printed: refused.
        let invented = merge(
            nil, ExtractedFields(distillery: "Lagavulin"),
            lines: ["16 YEARS OLD", "ISLAY SINGLE MALT", "43%"]
        )
        #expect(invented == nil)
    }

    @Test func buildsANameFromPrintedExpressionWords() {
        let result = merge(
            confidentLagavulin(),
            ExtractedFields(expression: "Distillers Edition", ageYears: 16),
            lines: ["LAGAVULIN", "DISTILLERS EDITION", "16 YEARS"]
        )
        #expect(result?.name == "Lagavulin Distillers Edition 16")
        #expect(result?.nameProvenance == .guessed)
    }

    @Test func doesNotRepeatTheDistilleryInTheName() {
        let result = merge(
            confidentLagavulin(),
            ExtractedFields(expression: "Lagavulin Offerman Edition"),
            lines: ["LAGAVULIN", "OFFERMAN EDITION"]
        )
        #expect(result?.name == "Lagavulin Offerman Edition")
    }

    @Test func fillsCaskWhenItsWordsArePrinted() {
        let result = merge(
            confidentLagavulin(), ExtractedFields(cask: "Pedro Ximenez"),
            lines: ["LAGAVULIN", "FINISHED IN PEDRO XIMENEZ CASKS"]
        )
        #expect(result?.cask == "Pedro Ximenez")
    }

    // MARK: - Hallucination guards

    @Test func rejectsImplausibleNumbers() {
        let result = merge(
            confidentLagavulin(), ExtractedFields(ageYears: 120, abvPercent: 430),
            lines: ["LAGAVULIN", "120", "430"]
        )
        #expect(result == confidentLagavulin(), "Out-of-range claims change nothing")
    }

    @Test func rejectsNumbersThatAreNotPrinted() {
        let result = merge(
            confidentLagavulin(), ExtractedFields(ageYears: 16, abvPercent: 43),
            lines: ["LAGAVULIN", "ISLAY SINGLE MALT"]
        )
        #expect(result == confidentLagavulin())
    }

    @Test func aNumberInsideALargerNumberIsNotEvidence() {
        // "43" appears inside "1943" and "43.5": neither is a 43% ABV.
        let result = merge(
            confidentLagavulin(), ExtractedFields(abvPercent: 43),
            lines: ["LAGAVULIN", "SINCE 1943", "43.5% vol"]
        )
        #expect(result?.abv == nil)

        let age = merge(
            confidentLagavulin(), ExtractedFields(ageYears: 16),
            lines: ["LAGAVULIN", "BATCH 116", "160 PROOF"]
        )
        #expect(age?.age == nil)
    }

    @Test func ageAcceptsAttachedUnitsLike16YO() {
        let result = merge(
            confidentLagavulin(), ExtractedFields(ageYears: 16),
            lines: ["LAGAVULIN", "16YO"]
        )
        #expect(result?.age == 16)
    }

    @Test func rejectsUnknownDistilleries() {
        let result = merge(
            nil, ExtractedFields(distillery: "Springfield Single Malt"),
            lines: ["SPRINGFIELD SINGLE MALT"]
        )
        #expect(result == nil)
    }

    @Test func rejectsAnExpressionThatIsNotPrinted() {
        let result = merge(
            confidentLagavulin(), ExtractedFields(expression: "Distillers Edition"),
            lines: ["LAGAVULIN", "16 YEARS"]
        )
        #expect(result?.name == "")
    }

    // MARK: - Tie-break between guessed alternates

    @Test func promotesTheModelsPickAmongTheParsersAlternates() throws {
        let lagavulin = try #require(store.exactMatch("Lagavulin"))
        let laphroaig = try #require(store.exactMatch("Laphroaig"))
        var base = LabelScanResult()
        base.distilleryName = "Lagavulin"
        base.region = "islay"
        base.distilleryProvenance = .guessed
        base.alternateDistilleries = [laphroaig]

        let result = merge(
            base, ExtractedFields(distillery: "Laphroaig"),
            lines: ["LAPHROIG", "LAGAVOULIN"]
        )
        #expect(result?.distilleryName == "Laphroaig")
        #expect(result?.distilleryProvenance == .guessed, "Still a guess: the person confirms it")
        #expect(result?.alternateDistilleries.map(\.name) == ["Lagavulin"])
        _ = lagavulin
    }

    @Test func ignoresAModelPickOutsideTheParsersAlternates() throws {
        let laphroaig = try #require(store.exactMatch("Laphroaig"))
        var base = LabelScanResult()
        base.distilleryName = "Lagavulin"
        base.distilleryProvenance = .guessed
        base.alternateDistilleries = [laphroaig]

        let result = merge(
            base, ExtractedFields(distillery: "Macallan"),
            lines: ["MACALLAN", "LAGAVOULIN"]
        )
        #expect(result?.distilleryName == "Lagavulin")
    }

    // MARK: - Nothing to say

    @Test func emptyFieldsReturnTheBaseUnchanged() {
        let base = confidentLagavulin()
        #expect(merge(base, ExtractedFields(), lines: ["LAGAVULIN"]) == base)
        #expect(merge(nil, ExtractedFields(), lines: ["ANYTHING"]) == nil)
    }
}

/// `enhance`: availability, timing and plumbing around the merge.
@MainActor
struct BottleExtractorEnhanceTests {
    struct Scripted: BottleExtracting {
        var available = true
        var fields: ExtractedFields?
        var delay: Duration = .zero

        var isAvailable: Bool { available }
        func prewarm() {}
        func extract(from lines: [String]) async -> ExtractedFields? {
            if delay > .zero { try? await Task.sleep(for: delay) }
            return fields
        }
    }

    private let store = DistilleryStore(distilleries: [
        Distillery(
            name: "Lagavulin", aliases: [], region: "islay",
            lat: 55.6365, lon: -6.1268, founded: 1816, owner: "Diageo",
            wikipediaTitle: "Lagavulin_distillery"
        ),
    ])

    private func enhance(_ extractor: Scripted, timeout: Duration = .seconds(1.5)) async -> LabelScanResult? {
        var base = LabelScanResult()
        base.distilleryName = "Lagavulin"
        base.distilleryProvenance = .confident
        return await extractor.enhance(
            base, lines: ["LAGAVULIN", "16 YEARS"],
            distilleryStore: store, expressionStore: ExpressionStore(expressions: []),
            timeout: timeout
        )
    }

    @Test func noModelLeavesTheBaseAlone() async {
        let result = await enhance(Scripted(available: false, fields: ExtractedFields(ageYears: 16)))
        #expect(result?.age == nil)
    }

    @Test func theNoOpExtractorIsUnavailable() {
        #expect(!NoOpBottleExtractor().isAvailable)
    }

    @Test func anAnswerInTimeIsMerged() async {
        let result = await enhance(Scripted(fields: ExtractedFields(ageYears: 16)))
        #expect(result?.age == 16)
    }

    @Test func aSlowModelIsAbandonedAtTheTimeout() async {
        let result = await enhance(
            Scripted(fields: ExtractedFields(ageYears: 16), delay: .seconds(5)),
            timeout: .milliseconds(100)
        )
        #expect(result?.age == nil, "A slow model must not hold up the confirmation sheet")
    }

    @Test func aModelThatAnswersNothingLeavesTheBaseAlone() async {
        let result = await enhance(Scripted(fields: nil))
        #expect(result?.distilleryName == "Lagavulin")
        #expect(result?.age == nil)
    }
}
