import Foundation
import SwiftData

/// Downloads a stock photo once and stores it like any other photo.
///
/// Hotlinking a remote URL on every view broke offline use, rotted when
/// hosts changed, leaked the person's IP address to arbitrary retailer
/// sites, and couldn't sync. A downloaded copy fixes all four. The source
/// URL is kept only for attribution and so a failed download can be retried.
///
/// The stock photo is its own `BottlePhoto` kind, so it never replaces the
/// person's own photo; the user photo simply outranks it as the primary.
@MainActor
struct StockPhotoImporter {
    typealias Fetch = @Sendable (URL) async throws -> (data: Data, mimeType: String?)

    var fetch: Fetch = StockPhotoImporter.networkFetch

    /// Product shots are small. Anything bigger is not a bottle photo.
    static let maxBytes = 8_000_000

    static let networkFetch: Fetch = { url in
        var request = URLRequest(url: url)
        request.setValue(AppNetwork.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await AppNetwork.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return (data, http.mimeType)
    }

    /// True when a stock photo is now stored for `bottle`. Any failure
    /// (offline, not an image, too big, bottle deleted meanwhile) returns
    /// false and changes nothing.
    @discardableResult
    func importPhoto(from urlString: String, for bottle: Bottle, in context: ModelContext) async -> Bool {
        guard let url = Self.secureURL(from: urlString) else { return false }
        do {
            let (data, mimeType) = try await fetch(url)
            guard data.count <= Self.maxBytes,
                  mimeType.map({ $0.hasPrefix("image/") }) ?? true else { return false }
            let encoded = try await PhotoEncoder.encodeOffMain(data)
            // The download can take seconds; the bottle may be gone.
            guard !bottle.isDeleted, bottle.modelContext != nil else { return false }
            try BottlePhotos.store(encoded, kind: .stock, for: bottle, in: context)
            bottle.stockPhotoURL = urlString
            bottle.stockPhotoAttribution = Self.attribution(for: url)
            try context.save()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Pure helpers

    /// App Transport Security blocks plain http, and many retailer image
    /// links are http only because nobody updated them. Upgrade, and refuse
    /// anything that still isn't https.
    static func secureURL(from string: String) -> URL? {
        guard var components = URLComponents(string: string), components.host != nil else { return nil }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        guard components.scheme?.lowercased() == "https" else { return nil }
        return components.url
    }

    /// The credit line shown with a stock photo. Commons images are
    /// community-licensed and ask for attribution; a source line is shown
    /// for every host so a stock photo never passes as the person's own.
    static func attribution(for url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasSuffix("wikimedia.org") || host.hasSuffix("wikipedia.org") {
            return Strings.Detail.photoViaCommons
        }
        if host.hasSuffix("openfoodfacts.org") {
            return Strings.Detail.photoViaOpenFoodFacts
        }
        return Strings.Detail.photoVia(host)
    }
}
