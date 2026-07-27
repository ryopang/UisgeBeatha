import Foundation
import Testing
import UIKit
@testable import UisgeBeatha

/// Accuracy measurement against **real user-taken bottle photos**, run
/// end to end through the shipping pipeline: `VisionLabelOCRService`
/// (real Vision, real tuning) → `LabelParser` → scored against ground
/// truth that came from Open Food Facts' database, never from the code
/// under test.
///
/// This is the measurement `LabelParserAccuracyTests` can't make.
/// That suite feeds hand-written strings to the parser, which proves the
/// parsing logic but says nothing about whether Vision can actually read a
/// curved, glare-lit, arm's-length phone photo of a real bottle. The
/// photos here are exactly that: OFF's product images are uploaded by
/// shoppers photographing bottles on shelves.
///
/// Opt-in and slow (real Vision on ~100 full-resolution photos). The
/// corpus lives outside the repo — third-party licensed images are never
/// added to the app bundle (project rule: "never bundle images downloaded
/// from the internet") and simulator tests can read host paths directly,
/// so nothing needs copying in. Point `UISGE_CORPUS` at the corpus
/// directory, or leave the default; the test skips when it's absent.
@MainActor
struct RealPhotoAccuracyTests {

    // MARK: - Corpus

    struct Entry: Decodable {
        let code: String
        let imageFile: String
        let gtDistillery: String
        let gtRegion: String
        let gtAbv: Double?
        let gtAgeProvisional: Int?
        let offProductName: String
        let offBrands: String?
        /// False for OFF thumbnails (< 640px long edge). A phone capture is
        /// never that small, so scoring them would understate real-world
        /// accuracy against photos the app will never actually be handed.
        let usable: Bool
        let pxW: Int?
        let pxH: Int?

        enum CodingKeys: String, CodingKey {
            case code
            case imageFile = "image_file"
            case gtDistillery = "gt_distillery"
            case gtRegion = "gt_region"
            case gtAbv = "gt_abv"
            case gtAgeProvisional = "gt_age_provisional"
            case offProductName = "off_product_name"
            case offBrands = "off_brands"
            case usable
            case pxW = "px_w"
            case pxH = "px_h"
        }
    }

    /// `nonisolated` so the `.enabled(if:)` trait — evaluated outside the
    /// main actor when the suite is collected — can reach it.
    nonisolated static var corpusDirectory: String {
        ProcessInfo.processInfo.environment["UISGE_CORPUS"]
            ?? "/private/tmp/claude-501/-Users-ryo-Claude-Code-UisgeBeatha"
                + "/3617a67b-df9f-4ad0-bdf3-ec57c26923f6/scratchpad/corpus"
    }

    nonisolated static var manifestPath: String { corpusDirectory + "/manifest.json" }

    nonisolated static var corpusAvailable: Bool {
        FileManager.default.fileExists(atPath: manifestPath)
    }

