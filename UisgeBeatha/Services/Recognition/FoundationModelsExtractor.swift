import Foundation

/// The one place the app talks to Apple's on-device language model.
///
/// Everything else depends on `BottleExtracting` and `TastingWordSuggesting`,
/// both of which have do-nothing implementations, so the app behaves
/// identically on hardware without Apple Intelligence. If this file ever
/// stops compiling against a new SDK, deleting it and returning the no-op
/// types from `OnDeviceIntelligence` below restores a fully working app.
///
/// Scope (PRD section 3): the on-device system model only. No cloud
/// provider, no API key, nothing leaves the phone.
nonisolated enum OnDeviceIntelligence {
    static func makeExtractor() -> any BottleExtracting {
        #if canImport(FoundationModels)
        if ProcessInfo.processInfo.arguments.contains("-disableOnDeviceModel") {
            return NoOpBottleExtractor()
        }
        return FoundationModelsAssistant()
        #else
        return NoOpBottleExtractor()
        #endif
    }

    static func makeSuggester() -> any TastingWordSuggesting {
        #if canImport(FoundationModels)
        if ProcessInfo.processInfo.arguments.contains("-disableOnDeviceModel") {
            return NoOpTastingWordSuggester()
        }
        return FoundationModelsAssistant()
        #else
        return NoOpTastingWordSuggester()
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// The model's structured answer for a label. Every field is optional:
/// "nil when unsure" is the instruction, and `ExtractionMerger` checks
/// whatever does come back against the source text before using it.
@Generable
nonisolated struct GeneratedBottleFields {
    @Guide(description: "Distillery name exactly as printed, or nil")
    var distillery: String?

    @Guide(description: "Expression name without the distillery or the age, for example 'Double Cask', or nil")
    var expression: String?

    @Guide(description: "Age statement in years, only if printed, or nil")
    var ageYears: Int?

    @Guide(description: "Alcohol by volume as a percentage, only if printed, or nil")
    var abvPercent: Double?

    @Guide(description: "Cask type or finish, only if printed, or nil")
    var cask: String?

    @Guide(description: "true only if the text itself says Scotch or Scotland, otherwise nil")
    var saysScotch: Bool?
}

@Generable
nonisolated struct GeneratedWheelWords {
    @Guide(description: "Up to six words chosen only from the allowed list")
    var words: [String]
}

nonisolated struct FoundationModelsAssistant: BottleExtracting, TastingWordSuggesting {
    /// Characters of OCR text handed to the model. The context window is
    /// small and a label never needs more.
    private static let maxInputCharacters = 1500

    private static let extractionInstructions = """
        You read the text printed on a bottle of Scotch whisky, or a retailer's listing for one. \
        Extract only what is printed in the text. Never use general knowledge about whisky to \
        fill anything in. If a field is not clearly printed, leave it nil.
        """

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: Self.extractionInstructions).prewarm()
    }

    func extract(from lines: [String]) async -> ExtractedFields? {
        guard isAvailable, !lines.isEmpty else { return nil }
        // A fresh session per call: a session keeps its transcript, and an
        // earlier bottle's label must never colour the next one.
        let session = LanguageModelSession(instructions: Self.extractionInstructions)
        let prompt = "Text, one line per row:\n" + String(lines.joined(separator: "\n").prefix(Self.maxInputCharacters))
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedBottleFields.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let generated = response.content
            return ExtractedFields(
                distillery: generated.distillery,
                expression: generated.expression,
                ageYears: generated.ageYears,
                abvPercent: generated.abvPercent,
                cask: generated.cask,
                saysScotch: generated.saysScotch
            )
        } catch {
            // Guardrails, context overflow, cancellation: all just mean
            // "no help from the model this time".
            return nil
        }
    }

    func suggestions(for text: String) async -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, !trimmed.isEmpty else { return [] }
        let allowed = WheelVocabulary.descriptors.joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            You help someone find words for their whisky tasting notes. Choose words only from \
            this list: \(allowed). Pick the ones that fit what they have written, and words that \
            sit alongside them. Never use a word that is not on the list.
            """)
        do {
            let response = try await session.respond(
                to: "Tasting notes so far:\n" + String(trimmed.prefix(Self.maxInputCharacters)),
                generating: GeneratedWheelWords.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return WheelVocabulary.validated(response.content.words, excludingWordsIn: trimmed)
        } catch {
            return []
        }
    }
}
#endif
