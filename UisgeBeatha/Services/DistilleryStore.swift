import Foundation

/// Loads the bundled distillery seed data and matches free-form text
/// (typed names, scanned product titles) against it.
nonisolated struct DistilleryStore: Sendable {
    enum LoadError: Error {
        case resourceMissing
    }

    let distilleries: [Distillery]

    /// Every distillery's normalized name plus its "eligible" aliases —
    /// computed once at load rather than on every match call. A label-scan
    /// pass calls `bestMatch` once per OCR line (and, after the L1 rewrite,
    /// once per line-window too), so this turns an O(lines × names ×
    /// aliases) re-normalization into a single pass at startup.
    ///
    /// "Eligible" excludes aliases that are short or purely numeric
    /// ("1770" → Glasgow Distillery, "Spey" → Speyside Distillery) from
    /// substring and token-overlap matching — a founding year or a stray
    /// mention of the River Spey on an unrelated label is a real
    /// false-positive risk that a distillery's own curated primary name
    /// doesn't carry. Those short aliases still work for an *exact* typed
    /// match (autocomplete), just not as free-text substring/fuzzy bait.
    nonisolated private struct NormalizedEntry {
        let distillery: Distillery
        let normalizedName: String
        let eligibleAliasCandidates: [String]
    }
    private let normalizedEntries: [NormalizedEntry]
    private let byNormalizedExactKey: [String: Distillery]

    init(distilleries: [Distillery]) {
        self.distilleries = distilleries
        self.normalizedEntries = distilleries.map { distillery in
            NormalizedEntry(
                distillery: distillery,
                normalizedName: Self.normalize(distillery.name),
                eligibleAliasCandidates: distillery.aliases.filter(Self.isEligibleAlias)
            )
        }
        var exactKeys: [String: Distillery] = [:]
        for distillery in distilleries {
            exactKeys[Self.normalize(distillery.name)] = distillery
            for alias in distillery.aliases {
                exactKeys[Self.normalize(alias)] = distillery
            }
        }
        self.byNormalizedExactKey = exactKeys
    }

    /// A short (<5 normalized chars) or purely numeric alias is excluded
    /// from substring/fuzzy matching — see `normalizedEntries` above.
    private static func isEligibleAlias(_ alias: String) -> Bool {
        let normalized = normalize(alias)
        return normalized.count >= 5 && !normalized.allSatisfy(\.isNumber)
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

    /// Case-insensitive equality against a distillery name or alias. Short
    /// and numeric aliases are still eligible here — an exact typed match
    /// (autocomplete) carries none of substring/fuzzy matching's
    /// false-positive risk.
    func exactMatch(_ name: String) -> Distillery? {
        let needle = Self.normalize(name)
        guard !needle.isEmpty else { return nil }
        return byNormalizedExactKey[needle]
    }

    /// Case-insensitive substring match: the distillery name (or an
    /// eligible alias) appears somewhere inside `text`. The longest
    /// matching name wins so "Glen Grant" beats a shorter accidental hit.
    func containsMatch(in text: String) -> Distillery? {
        let haystack = " \(Self.normalize(text)) "
        guard haystack.count > 2 else { return nil }

        var best: (distillery: Distillery, length: Int)?
        for entry in normalizedEntries {
            for needle in [entry.normalizedName] + entry.eligibleAliasCandidates.map(Self.normalize) {
                // Word-boundary match to avoid "Arran" hitting inside another word.
                guard !needle.isEmpty, haystack.contains(" \(needle) ") else { continue }
                if needle.count > (best?.length ?? 0) {
                    best = (entry.distillery, needle.count)
                }
            }
        }
        return best?.distillery
    }

    /// Simple fuzzy match for scanned product names like
    /// "LAGAVULIN 16YO ISLAY SINGLE MALT": token overlap first, then a
    /// Levenshtein pass to absorb small misspellings. Eligible names/aliases
    /// only — see `isEligibleAlias`.
    func fuzzyMatch(_ text: String) -> Distillery? {
        let textTokens = Self.significantTokens(in: text)
        guard !textTokens.isEmpty else { return nil }

        // Pass 1: every token of the distillery name appears in the text.
        var best: (distillery: Distillery, score: Int)?
        for entry in normalizedEntries {
            for candidate in [entry.distillery.name] + entry.eligibleAliasCandidates {
                let nameTokens = Self.significantTokens(in: candidate)
                guard !nameTokens.isEmpty, nameTokens.isSubset(of: textTokens) else { continue }
                let score = nameTokens.reduce(0) { $0 + $1.count }
                if score > (best?.score ?? 0) {
                    best = (entry.distillery, score)
                }
            }
        }
        if let best { return best.distillery }

        // Pass 2: near-miss single tokens (e.g. "LAGAVULN") within edit distance 2.
        var nearest: (distillery: Distillery, distance: Int, length: Int)?
        for entry in normalizedEntries {
            for candidate in [entry.distillery.name] + entry.eligibleAliasCandidates {
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
                        nearest = (entry.distillery, distance, nameToken.count)
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

    /// Match tier, most to least certain — used by the label-scan global
    /// scorer (LabelParser) to pick the best match across every OCR line
    /// rather than trusting whichever line happened to come first.
    enum MatchTier: Int, Comparable, Sendable {
        case exact = 0
        case contains = 1
        case fuzzySubset = 2
        case fuzzyLevenshtein = 3

        static func < (lhs: MatchTier, rhs: MatchTier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// `bestMatch`, but reporting which tier answered and how long the
    /// matched name/alias was — the scoring signal a global (multi-line)
    /// match needs that a single boolean match/no-match can't provide.
    func tieredMatch(for text: String) -> (distillery: Distillery, tier: MatchTier, matchedLength: Int)? {
        if let hit = exactMatch(text) {
            return (hit, .exact, Self.normalize(text).count)
        }
        let haystack = " \(Self.normalize(text)) "
        if haystack.count > 2 {
            var best: (Distillery, Int)?
            for entry in normalizedEntries {
                for needle in [entry.normalizedName] + entry.eligibleAliasCandidates.map(Self.normalize) {
                    guard !needle.isEmpty, haystack.contains(" \(needle) ") else { continue }
                    if needle.count > (best?.1 ?? 0) { best = (entry.distillery, needle.count) }
                }
            }
            if let best { return (best.0, .contains, best.1) }
        }
        let textTokens = Self.significantTokens(in: text)
        if !textTokens.isEmpty {
            var bestSubset: (Distillery, Int)?
            for entry in normalizedEntries {
                for candidate in [entry.distillery.name] + entry.eligibleAliasCandidates {
                    let nameTokens = Self.significantTokens(in: candidate)
                    guard !nameTokens.isEmpty, nameTokens.isSubset(of: textTokens) else { continue }
                    let length = nameTokens.reduce(0) { $0 + $1.count }
                    if length > (bestSubset?.1 ?? 0) { bestSubset = (entry.distillery, length) }
                }
            }
            if let bestSubset { return (bestSubset.0, .fuzzySubset, bestSubset.1) }
        }
        if let fuzzy = fuzzyMatch(text) {
            return (fuzzy, .fuzzyLevenshtein, Self.normalize(fuzzy.name).count)
        }
        return nil
    }

    // MARK: - Text helpers

    /// Words too generic to identify a distillery on their own.
    nonisolated private static let stopWords: Set<String> = [
        "the", "distillery", "distillers", "single", "malt", "malts", "scotch",
        "whisky", "whiskey", "aged", "years", "year", "yo", "old", "cask",
        "strength", "reserve", "edition", "isle", "of", "islay", "speyside",
        "highland", "lowland", "islands", "campbeltown", "scotland",
    ]

    /// Lowercased, diacritics folded, punctuation collapsed to spaces.
    /// `nonisolated` (pure, no actor state) so text-cleanup helpers like
    /// `LabelText` — which run off the main actor alongside OCR — can call
    /// it without an actor hop.
    nonisolated static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Normalized alphabetic tokens with stop words and numbers removed.
    nonisolated static func significantTokens(in text: String) -> Set<String> {
        Set(
            normalize(text)
                .split(separator: " ")
                .map(String.init)
                .filter { !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
        )
    }

    /// Classic dynamic-programming edit distance.
    nonisolated static func levenshtein(_ a: String, _ b: String) -> Int {
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
