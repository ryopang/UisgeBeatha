import Foundation
import SwiftUI
import Vision

// MARK: - Service

/// Reads a photographed bottle label via on-device text recognition, as a
/// fallback when a barcode lookup misses (PRD F1's miss path otherwise has
/// nothing at all to prefill from). Best-effort only, same philosophy as
/// WhiskyLabelParser: returns raw recognized lines, never anything treated
/// as authoritative — callers still let the person confirm or edit before
/// saving.
protocol LabelOCRServicing: Sendable {
    /// `nonisolated` so the (potentially slow) recognition pass runs off
    /// the main actor regardless of the caller's isolation — the same
    /// class of "camera work quietly blocking the main thread" bug already
    /// hit once this session with the barcode scanner.
    nonisolated func recognizeText(in image: UIImage) async throws -> [String]
}

/// Words Vision should bias toward beyond the seed data — general whisky
/// terminology a distillery/expression name list alone wouldn't cover,
/// chosen from what actually shows up across real label copy.
nonisolated private enum WhiskyVocabulary {
    static let terms = [
        "Single", "Malt", "Grain", "Blended", "Scotch", "Whisky", "Distillery",
        "Cask", "Strength", "Sherry", "Oloroso", "Quarter", "Double", "Triple",
        "Wood", "Finish", "Batch", "Chill", "Filtered", "Unchillfiltered",
        "Natural", "Colour", "Vintage", "Reserve", "Edition", "Limited",
        "Signature", "Highland", "Lowland", "Islay", "Speyside", "Islands",
        "Campbeltown", "Proof", "Vol", "Alc", "Old", "Years", "Aged",
    ]
}

