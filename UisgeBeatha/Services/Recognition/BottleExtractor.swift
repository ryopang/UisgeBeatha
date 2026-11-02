import Foundation
import SwiftUI

// MARK: - Contract

/// What an on-device model claims to have read off a label or listing.
/// Plain, `Sendable` and free of any framework type, so the merge rules
/// below are testable without a model, and the rest of the app never
/// depends on Foundation Models being present.
nonisolated struct ExtractedFields: Sendable, Equatable {
    var distillery: String?
    /// The expression name without distillery or age, e.g. "Double Cask".
    var expression: String?
    var ageYears: Int?
    var abvPercent: Double?
    var cask: String?
    var saysScotch: Bool?
}

/// Reads bottle fields out of messy text (OCR lines, or a terse retailer
/// title and description). Optional by design: when the model is missing
/// (older hardware, Apple Intelligence off, still downloading) the app
/// behaves exactly as it did without one.
nonisolated protocol BottleExtracting: Sendable {
    var isAvailable: Bool { get }
    /// Warms the model so the first real call is quick. Cheap and safe to
    /// call repeatedly.
    func prewarm()
    /// nil when unavailable, when the model refuses, or on any error.
    func extract(from lines: [String]) async -> ExtractedFields?
}

/// The behavior when there is no model.
nonisolated struct NoOpBottleExtractor: BottleExtracting {
    var isAvailable: Bool { false }
    func prewarm() {}
    func extract(from lines: [String]) async -> ExtractedFields? { nil }
}

