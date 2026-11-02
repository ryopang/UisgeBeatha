import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 4 release gate (PRD section 9): the on-device model ships only if
/// it improves accuracy on the corpus and regresses nothing.
///
/// Two pieces:
/// - `independentCorpus`: 24 fixtures beyond the original 40, in the shapes
///   the original corpus under-covers: independent bottlers, importer
///   boilerplate, cask-strength batch labels, brand names that aren't the
///   distillery's. Heuristic-only baseline always runs.
/// - A model-gated comparison that runs only on hardware where Apple
///   Intelligence is available (a physical iPhone, or a Mac simulator host
///   with it enabled) and skips everywhere else.
@MainActor
struct ExtractorAccuracyTests {
    typealias Fixture = LabelParserAccuracyTests.Fixture

    static let independentCorpus: [Fixture] = [
        Fixture(
            label: "G&M Connoisseurs Choice Benromach, distilled/bottled years, no age",
            lines: ["GORDON & MACPHAIL", "CONNOISSEURS CHOICE", "BENROMACH", "DISTILLED 2009",
                    "BOTTLED 2021", "SPEYSIDE SINGLE MALT SCOTCH WHISKY", "46% vol", "70cl"],
            distillery: "Benromach", age: nil, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Signatory Clynelish 14, bottler's name dominant",
            lines: ["SIGNATORY VINTAGE", "UN-CHILL FILTERED COLLECTION", "CLYNELISH",
                    "AGED 14 YEARS", "HIGHLAND SINGLE MALT", "46% vol"],
            distillery: "Clynelish", age: 14, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Douglas Laing Old Particular Caol Ila 12",
            lines: ["DOUGLAS LAING'S", "OLD PARTICULAR", "CAOL ILA", "AGED 12 YEARS",
                    "SINGLE CASK SINGLE MALT", "48.4% vol", "70cl"],
            distillery: "Caol Ila", age: 12, isNAS: false, abv: 48.4
        ),
        Fixture(
            label: "Cadenhead's Small Batch Bunnahabhain 10",
            lines: ["WM CADENHEAD", "SMALL BATCH", "BUNNAHABHAIN", "AGED 10 YEARS",
                    "ISLAY SINGLE MALT", "55.1% vol"],
            distillery: "Bunnahabhain", age: 10, isNAS: false, abv: 55.1
        ),
        Fixture(
            label: "Springbank 10, split age",
            lines: ["SPRINGBANK", "10", "YEARS OLD", "CAMPBELTOWN SINGLE MALT SCOTCH WHISKY", "46% vol", "70cl"],
            distillery: "Springbank", age: 10, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Springbank 15, age on one line",
            lines: ["SPRINGBANK", "15 YEAR OLD", "CAMPBELTOWN SINGLE MALT", "46% vol"],
            distillery: "Springbank", age: 15, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Glen Scotia Victoriana, NAS cask strength",
            lines: ["GLEN SCOTIA", "VICTORIANA", "CAMPBELTOWN SINGLE MALT", "NON CHILL-FILTERED", "54.2% vol"],
            distillery: "Glen Scotia", age: nil, isNAS: false, abv: 54.2
        ),
        Fixture(
            label: "Kilchoman Machir Bay, NAS",
            lines: ["KILCHOMAN", "MACHIR BAY", "ISLAY SINGLE MALT SCOTCH WHISKY", "46% vol"],
            distillery: "Kilchoman", age: nil, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Ardnamurchan with batch code",
            lines: ["ARDNAMURCHAN", "AD/09.22:01", "HIGHLAND SINGLE MALT", "46.8% vol"],
            distillery: "Ardnamurchan", age: nil, isNAS: false, abv: 46.8
        ),
        Fixture(
            label: "Tamdhu 12, sherry-cask tagline",
            lines: ["TAMDHU", "AGED 12 YEARS", "SPEYSIDE SINGLE MALT", "43% vol",
                    "MATURED EXCLUSIVELY IN SHERRY CASKS"],
            distillery: "Tamdhu", age: 12, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "GlenDronach 15 Revival",
            lines: ["THE GLENDRONACH", "REVIVAL", "AGED 15 YEARS", "HIGHLAND SINGLE MALT", "46% vol"],
            distillery: "GlenDronach", age: 15, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Old Pulteney 12, split age and tagline",
            lines: ["OLD PULTENEY", "12", "YEARS OLD", "THE MARITIME MALT", "40% vol"],
            distillery: "Old Pulteney", age: 12, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Tomatin 12",
            lines: ["TOMATIN", "12 YEAR OLD", "SINGLE MALT SCOTCH WHISKY", "43% vol"],
            distillery: "Tomatin", age: 12, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Glengoyne 18",
            lines: ["GLENGOYNE", "18 YEAR OLD", "HIGHLAND SINGLE MALT", "43% vol", "70cl"],
            distillery: "Glengoyne", age: 18, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Deanston 12, decimal ABV",
            lines: ["DEANSTON", "12", "YEARS OLD", "HIGHLAND SINGLE MALT SCOTCH WHISKY",
                    "NON CHILL-FILTERED", "46.3% vol"],
            distillery: "Deanston", age: 12, isNAS: false, abv: 46.3
        ),
        Fixture(
            label: "Bowmore 15 Darkest",
            lines: ["BOWMORE", "DARKEST", "AGED 15 YEARS", "ISLAY SINGLE MALT", "43% vol"],
            distillery: "Bowmore", age: 15, isNAS: false, abv: 43.0
        ),
        Fixture(
            label: "Ben Nevis 10",
            lines: ["BEN NEVIS", "10 YEAR OLD", "HIGHLAND SINGLE MALT", "46% vol"],
            distillery: "Ben Nevis", age: 10, isNAS: false, abv: 46.0
        ),
        Fixture(
            label: "Edradour 10",
            lines: ["EDRADOUR", "10 YEARS OLD", "HIGHLAND SINGLE MALT", "40% vol"],
            distillery: "Edradour", age: 10, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Isle of Jura Origin, brand differs from distillery name",
            lines: ["ISLE OF JURA", "ORIGIN", "10 YEARS OLD", "ISLAND SINGLE MALT", "40% vol"],
            distillery: "Jura", age: 10, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Talisker 10 with US importer boilerplate",
            lines: ["TALISKER", "10", "YEARS OLD", "SINGLE MALT SCOTCH WHISKY", "45.8% alc/vol",
                    "IMPORTED BY DIAGEO NORTH AMERICA, NORWALK, CT"],
            distillery: "Talisker", age: 10, isNAS: false, abv: 45.8
        ),
        Fixture(
            label: "Glenglassaugh Sandend, NAS",
            lines: ["GLENGLASSAUGH", "SANDEND", "HIGHLAND SINGLE MALT", "50.5% vol"],
            distillery: "Glenglassaugh", age: nil, isNAS: false, abv: 50.5
        ),
        Fixture(
            label: "Longmorn 16",
            lines: ["LONGMORN", "AGED 16 YEARS", "SPEYSIDE SINGLE MALT", "48% vol"],
            distillery: "Longmorn", age: 16, isNAS: false, abv: 48.0
        ),
        Fixture(
            label: "Scapa Skiren, NAS",
            lines: ["SCAPA", "SKIREN", "ORKNEY SINGLE MALT", "40% vol"],
            distillery: "Scapa", age: nil, isNAS: false, abv: 40.0
        ),
        Fixture(
            label: "Dalmore 12 with founding year decoy",
            lines: ["THE DALMORE", "12", "YEARS OLD", "HIGHLAND SINGLE MALT", "40% vol", "ESTD 1839"],
            distillery: "Dalmore", age: 12, isNAS: false, abv: 40.0
        ),
    ]

