import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A photo ready to store: a downsampled full image plus a thumbnail, both
/// JPEG. Shared by every `ImageStore` implementation so the file-backed
/// store and the synced store produce identical bytes.
nonisolated struct EncodedPhoto: Sendable, Equatable {
    var full: Data
    var thumbnail: Data
}

/// Pure ImageIO work, with no actor state, so it can run anywhere. Use
/// `encodeOffMain` from UI code: a 12 MP capture takes two decode-and-encode
/// passes, which is a visible hitch on the main thread.
nonisolated enum PhotoEncoder {
    enum EncodingError: Error {
        case unreadableImage
        case encodingFailed
    }

    /// Max long edge for stored photos (PRD section 5).
    static let maxPixelSize: CGFloat = 2000
    static let thumbnailPixelSize: CGFloat = 300
    static let jpegQuality: Double = 0.8

    static func encode(_ data: Data) throws -> EncodedPhoto {
        EncodedPhoto(
            full: try downsampledJPEG(from: data, maxPixelSize: maxPixelSize),
            thumbnail: try downsampledJPEG(from: data, maxPixelSize: thumbnailPixelSize)
        )
    }

    /// Runs `encode` on a background thread regardless of the caller's
    /// isolation. `Task.detached` rather than relying on a `nonisolated
    /// async` function's inherited executor, which differs by build setting.
    static func encodeOffMain(_ data: Data) async throws -> EncodedPhoto {
        try await Task.detached(priority: .userInitiated) {
            try encode(data)
        }.value
    }

    /// JPEG-encodes a camera frame off the main actor, so handing a
    /// full-resolution capture to `encode` doesn't hitch the UI.
    static func jpegDataOffMain(from image: UIImage, quality: CGFloat = 0.9) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: quality)
        }.value
    }

    /// ImageIO downsampling: decodes at target size instead of loading the
    /// full image into memory. Never upscales.
    static func downsampledJPEG(from data: Data, maxPixelSize: CGFloat) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw EncodingError.unreadableImage
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
            throw EncodingError.unreadableImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw EncodingError.encodingFailed
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.encodingFailed
        }
        return output as Data
    }
}
