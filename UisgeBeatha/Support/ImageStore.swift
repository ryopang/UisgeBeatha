import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// All photo persistence goes through this protocol (PRD section 10.1).
/// v1 ships LocalImageStore; a synced implementation can replace it later
/// without touching any view.
protocol ImageStore: Sendable {
    /// Downsamples and stores image data as JPEG plus a thumbnail.
    /// Returns the filename to keep in SwiftData.
    func save(imageData: Data) throws -> String
    func imageURL(for filename: String) -> URL
    func thumbnailURL(for filename: String) -> URL
    /// Removes both the full image and its thumbnail.
    func delete(filename: String) throws
}

/// Files on disk in Application Support/Photos. The database stores
/// filenames only, keeping SwiftData fast and exports small.
struct LocalImageStore: ImageStore {
    enum ImageStoreError: Error {
        case unreadableImage
        case encodingFailed
    }

    /// Max long edge for stored photos (PRD section 5).
    static let maxPixelSize: CGFloat = 2000
    static let thumbnailPixelSize: CGFloat = 300
    static let jpegQuality: Double = 0.8

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

    func save(imageData: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".jpg"
        try downsampledJPEG(from: imageData, maxPixelSize: Self.maxPixelSize)
            .write(to: imageURL(for: filename))
        try downsampledJPEG(from: imageData, maxPixelSize: Self.thumbnailPixelSize)
            .write(to: thumbnailURL(for: filename))
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

    /// ImageIO downsampling: decodes at target size instead of loading the
    /// full image into memory. Never upscales.
    private func downsampledJPEG(from data: Data, maxPixelSize: CGFloat) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageStoreError.unreadableImage
        }
        // ImageIO happily upscales to MaxPixelSize; clamp to the source's
        // own long edge so small images pass through untouched.
        var targetSize = maxPixelSize
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            targetSize = min(maxPixelSize, max(width, height))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageStoreError.unreadableImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ImageStoreError.encodingFailed
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageStoreError.encodingFailed
        }
        return output as Data
    }
}

extension EnvironmentValues {
    @Entry var imageStore: any ImageStore = LocalImageStore()
}