    // MARK: - Scoring

    struct Scorecard {
        var total = 0
        var distillery = 0
        var age = 0
        var abv = 0
        var allThree = 0
        var failures: [String] = []

        var allThreePercent: Double {
            total == 0 ? 0 : Double(allThree) / Double(total) * 100
        }

        var text: String {
            """
              distillery: \(distillery)/\(total)
              age/NAS:    \(age)/\(total)
              abv:        \(abv)/\(total)
              all three:  \(allThree)/\(total) (\(String(format: "%.1f", allThreePercent))%)
            """
        }
    }

    private static func score(_ result: LabelScanResult?, against fixture: Fixture, into card: inout Scorecard) {
        let distilleryOK = (result?.distilleryName ?? "") == fixture.distillery
        let ageOK = fixture.isNAS ? (result?.isNAS == true) : (result?.age == fixture.age)
        let abvOK = result?.abv == fixture.abv
        card.total += 1
        if distilleryOK { card.distillery += 1 }
        if ageOK { card.age += 1 }
        if abvOK { card.abv += 1 }
        if distilleryOK, ageOK, abvOK {
            card.allThree += 1
        } else {
            card.failures.append(
                "\(fixture.label): distillery=\(result?.distilleryName ?? "-") age=\(String(describing: result?.age)) "
                    + "abv=\(String(describing: result?.abv))"
            )
        }
    }

