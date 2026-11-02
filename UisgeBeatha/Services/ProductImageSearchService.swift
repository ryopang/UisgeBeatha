import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Best-effort stock-photo backfill for bottles that never saw a barcode
/// hit (label OCR or fully manual entry) — those have a name and
/// distillery but no image_url the way BarcodeLookupService's cascade
/// gets one. A miss or a mismatched photo is expected and never treated as
/// authoritative; the person can always replace it with their own photo.
protocol ProductImageSearching: Sendable {
    /// `bypassCache` is true for an explicit "look up photo" retry — a
    /// person pressing that button a second time clearly wants a fresh
    /// attempt, not the same cached hit (or miss) served back at them
    /// again. The result is still written to the cache either way, so a
    /// later automatic backfill for a different bottle with the same
    /// query benefits from it.
    func findImage(request: ImageLookupRequest, bypassCache: Bool) async -> ImageLookupResult
}

/// Everything a lookup can use to find a photo. `barcode` and
/// `distilleryWikipediaTitle` are optional extras beyond name/distillery/age
/// that let the cascade try more reliable, product-specific sources before
/// falling back to free-text search.
nonisolated struct ImageLookupRequest: Sendable, Equatable {
    var name: String
    var distilleryName: String
    var age: Int?
    /// When present, tried first via Open Food Facts' *product* endpoint —
    /// the same reliable, exact-match endpoint the barcode-lookup cascade
    /// itself uses, not its flaky free-text search.
    var barcode: String?
    /// The matched distillery's Wikipedia article title (from seed data),
    /// tried second — always relevant (it's a real photo of the actual
    /// distillery), never a guess, but not a photo of this specific
    /// bottle. `ImageLookupResult.found` reports when a hit came from here
    /// so the UI can label it honestly.
    var distilleryWikipediaTitle: String?
}

/// Distinguishes a clean "no match" from every tier being unreachable —
/// worth telling the person apart from "nothing found" (same "never
/// silently look broken" spirit as the label-OCR failure banner).
nonisolated enum ImageLookupResult: Sendable, Equatable {
    case found(url: String, isDistilleryPhoto: Bool)
    case notFound
    case unavailable
}

/// What's actually worth caching for 90 days — "unavailable" is transient
/// (today's outage isn't tomorrow's), so it's never persisted, same rule as
/// the barcode cascade never caching a transport error.
nonisolated enum ImageSearchOutcome: Codable, Sendable, Equatable {
    case found(url: String, isDistilleryPhoto: Bool)
    case notFound
}

// MARK: - Tiers

/// One free-text source in the image-search cascade. Return nil for a
/// definitive "no photo here"; throw for transport problems (down,
/// rate-limited) so the cascade can fall through to the next tier without
/// caching a false miss — same contract as BarcodeLookupTier.
protocol ImageSearchTier: Sendable {
    var tierName: String { get }
    func findImage(query: String) async throws -> String?
}

/// The barcode-keyed source in the cascade, kept as its own small protocol
/// (rather than folded into `ImageSearchTier`) since it takes a barcode,
/// not a text query — same contract otherwise (nil for a definitive miss,
/// throw for a transport problem), and injectable the same way for tests.
protocol BarcodeImageSearching: Sendable {
    var tierName: String { get }
    func findImage(barcode: String) async throws -> String?
}

