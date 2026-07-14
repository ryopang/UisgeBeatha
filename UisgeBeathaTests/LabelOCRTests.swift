import Foundation
import Testing
@testable import UisgeBeatha

/// LabelParser.parse is pure and synchronous — testable with plain string
/// fixtures standing in for OCR output, no Vision or camera involved.
struct LabelOCRTests {
    let store: DistilleryStore

    init() throws {
        store = try DistilleryStore.loadBundled()
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
        let result = LabelParser.parse(lines: lines, distilleryStore: store)
        #expect(result?.distilleryName == "Lagavulin")
        #expect(result?.region == "islay")
        #expect(result?.age == 16)
        #expect(result?.abv == 43)
    }

    @Test func prefersTheLineNamingTheMatchedDistilleryAsTheName() {
        let lines = [
            "IMPORTED BY SOME DISTRIBUTOR LLC NEW YORK NY 10001",
            "Talisker 10 Year Old",
            "Single Malt Scotch Whisky",
        ]
        let result = LabelParser.parse(lines: lines, distilleryStore: store)
        #expect(result?.name == "Talisker 10 Year Old")
        #expect(result?.distilleryName == "Talisker")
        #expect(result?.region == "islands")
    }

    @Test func fallsBackToTheLongestLineWhenNoDistilleryMatches() {
        let lines = ["Small Batch", "A Very Long Unrecognized Product Name Line"]
        let result = LabelParser.parse(lines: lines, distilleryStore: store)
        #expect(result?.name == "A Very Long Unrecognized Product Name Line")
        #expect(result?.distilleryName == "")
    }

    @Test func emptyLinesProduceNoResult() {
        #expect(LabelParser.parse(lines: [], distilleryStore: store) == nil)
    }

    @Test func proofIsRecognizedOnLabelsToo() {
        let lines = ["Wild Turkey", "101 Proof", "Kentucky Straight Bourbon Whiskey"]
        let result = LabelParser.parse(lines: lines, distilleryStore: store)
        #expect(result?.abv == 50.5)
    }
}
