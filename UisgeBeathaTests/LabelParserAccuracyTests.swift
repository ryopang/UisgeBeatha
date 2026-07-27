import Foundation
import Testing
@testable import UisgeBeatha

/// L0: a labelled corpus of ~40 realistic label-OCR line sets — the
/// measurement harness the label-scan rewrite was built against. Covers
/// all six Scotland regions, split-line ages, European comma ABVs, NAS
/// bottlings, cask-strength ABVs, importer boilerplate, indie-bottler
/// naming, travel retail, and deliberate OCR corruption (character swaps,
/// dropped characters). See docs/label-scan-plan.md §0 and §L0 for how
/// this was derived and what it's for.
///
/// Distilleries with no expressions.json entry are included deliberately
/// so the corpus exercises the parser's own regex/descriptor-line logic,
/// not just the expression catalog papering over it.
struct LabelParserAccuracyTests {
    struct Fixture {
        let label: String
        let lines: [String]
        let distillery: String
        let age: Int?
        let isNAS: Bool
        let abv: Double?
    }

    static let corpus: [Fixture] = [
        // MARK: Speyside
        Fixture(
            label: "Macallan 12 Double Cask, split age lines",
            lines: ["THE MACALLAN", "DOUBLE CASK", "12", "YEARS OLD",
                    "HIGHLAND SINGLE MALT SCOTCH WHISKY", "40% vol"],
            distillery: "Macallan", age: 12, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Glenfiddich 12, European comma ABV",
            lines: ["Glenfiddich", "SINGLE MALT SCOTCH WHISKY", "AGED 12 YEARS", "40,0% vol", "70cl"],
            distillery: "Glenfiddich", age: 12, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Glenlivet Founder's Reserve, NAS",
            lines: ["THE GLENLIVET", "FOUNDER'S RESERVE", "SINGLE MALT SCOTCH WHISKY", "40% vol"],
            distillery: "Glenlivet", age: nil, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Aberlour A'bunadh, explicit NAS + cask strength",
            lines: ["ABERLOUR", "A'BUNADH", "NO AGE STATEMENT", "CASK STRENGTH", "60.3% vol"],
            distillery: "Aberlour", age: nil, isNAS: true, abv: 60.3
        ),
        Fixture(
            label: "Balvenie DoubleWood 12, alias \"The Balvenie\"",
            lines: ["THE BALVENIE", "DOUBLEWOOD", "AGED 12 YEARS", "SPEYSIDE SINGLE MALT SCOTCH WHISKY", "40% alc/vol"],
            distillery: "Balvenie", age: 12, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Glenfarclas 105, cask-strength constant",
            lines: ["GLENFARCLAS", "105", "CASK STRENGTH", "HIGHLAND MALT SCOTCH WHISKY", "60% vol"],
            distillery: "Glenfarclas", age: nil, isNAS: false, abv: 60.0
        ),
        Fixture(
            label: "Mortlach 16, not in expressions catalog by that exact ABV rounding",
            lines: ["MORTLACH", "16", "YEARS OLD", "SPEYSIDE SINGLE MALT SCOTCH WHISKY", "43.4% vol"],
            distillery: "Mortlach", age: 16, isNAS: false, abv: 43.4
        ),
        Fixture(
            label: "Craigellachie 13, no catalog entry needed for parser alone",
            lines: ["CRAIGELLACHIE", "13", "YEARS OLD", "SPEYSIDE SINGLE MALT SCOTCH WHISKY", "46% vol"],
            distillery: "Craigellachie", age: 13, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "GlenAllachie 12, not in expressions catalog at all",
            lines: ["THE GLENALLACHIE", "12", "YEARS OLD", "SPEYSIDE SINGLE MALT", "46% vol"],
            distillery: "GlenAllachie", age: 12, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Tomintoul 12, distillery absent from expressions catalog",
            lines: ["TOMINTOUL", "THE GENTLE DRAM", "AGED 12 YEARS", "SPEYSIDE SINGLE MALT SCOTCH WHISKY", "40% vol"],
            distillery: "Tomintoul", age: 12, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Cragganmore 12, OCR-dropped final letter (CRAGGANMOR)",
            lines: ["CRAGGANMOR", "12", "YEARS OLD", "SPEYSIDE SINGLE MALT SCOTCH WHISKY", "40% vol"],
            distillery: "Cragganmore", age: 12, isNAS: false, abv: 40.0
        ),

        // MARK: Highland
        Fixture(
            label: "Glenmorangie Quinta Ruban 14",
            lines: ["GLENMORANGIE", "QUINTA RUBAN", "14", "YEARS OLD",
                    "HIGHLAND SINGLE MALT SCOTCH WHISKY", "46% Vol"],
            distillery: "Glenmorangie", age: 14, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Glenmorangie 18, Y.O. abbreviation",
            lines: ["GLENMORANGIE", "THE EXTREMELY RARE", "18 Y.O.",
                    "HIGHLAND SINGLE MALT SCOTCH WHISKY", "43% vol"],
            distillery: "Glenmorangie", age: 18, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Oban 14, importer boilerplate first line",
            lines: ["IMPORTED BY EDRINGTON AMERICAS NEW YORK NY", "OBAN", "WEST HIGHLAND",
                    "14", "YEARS", "SINGLE MALT SCOTCH WHISKY", "43% ALC/VOL"],
            distillery: "Oban", age: 14, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Dalmore 15, definite article prefix",
            lines: ["THE DALMORE", "15", "YEARS OLD", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "40% vol"],
            distillery: "Dalmore", age: 15, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Clynelish 14, OCR digit-for-letter corruption (CLYNEL1SH)",
            lines: ["CLYNEL1SH", "14", "YEARS OLD", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "46% vol"],
            distillery: "Clynelish", age: 14, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Ardmore Legacy, no explicit NAS text printed",
            lines: ["ARDMORE", "LEGACY", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "NON CHILL-FILTERED", "40% ALC/VOL"],
            distillery: "Ardmore", age: nil, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Deanston 12, founding-year decoy line",
            lines: ["DEANSTON", "SINCE 1785", "12", "YEARS OLD", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "46.3% vol"],
            distillery: "Deanston", age: 12, isNAS: false, abv: 46.3
        ),
        Fixture(
            label: "Royal Brackla 12, small-batch style label",
            lines: ["ROYAL BRACKLA", "12", "YEARS OLD", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "40% vol", "700ml"],
            distillery: "Royal Brackla", age: 12, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Glengoyne 18, spelled-out age fallback (\"Eighteen Years\")",
            lines: ["GLENGOYNE", "EIGHTEEN YEARS", "HIGHLAND SINGLE MALT SCOTCH WHISKY", "43% vol"],
            distillery: "Glengoyne", age: 18, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Ben Nevis 10, vintage-year decoy near age line",
            lines: ["BEN NEVIS", "ESTABLISHED 1825", "10", "YEARS OLD", "HIGHLAND SINGLE MALT", "46% vol"],
            distillery: "Ben Nevis", age: 10, isNAS: false, abv: 46.0
        ),

        // MARK: Islay
        Fixture(
            label: "Lagavulin 16, baseline",
            lines: ["LAGAVULIN", "16 Years Old", "Islay Single Malt Scotch Whisky",
                    "Distilled and Bottled in Scotland", "43% Vol", "700ml"],
            distillery: "Lagavulin", age: 16, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Laphroaig 10, split numeral + AGED line",
            lines: ["LAPHROAIG", "10", "SINGLE ISLAY MALT SCOTCH WHISKY", "AGED 10 YEARS", "43% vol", "70cle"],
            distillery: "Laphroaig", age: 10, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Ardbeg Uigeadail, NAS expression name resolves ABV",
            lines: ["ARDBEG", "UIGEADAIL", "ISLAY SINGLE MALT SCOTCH WHISKY", "NON CHILL-FILTERED",
                    "54.2% ALC./VOL", "750 ML"],
            distillery: "Ardbeg", age: nil, isNAS: false, abv: 54.2
        ),
        Fixture(
            label: "Bunnahabhain 12, hard name, un-chill filtered line",
            lines: ["BUNNAHABHAIN", "12", "UN-CHILL FILTERED", "ISLAY SINGLE MALT", "46.3% vol"],
            distillery: "Bunnahabhain", age: 12, isNAS: false, abv: 46.3
        ),
        Fixture(
            label: "Bowmore 15 Darkest, sherry-cask descriptor line",
            lines: ["BOWMORE", "DARKEST", "15 YEARS OLD", "ISLAY SINGLE MALT SCOTCH WHISKY", "43% vol"],
            distillery: "Bowmore", age: 15, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Kilchoman Machir Bay, young distillery, NAS",
            lines: ["KILCHOMAN", "MACHIR BAY", "ISLAY SINGLE MALT SCOTCH WHISKY",
                    "FROM FARM TO BOTTLE", "46% vol"],
            distillery: "Kilchoman", age: nil, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Bruichladdich Classic Laddie, explicit NAS text",
            lines: ["BRUICHLADDICH", "THE CLASSIC LADDIE", "SCOTTISH BARLEY", "NO AGE STATEMENT", "50% vol"],
            distillery: "Bruichladdich", age: nil, isNAS: true, abv: 50.0
        ),
        Fixture(
            label: "Caol Ila 12, OCR letter-swap (CAOL 1LA)",
            lines: ["CAOL 1LA", "12", "YEARS OLD", "ISLAY SINGLE MALT SCOTCH WHISKY", "43% vol"],
            distillery: "Caol Ila", age: 12, isNAS: false, abv: 43.0
        ),

        // MARK: Islands
        Fixture(
            label: "Talisker 10, OCR typo TALISKFR",
            lines: ["TALISKFR", "10", "MADE BY THE SEA", "SINGLE MALT SCOTCH WHISKY", "45.8% vol"],
            distillery: "Talisker", age: 10, isNAS: false, abv: 45.8
        ),
        Fixture(
            label: "Highland Park 18, Viking-themed descriptor line",
            lines: ["IMPORTED BY EDRINGTON AMERICAS NEW YORK NY", "HIGHLAND PARK", "18",
                    "VIKING PRIDE", "ORKNEY SINGLE MALT", "43% ALC/VOL"],
            distillery: "Highland Park", age: 18, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Arran 10, isle-of prefix in text",
            lines: ["ISLE OF ARRAN", "10", "YEARS OLD", "SINGLE MALT SCOTCH WHISKY", "46% vol"],
            distillery: "Arran", age: 10, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Tobermory 12, alias Ledaig present elsewhere on label",
            lines: ["TOBERMORY", "12", "YEARS OLD", "ISLE OF MULL SINGLE MALT SCOTCH WHISKY", "46.3% vol"],
            distillery: "Tobermory", age: 12, isNAS: false, abv: 46.3
        ),
        Fixture(
            label: "Jura 18, no comma ABV, standard",
            lines: ["JURA", "18", "YEARS OLD", "SINGLE MALT SCOTCH WHISKY", "44% vol"],
            distillery: "Jura", age: 18, isNAS: false, abv: 44.0
        ),
        Fixture(
            label: "Scapa Skiren, NAS, Orkney",
            lines: ["SCAPA", "SKIREN", "ORKNEY SINGLE MALT SCOTCH WHISKY", "40% vol"],
            distillery: "Scapa", age: nil, isNAS: false, abv: 40.0
        ),

        // MARK: Lowland
        Fixture(
            label: "Auchentoshan Three Wood, NAS expression name",
            lines: ["AUCHENTOSHAN", "THREE WOOD", "LOWLAND SINGLE MALT SCOTCH WHISKY", "43% vol"],
            distillery: "Auchentoshan", age: nil, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Glenkinchie 12, capital-region descriptor",
            lines: ["GLENKINCHIE", "12", "YEARS OLD", "THE EDINBURGH MALT", "LOWLAND SINGLE MALT", "43% vol"],
            distillery: "Glenkinchie", age: 12, isNAS: false, abv: 43.0
        ),

        // MARK: Campbeltown
        Fixture(
            label: "Springbank 15, 100%-malted-barley decoy before ABV",
            lines: ["SPRINGBANK", "15 YEARS OLD", "100% MATURED IN SHERRY CASKS",
                    "CAMPBELTOWN SINGLE MALT", "46% vol"],
            distillery: "Springbank", age: 15, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Glen Scotia Double Cask, NAS",
            lines: ["GLEN SCOTIA", "DOUBLE CASK", "CAMPBELTOWN SINGLE MALT SCOTCH WHISKY", "46% vol"],
            distillery: "Glen Scotia", age: nil, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Glengyle Kilkerran 12, alias as the printed brand name",
            lines: ["KILKERRAN", "12", "YEARS OLD", "CAMPBELTOWN SINGLE MALT SCOTCH WHISKY", "46% vol"],
            distillery: "Glengyle", age: 12, isNAS: false, abv: 46.0
        ),

        // MARK: Traps — none of these should resolve to a wrong distillery
        Fixture(
            label: "Unrelated bottling with a founding-year decoy only",
            lines: ["SOME BLENDED WHISKY", "ESTABLISHED 1770", "40% vol"],
            distillery: "", age: nil, isNAS: false, abv: 40.0
        ),
    ]

    @Test func labelParserMeetsTheAccuracyFloor() throws {
        let distilleryStore = try DistilleryStore.loadBundled()
        let expressionStore = try ExpressionStore.loadBundled()

        var distilleryCorrect = 0
        var ageCorrect = 0
        var abvCorrect = 0
        var allThreeCorrect = 0
        var failures: [String] = []

        for fixture in Self.corpus {
            let result = LabelParser.parse(
                lines: fixture.lines, distilleryStore: distilleryStore, expressionStore: expressionStore
            )
            let distilleryOK = (result?.distilleryName ?? "") == fixture.distillery
            let ageOK = fixture.isNAS
                ? (result?.isNAS == true)
                : (result?.age == fixture.age)
            let abvOK = result?.abv == fixture.abv

            if distilleryOK { distilleryCorrect += 1 }
            if ageOK { ageCorrect += 1 }
            if abvOK { abvCorrect += 1 }
            if distilleryOK, ageOK, abvOK {
                allThreeCorrect += 1
            } else {
                failures.append(
                    "\(fixture.label): distillery=\(result?.distilleryName ?? "-") (want \(fixture.distillery)) "
                        + "age=\(String(describing: result?.age)) isNAS=\(result?.isNAS ?? false) "
                        + "(want \(String(describing: fixture.age)) isNAS=\(fixture.isNAS)) "
                        + "abv=\(String(describing: result?.abv)) (want \(String(describing: fixture.abv)))"
                )
            }
        }

        let total = Self.corpus.count
        let allThreePercent = Double(allThreeCorrect) / Double(total) * 100

        let scorecard = """
        Label parser accuracy scorecard (\(total) fixtures):
          distillery: \(distilleryCorrect)/\(total)
          age/NAS:    \(ageCorrect)/\(total)
          abv:        \(abvCorrect)/\(total)
          all three:  \(allThreeCorrect)/\(total) (\(String(format: "%.1f", allThreePercent))%)
        \(failures.isEmpty ? "" : "\nFailures:\n" + failures.map { "  - \($0)" }.joined(separator: "\n"))
        """
        // Printed unconditionally so the number is visible even on a pass —
        // this is the harness's whole point: "25% → X%" as a measured fact.
        print(scorecard)

        // The floor: 85%, agreed with the project owner (docs/label-scan-plan.md §4).
        #expect(allThreePercent >= 85.0, "\n\(scorecard)")
    }
}