/// Open Food Facts' *product* endpoint, fetched by barcode — the exact
/// reliable endpoint the barcode-lookup cascade itself uses
/// (OpenFoodFactsTier), not the free-text search endpoint below (whose own
/// doc comment notes it "returns 503s for stretches at a time"). A barcode
/// identifies the exact product, so this is tried before anything
/// text-based when the bottle has one.
struct OpenFoodFactsBarcodeImageTier: BarcodeImageSearching {
    let tierName = "Open Food Facts (barcode)"
    var session: URLSession = AppNetwork.session

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "ImageSearch")

    func findImage(barcode: String) async throws -> String? {
        guard let url = URL(
            string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=image_url"
        ) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(AppNetwork.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Self.parse(data)
    }

    /// Exposed for tests.
    static func parse(_ data: Data) -> String? {
        struct Response: Decodable {
            struct Product: Decodable {
                let imageURL: String?
                enum CodingKeys: String, CodingKey { case imageURL = "image_url" }
            }
            let status: Int?
            let product: Product?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.status == 1,
              let imageURL = response.product?.imageURL, !imageURL.isEmpty else {
            return nil
        }
        return imageURL
    }
}

/// Wikimedia Commons' media search (free, no key). Community-uploaded
/// product photography gives decent whisky-bottle coverage, and it runs on
/// Wikimedia's infrastructure — in practice far more reliable than Open
/// Food Facts' free-text search endpoint, which returns 503s for stretches
/// at a time.
struct WikimediaCommonsImageTier: ImageSearchTier {
    let tierName = "Wikimedia Commons"
    var session: URLSession = AppNetwork.session
    var maxAttempts = 2
    var retryDelay: Duration = .milliseconds(400)

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "ImageSearch")

    func findImage(query: String) async throws -> String? {
        // Built with URLComponents rather than manual percent-encoding +
        // string interpolation: a raw "|" anywhere in the string (as in
        // "iiprop=url|mime") makes URL(string:) fall back to re-encoding
        // the *whole* string, double-encoding the already-escaped search
        // term into garbage the API silently fails to match — the exact
        // reason this tier was quietly returning nothing.
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            // "whisky bottle" biases matches toward product photos rather
            // than distillery buildings or landscapes, which also turn up
            // otherwise.
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: "\(query) whisky bottle"),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            // Wider than 1 because the File namespace also holds PDFs,
            // audio, and video (a "Making malt whisky" .webm outranked an
            // actual bottle photo for one query in testing) — parse()
            // below walks results in relevance order and picks the first
            // that's actually an image.
            URLQueryItem(name: "gsrlimit", value: "8"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|mime"),
            // Ask for a server-rendered thumbnail. The plain `url` is the
            // original upload, often a multi-megabyte camera file, which
            // the list then decoded into a 48pt thumbnail on every scroll.
            URLQueryItem(name: "iiurlwidth", value: "800"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(AppNetwork.userAgent, forHTTPHeaderField: "User-Agent")

        var lastError: Error = URLError(.unknown)
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                return Self.parse(data)
            } catch {
                lastError = error
                Self.logger.notice("\(tierName) attempt \(attempt)/\(maxAttempts) failed for \(query): \(error)")
                if attempt < maxAttempts { try? await Task.sleep(for: retryDelay) }
            }
        }
        throw lastError
    }

    /// Exposed for tests. Picks the most relevant result (lowest `index`)
    /// whose mime type is actually an image — Commons' search ranks by
    /// text relevance only, so a well-matched PDF or video can outrank a
    /// worse-matched photo.
    static func parse(_ data: Data) -> String? {
        struct Response: Decodable {
            struct Query: Decodable { let pages: [String: Page]? }
            struct Page: Decodable {
                let index: Int?
                let imageinfo: [ImageInfo]?
            }
            struct ImageInfo: Decodable {
                let url: String?
                let thumburl: String?
                let mime: String?
            }
            let query: Query?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let pages = response.query?.pages?.values else {
            return nil
        }
        let imageURL = pages
            .sorted { ($0.index ?? .max) < ($1.index ?? .max) }
            .lazy
            .compactMap { $0.imageinfo?.first }
            .first { ($0.mime ?? "").hasPrefix("image/") && !($0.url ?? "").isEmpty }
            .flatMap { info -> String? in
                // Prefer the sized thumbnail; fall back to the original
                // when the API didn't render one.
                if let thumb = info.thumburl, !thumb.isEmpty { return thumb }
                return info.url
            }
        guard let imageURL, !imageURL.isEmpty else {
            return nil
        }
        return imageURL
    }
}

