import Foundation
import OSLog
import SwiftUI

nonisolated struct WikipediaSummary: Codable, Sendable, Equatable {
    let title: String
    let extract: String
    let thumbnailURL: String?
    let pageURL: String?
}

/// Distillery summary client (PRD F6), behind a protocol per PRD 10.1.
protocol WikipediaServicing: Sendable {
    /// Tries candidate titles in order (seed title, "{name}_distillery",
    /// "{name}"); nil when nothing resolves. Failures are quiet — callers
    /// fall back to seed facts, never an error banner.
    func summary(forTitles titles: [String]) async -> WikipediaSummary?
}

struct WikipediaService: WikipediaServicing {
    var session: URLSession = .shared
    let cache: DiskCache<WikipediaSummary>

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "Wikipedia")

    init(cache: DiskCache<WikipediaSummary> = DiskCache(folderName: "WikipediaCache", maxAge: 30 * 24 * 3600)) {
        self.cache = cache
    }

    func summary(forTitles titles: [String]) async -> WikipediaSummary? {
        for title in titles {
            if let cached = await cache.value(forKey: title) {
                return cached
            }
        }
        for title in titles {
            do {
                if let summary = try await fetch(title: title) {
                    await cache.store(summary, forKey: title)
                    return summary
                }
            } catch {
                // Offline or flaky network: quiet degradation to seed facts.
                Self.logger.notice("Wikipedia fetch failed for \(title): \(error)")
            }
        }
        return nil
    }

    private func fetch(title: String) async throws -> WikipediaSummary? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowedCharacters) ?? title
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("UisgeBeatha/1.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Self.parse(data)
    }

    /// Exposed for tests.
    static func parse(_ data: Data) -> WikipediaSummary? {
        struct Response: Decodable {
            struct Thumbnail: Decodable { let source: String? }
            struct ContentURLs: Decodable {
                struct Page: Decodable { let page: String? }
                let mobile: Page?
                let desktop: Page?
            }
            let title: String?
            let extract: String?
            let thumbnail: Thumbnail?
            let contentUrls: ContentURLs?

            enum CodingKeys: String, CodingKey {
                case title, extract, thumbnail
                case contentUrls = "content_urls"
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let title = response.title,
              let extract = response.extract, !extract.isEmpty else {
            return nil
        }
        return WikipediaSummary(
            title: title,
            extract: extract,
            thumbnailURL: response.thumbnail?.source,
            pageURL: response.contentUrls?.mobile?.page ?? response.contentUrls?.desktop?.page
        )
    }
}

private extension CharacterSet {
    static let urlPathAllowedCharacters = CharacterSet.urlPathAllowed
}

extension EnvironmentValues {
    @Entry var wikipedia: any WikipediaServicing = WikipediaService()
}

#if DEBUG
/// Canned summary so the UI driver can assert the distillery card offline.
struct StubWikipediaService: WikipediaServicing {
    func summary(forTitles titles: [String]) async -> WikipediaSummary? {
        WikipediaSummary(
            title: titles.first ?? "Distillery",
            extract: "A stub distillery summary for UI testing: founded on the shore of a peaty loch.",
            thumbnailURL: nil,
            pageURL: "https://en.wikipedia.org/wiki/Lagavulin_distillery"
        )
    }
}
#endif
