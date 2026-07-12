import Foundation
import OSLog
import SwiftUI

// MARK: - Result types

/// A product found by any lookup tier, normalized before any UI sees it.
nonisolated struct LookupProduct: Codable, Sendable, Equatable {
    var name: String
    var brand: String?
    var imageURL: String?
    var abv: Double?
    var categoryTags: [String] = []
}

nonisolated enum LookupOutcome: Codable, Sendable, Equatable {
    case hit(LookupProduct)
    case miss
}

struct LookupResult: Sendable, Equatable {
    let barcode: String
    let outcome: LookupOutcome
    /// Which tier answered, for the debug setting.
    let source: String
}

// MARK: - Protocols

/// The lookup entry point views use (PRD 10.1: network services stay
/// behind protocols).
protocol BarcodeLookupServicing: Sendable {
    func lookup(barcode: String) async -> LookupResult
}

/// One tier of the cascade. Return nil for a definitive "not in this
/// database"; throw for transport problems (offline, 429) so the cascade
/// can skip silently without caching a false miss. Adding a tier 3 later
/// is a single new conformance.
protocol BarcodeLookupTier: Sendable {
    var tierName: String { get }
    func lookup(barcode: String) async throws -> LookupProduct?
}

// MARK: - Cascade

/// Runs the tiers in order, stops at the first usable product, and caches
/// every definitive outcome (hit or miss) on disk for 90 days so rescans
/// and duplicate checks cost no network calls.
struct CascadeBarcodeLookupService: BarcodeLookupServicing {
    static let debugSourceDefaultsKey = "debugLastLookupSource"

    let tiers: [any BarcodeLookupTier]
    let cache: DiskCache<LookupOutcome>

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "Lookup")

    init(
        tiers: [any BarcodeLookupTier] = [OpenFoodFactsTier(), UPCItemDBTier()],
        cache: DiskCache<LookupOutcome> = DiskCache(folderName: "LookupCache", maxAge: 90 * 24 * 3600)
    ) {
        self.tiers = tiers
        self.cache = cache
    }

    func lookup(barcode: String) async -> LookupResult {
        if let cached = await cache.value(forKey: barcode) {
            recordSource("Cache")
            return LookupResult(barcode: barcode, outcome: cached, source: "Cache")
        }

        var sawTransportError = false
        for tier in tiers {
            do {
                if let product = try await tier.lookup(barcode: barcode) {
                    Self.logger.info("Lookup hit via \(tier.tierName) for \(barcode)")
                    recordSource(tier.tierName)
                    let outcome = LookupOutcome.hit(product)
                    await cache.store(outcome, forKey: barcode)
                    return LookupResult(barcode: barcode, outcome: outcome, source: tier.tierName)
                }
            } catch {
                // Skip silently to the next tier / the miss path (PRD F1).
                Self.logger.notice("\(tier.tierName) unavailable for \(barcode): \(error)")
                sawTransportError = true
            }
        }

        // Only cache the miss when every tier definitively answered;
        // an offline failure must not poison the cache for 90 days.
        if !sawTransportError {
            await cache.store(.miss, forKey: barcode)
        }
        recordSource("None")
        return LookupResult(barcode: barcode, outcome: .miss, source: "None")
    }

    private func recordSource(_ source: String) {
        UserDefaults.standard.set(source, forKey: Self.debugSourceDefaultsKey)
    }
}

// MARK: - Tier 1: Open Food Facts

struct OpenFoodFactsTier: BarcodeLookupTier {
    let tierName = "Open Food Facts"
    var session: URLSession = .shared

    func lookup(barcode: String) async throws -> LookupProduct? {
        guard let url = URL(
            string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
                + "?fields=product_name,brands,image_url,alcohol_by_volume,categories_tags"
        ) else { return nil }
        var request = URLRequest(url: url)
        // OFF etiquette: identify the client.
        request.setValue("UisgeBeatha/1.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Self.parse(data)
    }

    /// Exposed for tests.
    static func parse(_ data: Data) -> LookupProduct? {
        struct Response: Decodable {
            let status: Int?
            let product: Product?
        }
        struct Product: Decodable {
            let productName: String?
            let brands: String?
            let imageURL: String?
            let alcoholByVolume: LenientDouble?
            let categoriesTags: [String]?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case brands
                case imageURL = "image_url"
                case alcoholByVolume = "alcohol_by_volume"
                case categoriesTags = "categories_tags"
            }
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.status == 1,
              let product = response.product,
              let name = product.productName, !name.isEmpty else {
            return nil
        }
        return LookupProduct(
            name: name,
            brand: product.brands,
            imageURL: product.imageURL,
            abv: product.alcoholByVolume?.value,
            categoryTags: product.categoriesTags ?? []
        )
    }
}

/// OFF sometimes returns numbers as strings.
struct LenientDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = Double(string)
        } else {
            value = nil
        }
    }
}

// MARK: - Tier 2: UPCitemdb trial endpoint

struct UPCItemDBTier: BarcodeLookupTier {
    struct RateLimited: Error {}

    let tierName = "UPCitemdb"
    var session: URLSession = .shared

    func lookup(barcode: String) async throws -> LookupProduct? {
        guard let url = URL(string: "https://api.upcitemdb.com/prod/trial/lookup?upc=\(barcode)") else {
            return nil
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // On HTTP 429, skip silently to the miss path (PRD F1).
        if http.statusCode == 429 { throw RateLimited() }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Self.parse(data)
    }

    /// Exposed for tests.
    static func parse(_ data: Data) -> LookupProduct? {
        struct Response: Decodable {
            let items: [Item]?
        }
        struct Item: Decodable {
            let title: String?
            let brand: String?
            let images: [String]?
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let item = response.items?.first,
              let title = item.title, !title.isEmpty else {
            return nil
        }
        return LookupProduct(
            name: title,
            brand: item.brand,
            imageURL: item.images?.first,
            abv: nil,
            categoryTags: []
        )
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var barcodeLookup: any BarcodeLookupServicing = CascadeBarcodeLookupService()
    @Entry var collectionPolicy = CollectionPolicy.scotchOnly
}

// MARK: - UI-test stub

#if DEBUG
/// Installed when launched with -uiTestLookupStub so the UI driver can
/// exercise the whole post-scan pipeline without network or camera.
struct StubBarcodeLookupService: BarcodeLookupServicing {
    func lookup(barcode: String) async -> LookupResult {
        switch barcode {
        case "1111111111111":
            let product = LookupProduct(
                name: "Lagavulin 16 Year Old Islay Single Malt",
                brand: "Lagavulin",
                imageURL: nil,
                abv: 43.0,
                categoryTags: ["en:scotch-whisky"]
            )
            return LookupResult(barcode: barcode, outcome: .hit(product), source: "Stub")
        case "2222222222222":
            let product = LookupProduct(
                name: "Frontier Bourbon Whiskey",
                brand: "Frontier",
                imageURL: nil,
                abv: 45.0,
                categoryTags: ["en:bourbon-whiskey"]
            )
            return LookupResult(barcode: barcode, outcome: .hit(product), source: "Stub")
        default:
            return LookupResult(barcode: barcode, outcome: .miss, source: "Stub")
        }
    }
}
#endif
