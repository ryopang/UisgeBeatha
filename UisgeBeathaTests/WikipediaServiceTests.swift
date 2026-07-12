import Foundation
import Testing
@testable import UisgeBeatha

struct WikipediaServiceTests {
    @Test func parsesASummaryResponse() {
        let json = """
        {"title": "Lagavulin distillery",
         "extract": "Lagavulin distillery is a malt whisky distillery on Islay.",
         "thumbnail": {"source": "https://upload.wikimedia.org/x.jpg"},
         "content_urls": {"mobile": {"page": "https://en.m.wikipedia.org/wiki/Lagavulin_distillery"},
                          "desktop": {"page": "https://en.wikipedia.org/wiki/Lagavulin_distillery"}}}
        """
        let summary = WikipediaService.parse(Data(json.utf8))
        #expect(summary?.title == "Lagavulin distillery")
        #expect(summary?.extract.contains("Islay") == true)
        #expect(summary?.thumbnailURL == "https://upload.wikimedia.org/x.jpg")
        #expect(summary?.pageURL == "https://en.m.wikipedia.org/wiki/Lagavulin_distillery")
    }

    @Test func emptyExtractIsNoSummary() {
        let json = #"{"title": "X", "extract": ""}"#
        #expect(WikipediaService.parse(Data(json.utf8)) == nil)
    }

    @Test func summariesAreCachedByTitle() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WikiTests-\(UUID().uuidString)", isDirectory: true)
        let cache = DiskCache<WikipediaSummary>(folderName: "w", maxAge: 3600, directory: directory)
        let summary = WikipediaSummary(title: "T", extract: "E", thumbnailURL: nil, pageURL: nil)
        await cache.store(summary, forKey: "Lagavulin_distillery")
        let cached = await cache.value(forKey: "Lagavulin_distillery")
        #expect(cached == summary)
    }
}
