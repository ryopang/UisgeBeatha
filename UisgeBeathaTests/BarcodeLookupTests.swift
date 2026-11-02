import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 4: lookup cascade ordering, caching rules, and tier parsing.
struct BarcodeLookupTests {

    // MARK: - Mock tier

    /// Scripted tier that records how often it was called.
    final class MockTier: BarcodeLookupTier, @unchecked Sendable {
        enum Behavior {
            case hit(LookupProduct)
            case definitiveMiss
            case transportError
        }

        let tierName: String
        let behavior: Behavior
        private(set) var callCount = 0

        init(_ tierName: String, _ behavior: Behavior) {
            self.tierName = tierName
            self.behavior = behavior
        }

        func lookup(barcode: String) async throws -> LookupProduct? {
            callCount += 1
            switch behavior {
            case .hit(let product): return product
            case .definitiveMiss: return nil
            case .transportError: throw URLError(.notConnectedToInternet)
            }
        }
    }

    private let product = LookupProduct(name: "Lagavulin 16", brand: "Lagavulin", categoryTags: ["en:scotch-whisky"])

    private func makeCache() -> DiskCache<LookupOutcome> {
        DiskCache(
            folderName: "test",
            maxAge: 90 * 24 * 3600,
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("LookupTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    // MARK: - Cascade

    @Test func firstTierHitStopsCascade() async {
        let tier1 = MockTier("T1", .hit(product))
        let tier2 = MockTier("T2", .hit(product))
        let service = CascadeBarcodeLookupService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.lookup(barcode: "123")
        #expect(result.outcome == .hit(product))
        #expect(result.source == "T1")
        #expect(tier2.callCount == 0)
    }

    @Test func tierOneMissFallsThroughToTierTwo() async {
        let tier1 = MockTier("T1", .definitiveMiss)
        let tier2 = MockTier("T2", .hit(product))
        let service = CascadeBarcodeLookupService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.lookup(barcode: "123")
        #expect(result.outcome == .hit(product))
        #expect(result.source == "T2")
    }

    @Test func rateLimitSkipsSilentlyToMissPath() async {
        let tier1 = MockTier("T1", .transportError)
        let tier2 = MockTier("T2", .transportError)
        let service = CascadeBarcodeLookupService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.lookup(barcode: "123")
        #expect(result.outcome == .miss)
    }

    @Test func hitsAreServedFromCacheOnRescan() async {
        let cache = makeCache()
        let tier1 = MockTier("T1", .hit(product))
        let service = CascadeBarcodeLookupService(tiers: [tier1], cache: cache)

        _ = await service.lookup(barcode: "123")
        let second = await service.lookup(barcode: "123")
        #expect(second.outcome == .hit(product))
        #expect(second.source == "Cache")
        #expect(tier1.callCount == 1, "Rescan must cost no network call")
    }

    @Test func definitiveMissesAreCachedToo() async {
        let cache = makeCache()
        let tier1 = MockTier("T1", .definitiveMiss)
        let service = CascadeBarcodeLookupService(tiers: [tier1], cache: cache)

        _ = await service.lookup(barcode: "123")
        let second = await service.lookup(barcode: "123")
        #expect(second.source == "Cache")
        #expect(tier1.callCount == 1)
    }

    @Test func transportErrorsAreNeverCached() async {
        let cache = makeCache()
        let tier1 = MockTier("T1", .transportError)
        let service = CascadeBarcodeLookupService(tiers: [tier1], cache: cache)

        _ = await service.lookup(barcode: "123")
        _ = await service.lookup(barcode: "123")
        #expect(tier1.callCount == 2, "An offline miss must retry next time")
    }

    @Test func expiredCacheEntriesAreIgnored() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LookupTests-\(UUID().uuidString)", isDirectory: true)
        let shortCache = DiskCache<LookupOutcome>(folderName: "t", maxAge: 0.01, directory: directory)
        await shortCache.store(.hit(product), forKey: "123")
        try? await Task.sleep(for: .milliseconds(50))
        let cached = await shortCache.value(forKey: "123")
        #expect(cached == nil)
    }

    // MARK: - Tier parsing

    @Test func openFoodFactsParsesAHit() {
        let json = """
        {"status": 1, "product": {"product_name": "Glenlivet 12", "brands": "The Glenlivet",
         "image_url": "https://example.org/x.jpg", "alcohol_by_volume": "40",
         "categories_tags": ["en:scotch-whisky"]}}
        """
        let product = OpenFoodFactsTier.parse(Data(json.utf8))
        #expect(product?.name == "Glenlivet 12")
        #expect(product?.abv == 40)
        #expect(product?.categoryTags == ["en:scotch-whisky"])
    }

    @Test func openFoodFactsStatusZeroIsAMiss() {
        let json = #"{"status": 0, "product": null}"#
        #expect(OpenFoodFactsTier.parse(Data(json.utf8)) == nil)
    }

    @Test func openFoodFactsEmptyNameIsAMiss() {
        let json = #"{"status": 1, "product": {"product_name": ""}}"#
        #expect(OpenFoodFactsTier.parse(Data(json.utf8)) == nil)
    }

    @Test func upcItemDBParsesFirstItem() {
        let json = """
        {"code": "OK", "items": [{"title": "Talisker 10 Single Malt", "brand": "Talisker",
         "images": ["https://example.org/t.jpg"]}]}
        """
        let product = UPCItemDBTier.parse(Data(json.utf8))
        #expect(product?.name == "Talisker 10 Single Malt")
        #expect(product?.imageURL == "https://example.org/t.jpg")
    }

    @Test func upcItemDBEmptyItemsIsAMiss() {
        #expect(UPCItemDBTier.parse(Data(#"{"code": "OK", "items": []}"#.utf8)) == nil)
    }

    @Test func upcItemDBCapturesDescriptionForLabelParsing() {
        let json = """
        {"code": "OK", "items": [{"title": "Talisker 10", "brand": "Talisker",
         "description": "Talisker 10 Year Old Single Malt Scotch Whisky, 45.8% ABV, 750ml"}]}
        """
        let product = UPCItemDBTier.parse(Data(json.utf8))
        #expect(product?.descriptionText?.contains("45.8%") == true)
    }

    // MARK: - Label text fallback

    @Test func labelParserExtractsAgeFromCommonPhrasings() {
        #expect(WhiskyLabelParser.age(from: "Lagavulin 16 Year Old Islay Single Malt") == 16)
        #expect(WhiskyLabelParser.age(from: "Talisker 10YO Single Malt") == 10)
        #expect(WhiskyLabelParser.age(from: "Glenfiddich 18 Years") == 18)
        #expect(WhiskyLabelParser.age(from: "Highland Park 12-Year-Old") == 12)
    }

    @Test func labelParserAgeIsNilWithoutAUnitWord() {
        #expect(WhiskyLabelParser.age(from: "Talisker 10 Single Malt") == nil)
    }

    @Test func labelParserExtractsABVFromPercentSign() {
        #expect(WhiskyLabelParser.abv(from: "Ardbeg 10 Year Old 46%") == 46)
        #expect(WhiskyLabelParser.abv(from: "Lagavulin 16 43.0% Vol") == 43.0)
    }

    @Test func labelParserExtractsABVFromProof() {
        #expect(WhiskyLabelParser.abv(from: "Wild Turkey 101 Proof") == 50.5)
        #expect(WhiskyLabelParser.abv(from: "Elijah Craig 94 Proof Bourbon") == 47)
    }

    @Test func labelParserABVIgnoresImplausibleValues() {
        #expect(WhiskyLabelParser.abv(from: "Bottled at 5% by an unrelated product") == nil)
        #expect(WhiskyLabelParser.abv(from: "No percentage here") == nil)
    }

    @Test func labelParserSearchesEverySourceUntilAMatch() {
        // Title alone is too terse; the description carries the details.
        let title = "Talisker 10"
        let description = "Talisker 10 Year Old Single Malt Scotch Whisky, 45.8% ABV"
        #expect(WhiskyLabelParser.age(in: [title, description]) == 10)
        #expect(WhiskyLabelParser.abv(in: [title, description]) == 45.8)
        // A match in the first source short-circuits the rest.
        #expect(WhiskyLabelParser.age(in: ["12 Year Old", "18 Year Old"]) == 12)
    }

    @Test func upcItemDBUpgradesPlainHTTPImagesToHTTPS() {
        #expect(UPCItemDBTier.secureImageURL("http://example.org/t.jpg") == "https://example.org/t.jpg")
        #expect(UPCItemDBTier.secureImageURL("https://example.org/t.jpg") == "https://example.org/t.jpg")
    }
}