/// Modern struct-based Vision API (`RecognizeTextRequest` /
/// `ImageRequestHandler`, iOS 18+ — this project's iOS 26 minimum makes it
/// unconditionally available). Rewritten after measuring the previous
/// version's configuration against the parsing pipeline (see
/// docs/label-scan-plan.md §A5): three settings were actively working
/// against distillery-name recognition.
///
/// 1. **`usesLanguageCorrection` was `true`.** English-language
///    autocorrection applied to words like "Bunnahabhain" and
///    "Auchentoshan", which aren't English — when it rewrites one, nothing
///    downstream has a chance. The primary pass here runs with correction
///    off; a second pass with it on only runs (and is merged in, not
///    substituted) when the first pass came back thin, since the two fail
///    in different, complementary ways.
/// 2. **Only the top candidate per observation was kept.** A misread whose
///    *second*-best reading was correct had no way to recover. Now the top
///    3 candidates per observation are all handed to the parser as
///    additional lines — cheap, since `LabelParser` already scans every
///    line globally rather than trusting line order for identity.
/// 3. **No `customWords`.** The 126-distillery seed catalog and the
///    expression catalog were sitting in memory unused as a bias hint,
///    despite existing for exactly this purpose.
nonisolated struct VisionLabelOCRService: LabelOCRServicing {
    /// Long-edge cap before recognition. A 12MP capture is slower to
    /// process without being meaningfully more accurate above this —
    /// ImageStore's own stored-photo cap (LocalImageStore.maxPixelSize) is
    /// the same number for the same reason.
    static let maxPixelSize: CGFloat = 2000

    let customWords: [String]

    init(customWords: [String] = []) {
        self.customWords = customWords
    }

    /// Builds `customWords` from the bundled seed data: every distillery
    /// name/alias and expression name, split into individual words (Vision
    /// biases per-word, not per-phrase), plus general whisky terminology.
    static func customWords(distilleryStore: DistilleryStore, expressionStore: ExpressionStore) -> [String] {
        var words = Set<String>()
        for distillery in distilleryStore.distilleries {
            for phrase in [distillery.name] + distillery.aliases {
                for word in phrase.split(separator: " ") { words.insert(String(word)) }
            }
        }
        for expression in expressionStore.expressions where !expression.name.isEmpty {
            for word in expression.name.split(separator: " ") { words.insert(String(word)) }
        }
        words.formUnion(WhiskyVocabulary.terms)
        return Array(words)
    }

    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let downsampled = Self.downsample(cgImage, maxPixelSize: Self.maxPixelSize) ?? cgImage
        let handler = ImageRequestHandler(downsampled, orientation: orientation)

        let primary = try await handler.perform(makeRequest(usesLanguageCorrection: false))
        let primaryLines = Self.linesWithAlternates(from: primary)

        // A thin first pass (very little text found at all — a dark
        // bottle, a bad angle) is worth a second, different-tradeoff
        // attempt; a healthy first pass isn't worth the extra recognition
        // time for what merging would add.
        guard primaryLines.count < 3 else { return primaryLines }

        let secondary = try await handler.perform(makeRequest(usesLanguageCorrection: true))
        let secondaryLines = Self.linesWithAlternates(from: secondary)

        var merged = primaryLines
        for line in secondaryLines where !merged.contains(where: { $0.caseInsensitiveCompare(line) == .orderedSame }) {
            merged.append(line)
        }
        return merged
    }

    private func makeRequest(usesLanguageCorrection: Bool) -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        request.customWords = customWords
        request.recognitionLanguages = [Locale.Language(identifier: "en-GB"), Locale.Language(identifier: "en-US")]
        // Default is 1/32 of the image height; ABV and volume are the
        // smallest print on a label and were falling under that threshold
        // in a full-bottle photo.
        request.minimumTextHeightFraction = 0.012
        return request
    }

    /// Each observation's best reading, in Vision's own order (line-window
    /// pairing in LabelParser depends on that order), followed by its
    /// next-best alternates when they differ from the best — extra lines
    /// for the parser's global distillery scan to consider, not a
    /// replacement for the primary reading.
    private static func linesWithAlternates(from observations: [RecognizedTextObservation]) -> [String] {
        var primary: [String] = []
        var alternates: [String] = []
        for observation in observations {
            let candidates = observation.topCandidates(3)
            guard let best = candidates.first?.string, !best.isEmpty else { continue }
            primary.append(best)
            for candidate in candidates.dropFirst() {
                let text = candidate.string
                guard !text.isEmpty, text.caseInsensitiveCompare(best) != .orderedSame else { continue }
                alternates.append(text)
            }
        }
        return primary + alternates
    }

    /// Never upscales; a photo already under the cap passes through untouched.
    private static func downsample(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage? {
        let longestEdge = CGFloat(max(image.width, image.height))
        guard longestEdge > maxPixelSize else { return image }
        let scale = maxPixelSize / longestEdge
        let targetWidth = max(1, Int(CGFloat(image.width) * scale))
        let targetHeight = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: targetWidth, height: targetHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}

private extension CGImagePropertyOrientation {
    /// VNImageRequestHandler/ImageRequestHandler take a CGImage, which
    /// (unlike UIImage) carries no orientation of its own — without this, a
    /// portrait camera photo gets read sideways and recognition quality
    /// collapses. `nonisolated` so it can be called from the OCR service's
    /// nonisolated (off-main) recognition pass.
    nonisolated init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Label text to form fields

/// How confidently a `LabelScanResult` field was determined. Drives what
/// the scan confirmation UI shows the person before anything is saved —
/// with a pipeline that's sometimes wrong, "read vs. guessed vs. nothing
/// found" matters more than a single merged best-guess value.
nonisolated enum FieldProvenance: Sendable, Equatable {
    /// A high-tier distillery match (exact/contains), an explicit "N
    /// years"/"N%" pattern actually present on the label, or a value filled
    /// from an expression-catalog entry matched on distillery *and* age.
    case confident
    /// A fuzzy/Levenshtein distillery match, the guarded standalone-numeral
    /// age fallback, or a catalog fill matched on name-token overlap alone.
    case guessed
    /// Nothing found for this field.
    case none
}

/// Everything a label scan resolved, each field tagged with how sure the
/// parse is. `LabelParser.parse` returns this; `asPrefill()` bridges it
/// into the plain `LookupPrefill` shape the entry form already knows how
/// to apply, for callers that don't (yet) show provenance.
nonisolated struct LabelScanResult: Sendable, Equatable {
    var name = ""
    var nameProvenance = FieldProvenance.none
    var distilleryName = ""
    var distilleryProvenance = FieldProvenance.none
    var region = ""
    var abv: Double?
    var abvProvenance = FieldProvenance.none
    var age: Int?
    var isNAS = false
    var ageProvenance = FieldProvenance.none
    /// Cask or finish, only ever set by the on-device model (the
    /// heuristic parser doesn't read it).
    var cask: String?
    /// Other plausible distilleries, offered when the top match came from a
    /// fuzzy tier and might be wrong — never populated for a confident match.
    var alternateDistilleries: [Distillery] = []

    func asPrefill(barcode: String? = nil, stockPhotoURL: String? = nil) -> LookupPrefill {
        LookupPrefill(
            name: name, distilleryName: distilleryName, region: region,
            abv: abv, age: age, caskType: cask, barcode: barcode, stockPhotoURL: stockPhotoURL
        )
    }
}

/// Turns OCR'd label lines into a best-guess prefill (PRD F1's miss path),
/// sourced from a photo instead of a product database. Synchronous and
/// pure so it's testable with plain string fixtures, no Vision or camera
/// involved. `nonisolated` (as are DistilleryStore and ExpressionStore) so
/// the live scanner can parse off the main actor instead of on every
/// camera frame.
///
/// Rewritten after measuring the original version against realistic label
/// fixtures at 5/12 all-three-fields-correct. Three changes account for
/// nearly all of the gap:
///
/// 1. Distillery match is a **global scan across every line**, scored by
///    match tier (exact > contains > fuzzy), not "whichever line matched
///    first" — Vision doesn't guarantee reading order, so line position
///    was never a signal worth trusting.
/// 2. Age/ABV are read from **line windows** (each line, each adjacent
///    pair joined, the whole label joined), not single lines in isolation
///    — a label prints "12" and "YEARS OLD" as two separate observations
///    far more often than as one.
/// 3. The product name is **constructed** from the matched distillery, an
///    expression-catalog or descriptor-line name, and the age — not lifted
///    as one raw OCR line, which was almost always either the bare
///    distillery name or a boilerplate sentence.
nonisolated enum LabelParser {
    static func parse(
        lines: [String],
        distilleryStore: DistilleryStore,
        expressionStore: ExpressionStore = ExpressionStore(expressions: [])
    ) -> LabelScanResult? {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleanedLines.isEmpty else { return nil }

        let allWindows = lineWindows(for: cleanedLines)
        var result = LabelScanResult()

        let distilleryMatch = bestDistillery(in: cleanedLines, store: distilleryStore)
        if let distilleryMatch {
            result.distilleryName = distilleryMatch.distillery.name
            result.region = distilleryMatch.distillery.region
            result.distilleryProvenance = distilleryMatch.tier <= .contains ? .confident : .guessed
            if distilleryMatch.tier > .contains {
                result.alternateDistilleries = alternateDistilleries(
                    in: cleanedLines, store: distilleryStore, excluding: distilleryMatch.distillery
                )
            }
        }

        if let age = WhiskyLabelParser.age(in: allWindows) {
            result.age = age
            result.ageProvenance = .confident
        } else if LabelText.mentionsNAS(cleanedLines) {
            result.isNAS = true
            result.ageProvenance = .confident
        } else if let guessed = guessedStandaloneAge(in: cleanedLines) {
            result.age = guessed
            result.ageProvenance = .guessed
        }

        if let abv = WhiskyLabelParser.abv(in: allWindows) {
            result.abv = abv
            result.abvProvenance = .confident
        }

        // Expression-catalog fill: fills a gap, never overrides a value
        // already read directly off the label — a real bottle can be a
        // cask-strength or travel-retail variant the catalog doesn't know
        // about, and a live read beats a guessed catalog match.
        var matchedExpression: Expression?
        if let distillery = distilleryMatch?.distillery {
            let expression = expressionStore.match(
                distillery: distillery.name, age: result.age, candidateText: cleanedLines
            )
            matchedExpression = expression
            if let expression {
                if result.abv == nil {
                    result.abv = expression.abv
                    result.abvProvenance = .confident
                }
                if result.age == nil, !result.isNAS, let age = expression.age {
                    result.age = age
                    result.ageProvenance = .confident
                }
            } else if result.abv == nil, result.age == nil, !result.isNAS,
                      let sole = expressionStore.soleNASExpression(distillery: distillery.name) {
                // No age was read at all and the distillery has exactly one
                // NAS core expression — a reasonable guess, not a fact.
                result.abv = sole.abv
                result.abvProvenance = .guessed
            }
        }

        result.name = buildName(
            lines: cleanedLines,
            distillery: distilleryMatch?.distillery,
            expression: matchedExpression,
            age: result.age,
            distilleryStore: distilleryStore
        )
        result.nameProvenance = result.name.isEmpty
            ? .none
            : (distilleryMatch != nil ? .confident : .guessed)

        guard !result.name.isEmpty || distilleryMatch != nil else { return nil }
        return result
    }

    /// Each line alone, then each adjacent pair joined, then the whole
    /// label joined — single-line matches are tried first (a cross-line
    /// join risks pasting unrelated text together), but a real label very
    /// often splits its age across exactly two observations.
    private static func lineWindows(for lines: [String]) -> [String] {
        let pairs = zip(lines, lines.dropFirst()).map { "\($0) \($1)" }
        return lines + pairs + [lines.joined(separator: " ")]
    }

    /// Scores every line *and every adjacent run of lines* against the
    /// distillery store, keeping the best tier (ties broken by longer
    /// matched name) — a weak fuzzy hit on line 1 no longer beats an exact
    /// hit on line 4 just for being first.
    ///
    /// The adjacent runs matter more than they look: a fifth of the seed
    /// catalog has a multi-word name (Glen Moray, Royal Lochnagar, Highland
    /// Park, Caol Ila, Old Pulteney…) and labels routinely set those words
    /// on separate typographic lines, which Vision returns as separate
    /// observations. Measured against real bottle photos, matching lines
    /// only in isolation missed "GLEN" / "MORAY" and "ROYAL IBAS" /
    /// "LOCHNAGAR." — the name was read correctly and thrown away for
    /// being on two lines. Joining also rescues names with OCR garbage
    /// wedged between the words, since the token-subset tier ignores the
    /// interloper.
    private static func bestDistillery(
        in lines: [String], store: DistilleryStore
    ) -> (distillery: Distillery, tier: DistilleryStore.MatchTier)? {
        var best: (Distillery, DistilleryStore.MatchTier, Int)?
        for window in adjacentWindows(lines) {
            guard let match = store.tieredMatch(for: window) else { continue }
            let isBetter = best.map {
                match.tier < $0.1 || (match.tier == $0.1 && match.matchedLength > $0.2)
            } ?? true
            if isBetter { best = (match.distillery, match.tier, match.matchedLength) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Each line alone, then each adjacent pair, then each adjacent triple.
    /// Capped at three because no seed distillery name is longer, and
    /// wider joins would start inventing matches out of unrelated text.
    private static func adjacentWindows(_ lines: [String]) -> [String] {
        var windows = lines
        for span in 2...3 where lines.count >= span {
            for start in 0...(lines.count - span) {
                windows.append(lines[start..<(start + span)].joined(separator: " "))
            }
        }
        return windows
    }

    /// Up to 2 other plausible distilleries, scanned the same way as
    /// `bestDistillery` — offered only when the top match itself came from
    /// a fuzzy tier and might be wrong, so the confirmation UI has
    /// something concrete to offer instead of just "not sure".
    private static func alternateDistilleries(
        in lines: [String], store: DistilleryStore, excluding top: Distillery
    ) -> [Distillery] {
        var candidates: [(distillery: Distillery, tier: DistilleryStore.MatchTier, length: Int)] = []
        for window in adjacentWindows(lines) {
            guard let match = store.tieredMatch(for: window), match.distillery != top,
                  !candidates.contains(where: { $0.distillery == match.distillery }) else { continue }
            candidates.append((match.distillery, match.tier, match.matchedLength))
        }
        return candidates
            .sorted { $0.tier < $1.tier || ($0.tier == $1.tier && $0.length > $1.length) }
            .prefix(2)
            .map(\.distillery)
    }

    /// A short standalone-numeral line (just "12", nothing else) in a
    /// plausible age set, when no explicit "N years" form was found
    /// anywhere. The riskiest heuristic here, so it's deliberately narrow:
    /// only fires for values distilleries actually use, and rejects a line
    /// that reads as a volume, a year, or sits directly beside an ABV/proof
    /// mention (a cask or batch number often does).
    private static func guessedStandaloneAge(in lines: [String]) -> Int? {
        let plausibleAges: Set<Int> = [8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23, 25, 26, 30, 35, 40, 50]
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let value = Int(trimmed), plausibleAges.contains(value) else { continue }
            guard !LabelText.isFourDigitYear(trimmed) else { continue }
            let neighbors = [lines[safe: index - 1], lines[safe: index + 1]].compactMap { $0 }
            let neighborhoodIsClean = neighbors.allSatisfy { neighbor in
                WhiskyLabelParser.abv(in: [neighbor]) == nil
                    && !LabelText.isVolumeStatement(DistilleryStore.normalize(neighbor))
                    && !neighbor.localizedCaseInsensitiveContains("proof")
                    && !neighbor.localizedCaseInsensitiveContains("batch")
                    && !neighbor.localizedCaseInsensitiveContains("cask no")
            }
            guard neighborhoodIsClean else { continue }
            return value
        }
        return nil
    }

    /// Distillery name + an expression descriptor (from the catalog if
    /// matched, else a nearby non-boilerplate line) + age, in the order a
    /// bottle's own labeling reads — "Macallan Double Cask 12" — rather
    /// than one raw OCR line.
    private static func buildName(
        lines: [String], distillery: Distillery?, expression: Expression?, age: Int?,
        distilleryStore: DistilleryStore
    ) -> String {
        guard let distillery else {
            let candidates = lines.filter { !LabelText.isBoilerplate($0) }
            guard let longest = candidates.max(by: { $0.count < $1.count }) else { return "" }
            return LabelText.titleCased(longest, knownCasing: [:])
        }

        var parts = [distillery.name]
        if let expression {
            // The catalog matched (even to a plain, unnamed age-stated
            // bottling) — that's an authoritative answer to "is there an
            // expression name here", so a descriptor line is never hunted
            // for on top of it.
            if !expression.name.isEmpty { parts.append(expression.name) }
        } else if let descriptor = descriptorLine(in: lines, distillery: distillery) {
            parts.append(LabelText.titleCased(descriptor, knownCasing: LabelText.knownCasing(from: distilleryStore)))
        }
        if let age {
            parts.append(String(age))
        }
        return parts.joined(separator: " ")
    }

    /// The first line that names neither the distillery nor is boilerplate,
    /// a bare number, a year, or a short ABV mention — usually the
    /// expression name itself ("Double Cask", "Uigeadail") when the
    /// catalog didn't already resolve one.
    private static func descriptorLine(in lines: [String], distillery: Distillery) -> String? {
        let distilleryNormalized = DistilleryStore.normalize(distillery.name)
        let aliasNormalized = Set(distillery.aliases.map(DistilleryStore.normalize))
        for line in lines {
            let normalized = DistilleryStore.normalize(line)
            guard !normalized.isEmpty, !LabelText.isBoilerplate(line) else { continue }
            if normalized == distilleryNormalized || aliasNormalized.contains(normalized) { continue }
            if line.localizedCaseInsensitiveContains(distillery.name) { continue }
            if normalized.allSatisfy({ $0.isNumber || $0 == " " }) { continue }
            if LabelText.isFourDigitYear(line.trimmingCharacters(in: .whitespaces)) { continue }
            if WhiskyLabelParser.abv(in: [line]) != nil { continue }
            return line
        }
        return nil
    }
}

nonisolated private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var labelOCR: any LabelOCRServicing = VisionLabelOCRService()
}

// MARK: - UI-test stub

#if DEBUG
/// Installed when launched with -uiTestLookupStub, matching the other
/// service stubs. The camera itself is still unavailable in the simulator,
/// so this only matters if a future test drives the flow via an injected
/// image rather than the live camera.
struct StubLabelOCRService: LabelOCRServicing {
    nonisolated func recognizeText(in image: UIImage) async throws -> [String] {
        ["Lagavulin 16 Year Old", "Islay Single Malt Scotch Whisky", "43% Vol", "700ml"]
    }
}
#endif
