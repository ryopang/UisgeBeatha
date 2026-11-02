import Foundation
import SwiftUI

/// The words the flavour wheel knows. The wheel, the tappable segments and
/// the model's "Suggest words" all draw from this one list, so a suggestion
/// is always a word the person can also find on the wheel.
nonisolated struct WheelCategory: Sendable, Equatable {
    let name: String
    let descriptors: [String]
}

nonisolated enum WheelVocabulary {
    /// The eight categories in wheel order, clockwise from 12 o'clock.
    static let categories: [WheelCategory] = [
        WheelCategory(name: Strings.Wheel.smoky, descriptors: Strings.Wheel.smokyDescriptors),
        WheelCategory(name: Strings.Wheel.fruity, descriptors: Strings.Wheel.fruityDescriptors),
        WheelCategory(name: Strings.Wheel.floral, descriptors: Strings.Wheel.floralDescriptors),
        WheelCategory(name: Strings.Wheel.malty, descriptors: Strings.Wheel.maltyDescriptors),
        WheelCategory(name: Strings.Wheel.woody, descriptors: Strings.Wheel.woodyDescriptors),
        WheelCategory(name: Strings.Wheel.spicy, descriptors: Strings.Wheel.spicyDescriptors),
        WheelCategory(name: Strings.Wheel.sweet, descriptors: Strings.Wheel.sweetDescriptors),
        WheelCategory(name: Strings.Wheel.maritime, descriptors: Strings.Wheel.maritimeDescriptors),
    ]

    /// Every outer-ring descriptor, in wheel order.
    static let descriptors: [String] = categories.flatMap(\.descriptors)

    /// Keeps only what's really on the wheel (case-insensitive), in the
    /// wheel's own spelling, without repeats, without words the note
    /// already uses, and at most `limit` of them. A model answer is never
    /// shown to the person unfiltered.
    static func validated(_ candidates: [String], excludingWordsIn text: String = "", limit: Int = 6) -> [String] {
        let existing = text.lowercased()
        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates {
            let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let match = descriptors.first(where: { $0.lowercased() == key }),
                  !seen.contains(key),
                  !existing.contains(key) else { continue }
            seen.insert(key)
            result.append(match)
            if result.count == limit { break }
        }
        return result
    }
}

/// Suggests wheel descriptors for what a person has typed so far.
/// Suggestions only: nothing is ever inserted without a tap.
nonisolated protocol TastingWordSuggesting: Sendable {
    var isAvailable: Bool { get }
    /// Wheel descriptors that fit `text`, already validated against
    /// `WheelVocabulary`. Empty when unavailable or on any error.
    func suggestions(for text: String) async -> [String]
}

nonisolated struct NoOpTastingWordSuggester: TastingWordSuggesting {
    var isAvailable: Bool { false }
    func suggestions(for text: String) async -> [String] { [] }
}

/// Inserting a tapped word into a note field.
nonisolated enum TastingText {
    /// Appends `word` to `text`, separated by a comma when there is
    /// already something there. Lowercase, since it joins running prose
    /// ("Peat, bonfire") rather than starting a sentence.
    static func inserting(_ word: String, into text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = word.lowercased()
        guard !trimmed.isEmpty else { return word }
        // Already there: don't double up.
        if trimmed.lowercased().contains(lowered) { return text }
        if let last = trimmed.last, ",;.".contains(last) {
            return trimmed + " " + lowered
        }
        return trimmed + ", " + lowered
    }
}

extension EnvironmentValues {
    @Entry var tastingSuggester: any TastingWordSuggesting = OnDeviceIntelligence.makeSuggester()
}