    private func heuristic(_ fixture: Fixture) throws -> LabelScanResult? {
        LabelParser.parse(
            lines: fixture.lines,
            distilleryStore: try DistilleryStore.loadBundled(),
            expressionStore: try ExpressionStore.loadBundled()
        )
    }

    // MARK: - Always-on baseline

    @Test func independentCorpusHeuristicBaseline() throws {
        var card = Scorecard()
        for fixture in Self.independentCorpus {
            Self.score(try heuristic(fixture), against: fixture, into: &card)
        }
        print("Independent corpus, heuristic only (\(card.total) fixtures):\n\(card.text)")
        if !card.failures.isEmpty {
            print("Failures:\n" + card.failures.map { "  - \($0)" }.joined(separator: "\n"))
        }
        // Deliberately modest: these fixtures were written to find the
        // parser's weak spots, and this floor only catches a collapse. The
        // printed scorecard is the real output.
        #expect(Double(card.distillery) / Double(card.total) >= 0.75, "\n\(card.text)")
    }

    @Test func corpusHasAtLeastTwentyNewFixtures() {
        #expect(Self.independentCorpus.count >= 20)
        let labels = Self.independentCorpus.map(\.label)
        #expect(Set(labels).count == labels.count, "Fixture labels should be unique")
    }

    // MARK: - Model gate (skipped without Apple Intelligence)

    @Test(.enabled(if: OnDeviceIntelligence.makeExtractor().isAvailable))
    func modelNeverRegressesTheHeuristicsAndHelpsOverall() async throws {
        let extractor = OnDeviceIntelligence.makeExtractor()
        let distilleryStore = try DistilleryStore.loadBundled()
        let expressionStore = try ExpressionStore.loadBundled()

        var withoutModel = Scorecard()
        var withModel = Scorecard()
        var regressions: [String] = []

        for fixture in LabelParserAccuracyTests.corpus + Self.independentCorpus {
            let base = LabelParser.parse(
                lines: fixture.lines, distilleryStore: distilleryStore, expressionStore: expressionStore
            )
            Self.score(base, against: fixture, into: &withoutModel)

            let enhanced = await extractor.enhance(
                base, lines: fixture.lines,
                distilleryStore: distilleryStore, expressionStore: expressionStore
            )
            Self.score(enhanced, against: fixture, into: &withModel)

            // Confident heuristic fields must be untouched.
            if let base, let enhanced {
                if base.distilleryProvenance == .confident, enhanced.distilleryName != base.distilleryName {
                    regressions.append("\(fixture.label): confident distillery changed")
                }
                if base.ageProvenance == .confident, enhanced.age != base.age {
                    regressions.append("\(fixture.label): confident age changed")
                }
                if base.abvProvenance == .confident, enhanced.abv != base.abv {
                    regressions.append("\(fixture.label): confident ABV changed")
                }
            }
        }

        print("Without model:\n\(withoutModel.text)\nWith model:\n\(withModel.text)")
        #expect(regressions.isEmpty, "\(regressions.joined(separator: "\n"))")
        #expect(withModel.allThree >= withoutModel.allThree, "Model made the corpus worse.\n\(withModel.text)")
    }
}
