import Foundation

/// One known core-range bottling: a fixed, published (distillery, age, ABV)
/// combination. Deliberately excludes anything whose ABV varies by batch or
/// release (cask-strength single barrels, annual limited editions) — a wrong
/// number here would be worse than no number, since the app would present it
/// with the same false confidence that made the label-scan problem worth
/// fixing in the first place. See Resources/expressions.json for the data
/// and its sourcing note.
nonisolated struct Expression: Codable, Sendable, Equatable {
    /// Matches a `Distillery.name` in distilleries.json exactly.
    let distillery: String
    /// The expression's own name, e.g. "Double Cask", "Uigeadail",
    /// "Quarter Cask" — empty string for a plain age-stated core bottling
    /// with no further name ("Glenfiddich 12" has no expression name beyond
    /// its age).
    let name: String
    /// nil means NAS (no age statement).
    let age: Int?
    let abv: Double
}

/// Loads the bundled expression catalog and resolves OCR/lookup reads
/// against it. Used only as a *fallback fill and cross-check*, never to
/// silently overwrite a value the OCR or a barcode lookup actually read —
/// a real bottle may be a cask-strength or travel-retail variant this
/// catalog doesn't know about, and trusting a live read over a guessed
/// catalog match is the safer default.
nonisolated struct ExpressionStore: Sendable {
    enum LoadError: Error {
        case resourceMissing
    }

    let expressions: [Expression]
    private let byDistillery: [String: [Expression]]

    init(expressions: [Expression]) {
        self.expressions = expressions
        self.byDistillery = Dictionary(grouping: expressions) { DistilleryStore.normalize($0.distillery) }
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> ExpressionStore {
        guard let url = bundle.url(forResource: "expressions", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let expressions = try JSONDecoder().decode([Expression].self, from: data)
        return ExpressionStore(expressions: expressions)
    }

    /// Best match for a distillery, given whatever the OCR/lookup pass
    /// already resolved.
    ///
    /// A distillery's core range very often has several expressions at the
    /// *same* age (Macallan's 12 Year Old alone is Sherry Oak, Double Cask,
    /// and Triple Cask, at three different ABVs) — so an age match alone
    /// isn't enough to pick one. This prefers, in order: the age-matched
    /// expression whose own name is actually mentioned in the candidate
    /// text; the sole age match if there's only one; the plain (unnamed)
    /// age-stated bottling if the catalog has one; otherwise gives up
    /// rather than guessing between several equally-plausible named
    /// variants with no textual hint to prefer one. Falls back to pure
    /// expression-name token overlap when no age is available at all (e.g.
    /// a line containing "UIGEADAIL" or "QUARTER CASK").
    func match(distillery: String, age: Int?, candidateText: [String]) -> Expression? {
        guard let candidates = byDistillery[DistilleryStore.normalize(distillery)], !candidates.isEmpty else {
            return nil
        }
        let haystack = " \(DistilleryStore.normalize(candidateText.joined(separator: " "))) "

        if let age {
            let ageMatches = candidates.filter { $0.age == age }
            if !ageMatches.isEmpty {
                if let named = ageMatches.first(where: { expression in
                    guard !expression.name.isEmpty else { return false }
                    let needle = DistilleryStore.normalize(expression.name)
                    return haystack.contains(" \(needle) ")
                }) {
                    return named
                }
                if ageMatches.count == 1 { return ageMatches[0] }
                if let plain = ageMatches.first(where: { $0.name.isEmpty }) { return plain }
                return nil
            }
        }

        var best: (Expression, Int)?
        for expression in candidates where !expression.name.isEmpty {
            let needle = DistilleryStore.normalize(expression.name)
            guard !needle.isEmpty, haystack.contains(" \(needle) ") else { continue }
            if needle.count > (best?.1 ?? 0) { best = (expression, needle.count) }
        }
        return best?.0
    }

    /// The one NAS (no fixed age) expression for a distillery, if the
    /// catalog has exactly one and the candidate text doesn't clearly name a
    /// different, aged expression. Used only when OCR found no age at all.
    func soleNASExpression(distillery: String) -> Expression? {
        guard let candidates = byDistillery[DistilleryStore.normalize(distillery)] else { return nil }
        let nasCandidates = candidates.filter { $0.age == nil }
        return nasCandidates.count == 1 ? nasCandidates.first : nil
    }
}

nonisolated extension Expression {
    /// A display name combining distillery, expression name and age, in the
    /// order a bottle's own labeling would read — e.g. "Macallan Double
    /// Cask 12" or "Ardbeg Uigeadail".
    func displayName() -> String {
        var parts = [distillery]
        if !name.isEmpty { parts.append(name) }
        if let age { parts.append(String(age)) }
        return parts.joined(separator: " ")
    }
}
