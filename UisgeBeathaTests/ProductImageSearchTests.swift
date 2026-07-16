import Foundation
import Testing
@testable import UisgeBeatha

/// Name-based stock-photo backfill for bottles that never saw a barcode
/// hit (label OCR / fully manual entry): cascade ordering/caching, and
/// each tier's own response parsing.
struct ProductImageSearchTests {

    // MARK: - Mock tier

    /// Scripted tier that records how often it was called.
    final class MockTier: ImageSearchTier, @unchecked Sendable {
        enum Behavior {
            case hit(String)
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

        func findImage(query: String) async throws -> String? {
            callCount += 1
            switch behavior {
            case .hit(let url): return url
            case .definitiveMiss: return nil
            case .transportError: throw URLError(.notConnectedToInternet)
            }
        }
    }

    /// Returns a different answer each call, in order (clamping on the
    /// last), so tests can tell a fresh network attempt apart from a
    /// cached repeat of the first answer.
    final class SequencedMockTier: ImageSearchTier, @unchecked Sendable {
        let tierName = "Seq"
        private let responses: [String?]
        private(set) var callCount = 0

        init(_ responses: [String?]) {
            self.responses = responses
        }

        func findImage(query: String) async throws -> String? {
            defer { callCount += 1 }
            return callCount < responses.count ? responses[callCount] : responses.last ?? nil
        }
    }

