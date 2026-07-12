import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 1 acceptance: seed data loading and name matching.
struct DistilleryStoreTests {
    let store: DistilleryStore

    init() throws {
        store = try DistilleryStore.loadBundled()
    }

    // MARK: - Seed loading

    @Test func seedDataHasMoreThan120Distilleries() {
        #expect(store.distilleries.count > 120)
    }

    @Test func allSixRegionsArePresentInSeedData() {
        let seededRegions = Set(store.distilleries.map(\.region))
        let catalogRegions = Set(RegionCatalog.regions.map(\.id))
        #expect(seededRegions == catalogRegions)
    }

    @Test func everySeedRegionExistsInCatalog() {
        for distillery in store.distilleries {
            #expect(
                RegionCatalog.region(id: distillery.region) != nil,
                "\(distillery.name) has unknown region \(distillery.region)"
            )
        }
    }

    @Test(arguments: [
        ("Lagavulin", "islay"),
        ("Glenfarclas", "speyside"),
        ("Springbank", "campbeltown"),
        ("Talisker", "islands"),
    ])
    func seedSpotChecks(name: String, expectedRegion: String) throws {
        let distillery = try #require(store.exactMatch(name), "\(name) missing from seed data")
        #expect(distillery.region == expectedRegion)
    }

    @Test func prdListedIslandsDistilleriesAreMarkedIslands() throws {
        let islandsNames = [
            "Talisker", "Highland Park", "Scapa", "Jura", "Tobermory",
            "Arran", "Raasay", "Abhainn Dearg", "Torabhaig", "Lagg",
        ]
        for name in islandsNames {
            let distillery = try #require(store.exactMatch(name), "\(name) missing from seed data")
            #expect(distillery.region == "islands", "\(name) should be islands")
        }
    }

    @Test func seedNamesAreUnique() {
        let names = store.distilleries.map { DistilleryStore.normalize($0.name) }
        #expect(Set(names).count == names.count)
    }

    // MARK: - Matching

    @Test func exactMatchIsCaseInsensitive() {
        #expect(store.exactMatch("LAGAVULIN")?.name == "Lagavulin")
        #expect(store.exactMatch("lagavulin")?.name == "Lagavulin")
    }

    @Test func exactMatchResolvesAliases() {
        #expect(store.exactMatch("The Macallan")?.name == "Macallan")
        #expect(store.exactMatch("Kilkerran")?.name == "Glengyle")
        #expect(store.exactMatch("anCnoc")?.name == "Knockdhu")
    }

    @Test func fuzzyMatchResolvesScannedProductName() {
        #expect(store.fuzzyMatch("LAGAVULIN 16 YEARS")?.name == "Lagavulin")
    }

    @Test func bestMatchResolvesNoisyScannedTitles() {
        #expect(store.bestMatch(for: "LAGAVULIN 16YO ISLAY SINGLE MALT")?.name == "Lagavulin")
        #expect(store.bestMatch(for: "The Glenlivet 12 Year Old Single Malt Scotch Whisky")?.name == "Glenlivet")
        #expect(store.bestMatch(for: "Highland Park 12 Viking Honour")?.name == "Highland Park")
        #expect(store.bestMatch(for: "Glen Grant Arboralis")?.name == "Glen Grant")
    }

    @Test func fuzzyMatchAbsorbsSmallMisspellings() {
        #expect(store.fuzzyMatch("LAGAVULN 16")?.name == "Lagavulin")
    }

    @Test func matchingReturnsNilForUnrelatedText() {
        #expect(store.bestMatch(for: "Jack Daniel's Tennessee Whiskey") == nil)
        #expect(store.bestMatch(for: "") == nil)
    }
}
