import CoreGraphics
import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 4: tappable wheel geometry, the shared vocabulary, and what a
/// model's suggestions are allowed to be.
struct TastingWheelTests {
    // MARK: - Vocabulary

    @Test func vocabularyIsEightCategoriesOfThree() {
        #expect(WheelVocabulary.categories.count == 8)
        #expect(WheelVocabulary.categories.allSatisfy { $0.descriptors.count == 3 })
        #expect(WheelVocabulary.descriptors.count == 24)
        #expect(Set(WheelVocabulary.descriptors).count == 24, "No descriptor appears twice")
    }

    @Test func validatedKeepsOnlyWheelWordsInWheelSpelling() {
        let result = WheelVocabulary.validated(["peat", "BONFIRE", "unicorn", "dried fruit", "Peat"])
        #expect(result == ["Peat", "Bonfire", "Dried Fruit"])
    }

    @Test func validatedSkipsWordsTheNoteAlreadyUses() {
        let result = WheelVocabulary.validated(["Peat", "Oak", "Honey"], excludingWordsIn: "Smoky peat and honey")
        #expect(result == ["Oak"])
    }

    @Test func validatedRespectsTheLimit() {
        let result = WheelVocabulary.validated(WheelVocabulary.descriptors, limit: 4)
        #expect(result.count == 4)
    }

    @Test func validatedHandlesEmptyInput() {
        #expect(WheelVocabulary.validated([]).isEmpty)
        #expect(WheelVocabulary.validated(["", "  "]).isEmpty)
    }

    // MARK: - Geometry

    private let size = CGSize(width: 400, height: 400)
    private var center: CGPoint { CGPoint(x: 200, y: 200) }
    private var outerRadius: CGFloat { 200 - WheelGeometry.margin }

    /// A point at `degrees` clockwise from 12 o'clock, `fraction` of the way
    /// from the center to the outer edge.
    private func point(degrees: CGFloat, fraction: CGFloat) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        let radius = outerRadius * fraction
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    @Test func outerRingJustPastTwelveIsTheFirstDescriptor() {
        let first = WheelVocabulary.categories[0]
        #expect(WheelGeometry.word(at: point(degrees: 3, fraction: 0.85), in: size) == first.descriptors[0])
    }

    @Test func outerRingWalksThroughEachCategorysDescriptors() {
        let smoky = WheelVocabulary.categories[0].descriptors
        #expect(WheelGeometry.word(at: point(degrees: 7, fraction: 0.85), in: size) == smoky[0])
        #expect(WheelGeometry.word(at: point(degrees: 22, fraction: 0.85), in: size) == smoky[1])
        #expect(WheelGeometry.word(at: point(degrees: 37, fraction: 0.85), in: size) == smoky[2])
    }

    @Test func eachCategoryOwnsItsFortyFiveDegrees() {
        for (index, category) in WheelVocabulary.categories.enumerated() {
            let middle = CGFloat(index) * 45 + 22.5
            #expect(WheelGeometry.word(at: point(degrees: middle, fraction: 0.85), in: size) == category.descriptors[1])
            #expect(WheelGeometry.word(at: point(degrees: middle, fraction: 0.45), in: size) == category.name)
        }
    }

    @Test func theHubAndTheOutsideAreNotWords() {
        #expect(WheelGeometry.word(at: center, in: size) == nil)
        #expect(WheelGeometry.word(at: point(degrees: 90, fraction: 0.1), in: size) == nil)
        #expect(WheelGeometry.word(at: CGPoint(x: 0, y: 0), in: size) == nil)
        #expect(WheelGeometry.word(at: point(degrees: 90, fraction: 1.2), in: size) == nil)
    }

    @Test func geometryFollowsTheSizeNotAFixedScale() {
        let small = CGSize(width: 200, height: 200)
        let smallCenter = CGPoint(x: 100, y: 100)
        let radius = (100 - WheelGeometry.margin) * 0.85
        let tap = CGPoint(x: smallCenter.x + radius * cos(-87 * .pi / 180),
                          y: smallCenter.y + radius * sin(-87 * .pi / 180))
        #expect(WheelGeometry.word(at: tap, in: small) == WheelVocabulary.categories[0].descriptors[0])
    }

    // MARK: - Inserting words

    @Test func insertingIntoAnEmptyFieldUsesTheWordAsIs() {
        #expect(TastingText.inserting("Peat", into: "") == "Peat")
        #expect(TastingText.inserting("Peat", into: "   ") == "Peat")
    }

    @Test func insertingAppendsWithACommaInLowercase() {
        #expect(TastingText.inserting("Honey", into: "Peat smoke") == "Peat smoke, honey")
    }

    @Test func insertingAfterPunctuationDoesNotDoubleIt() {
        #expect(TastingText.inserting("Honey", into: "Peat smoke,") == "Peat smoke, honey")
        #expect(TastingText.inserting("Honey", into: "Peat smoke.") == "Peat smoke. honey")
    }

    @Test func insertingAWordAlreadyThereChangesNothing() {
        #expect(TastingText.inserting("Peat", into: "Lots of peat") == "Lots of peat")
    }
}