    private func makeCache() -> DiskCache<ImageSearchOutcome> {
        DiskCache(
            folderName: "test",
            maxAge: 90 * 24 * 3600,
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ImageSearchTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    // MARK: - Cascade

    @Test func firstTierHitStopsCascade() async {
        let tier1 = MockTier("T1", .hit("https://example.org/a.jpg"))
        let tier2 = MockTier("T2", .hit("https://example.org/b.jpg"))
        let service = CascadeImageSearchService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        #expect(result == .found("https://example.org/a.jpg"))
        #expect(tier2.callCount == 0)
    }

    @Test func tierOneMissFallsThroughToTierTwo() async {
        let tier1 = MockTier("T1", .definitiveMiss)
        let tier2 = MockTier("T2", .hit("https://example.org/b.jpg"))
        let service = CascadeImageSearchService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        #expect(result == .found("https://example.org/b.jpg"))
    }

    @Test func transportErrorSkipsSilentlyToNextTier() async {
        let tier1 = MockTier("T1", .transportError)
        let tier2 = MockTier("T2", .hit("https://example.org/b.jpg"))
        let service = CascadeImageSearchService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        #expect(result == .found("https://example.org/b.jpg"))
    }

    @Test func everyTierMissingIsADefinitiveNotFound() async {
        let tier1 = MockTier("T1", .definitiveMiss)
        let tier2 = MockTier("T2", .definitiveMiss)
        let service = CascadeImageSearchService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        #expect(result == .notFound)
    }

    @Test func everyTierUnreachableIsUnavailableNotNotFound() async {
        let tier1 = MockTier("T1", .transportError)
        let tier2 = MockTier("T2", .transportError)
        let service = CascadeImageSearchService(tiers: [tier1, tier2], cache: makeCache())

        let result = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        #expect(result == .unavailable)
    }

    @Test func cachedHitIsServedWithoutReturningToNetwork() async {
        let cache = makeCache()
        let tier1 = MockTier("T1", .hit("https://example.org/a.jpg"))
        let service = CascadeImageSearchService(tiers: [tier1], cache: cache)

        _ = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        let second = await service.findImage(name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16, bypassCache: false)
        #expect(second == .found("https://example.org/a.jpg"))
        #expect(tier1.callCount == 1, "Repeat lookups must cost no network call")
    }

    @Test func bypassCacheForcesAFreshAttemptAndOverwritesTheCache() async {
        // Reproduces the reported bug: pressing "look up photo" again did
        // nothing because the cached result from the first attempt was
        // always served back, whether it was a hit or a miss.
        let cache = makeCache()
        let tier1 = SequencedMockTier([nil, "https://example.org/second.jpg"])
        let service = CascadeImageSearchService(tiers: [tier1], cache: cache)

        let first = await service.findImage(name: "Lagavulin 16", distilleryName: "", age: nil, bypassCache: false)
        #expect(first == .notFound)

        let second = await service.findImage(name: "Lagavulin 16", distilleryName: "", age: nil, bypassCache: false)
        #expect(second == .notFound)
        #expect(tier1.callCount == 1, "A normal call must be served from the cached miss")

        let third = await service.findImage(name: "Lagavulin 16", distilleryName: "", age: nil, bypassCache: true)
        #expect(third == .found("https://example.org/second.jpg"), "bypassCache must ignore the cached miss and retry")
        #expect(tier1.callCount == 2)

        let fourth = await service.findImage(name: "Lagavulin 16", distilleryName: "", age: nil, bypassCache: false)
        #expect(fourth == .found("https://example.org/second.jpg"), "The fresh hit should now be cached")
        #expect(tier1.callCount == 2, "Should be served from the freshly-overwritten cache")
    }

    @Test func definitiveMissesAreCachedToo() async {
        let cache = makeCache()
        let tier1 = MockTier("T1", .definitiveMiss)
        let service = CascadeImageSearchService(tiers: [tier1], cache: cache)

        _ = await service.findImage(name: "Some Obscure Bottle", distilleryName: "", age: nil, bypassCache: false)
        _ = await service.findImage(name: "Some Obscure Bottle", distilleryName: "", age: nil, bypassCache: false)
        #expect(tier1.callCount == 1)
    }

    @Test func unavailableResultsAreNeverCached() async {
        let cache = makeCache()
        let tier1 = MockTier("T1", .transportError)
        // Empty distillery/age keeps this to a single query variant, so
        // the call count isolates the caching behavior from the separate
        // query-broadening behavior covered below.
        let service = CascadeImageSearchService(tiers: [tier1], cache: cache)

        _ = await service.findImage(name: "Lagavulin 16", distilleryName: "", age: nil, bypassCache: false)
        _ = await service.findImage(name: "Lagavulin 16", distilleryName: "", age: nil, bypassCache: false)
        #expect(tier1.callCount == 2, "An outage must retry next time, not stick around for 90 days")
    }

    @Test func broaderVariantIsTriedWhenTheSpecificQueryMissesEverywhere() async {
        let tier1 = MockTier("T1", .definitiveMiss)
        let service = CascadeImageSearchService(tiers: [tier1], cache: makeCache())

        // Nothing matches "Macallan 12 Year Old Double Cask" or "Macallan
        // 12" in this mock, but "Macallan" alone (variant 3) should still
        // get tried before giving up — assert via call count since the
        // mock can't distinguish which variant text it received.
        _ = await service.findImage(
            name: "Macallan 12 Year Old Double Cask", distilleryName: "Macallan", age: 12, bypassCache: false
        )
        #expect(tier1.callCount == 3, "Expected one attempt per query variant: full name, distillery+age, distillery alone")
    }

    @Test func broadeningStopsAtTheFirstHit() async {
        let tier1 = MockTier("T1", .hit("https://example.org/a.jpg"))
        let service = CascadeImageSearchService(tiers: [tier1], cache: makeCache())

        let result = await service.findImage(
            name: "Macallan 12 Year Old Double Cask", distilleryName: "Macallan", age: 12, bypassCache: false
        )
        #expect(result == .found("https://example.org/a.jpg"))
        #expect(tier1.callCount == 1, "The first (most specific) variant already hit — no need to broaden")
    }

    @Test func emptyQueryIsANotFoundWithoutReturningToNetwork() async {
        let tier1 = MockTier("T1", .hit("https://example.org/a.jpg"))
        let service = CascadeImageSearchService(tiers: [tier1], cache: makeCache())

        let result = await service.findImage(name: "", distilleryName: "", age: nil, bypassCache: false)
        #expect(result == .notFound)
        #expect(tier1.callCount == 0)
    }

    // MARK: - Query building

    @Test func queryIncludesNameAloneWhenDistilleryIsRedundant() {
        let query = CascadeImageSearchService.buildQuery(
            name: "Lagavulin 16 Year Old", distilleryName: "Lagavulin", age: 16
        )
        #expect(query == "Lagavulin 16 Year Old")
    }

    @Test func queryAddsDistilleryWhenNameDoesNotMentionIt() {
        let query = CascadeImageSearchService.buildQuery(
            name: "The Original 12", distilleryName: "Glenlivet", age: nil
        )
        #expect(query == "The Original 12 Glenlivet")
    }

    @Test func queryAddsAgeWhenNameOmitsIt() {
        let query = CascadeImageSearchService.buildQuery(
            name: "Talisker", distilleryName: "Talisker", age: 10
        )
        #expect(query == "Talisker 10 year")
    }

    @Test func emptyNameProducesEmptyQuery() {
        let query = CascadeImageSearchService.buildQuery(name: "", distilleryName: "", age: nil)
        #expect(query.isEmpty)
    }

    // MARK: - Query broadening

    @Test func variantsBroadenFromFullNameToDistilleryAlone() {
        let variants = CascadeImageSearchService.buildQueryVariants(
            name: "Macallan 12 Year Old Double Cask", distilleryName: "Macallan", age: 12
        )
        #expect(variants == ["Macallan 12 Year Old Double Cask", "Macallan 12", "Macallan"])
    }

    @Test func variantsDedupWhenDistilleryAgeMatchesTheFullQuery() {
        // "Lagavulin 16" (distillery + age) is identical to the full-name
        // variant here, so it shouldn't appear twice.
        let variants = CascadeImageSearchService.buildQueryVariants(
            name: "Lagavulin 16", distilleryName: "Lagavulin", age: 16
        )
        #expect(variants == ["Lagavulin 16", "Lagavulin"])
    }

    @Test func variantsWithNoDistilleryIsJustTheName() {
        let variants = CascadeImageSearchService.buildQueryVariants(
            name: "Some Obscure Bottle", distilleryName: "", age: nil
        )
        #expect(variants == ["Some Obscure Bottle"])
    }

    @Test func variantsAreEmptyWhenNothingIsAvailable() {
        let variants = CascadeImageSearchService.buildQueryVariants(name: "", distilleryName: "", age: nil)
        #expect(variants.isEmpty)
    }

    // MARK: - Open Food Facts tier parsing

    @Test func openFoodFactsParsesFirstProductImageURL() {
        let json = """
        {"count": 2, "products": [{"image_url": "https://example.org/a.jpg"}, {"image_url": "https://example.org/b.jpg"}]}
        """
        #expect(OpenFoodFactsImageTier.parse(Data(json.utf8)) == "https://example.org/a.jpg")
    }

    @Test func openFoodFactsEmptyResultsIsAMiss() {
        #expect(OpenFoodFactsImageTier.parse(Data(#"{"count": 0, "products": []}"#.utf8)) == nil)
    }

    @Test func openFoodFactsMissingImageURLIsAMiss() {
        #expect(OpenFoodFactsImageTier.parse(Data(#"{"count": 1, "products": [{}]}"#.utf8)) == nil)
    }

    @Test func openFoodFactsBlankImageURLIsAMiss() {
        let json = #"{"count": 1, "products": [{"image_url": ""}]}"#
        #expect(OpenFoodFactsImageTier.parse(Data(json.utf8)) == nil)
    }

    // MARK: - Wikimedia Commons tier parsing

    @Test func wikimediaCommonsParsesTheImageURL() {
        let json = """
        {"query": {"pages": {"123": {"index": 1, "imageinfo": [
            {"url": "https://upload.wikimedia.org/x.jpg", "mime": "image/jpeg"}
        ]}}}}
        """
        #expect(WikimediaCommonsImageTier.parse(Data(json.utf8)) == "https://upload.wikimedia.org/x.jpg")
    }

    @Test func wikimediaCommonsNoPagesIsAMiss() {
        #expect(WikimediaCommonsImageTier.parse(Data(#"{"query": {"pages": {}}}"#.utf8)) == nil)
    }

    @Test func wikimediaCommonsMissingImageInfoIsAMiss() {
        let json = #"{"query": {"pages": {"123": {"index": 1}}}}"#
        #expect(WikimediaCommonsImageTier.parse(Data(json.utf8)) == nil)
    }

    @Test func wikimediaCommonsBlankURLIsAMiss() {
        let json = """
        {"query": {"pages": {"123": {"index": 1, "imageinfo": [{"url": "", "mime": "image/jpeg"}]}}}}
        """
        #expect(WikimediaCommonsImageTier.parse(Data(json.utf8)) == nil)
    }

    @Test func wikimediaCommonsSkipsNonImageFilesRegardlessOfRank() {
        // A better-ranked video (index 1) must not beat a worse-ranked
        // photo (index 2) — this is the exact shape of a real response
        // that returned a "Making malt whisky" .webm ahead of an actual
        // bottle photo.
        let json = """
        {"query": {"pages": {
            "1": {"index": 1, "imageinfo": [{"url": "https://upload.wikimedia.org/clip.webm", "mime": "video/webm"}]},
            "2": {"index": 2, "imageinfo": [{"url": "https://upload.wikimedia.org/bottle.jpg", "mime": "image/jpeg"}]}
        }}}
        """
        #expect(WikimediaCommonsImageTier.parse(Data(json.utf8)) == "https://upload.wikimedia.org/bottle.jpg")
    }

    @Test func wikimediaCommonsAllNonImageResultsIsAMiss() {
        let json = """
        {"query": {"pages": {"1": {"index": 1, "imageinfo": [
            {"url": "https://upload.wikimedia.org/doc.pdf", "mime": "application/pdf"}
        ]}}}}
        """
        #expect(WikimediaCommonsImageTier.parse(Data(json.utf8)) == nil)
    }
}
