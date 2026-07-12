import Testing
@testable import UisgeBeatha

struct CollectionSortTests {
    private func makeBottles() -> [Bottle] {
        [
            Bottle(name: "Talisker 10", distilleryName: "Talisker", region: "islands"),
            Bottle(name: "Ardbeg 10", distilleryName: "Ardbeg", region: "islay"),
            Bottle(name: "lagavulin 8", distilleryName: "Lagavulin", region: "islay"),
            Bottle(name: "Glenfarclas 12", distilleryName: "Glenfarclas", region: "speyside"),
            Bottle(name: "Clynelish 14", distilleryName: "Clynelish", region: "highland"),
        ]
    }

    @Test func sortByNameIsCaseInsensitive() {
        let sorted = CollectionSortKey.name.sorted(makeBottles())
        #expect(sorted.map(\.name) == [
            "Ardbeg 10", "Clynelish 14", "Glenfarclas 12", "lagavulin 8", "Talisker 10",
        ])
    }

    @Test func sortByDistilleryFallsBackToName() {
        let bottles = [
            Bottle(name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay"),
            Bottle(name: "Lagavulin 8", distilleryName: "Lagavulin", region: "islay"),
            Bottle(name: "Ardbeg 10", distilleryName: "Ardbeg", region: "islay"),
        ]
        let sorted = CollectionSortKey.distillery.sorted(bottles)
        #expect(sorted.map(\.name) == ["Ardbeg 10", "Lagavulin 16", "Lagavulin 8"])
    }

    @Test func sortByRegionUsesCatalogOrderNotAlphabetical() {
        let sorted = CollectionSortKey.region.sorted(makeBottles())
        // Catalog order: highland, lowland, islay, speyside, islands, campbeltown.
        #expect(sorted.map(\.region) == ["highland", "islay", "islay", "speyside", "islands"])
        // Within a region, names sort ascending.
        #expect(sorted[1].name == "Ardbeg 10")
        #expect(sorted[2].name == "lagavulin 8")
    }

    @Test func unknownRegionSortsLast() {
        let bottles = [
            Bottle(name: "Mystery", distilleryName: "X", region: "atlantis"),
            Bottle(name: "Springbank 10", distilleryName: "Springbank", region: "campbeltown"),
        ]
        let sorted = CollectionSortKey.region.sorted(bottles)
        #expect(sorted.map(\.name) == ["Springbank 10", "Mystery"])
    }

    @Test func statusCyclesInOrder() {
        #expect(BottleStatus.sealed.next == .open)
        #expect(BottleStatus.open.next == .finished)
        #expect(BottleStatus.finished.next == .sealed)
    }
}
