import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 2: selection persistence and the search/filter/sort pipeline that
/// both the compact and split layouts read.
@MainActor
struct CollectionSelectionTests {
    private let lagavulin = Bottle(
        name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay",
        caskType: "Ex-bourbon", status: .open
    )
    private let glenfarclas = Bottle(
        name: "Glenfarclas 15", distilleryName: "Glenfarclas", region: "speyside",
        caskType: "Oloroso Sherry", status: .sealed
    )
    private let talisker = Bottle(
        name: "Talisker 10", distilleryName: "Talisker", region: "islands",
        caskType: nil, status: nil
    )

    private var all: [Bottle] { [lagavulin, glenfarclas, talisker] }

    // MARK: - Stored selection

    @Test func selectionRoundTripsThroughSceneStorage() {
        let stored = CollectionSelection.stored(lagavulin.id)
        #expect(CollectionSelection.id(fromStored: stored) == lagavulin.id)
    }

    @Test func emptyOrGarbageStorageMeansNoSelection() {
        #expect(CollectionSelection.id(fromStored: "") == nil)
        #expect(CollectionSelection.id(fromStored: "not-a-uuid") == nil)
        #expect(CollectionSelection.stored(nil) == "")
    }

    @Test func selectionResolvesToTheBottleOrNil() {
        #expect(CollectionSelection.bottle(for: glenfarclas.id, in: all) === glenfarclas)
        #expect(CollectionSelection.bottle(for: UUID(), in: all) == nil)
        #expect(CollectionSelection.bottle(for: nil, in: all) == nil)
    }

    @Test func aDeletedBottleNoLongerResolves() {
        let remaining = [lagavulin, talisker]
        #expect(CollectionSelection.bottle(for: glenfarclas.id, in: remaining) == nil)
    }

    // MARK: - Search

    @Test func emptyQueryMatchesEverything() {
        #expect(all.allSatisfy { CollectionSelection.matches($0, query: "") })
        #expect(all.allSatisfy { CollectionSelection.matches($0, query: "   ") })
    }

    @Test func searchMatchesNameAndDistillery() {
        #expect(CollectionSelection.matches(lagavulin, query: "lagav"))
        #expect(!CollectionSelection.matches(glenfarclas, query: "lagav"))
    }

    @Test func searchMatchesRegionCaskAndStatus() {
        #expect(CollectionSelection.matches(lagavulin, query: "islay"))
        #expect(CollectionSelection.matches(glenfarclas, query: "sherry"))
        #expect(CollectionSelection.matches(lagavulin, query: "open"))
        #expect(!CollectionSelection.matches(glenfarclas, query: "open"))
    }

    @Test func everyTokenMustMatchSomething() {
        #expect(CollectionSelection.matches(lagavulin, query: "islay open"))
        #expect(!CollectionSelection.matches(lagavulin, query: "islay sealed"))
        #expect(CollectionSelection.matches(glenfarclas, query: "speyside sherry"))
    }

    @Test func aBottleWithNoCaskOrStatusStillMatchesOnTheRest() {
        #expect(CollectionSelection.matches(talisker, query: "talisker islands"))
    }

    // MARK: - Pipeline

    @Test func regionFilterNarrowsTheList() {
        let result = CollectionSelection.visible(all, query: "", regionID: "islay", sortKey: .name)
        #expect(result.map(\.name) == ["Lagavulin 16"])
    }

    @Test func emptyRegionMeansAllRegions() {
        let result = CollectionSelection.visible(all, query: "", regionID: "", sortKey: .name)
        #expect(result.map(\.name) == ["Glenfarclas 15", "Lagavulin 16", "Talisker 10"])
    }

    @Test func searchAndRegionCombine() {
        let none = CollectionSelection.visible(all, query: "talisker", regionID: "islay", sortKey: .name)
        #expect(none.isEmpty)
        let one = CollectionSelection.visible(all, query: "talisker", regionID: "islands", sortKey: .name)
        #expect(one.map(\.name) == ["Talisker 10"])
    }

    @Test func sortKeyIsApplied() {
        let byRegion = CollectionSelection.visible(all, query: "", regionID: "", sortKey: .region)
        #expect(byRegion.map(\.region) == byRegion.map(\.region).sorted {
            RegionCatalog.sortIndex(of: $0) < RegionCatalog.sortIndex(of: $1)
        })
    }
}