    static func loadEntries() throws -> [Entry] {
        let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    // MARK: - Measurement

    /// One photo's outcome, kept so the scorecard can separate "Vision
    /// read nothing off this photo" from "Vision read plenty and the
    /// matcher still picked wrong" — very different problems.
    struct Outcome {
        let entry: Entry
        let lines: [String]
        let parsed: LabelScanResult?
        var lineCount: Int { lines.count }
        /// Whether the photo shows an ABV at all. Distinguishes "the
        /// parser missed a number that was right there" from "the bottle's
        /// ABV simply wasn't in frame" — only the former is a bug.
        var showsABVText: Bool {
            lines.contains { $0.contains("%") || $0.range(of: "vol", options: .caseInsensitive) != nil }
        }
        /// Whether the expected age appears anywhere in the recognised
        /// text. Same reasoning as `showsABVText`: an age statement that
        /// isn't in frame can't be read.
        var showsExpectedAgeText: Bool {
            guard let expected = entry.gtAgeProvisional else { return false }
            return lines.joined(separator: " ").contains("\(expected)")
        }
        var distilleryCorrect: Bool { parsed?.distilleryName == entry.gtDistillery }
        var abvCorrect: Bool? {
            guard let expected = entry.gtAbv else { return nil }
            guard let actual = parsed?.abv else { return false }
            return abs(actual - expected) < 0.06
        }
        var ageCorrect: Bool? {
            guard let expected = entry.gtAgeProvisional else { return nil }
            return parsed?.age == expected
        }
    }

    @Test(.enabled(if: RealPhotoAccuracyTests.corpusAvailable), .timeLimit(.minutes(60)))
    func measureRealPhotoAccuracy() async throws {
        let distilleryStore = try DistilleryStore.loadBundled()
        let expressionStore = try ExpressionStore.loadBundled()
        let ocr = VisionLabelOCRService(
            customWords: VisionLabelOCRService.customWords(
                distilleryStore: distilleryStore, expressionStore: expressionStore
            )
        )
        let entries = try Self.loadEntries().filter(\.usable)

        var outcomes: [Outcome] = []
        for entry in entries {
            let path = Self.corpusDirectory + "/images/" + entry.imageFile
            guard let image = UIImage(contentsOfFile: path) else {
                print("  ! unreadable image: \(entry.imageFile)")
                continue
            }
            let lines = (try? await ocr.recognizeText(in: image)) ?? []
            let parsed = LabelParser.parse(
                lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
            )
            outcomes.append(Outcome(entry: entry, lines: lines, parsed: parsed))
        }

        report(outcomes)

        let scored = outcomes.count
        let distilleryHits = outcomes.filter(\.distilleryCorrect).count
        let percent = scored == 0 ? 0 : Double(distilleryHits) / Double(scored) * 100

        #expect(scored > 0, "Corpus produced no scoreable photos")
        // Target agreed with the project owner: 90% correct distillery.
        #expect(
            percent >= 90.0,
            "Distillery accuracy \(String(format: "%.1f", percent))% is below the 90% target"
        )
    }

