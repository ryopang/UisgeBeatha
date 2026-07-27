import Foundation
import Testing
import UIKit
@testable import UisgeBeatha

/// End-to-end: synthetic label image → real Vision recognition (the actual
/// `VisionLabelOCRService`, not the UI-test stub) → `LabelParser`. Unlike
/// `LabelParserAccuracyTests` (hand-typed strings standing in for OCR
/// output), this exercises the real Vision request pipeline — the
/// `customWords` seeding, `usesLanguageCorrection = false`, and
/// `minimumTextHeightFraction` changes from the L2 rewrite only matter if
/// Vision itself reads the image correctly, and nothing else in this test
/// suite touches Vision at all.
///
/// Rendered mockups, not real photos: no curved glass, no glare, no
/// lighting variation. This proves the Vision *configuration* is sound and
/// that the pipeline recovers a label's small print end to end; it is not
/// a substitute for a real-photo accuracy measurement (docs/label-scan-plan.md §0.1).
struct VisionOCRIntegrationTests {
    let distilleryStore: DistilleryStore
    let expressionStore: ExpressionStore
    let ocrService: VisionLabelOCRService

    init() throws {
        distilleryStore = try DistilleryStore.loadBundled()
        expressionStore = try ExpressionStore.loadBundled()
        ocrService = VisionLabelOCRService(
            customWords: VisionLabelOCRService.customWords(
                distilleryStore: distilleryStore, expressionStore: expressionStore
            )
        )
    }

    private func recognizeAndParse(_ lines: [SyntheticLabelImage.Line]) async throws -> LabelScanResult? {
        let image = SyntheticLabelImage.render(lines: lines)
        let recognized = try await ocrService.recognizeText(in: image)
        return LabelParser.parse(lines: recognized, distilleryStore: distilleryStore, expressionStore: expressionStore)
    }

    @Test func recognizesLagavulin16EndToEnd() async throws {
        let result = try await recognizeAndParse([
            .init("LAGAVULIN", fontSize: 46),
            .init("16 Years Old", fontSize: 30),
            .init("Islay Single Malt Scotch Whisky", fontSize: 22, weight: .regular),
            .init("43% Vol", fontSize: 18, weight: .regular),
        ])
        #expect(result?.distilleryName == "Lagavulin")
        #expect(result?.age == 16)
        #expect(result?.abv == 43.0)
    }

    @Test func recognizesMacallanDoubleCask12WithSplitAgeLines() async throws {
        let result = try await recognizeAndParse([
            .init("THE MACALLAN", fontSize: 44),
            .init("DOUBLE CASK", fontSize: 26, weight: .regular),
            .init("12", fontSize: 40),
            .init("YEARS OLD", fontSize: 20, weight: .regular),
            .init("40% vol", fontSize: 17, weight: .regular),
        ])
        #expect(result?.distilleryName == "Macallan")
        #expect(result?.age == 12)
    }

    /// A distillery name Vision's English-language autocorrection has a
    /// real incentive to "fix" into something English-shaped — the
    /// specific failure mode `usesLanguageCorrection = false` targets.
    @Test func recognizesBunnahabhainWithoutLanguageCorrectionMangling() async throws {
        let result = try await recognizeAndParse([
            .init("BUNNAHABHAIN", fontSize: 40),
            .init("12", fontSize: 34),
            .init("Islay Single Malt Scotch Whisky", fontSize: 20, weight: .regular),
            .init("46.3% vol", fontSize: 17, weight: .regular),
        ])
        #expect(result?.distilleryName == "Bunnahabhain")
    }

    @Test func recognizesSmallPrintABVAtRealisticLabelScale() async throws {
        // ABV rendered small (18pt in a 1400pt-tall image, ≈1.3% of image
        // height) — smaller than Vision's default 1/32 (≈3.1%) minimum text
        // height, which is exactly what was silently dropping ABV/volume
        // text on real full-bottle photos before minimumTextHeightFraction
        // was lowered.
        let result = try await recognizeAndParse([
            .init("GLENFIDDICH", fontSize: 44),
            .init("AGED 12 YEARS", fontSize: 24, weight: .regular),
            .init("40% vol", fontSize: 18, weight: .regular),
        ])
        #expect(result?.abv == 40.0)
    }

    @Test func recognizesTaliskerIslandsBottling() async throws {
        let result = try await recognizeAndParse([
            .init("TALISKER", fontSize: 44),
            .init("10", fontSize: 34),
            .init("Made by the Sea", fontSize: 20, weight: .regular),
            .init("45.8% vol", fontSize: 17, weight: .regular),
        ])
        #expect(result?.distilleryName == "Talisker")
        #expect(result?.region == "islands")
    }

    @Test func recognizesArdbegUigeadailNASExpression() async throws {
        let result = try await recognizeAndParse([
            .init("ARDBEG", fontSize: 46),
            .init("UIGEADAIL", fontSize: 32),
            .init("Islay Single Malt Scotch Whisky", fontSize: 20, weight: .regular),
            .init("54.2% vol", fontSize: 17, weight: .regular),
        ])
        #expect(result?.distilleryName == "Ardbeg")
        #expect(result?.abv == 54.2)
    }
}
