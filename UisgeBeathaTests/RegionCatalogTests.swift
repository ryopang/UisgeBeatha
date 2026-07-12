import Testing
@testable import UisgeBeatha

struct RegionCatalogTests {
    @Test func catalogShipsExactlyTheSixScotlandRegions() {
        let ids = RegionCatalog.regions.map(\.id)
        #expect(ids.count == 6)
        #expect(Set(ids) == ["highland", "lowland", "islay", "speyside", "islands", "campbeltown"])
        #expect(RegionCatalog.regions.allSatisfy { $0.country == "Scotland" })
    }

    @Test func displayNamesUseCorrectSpelling() {
        #expect(RegionCatalog.region(id: "campbeltown")?.displayName == "Campbeltown")
        #expect(RegionCatalog.region(id: "islay")?.displayName == "Islay")
    }

    @Test func lookupByIDRoundTrips() {
        for region in RegionCatalog.regions {
            #expect(RegionCatalog.region(id: region.id) == region)
        }
        #expect(RegionCatalog.region(id: "kentucky") == nil)
    }

    @Test func sortIndexPutsUnknownRegionsLast() {
        #expect(RegionCatalog.sortIndex(of: "highland") == 0)
        #expect(RegionCatalog.sortIndex(of: "kentucky") == RegionCatalog.regions.count)
    }
}
