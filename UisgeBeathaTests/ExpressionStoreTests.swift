import Foundation
import Testing
@testable import UisgeBeatha

/// Expression-catalog loading and the disambiguation logic that picks
/// among same-age expressions from a distillery's core range.
struct ExpressionStoreTests {
    let store: ExpressionStore

    init() throws {
        store = try ExpressionStore.loadBundled()
    }

    @Test func loadsMoreThanOneHundredExpressions() {
        #expect(store.expressions.count > 100)
    }

    @Test func everyExpressionDistilleryMatchesSeedData() throws {
        let distilleryStore = try DistilleryStore.loadBundled()
        for expression in store.expressions {
            #expect(
                distilleryStore.exactMatch(expression.distillery) != nil,
                "\(expression.distillery) is not in distilleries.json"
            )
        }
    }

    /// Macallan has three different expressions at age 12 (Sherry Oak,
    /// Double Cask, Triple Cask) — an age match alone can't disambiguate,
    /// and picking the wrong one would put a wrong ABV in front of the
    /// person with full confidence. This was a real regression caught by
    /// LabelOCRTests.findsAgeSplitAcrossTwoLines.
    @Test func disambiguatesSameAgeExpressionsUsingCandidateText() {
        let doubleCask = store.match(distillery: "Macallan", age: 12, candidateText: ["THE MACALLAN", "DOUBLE CASK"])
        #expect(doubleCask?.name == "Double Cask")
        #expect(doubleCask?.abv == 40.0)

        let sherryOak = store.match(distillery: "Macallan", age: 12, candidateText: ["THE MACALLAN", "SHERRY OAK"])
        #expect(sherryOak?.name == "Sherry Oak")
        #expect(sherryOak?.abv == 43.0)
    }

    /// No text hint among several same-age named variants: refuse to guess
    /// rather than silently picking one and presenting it as read.
    @Test func returnsNilWhenSeveralSameAgeExpressionsHaveNoTextHint() {
        let result = store.match(distillery: "Macallan", age: 12, candidateText: ["THE MACALLAN", "12", "YEARS OLD"])
        #expect(result == nil)
    }

    @Test func fallsBackToPlainAgeStatedBottlingWhenUnambiguous() {
        // Talisker's only age-10 entry is the plain core bottling.
        let result = store.match(distillery: "Talisker", age: 10, candidateText: ["TALISKER", "10"])
        #expect(result?.name == "")
        #expect(result?.abv == 45.8)
    }

    @Test func matchesByNameWhenNoAgeIsAvailable() {
        let result = store.match(distillery: "Ardbeg", age: nil, candidateText: ["ARDBEG", "UIGEADAIL"])
        #expect(result?.name == "Uigeadail")
        #expect(result?.abv == 54.2)
    }

    @Test func soleNASExpressionOnlyReturnsWhenExactlyOneExists() {
        // Ardbeg has several NAS expressions (Uigeadail, Corryvreckan) —
        // ambiguous, so no sole answer.
        #expect(store.soleNASExpression(distillery: "Ardbeg") == nil)
        // Ardmore's "Legacy" is its only catalog entry, and it's NAS.
        #expect(store.soleNASExpression(distillery: "Ardmore")?.name == "Legacy")
    }

    @Test func returnsNilForAnUnknownDistillery() {
        #expect(store.match(distillery: "Not A Real Distillery", age: 12, candidateText: []) == nil)
    }

    @Test func displayNameCombinesDistilleryExpressionAndAge() {
        let expression = Expression(distillery: "Ardbeg", name: "Uigeadail", age: nil, abv: 54.2)
        #expect(expression.displayName() == "Ardbeg Uigeadail")

        let plain = Expression(distillery: "Lagavulin", name: "", age: 16, abv: 43.0)
        #expect(plain.displayName() == "Lagavulin 16")
    }
}