/// Open Food Facts' free-text product search (free, no key) — the same
/// database as the barcode cascade's tier 1, searched by name instead of
/// barcode. Last resort: it's product-specific (a real bottle shot, not a
/// distillery photo) when it works, but its search endpoint has turned out
/// to return 503 for extended periods, unlike its barcode/product endpoint
/// (OpenFoodFactsBarcodeImageTier, above) — which is why every other tier
/// in this cascade runs ahead of it.
struct OpenFoodFactsImageTier: ImageSearchTier {
    let tierName = "Open Food Facts"
    var session: URLSession = AppNetwork.session
    var maxAttempts = 3
    var retryDelay: Duration = .milliseconds(600)

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "ImageSearch")

    func findImage(query: String) async throws -> String? {
        // URLComponents, not manual percent-encoding + string interpolation
        // — see the Wikimedia tier's comment for why that combination is
        // fragile (it double-encodes as soon as any literal special
        // character shares the string with an already-escaped one).
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "1"),
            URLQueryItem(name: "fields", value: "image_url"),
        ]
        guard let url = components?.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(AppNetwork.userAgent, forHTTPHeaderField: "User-Agent")

        var lastError: Error = URLError(.unknown)
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                return Self.parse(data)
            } catch {
                lastError = error
                Self.logger.notice("\(tierName) attempt \(attempt)/\(maxAttempts) failed for \(query): \(error)")
                if attempt < maxAttempts { try? await Task.sleep(for: retryDelay) }
            }
        }
        throw lastError
    }

    /// Exposed for tests.
    static func parse(_ data: Data) -> String? {
        struct Response: Decodable {
            struct Product: Decodable {
                let imageURL: String?
                enum CodingKeys: String, CodingKey {
                    case imageURL = "image_url"
                }
            }
            let products: [Product]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let imageURL = response.products?.first?.imageURL,
              !imageURL.isEmpty else {
            return nil
        }
        return imageURL
    }
}

// MARK: - Cascade

