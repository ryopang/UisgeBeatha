import CryptoKit
import Foundation
import OSLog

/// Small JSON-file cache with an expiry, used by the lookup cascade
/// (90 days) and the Wikipedia client (30 days). One file per key.
actor DiskCache<Value: Codable & Sendable> {
    private struct Entry: Codable {
        let value: Value
        let savedAt: Date
    }

    private let directory: URL
    private let maxAge: TimeInterval
    private let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "DiskCache")

    init(folderName: String, maxAge: TimeInterval, directory: URL? = nil) {
        self.maxAge = maxAge
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.directory = caches.appendingPathComponent(folderName, isDirectory: true)
        }
    }

    func value(forKey key: String) -> Value? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        guard Date.now.timeIntervalSince(entry.savedAt) < maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.value
    }

    func store(_ value: Value, forKey key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Entry(value: value, savedAt: .now))
            try data.write(to: fileURL(forKey: key))
        } catch {
            // A failed cache write only costs a future network call.
            logger.error("Cache write failed for \(key): \(error)")
        }
    }

    /// A hash of the key, not a character-substitution of it — collapsing
    /// every non-alphanumeric character to "_" meant "Glen Grant 12" and
    /// "Glen-Grant-12" (or any two keys differing only in punctuation)
    /// silently shared one cache file, each one clobbering the other's
    /// entry. A hash has no such collisions for distinct keys.
    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hex + ".json")
    }
}