    private func report(_ outcomes: [Outcome]) {
        let total = outcomes.count
        let distilleryHits = outcomes.filter(\.distilleryCorrect).count
        let abvScored = outcomes.compactMap(\.abvCorrect)
        let ageScored = outcomes.compactMap(\.ageCorrect)
        let blind = outcomes.filter { $0.lineCount == 0 }.count
        let readButWrong = outcomes.filter { !$0.distilleryCorrect && $0.lineCount > 0 }.count

        func pct(_ hit: Int, _ of: Int) -> String {
            of == 0 ? "n/a" : String(format: "%.1f%%", Double(hit) / Double(of) * 100)
        }

        print("""

        ══════════════════════════════════════════════════════════════
         REAL-PHOTO ACCURACY  (\(total) user-taken bottle photos)
        ══════════════════════════════════════════════════════════════
          Distillery   \(distilleryHits)/\(total)   \(pct(distilleryHits, total))   <- headline metric
          ABV          \(abvScored.filter { $0 }.count)/\(abvScored.count)   \
        \(pct(abvScored.filter { $0 }.count, abvScored.count))
          Age          \(ageScored.filter { $0 }.count)/\(ageScored.count)   \
        \(pct(ageScored.filter { $0 }.count, ageScored.count))
        ──────────────────────────────────────────────────────────────
          Vision read nothing at all:      \(blind)
          Vision read text, match wrong:   \(readButWrong)
        ══════════════════════════════════════════════════════════════
        """)

        // ABV is only a parser failure when the number was actually on
        // screen; a bottle photographed from an angle that hides the ABV
        // is a limit of the photo, not of the recogniser.
        let abvFailures = outcomes.filter { $0.abvCorrect == false }
        let abvMissedVisible = abvFailures.filter(\.showsABVText)
        let ageFailures = outcomes.filter { $0.ageCorrect == false }
        let ageMissedVisible = ageFailures.filter(\.showsExpectedAgeText)
        let abvScoredCount = outcomes.compactMap(\.abvCorrect).count
        let ageScoredCount = outcomes.compactMap(\.ageCorrect).count

        // The honest denominators. A bottle photographed from an angle
        // that hides its ABV or age is a limit of the photo, not of the
        // recogniser, so scoring those as parser failures would understate
        // how well the pipeline actually reads what it can see.
        let abvVisibleTotal = abvScoredCount - (abvFailures.count - abvMissedVisible.count)
        let ageVisibleTotal = ageScoredCount - (ageFailures.count - ageMissedVisible.count)
        func pct2(_ hit: Int, _ of: Int) -> String {
            of == 0 ? "n/a" : String(format: "%.1f%%", Double(hit) / Double(of) * 100)
        }
        print("""
        ── when the value is actually legible in the photo ───────────
          ABV  \(abvScoredCount - abvFailures.count)/\(abvVisibleTotal)  \
        \(pct2(abvScoredCount - abvFailures.count, abvVisibleTotal))   \
        (\(abvFailures.count - abvMissedVisible.count) photos don't show ABV at all)
          Age  \(ageScoredCount - ageFailures.count)/\(ageVisibleTotal)  \
        \(pct2(ageScoredCount - ageFailures.count, ageVisibleTotal))   \
        (\(ageFailures.count - ageMissedVisible.count) photos don't show the age at all)
        ══════════════════════════════════════════════════════════════
        """)

        let failures = outcomes.filter { !$0.distilleryCorrect }
        if !failures.isEmpty {
            print("\nDISTILLERY FAILURES (\(failures.count)):")
            for failure in failures.sorted(by: { $0.lineCount < $1.lineCount }) {
                let got = failure.parsed?.distilleryName ?? ""
                print("""
                  \(failure.entry.code)  lines=\(failure.lineCount)  \
                px=\(failure.entry.pxW ?? 0)x\(failure.entry.pxH ?? 0)
                     want: \(failure.entry.gtDistillery)
                     got:  \(got.isEmpty ? "(no match)" : got)
                     off:  \(failure.entry.offProductName) | \(failure.entry.offBrands ?? "")
                     ocr:  \(failure.lines.prefix(14).map { "\u{201C}\($0)\u{201D}" }.joined(separator: " "))
                """)
            }
        }

        if !ageMissedVisible.isEmpty {
            print("\nAGE MISSED DESPITE BEING VISIBLE (\(ageMissedVisible.count)):")
            for failure in ageMissedVisible.prefix(12) {
                let expected = failure.entry.gtAgeProvisional.map { "\($0)" } ?? "?"
                let shown = failure.lines.filter { $0.contains(expected) }
                print("""
                  \(failure.entry.code)  want=\(expected)  \
                got=\(failure.parsed?.age.map { "\($0)" } ?? "nil")  \
                nas=\(failure.parsed?.isNAS ?? false)
                     lines: \(shown.prefix(5).map { "\u{201C}\($0)\u{201D}" }.joined(separator: " "))
                """)
            }
        }

        if !abvMissedVisible.isEmpty {
            print("\nABV MISSED DESPITE BEING VISIBLE (\(abvMissedVisible.count)):")
            for failure in abvMissedVisible.prefix(12) {
                let shown = failure.lines.filter {
                    $0.contains("%") || $0.range(of: "vol", options: .caseInsensitive) != nil
                }
                print("""
                  \(failure.entry.code)  want=\(failure.entry.gtAbv.map { "\($0)" } ?? "?")  \
                got=\(failure.parsed?.abv.map { "\($0)" } ?? "nil")
                     lines: \(shown.prefix(5).map { "\u{201C}\($0)\u{201D}" }.joined(separator: " "))
                """)
            }
        }
    }
}
