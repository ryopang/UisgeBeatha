import Foundation
import Testing
@testable import UisgeBeatha

/// LabelParser.parse is pure and synchronous — testable with plain string
/// fixtures standing in for OCR output, no Vision or camera involved.
struct LabelOCRTests {
    let store: DistilleryStore
    let expressions: ExpressionStore

    init() throws {
        store = try DistilleryStore.loadBundled()
        expressions = try ExpressionStore.loadBundled()
    }

    private func parse(_ lines: [String]) -> LabelScanResult? {
        LabelParser.parse(lines: lines, distilleryStore: store, expressionStore: expressions)
    }

    @Test func parsesDistilleryRegionAgeAndABVFromLabelLines() {
        let lines = [
            "LAGAVULIN",
            "16 Years Old",
            "Islay Single Malt Scotch Whisky",
            "Distilled and Bottled in Scotland",
            "43% Vol",
            "700ml",
        ]
        let result = parse(lines)
        #expect(result?.distilleryName == "Lagavulin")
        #expect(result?.region == "islay")
        #expect(result?.age == 16)
        #expect(result?.abv == 43)
        #expect(result?.distilleryProvenance == .confident)
        #expect(result?.ageProvenance == .confident)
    }

    /// The constructed name is now "Distillery [expression] [age]"
    /// ("Talisker 10", matching the app's own placeholder convention,
    /// Strings.Form.namePlaceholder == "Lagavulin 16") rather than one raw
    /// OCR line — a raw line was almost always either the bare distillery
    /// name or a boilerplate sentence in practice (see docs/label-scan-plan.md §A3).
    @Test func constructsANameFromDistilleryAndAgeRatherThanARawLine() {
        let lines = [
            "IMPORTED BY SOME DISTRIBUTOR LLC NEW YORK NY 10001",
            "Talisker 10 Year Old",
            "Single Malt Scotch Whisky",
        ]
        let result = parse(lines)
        #expect(result?.name == "Talisker 10")
        #expect(result?.distilleryName == "Talisker")
        #expect(result?.region == "islands")
        #expect(result?.age == 10)
    }

    @Test func fallsBackToTheLongestNonBoilerplateLineWhenNoDistilleryMatches() {
        let lines = ["Small Batch", "A Very Long Unrecognized Product Name Line"]
        let result = parse(lines)
        #expect(result?.name == "A Very Long Unrecognized Product Name Line")
        #expect(result?.distilleryName == "")
    }

    @Test func emptyLinesProduceNoResult() {
        #expect(parse([]) == nil)
    }

    @Test func proofIsRecognizedOnLabelsToo() {
        let lines = ["Wild Turkey", "101 Proof", "Kentucky Straight Bourbon Whiskey"]
        let result = parse(lines)
        #expect(result?.abv == 50.5)
    }

    // MARK: - Regressions for the specific bugs measured before the L1 rewrite

    /// The age was previously never found at all: "12" and "YEARS OLD"
    /// arrive as two separate Vision observations on almost every real
    /// label, and the original parser only ever looked at one line in
    /// isolation.
    @Test func findsAgeSplitAcrossTwoLines() {
        let lines = ["THE MACALLAN", "DOUBLE CASK", "12", "YEARS OLD", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "40% vol"]
        let result = parse(lines)
        #expect(result?.distilleryName == "Macallan")
        #expect(result?.age == 12)
        #expect(result?.name == "Macallan Double Cask 12")
    }

    /// "40,0% vol" previously matched the digit before the comma ("0"),
    /// failed its range check, and returned nil instead of trying "40".
    @Test func recognizesEuropeanCommaDecimalABV() {
        let lines = ["Glenfiddich", "SINGLE MALT SCOTCH WHISKY", "AGED 12 YEARS", "40,0% vol", "70cl"]
        let result = parse(lines)
        #expect(result?.abv == 40.0)
        #expect(result?.age == 12)
    }

    /// "18 Y.O." previously failed entirely: the trailing `\b` in the old
    /// regex never matches right after a period at the end of a string.
    @Test func recognizesYODotAbbreviation() {
        let lines = ["GLENMORANGIE", "THE EXTREMELY RARE", "18 Y.O.", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "43% vol"]
        let result = parse(lines)
        #expect(result?.age == 18)
    }

    /// A founding-year alias ("1770" → Glasgow Distillery) must never fire
    /// off an unrelated label that happens to print that year.
    @Test func foundingYearAliasDoesNotFalsePositive() {
        let lines = ["ARDBEG", "UIGEADAIL", "ISLAY SINGLE MALT SCOTCH WHISKY", "FOUNDED 1815", "54.2% ALC./VOL"]
        let result = parse(lines)
        #expect(result?.distilleryName == "Ardbeg")
    }

    /// A fuzzy-tier top match should come with alternates for the
    /// confirmation UI to offer; a confident (exact/contains) match never
    /// needs them, since there's nothing to second-guess.
    @Test func populatesAlternatesOnlyForAFuzzyTopMatch() {
        let fuzzy = parse(["TALISKFR", "10", "MADE BY THE SEA", "45.8% vol"])
        #expect(fuzzy?.distilleryProvenance == .guessed)

        let confident = parse(["LAGAVULIN", "16 Years Old", "43% Vol"])
        #expect(confident?.distilleryProvenance == .confident)
        #expect(confident?.alternateDistilleries.isEmpty == true)
    }

    /// NAS bottlings should say so rather than silently leaving age blank
    /// and indistinguishable from "not found".
    @Test func detectsExplicitNoAgeStatement() {
        let lines = ["ABERLOUR", "A'BUNADH", "NO AGE STATEMENT", "CASK STRENGTH", "60.3% vol"]
        let result = parse(lines)
        #expect(result?.isNAS == true)
        #expect(result?.age == nil)
    }
}