/// Runs the sources in order, stops at the first usable photo, and caches
/// every definitive outcome (hit or miss) on disk for 90 days — mirrors
/// CascadeBarcodeLookupService.
///
/// Order, most-likely-correct first (docs/label-scan-plan.md §L6):
/// 1. Open Food Facts *product* image, by barcode — an exact match, not a
///    guess, when the bottle has a barcode.
/// 2. The matched distillery's Wikipedia lead image — always relevant
///    (it's genuinely that distillery), reported back as
///    `isDistilleryPhoto` so the UI never passes it off as a bottle photo.
/// 3. Wikimedia Commons free-text search.
/// 4. Open Food Facts free-text search — kept as a last resort despite its
///    flaky uptime, since by this point every more-reliable source has
///    already been tried and come up empty.
struct CascadeImageSearchService: ProductImageSearching {
    let barcodeImageTier: any BarcodeImageSearching
    let wikipedia: any WikipediaServicing
    let tiers: [any ImageSearchTier]
    let cache: DiskCache<ImageSearchOutcome>

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "ImageSearch")

    init(
        barcodeImageTier: any BarcodeImageSearching = OpenFoodFactsBarcodeImageTier(),
        wikipedia: any WikipediaServicing = WikipediaService(),
        tiers: [any ImageSearchTier] = [WikimediaCommonsImageTier(), OpenFoodFactsImageTier()],
        // "V4": Commons hits are now sized thumbnails rather than
        // full-resolution originals (V3 added barcode/Wikipedia tiers and
        // the isDistilleryPhoto tag). Bumping the folder name gives
        // everyone a clean slate instead of waiting out the old expiry.
        cache: DiskCache<ImageSearchOutcome> = DiskCache(folderName: "ImageSearchCacheV4", maxAge: 90 * 24 * 3600)
    ) {
        self.barcodeImageTier = barcodeImageTier
        self.wikipedia = wikipedia
        self.tiers = tiers
        self.cache = cache
    }

    func findImage(request: ImageLookupRequest, bypassCache: Bool) async -> ImageLookupResult {
        let queries = Self.buildQueryVariants(
            name: request.name, distilleryName: request.distilleryName, age: request.age
        )
        guard let cacheKey = queries.first else { return .notFound }

        if !bypassCache, let cached = await cache.value(forKey: cacheKey) {
            switch cached {
            case .found(let url, let isDistilleryPhoto): return .found(url: url, isDistilleryPhoto: isDistilleryPhoto)
            case .notFound: return .notFound
            }
        }

        var sawTransportError = false

        if let barcode = request.barcode {
            do {
                if let url = try await barcodeImageTier.findImage(barcode: barcode) {
                    Self.logger.info("Image search hit via \(barcodeImageTier.tierName) for barcode \(barcode)")
                    await cache.store(.found(url: url, isDistilleryPhoto: false), forKey: cacheKey)
                    return .found(url: url, isDistilleryPhoto: false)
                }
            } catch {
                Self.logger.notice("\(barcodeImageTier.tierName) unavailable for barcode \(barcode): \(error)")
                sawTransportError = true
            }
        }

        if let wikipediaTitle = request.distilleryWikipediaTitle {
            // WikipediaServicing is quiet by contract (PRD F6: offline or
            // failure degrades to seed facts, no error surfaced) — a miss
            // here reads as "no image", not a transport error, since there
            // is no way to tell the two apart at this layer.
            if let summary = await wikipedia.summary(forTitles: [wikipediaTitle]),
               let thumbnail = summary.thumbnailURL, !thumbnail.isEmpty {
                Self.logger.info("Image search hit via distillery Wikipedia image for \(wikipediaTitle)")
                await cache.store(.found(url: thumbnail, isDistilleryPhoto: true), forKey: cacheKey)
                return .found(url: thumbnail, isDistilleryPhoto: true)
            }
        }

        // Most specific query first (the full name, descriptive extras and
        // all), broadening only if it comes up empty everywhere — Commons
        // and OFF both do literal text search, not fuzzy matching, so a
        // name with modifiers like "Double Cask" or "12 Year Old" often
        // finds nothing even though the same bottle's plain "distillery +
        // age" query succeeds. All variants share one cache entry: it's
        // still one lookup for one bottle, broadening is just how hard it
        // tries before giving up.
        for query in queries {
            for tier in tiers {
                do {
                    if let url = try await tier.findImage(query: query) {
                        Self.logger.info("Image search hit via \(tier.tierName) for \"\(query)\"")
                        await cache.store(.found(url: url, isDistilleryPhoto: false), forKey: cacheKey)
                        return .found(url: url, isDistilleryPhoto: false)
                    }
                } catch {
                    Self.logger.notice("\(tier.tierName) unavailable for \"\(query)\": \(error)")
                    sawTransportError = true
                }
            }
        }

        // Only cache a miss when every tier definitively answered; an
        // outage must not poison the cache for 90 days.
        if !sawTransportError {
            await cache.store(.notFound, forKey: cacheKey)
            return .notFound
        }
        return .unavailable
    }

    /// Progressively broader queries, most specific first: the full name
    /// (with distillery/age folded in if it doesn't already mention them),
    /// then distillery+age, then distillery alone. Order matters — callers
    /// try each in turn and stop at the first hit.
    static func buildQueryVariants(name: String, distilleryName: String, age: Int?) -> [String] {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDistillery = distilleryName.trimmingCharacters(in: .whitespaces)

        var variants: [String] = []
        if !trimmedName.isEmpty {
            variants.append(buildQuery(name: trimmedName, distilleryName: trimmedDistillery, age: age))
        }
        if !trimmedDistillery.isEmpty {
            if let age {
                variants.append("\(trimmedDistillery) \(age)")
            }
            variants.append(trimmedDistillery)
        }

        var seen = Set<String>()
        return variants.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Builds a search query from whatever fields are available, skipping
    /// any that are already implied by the name (e.g. "Lagavulin 16 Year
    /// Old" already names the distillery and the age).
    static func buildQuery(name: String, distilleryName: String, age: Int?) -> String {
        var terms = [name.trimmingCharacters(in: .whitespaces)]
        if !distilleryName.isEmpty, !name.localizedCaseInsensitiveContains(distilleryName) {
            terms.append(distilleryName)
        }
        if let age, !name.contains(String(age)) {
            terms.append("\(age) year")
        }
        return terms.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Backfill coordinator

/// Runs the search fire-and-forget and tracks which bottles currently have
/// one in flight (or just failed), so any view showing that bottle can
/// surface a spinner or a failure notice instead of a silent, unexplained
/// non-event. One instance lives for the app's lifetime (created in
/// UisgeBeathaApp, like TabRouter), so state survives navigating away and
/// back while a search is still running.
@MainActor @Observable
final class StockPhotoBackfill {
    private(set) var inFlightBottleIDs: Set<UUID> = []
    private(set) var unavailableBottleIDs: Set<UUID> = []
    private let search: any ProductImageSearching

    init(search: any ProductImageSearching) {
        self.search = search
    }

    func isSearching(_ bottle: Bottle) -> Bool {
        inFlightBottleIDs.contains(bottle.id)
    }

    /// True once a search has come back with every tier unreachable —
    /// distinct from a clean "no match", which stays silent like the rest
    /// of the app's best-effort lookups. Clears the next time a search is
    /// attempted for this bottle.
    func lookupFailed(_ bottle: Bottle) -> Bool {
        unavailableBottleIDs.contains(bottle.id)
    }

    /// A no-op if this bottle already has a search in flight. `bypassCache`
    /// should be true for a person explicitly pressing "look up photo"
    /// again — otherwise the cache would just serve back the same hit (or
    /// miss) as before, and the button would look like it does nothing.
    /// `distilleryWikipediaTitle` comes from the caller's DistilleryStore
    /// lookup (this type has no store of its own) so a Wikipedia-image
    /// fallback can be tried; nil is fine, it's just one fewer source.
    func fetch(
        for bottle: Bottle, modelContext: ModelContext,
        distilleryWikipediaTitle: String? = nil, bypassCache: Bool = false
    ) {
        guard !inFlightBottleIDs.contains(bottle.id) else { return }
        inFlightBottleIDs.insert(bottle.id)
        unavailableBottleIDs.remove(bottle.id)
        let id = bottle.id
        let request = ImageLookupRequest(
            name: bottle.name, distilleryName: bottle.distilleryName, age: bottle.ageStatement,
            barcode: bottle.barcode, distilleryWikipediaTitle: distilleryWikipediaTitle
        )
        Task {
            defer { inFlightBottleIDs.remove(id) }
            switch await search.findImage(request: request, bypassCache: bypassCache) {
            case .found(let url, let isDistilleryPhoto):
                // The search can take seconds; the bottle may have been
                // deleted meanwhile, and writing to a deleted model is a
                // SwiftData crash.
                guard !bottle.isDeleted, bottle.modelContext != nil else { return }
                bottle.stockPhotoURL = url
                bottle.isDistilleryPhoto = isDistilleryPhoto
                try? modelContext.save()
                // Download it once and keep it, rather than hotlinking the
                // URL on every view. If the download fails the URL stays
                // remembered and the store maintenance retries later.
                await StockPhotoImporter().importPhoto(from: url, for: bottle, in: modelContext)
            case .notFound:
                break
            case .unavailable:
                unavailableBottleIDs.insert(id)
            }
        }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var stockPhotoBackfill: StockPhotoBackfill?
}

// MARK: - UI-test stub

#if DEBUG
/// Installed when launched with -uiTestLookupStub, matching the other
/// service stubs.
struct StubProductImageSearchService: ProductImageSearching {
    func findImage(request: ImageLookupRequest, bypassCache: Bool) async -> ImageLookupResult {
        .notFound
    }
}
#endif
