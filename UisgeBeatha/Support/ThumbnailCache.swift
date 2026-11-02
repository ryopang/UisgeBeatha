import UIKit

/// In-memory cache of decoded list thumbnails.
///
/// Rows used to call `UIImage(contentsOfFile:)` inside `body`, which puts
/// disk and decode work on the main thread every time a row appears.
/// With hundreds of bottles that shows up as scroll hitching. Rows now
/// read this cache synchronously (a hit costs nothing) and load misses off
/// the main actor.
nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    // NSCache is thread-safe, which is what makes @unchecked Sendable sound.
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        return cache
    }()

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// Cache hit, or a background decode from `url` that fills the cache.
    func load(key: String, from url: URL) async -> UIImage? {
        if let cached = image(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }.value
        if let decoded { insert(decoded, forKey: key) }
        return decoded
    }

    /// Cache hit, or a background decode of in-memory image data.
    func load(key: String, data: Data) async -> UIImage? {
        if let cached = image(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .utility) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
        if let decoded { insert(decoded, forKey: key) }
        return decoded
    }
}
