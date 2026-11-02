import Foundation
import Testing
import UIKit
@testable import UisgeBeatha

/// Phase 1: list thumbnails are cached in memory and decoded off-main.
struct ThumbnailCacheTests {
    private func sampleJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test func missThenHit() async throws {
        let cache = ThumbnailCache()
        let key = "thumb-\(UUID().uuidString)"
        #expect(cache.image(forKey: key) == nil)

        let loaded = await cache.load(key: key, data: try sampleJPEG())
        #expect(loaded != nil)
        #expect(cache.image(forKey: key) != nil)
    }

    @Test func loadFromFileFillsTheCache() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).jpg")
        try sampleJPEG().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = ThumbnailCache()
        let loaded = await cache.load(key: "file-key", from: url)
        #expect(loaded != nil)
        #expect(cache.image(forKey: "file-key") != nil)
    }

    @Test func missingFileLoadsNothingAndCachesNothing() async {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/definitely/not/here.jpg")
        let loaded = await cache.load(key: "missing", from: url)
        #expect(loaded == nil)
        #expect(cache.image(forKey: "missing") == nil)
    }

    @Test func removeEvictsOneEntry() async throws {
        let cache = ThumbnailCache()
        let data = try sampleJPEG()
        _ = await cache.load(key: "a", data: data)
        _ = await cache.load(key: "b", data: data)
        cache.removeImage(forKey: "a")
        #expect(cache.image(forKey: "a") == nil)
        #expect(cache.image(forKey: "b") != nil)
    }
}
