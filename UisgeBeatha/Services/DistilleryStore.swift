import Foundation

/// Loads the bundled distillery seed data and matches free-form text
/// (typed names, scanned product titles) against it.
struct DistilleryStore: Sendable {
    enum LoadError: Error {
        case resourceMissing
    }

    let distilleries: [Distillery]

    init(distilleries: [Distillery]) {
        self.distilleries = distilleries
    }

    /// Loads Resources/distilleries.json from the given bundle.
    static func loadBundled(from bundle: Bundle = .main) throws -> DistilleryStore {
        guard let url = bundle.url(forResource: "distilleries", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let distilleries = try JSONDecoder().decode([Distillery].self, from: data)
        return DistilleryStore(distilleries: distilleries)
    }

    // MARK: - Matching

    /// Case-insensitive equality against a distillery name or alias.
    func exactMatch(_ name: String) -> Distillery? {
        let needle = Self.normalize(name)
        guard !needle.isEmpty else { return nil }
        return distilleries.first { distillery in
            Self.normalize(distillery.name) == needle
                || distillery.aliases.contains { Self.normalize($0) == needle }
        }
    }

    /// Case-insensitive substring match: the distillery name (or an alias)
    /// appears somewhere inside `text`. The longest matching name wins so
    /// "Glen Grant" beats a shorter accidental hit.
    func containsMatch(in text: String) -> Distillery? {
        let haystack = " \(Self.normalize(text)) "
        guard haystack.count > 2 else { return nil }

        var best: (distillery: Distillery, length: Int)?
        for distillery in distilleries {
            for candidate in [distillery.name] + distillery.aliases {
                let needle = Self.normalize(candidate)
                // Word-boundary match to avoid "Arran" hitting inside another word.
                guard !needle.isEmpty, haystack.contains(" \(needle) ") else { continue }
                if needle.count > (best?.length ?? 0) {
                    best = (distillery, needle.count)
                }
            }
        }
        return best?.distillery
    }

    /// Simple fuzzy match for scanned product names like
    /// "LAGAVULIN 16YO ISLAY SINGLE MALT": token overlap first, then a
    /// Levenshtein pass to absorb small misspellings.
    func fuzzyMatch(_ text: String) -> Distillery? {
        let textTokens = Self.significantTokens(in: text)
        guard !textTokens.isEmpty else { return nil }

        // Pass 1: every token of the distillery name appears in the text.
        var best: (distillery: Distillery, score: Int)?
        for distillery in distilleries {
            for candidate in [distillery.name] + distillery.aliases {
                let nameTokens = Self.significantTokens(in: candidate)
                guard !nameTokens.isEmpty, nameTokens.isSubset(of: textTokens) else { continue }
                let score = nameTokens.reduce(0) { $0 + $1.count }
                if score > (best?.score ?? 0) {
                    best = (distillery, score)
                }
            }
        }
        if let best { return best.distillery }

        // Pass 2: near-miss single tokens (e.g. "LAGAVULN") within edit distance 2.
        var nearest: (distillery: Distillery, distance: Int, length: Int)?
        for distillery in distilleries {
            for candidate in [distillery.name] + distillery.aliases {
                let nameTokens = Self.significantTokens(in: candidate)
                guard nameTokens.count == 1, let nameToken = nameTokens.first,
                      nameToken.count >= 5 else { continue }
                for token in textTokens where abs(token.count - nameToken.count) <= 2 {
                    let distance = Self.levenshtein(token, nameToken)
                    guard distance <= 2 else { continue }
                    let isBetter = nearest.map {
                        distance < $0.distance
                            || (distance == $0.distance && nameToken.count > $0.length)
                    } ?? true
                    if isBetter {
                        nearest = (distillery, distance, nameToken.count)
                    }
                }
            }
        }
        return nearest?.distillery
    }

    /// The cascade the rest of the app uses: exact, then contains, then fuzzy.
    func bestMatch(for text: String) -> Distillery? {
        exactMatch(text) ?? containsMatch(in: text) ?? fuzzyMatch(text)
    }

    // MARK: - Text helpers

    /// Words too generic to identify a distillery on their own.
    private static let stopWords: Set<String> = [
        "the", "distillery", "distillers", "single", "malt", "malts", "scotch",
        "whisky", "whiskey", "aged", "years", "year", "yo", "old", "cask",
        "strength", "reserve", "edition", "isle", "of", "islay", "speyside",
        "highland", "lowland", "islands", "campbeltown", "scotland",
    ]

    /// Lowercased, diacritics folded, punctuation collapsed to spaces.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Normalized alphabetic tokens with stop words and numbers removed.
    static func significantTokens(in text: String) -> Set<String> {
        Set(
            normalize(text)
                .split(separator: " ")
                .map(String.init)
                .filter { !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
        )
    }

    /// Classic dynamic-programming edit distance.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for (i, aChar) in aChars.enumerated() {
            current[0] = i + 1
            for (j, bChar) in bChars.enumerated() {
                let substitution = previous[j] + (aChar == bChar ? 0 : 1)
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }
}
