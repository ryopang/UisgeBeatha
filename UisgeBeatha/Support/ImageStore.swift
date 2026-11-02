import Foundation
import SwiftUI

/// All photo persistence goes through this protocol (PRD section 10.1).
/// `LocalImageStore` keeps files on disk. In v2 it is the source of the
/// one-time migration into synced `BottlePhoto` rows, and still the
/// store behind tests and any non-synced configuration.
///
/// `save` is `async` and runs off the main actor: downsampling a 12 MP
/// capture is too heavy for the UI thread.
nonisolated protocol ImageStore: Sendable {
    /// Downsamples and stores image data as JPEG plus a thumbnail.
    /// Returns the filename to keep in SwiftData.
    func save(imageData: Data) async throws -> String
    func imageURL(for filename: String) -> URL
    func thumbnailURL(for filename: String) -> URL
    /// Removes both the full image and its thumbnail.
    func delete(filename: String) throws
}

/// Files on disk in Application Support/Photos. The database stores
/// filenames only, keeping SwiftData fast and exports small.
nonisolated struct LocalImageStore: ImageStore {
    typealias ImageStoreError = PhotoEncoder.EncodingError

    static let maxPixelSize = PhotoEncoder.maxPixelSize
    static let thumbnailPixelSize = PhotoEncoder.thumbnailPixelSize
    static let jpegQuality = PhotoEncoder.jpegQuality

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.directory = support.appendingPathComponent("Photos", isDirectory: true)
        }
    }

    func save(imageData: Data) async throws -> String {
        let encoded = try await PhotoEncoder.encodeOffMain(imageData)
        return try write(encoded)
    }

    /// Small, local file writes; the heavy encode already happened off-main.
    private func write(_ encoded: EncodedPhoto) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".jpg"
        try encoded.full.write(to: imageURL(for: filename), options: .atomic)
        try encoded.thumbnail.write(to: thumbnailURL(for: filename), options: .atomic)
        return filename
    }

    func imageURL(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    func thumbnailURL(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        return directory.appendingPathComponent(base + "-thumb.jpg")
    }

    func delete(filename: String) throws {
        let fileManager = FileManager.default
        for url in [imageURL(for: filename), thumbnailURL(for: filename)]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

extension EnvironmentValues {
    @Entry var imageStore: any ImageStore = LocalImageStore()
}