nonisolated extension BottleExtracting {
    /// Runs the model on `lines` and merges what it found into `base`
    /// under the rules in `ExtractionMerger`, giving up after `timeout`
    /// (PRD: under 1.5 s after the person taps "Use This Label"). Returns
    /// `base` untouched when there is no model, no answer or no time.
    func enhance(
        _ base: LabelScanResult?,
        lines: [String],
        distilleryStore: DistilleryStore,
        expressionStore: ExpressionStore,
        timeout: Duration = .seconds(1.5)
    ) async -> LabelScanResult? {
        guard isAvailable, !lines.isEmpty else { return base }

        let fields: ExtractedFields? = await withTaskGroup(of: ExtractedFields?.self) { group in
            group.addTask { await self.extract(from: lines) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            // Whichever finishes first wins; a nil from the timer means
            // the model ran out of time.
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
        guard let fields else { return base }
        return ExtractionMerger.merge(
            base, with: fields, lines: lines,
            distilleryStore: distilleryStore, expressionStore: expressionStore
        )
    }
}

// MARK: - Validation and merge

/// Deterministic checks between a model's claims and what the app is
/// willing to believe. A language model can invent plausible-sounding
/// facts; nothing it says reaches a form unless it passes these.
///
/// Rules (PRD section 9):
/// - The heuristic parser's `confident` fields always win.
/// - The model may fill fields the parser left empty, and may break a tie
///   between the parser's own `guessed` alternates.
/// - Every model-filled field is marked `guessed`, so the confirmation UI
///   asks the person to check it.
/// - A claim must be *evidenced in the source text*, not just plausible.
///   The model is told to extract only what is printed; this enforces it.
nonisolated enum ExtractionMerger {
    static func merge(
        _ base: LabelScanResult?,
        with fields: ExtractedFields,
        lines: [String],
        distilleryStore: DistilleryStore,
        expressionStore: ExpressionStore
    ) -> LabelScanResult? {
        var result = base ?? LabelScanResult()
        var changed = false

        let joined = lines.joined(separator: " ")
        let normalizedText = " \(DistilleryStore.normalize(joined)) "

        // MARK: Distillery
        if let claimed = fields.distillery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !claimed.isEmpty,
           let match = distilleryStore.exactMatch(claimed) ?? distilleryStore.bestMatch(for: claimed) {
            switch result.distilleryProvenance {
            case .confident:
                break
            case .none:
                // Filling from nothing needs the name to actually be in
                // the text.
                if isEvidenced(distillery: match, in: normalizedText) {
                    result.distilleryName = match.name
                    result.region = match.region
                    result.distilleryProvenance = .guessed
                    changed = true
                }
            case .guessed:
                // Tie-break: the model picked one of the parser's own
                // runners-up. Promote it; the old pick becomes a runner-up.
                if match.name != result.distilleryName,
                   let promoted = result.alternateDistilleries.first(where: { $0.name == match.name }) {
                    var alternates = result.alternateDistilleries.filter { $0.name != promoted.name }
                    if let previous = distilleryStore.exactMatch(result.distilleryName) {
                        alternates.insert(previous, at: 0)
                    }
                    result.distilleryName = promoted.name
                    result.region = promoted.region
                    result.alternateDistilleries = alternates
                    changed = true
                }
            }
        }

        // MARK: Age
        if result.ageProvenance == .none,
           let age = fields.ageYears,
           WhiskyLabelParser.plausibleAge.contains(age),
           ageNumeralAppears(age, in: normalizedText) {
            result.age = age
            result.isNAS = false
            result.ageProvenance = .guessed
            changed = true
        }

        // MARK: ABV
        if result.abvProvenance == .none,
           let abv = fields.abvPercent,
           WhiskyLabelParser.plausibleABV.contains(abv),
           numberAppears(abv, in: joined) {
            result.abv = abv
            result.abvProvenance = .guessed
            changed = true
        }

        // MARK: Cask
        if (result.cask ?? "").isEmpty,
           let cask = fields.cask?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cask.isEmpty,
           isEvidenced(phrase: cask, in: normalizedText) {
            result.cask = cask
            changed = true
        }

        // MARK: Name
        // Built from the distillery, the printed expression and the age,
        // like the heuristic parser does. Only when the parser found no
        // name and the expression words are really in the text.
        if result.nameProvenance == .none,
           !result.distilleryName.isEmpty,
           let expression = fields.expression?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expression.isEmpty,
           isEvidenced(phrase: expression, in: normalizedText) {
            var parts = [result.distilleryName]
            // Don't repeat the distillery if the expression already starts with it.
            if !DistilleryStore.normalize(expression).hasPrefix(DistilleryStore.normalize(result.distilleryName)) {
                parts.append(expression)
            } else {
                parts = [expression]
            }
            if let age = result.age { parts.append(String(age)) }
            result.name = parts.joined(separator: " ")
            result.nameProvenance = .guessed
            changed = true
        }

        return changed ? result : base
    }

    // MARK: Evidence

    /// The distillery's name, or one of its aliases, appears as whole words.
    private static func isEvidenced(distillery: Distillery, in normalizedText: String) -> Bool {
        ([distillery.name] + distillery.aliases).contains { candidate in
            let needle = DistilleryStore.normalize(candidate)
            return !needle.isEmpty && normalizedText.contains(" \(needle) ")
        }
    }

    /// Every significant word of `phrase` appears in the text. Case,
    /// punctuation and word order are ignored.
    private static func isEvidenced(phrase: String, in normalizedText: String) -> Bool {
        let tokens = DistilleryStore.normalize(phrase).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { normalizedText.contains(" \($0) ") }
    }

    /// The age numeral leads some token of the (normalized) text. Labels
    /// print "16", "16YO" and "16Years", which normalize to "16", "16yo"
    /// and "16years"; "116" and "160" must not count.
    private static func ageNumeralAppears(_ age: Int, in normalizedText: String) -> Bool {
        let wanted = String(age)
        return normalizedText.split(separator: " ").contains { token in
            String(token.prefix { $0.isNumber }) == wanted
        }
    }

    /// The ABV number is printed somewhere in the source, in any of the
    /// ways labels write it: "43", "43.0", "46,3". Matches only whole
    /// numbers: "43" is not evidence inside "1943" or "43.5".
    private static func numberAppears(_ value: Double, in text: String) -> Bool {
        let oneDecimal = String(format: "%.1f", value)
        var variants = [oneDecimal, oneDecimal.replacingOccurrences(of: ".", with: ",")]
        if value == value.rounded() {
            variants.append(String(Int(value)))
        }
        return variants.contains { containsStandaloneNumber($0, in: text) }
    }

    private static func containsStandaloneNumber(_ number: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: number, range: searchStart..<text.endIndex) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let afterNext: Character? = {
                guard let after, after == "." || after == ",",
                      text.index(after: range.upperBound) < text.endIndex else { return nil }
                return text[text.index(after: range.upperBound)]
            }()
            let digitBefore = before?.isNumber ?? false
            let digitAfter = after?.isNumber ?? false
            let decimalContinues = afterNext?.isNumber ?? false
            if !digitBefore && !digitAfter && !decimalContinues { return true }
            searchStart = range.upperBound
        }
        return false
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var bottleExtractor: any BottleExtracting = OnDeviceIntelligence.makeExtractor()
}
