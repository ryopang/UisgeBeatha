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
    /// Longer free-text description, when the source provides one (only
    /// UPCitemdb does). Product titles are often too terse to mention ABV
    /// or age; descriptions more often spell them out.
    var descriptionText: String?
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
            let description: String?
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
            categoryTags: [],
            descriptionText: item.description
        )
    }
}

// MARK: - Label text fallback

/// Best-effort ABV / age extraction from whatever free text a lookup
/// returns. UPCitemdb never returns a structured ABV field and neither
/// tier returns age at all, but whisky listing titles and descriptions
/// almost always spell both out ("Lagavulin 16 Year Old ... 43%", "90
/// Proof"), so this backstops the structured fields when they're missing.
/// Titles alone are often too terse to mention either, so callers should
/// pass every text field a source provides (title, description, ...) —
/// the first source with a match wins.
///
/// Two correctness rules that weren't true of the first version of this
/// parser, found by running it against realistic label OCR fixtures:
///
/// 1. **Scan every match in a line, not just the first.** A European
///    label's "40,0% vol" has the decimal comma read as its own group by a
///    naive first-match regex; the plausible value ("40") is sitting right
///    there in the same string. Taking only the first candidate and giving
///    up if it fails the range check throws that away.
/// 2. **A label prints its age as a big standalone numeral with "YEARS
///    OLD" as a separate line or block below it.** Vision returns those as
///    separate text observations, so a regex that only ever looks at one
///    line in isolation never sees "12" and "YEARS OLD" together. Age
///    detection here is line-window aware (see `LabelParser`); this type
///    stays a pure per-text-window matcher.
nonisolated enum WhiskyLabelParser {
    static func abv(from name: String) -> Double? {
        abv(in: [name])
    }

    static func age(from name: String) -> Int? {
        age(in: [name])
    }

    static func abv(in texts: [String]) -> Double? {
        for text in texts {
            for value in percentMatches(in: text) where (20...80).contains(value) {
                return value
            }
        }
        for text in texts {
            for value in proofMatches(in: text) where (40...160).contains(value) {
                return value / 2
            }
        }
        return nil
    }

    static func age(in texts: [String]) -> Int? {
        for text in texts {
            for value in ageMatches(in: text) where (3...50).contains(value) {
                return value
            }
        }
        for text in texts {
            if let value = spelledOutAgeMatch(in: text), (3...50).contains(value) {
                return value
            }
        }
        // Last resort, and only after both strict passes have come up
        // empty: real labels set the age in ornate or embossed type that
        // OCR mangles predictably — "AGED 15 YEARS" comes back as
        // "AGKD 15 TRARS", "12 YEARS" as "12 YRANS" or "12 TEARS". The
        // number itself survives; only the word around it is corrupted.
        for text in texts {
            if let value = fuzzyAgeMatch(in: text) { return value }
        }
        return nil
    }

    /// "43%", "40,0% vol" (European comma decimal), "ALC 43 % VOL",
    /// "54.2% ALC./VOL" — anything with a plausible ABV number ahead of a
    /// literal "%". Every match in the text is returned so a caller can
    /// skip a decoy (a batch number, a cask number) and use the next.
    private static func percentMatches(in text: String) -> [Double] {
        allMatches(pattern: #"(\d{1,2}(?:[.,]\d)?)\s*%"#, in: text)
    }

    /// US retail listings often state proof (ABV × 2) instead of a percentage.
    private static func proofMatches(in text: String) -> [Double] {
        allMatches(pattern: #"(\d{2,3}(?:[.,]\d)?)\s*proof"#, options: [.caseInsensitive], in: text)
    }

    /// "16 Years Old", "AGED 12 YEARS", "18 Y.O.", "10YO", "12-Year",
    /// "aged 21". `(?![a-zA-Z])` instead of a trailing `\b` because `\b`
    /// never matches right after a period at the end of a string — which
    /// is exactly where "Y.O." ends, and silently dropped every match.
    private static func ageMatches(in text: String) -> [Int] {
        let numericWord = allMatches(
            pattern: #"(\d{1,2})\s*[- ]?(?:years?|yrs?|y\.?o\.?)(?![a-zA-Z])"#,
            options: [.caseInsensitive], in: text
        )
        let agedForm = allMatches(
            pattern: #"\baged\s+(\d{1,2})\b"#, options: [.caseInsensitive], in: text
        )
        return (numericWord + agedForm).map { Int($0) }
    }

    /// "Twelve Year Old", "Eighteen Years" — rarer than a numeral, but real
    /// on some traditional and travel-retail labels, and free once the
    /// numeric form has already come up empty.
    private static let spelledOutAges: [(word: String, value: Int)] = [
        ("ten", 10), ("twelve", 12), ("thirteen", 13), ("fourteen", 14),
        ("fifteen", 15), ("sixteen", 16), ("seventeen", 17), ("eighteen", 18),
        ("twenty", 20), ("twentyone", 21), ("twentyfive", 25), ("thirty", 30),
    ]
    private static func spelledOutAgeMatch(in text: String) -> Int? {
        let tokens = DistilleryStore.normalize(text).split(separator: " ").map(String.init)
        guard let yearIndex = tokens.firstIndex(where: { $0.hasPrefix("year") }), yearIndex > 0 else {
            return nil
        }
        let candidate = tokens[yearIndex - 1]
        return spelledOutAges.first { $0.word == candidate }?.value
    }

    /// Age words as they're *supposed* to read. Anything within a small
    /// edit distance of one of these counts, which is what rescues the
    /// OCR-mangled variants real bottle photos actually produce.
    private static let ageWords: Set<String> = ["years", "year", "yrs", "yr", "aged", "ans", "jahre"]

    private static func isAgeWord(_ token: String) -> Bool {
        if ageWords.contains(token) { return true }
        // Only worth fuzzy-matching tokens of roughly the right shape;
        // anything shorter collides with real words far too easily.
        guard token.count >= 4, token.count <= 6 else { return false }
        return ageWords.contains { reference in
            reference.count >= 4 && DistilleryStore.levenshtein(token, reference) <= 2
        }
    }

    /// A plausible age numeral sitting within two tokens of something that
    /// looks like an age word — order-independent, so "AGED 10 YEARS",
    /// "10 AGED YEARS" and "12 YRANS" all resolve. Runs only after the
    /// strict passes fail, so a clean label is never decided by this.
    private static func fuzzyAgeMatch(in text: String) -> Int? {
        let tokens = DistilleryStore.normalize(text).split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() {
            // A bare 4-digit year ("SINCE 1887") is never an age, and
            // Int() already rejects it by range below.
            guard let value = Int(token), (3...50).contains(value) else { continue }
            let lower = max(0, index - 2)
            let upper = min(tokens.count - 1, index + 2)
            for neighbour in lower...upper where neighbour != index {
                if isAgeWord(tokens[neighbour]) { return value }
            }
        }
        return nil
    }

    private static func allMatches(
        pattern: String, options: NSRegularExpression.Options = [], in text: String
    ) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[numberRange].replacingOccurrences(of: ",", with: "."))
        }
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
