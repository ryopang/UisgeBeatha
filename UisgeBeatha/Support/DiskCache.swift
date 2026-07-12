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

    private func fileURL(forKey key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }
}
