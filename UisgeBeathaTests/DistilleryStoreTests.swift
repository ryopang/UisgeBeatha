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

    // MARK: - Short/numeric alias guard (A4: "1770" firing on any label
    // printing that founding year, "Spey" firing on any mention of the river)

    @Test func shortAliasStillMatchesExactly() {
        // Autocomplete typing the alias verbatim should still work — only
        // free-text substring/fuzzy matching is guarded.
        #expect(store.exactMatch("1770")?.name == "Glasgow Distillery")
        #expect(store.exactMatch("Spey")?.name == "Speyside Distillery")
    }

    @Test func shortAliasDoesNotFalsePositiveOnUnrelatedLabelText() {
        // No real distillery name present in either line — only the risky
        // short/numeric alias fragment ("1770", "Spey") — so both must miss.
        #expect(store.containsMatch(in: "ESTABLISHED IN 1770 BY ROYAL CHARTER") == nil)
        #expect(store.bestMatch(for: "MATURED ON THE BANKS OF THE RIVER SPEY") == nil)
    }

    @Test func shortPrimaryNameStillMatchesAsSubstring() {
        // The length/numeric guard applies to aliases, not to a
        // distillery's own (curated, deliberately chosen) name — "Jura"
        // and "Oban" are both 4 characters.
        #expect(store.containsMatch(in: "JURA 10 SINGLE MALT")?.name == "Jura")
        #expect(store.containsMatch(in: "OBAN WEST HIGHLAND")?.name == "Oban")
    }

    // MARK: - tieredMatch (label-scan global distillery scoring)

    @Test func tieredMatchReportsExactTierForAnExactName() {
        let result = store.tieredMatch(for: "Lagavulin")
        #expect(result?.distillery.name == "Lagavulin")
        #expect(result?.tier == .exact)
    }

    @Test func tieredMatchReportsContainsTierForASubstringHit() {
        let result = store.tieredMatch(for: "THE MACALLAN DOUBLE CASK")
        #expect(result?.distillery.name == "Macallan")
        #expect(result?.tier == .contains)
    }

    @Test func tieredMatchReportsFuzzyTierForAMisspelling() {
        let result = store.tieredMatch(for: "TALISKFR 10")
        #expect(result?.distillery.name == "Talisker")
        #expect(result?.tier == .fuzzyLevenshtein)
    }

    @Test func matchTierOrdersExactBeforeContainsBeforeFuzzy() {
        #expect(DistilleryStore.MatchTier.exact < .contains)
        #expect(DistilleryStore.MatchTier.contains < .fuzzySubset)
        #expect(DistilleryStore.MatchTier.fuzzySubset < .fuzzyLevenshtein)
    }
}
