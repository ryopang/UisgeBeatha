import Foundation

/// Text cleanup shared by label-scan name construction: recognizing lines
/// that are boilerplate rather than product identity, and turning shouted
/// OCR caps into a name worth saving.
nonisolated enum LabelText {
    /// Normalized (see `DistilleryStore.normalize`) lines that carry no
    /// product identity — legal/description boilerplate that shows up
    /// on nearly every scotch label. Excluded from name construction and
    /// from the "longest line" fallback so the saved name is never
    /// "SINGLE MALT SCOTCH WHISKY".
    private static let boilerplatePhrases: Set<String> = [
        "single malt scotch whisky", "single grain scotch whisky",
        "blended scotch whisky", "blended malt scotch whisky", "scotch whisky",
        "product of scotland", "produce of scotland",
        "distilled and bottled in scotland", "distilled in scotland",
        "bottled in scotland", "matured in oak casks", "matured in oak",
        "non chill filtered", "un chill filtered", "unchillfiltered",
        "natural colour", "natural color", "no added colour", "no added color",
        "please enjoy responsibly", "please drink responsibly",
        "government warning", "keep out of reach of children",
    ]

    /// True for a boilerplate line, a volume statement ("700ml", "70cl"), or
    /// a line that's essentially just punctuation/whitespace.
    static func isBoilerplate(_ line: String) -> Bool {
        let normalized = DistilleryStore.normalize(line)
        guard !normalized.isEmpty else { return true }
        if boilerplatePhrases.contains(normalized) { return true }
        if isVolumeStatement(normalized) { return true }
        return false
    }

    /// "700ml", "70 cl", "750 ml", "1 l" — always volume, never age or ABV.
    static func isVolumeStatement(_ normalizedLine: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\d{1,4})\s*(ml|cl|l)$"#, options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(normalizedLine.startIndex..., in: normalizedLine)
        return regex.firstMatch(in: normalizedLine, range: range) != nil
    }

    /// A four-digit year (a founding date, a vintage) — never an age
    /// statement, and worth excluding from the guarded standalone-numeral
    /// age heuristic.
    static func isFourDigitYear(_ trimmedLine: String) -> Bool {
        guard trimmedLine.count == 4, let value = Int(trimmedLine) else { return false }
        return (1700...2100).contains(value)
    }

    /// "NO AGE STATEMENT" / a standalone "NAS" token — distinguishing "no
    /// age was printed" from "no age was found", since the two should read
    /// differently to a person reviewing the scan.
    static func mentionsNAS(_ lines: [String]) -> Bool {
        for line in lines {
            let normalized = DistilleryStore.normalize(line)
            if normalized == "no age statement" || normalized == "nas" { return true }
            let tokens = normalized.split(separator: " ")
            if tokens.contains("nas") { return true }
        }
        return false
    }

    /// De-shouts ALL-CAPS OCR text to a readable product name, preserving
    /// any token that matches a known distillery name/alias casing exactly
    /// (so "anCnoc", "Nc'nean", "GlenDronach", "BenRiach" keep their real
    /// casing instead of becoming "Ancnoc" or "Nc'Nean").
    static func titleCased(_ text: String, knownCasing: [String: String]) -> String {
        let lowercaseConnectors: Set<String> = ["of", "the", "and", "in", "on", "for", "&"]
        let words = text.split(separator: " ").map(String.init)
        var result: [String] = []
        for (index, word) in words.enumerated() {
            let key = DistilleryStore.normalize(word)
            if let known = knownCasing[key] {
                result.append(known)
                continue
            }
            if word.contains(where: \.isNumber) {
                // "12", "18", "10YO" — leave numerals/units untouched.
                result.append(word)
                continue
            }
            if index > 0, lowercaseConnectors.contains(word.lowercased()) {
                result.append(word.lowercased())
                continue
            }
            result.append(capitalizedWord(word))
        }
        return result.joined(separator: " ")
    }

    /// Capitalizes the first letter and lowercases the rest, preserving
    /// internal apostrophes/hyphens as word separators for casing purposes
    /// ("glen-dronach" stays a single visual word, but "d'or" → "D'or").
    private static func capitalizedWord(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst().lowercased()
    }

    /// Builds the known-casing lookup `titleCased` needs: every distillery
    /// name and alias, keyed by its normalized form, from the seed data
    /// already loaded for matching.
    static func knownCasing(from distilleryStore: DistilleryStore) -> [String: String] {
        var casing: [String: String] = [:]
        for distillery in distilleryStore.distilleries {
            for word in ([distillery.name] + distillery.aliases).flatMap({ $0.split(separator: " ") }) {
                casing[DistilleryStore.normalize(String(word))] = String(word)
            }
        }
        return casing
    }
}
