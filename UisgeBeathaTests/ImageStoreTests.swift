import Foundation
import ImageIO
import Testing
import UIKit
@testable import UisgeBeatha

/// Phase 3: photo persistence rules — downsampled JPEG + thumbnail on disk,
/// filenames only in the database, delete removes both files.
struct ImageStoreTests {
    private let store: LocalImageStore
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = LocalImageStore(directory: directory)
    }

    /// A synthetic photo larger than the 2000px storage cap.
    private func sampleImageData(width: CGFloat = 3000, height: CGFloat = 1200) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // exact pixel dimensions regardless of device scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    @Test func saveWritesDownsampledImageAndThumbnail() throws {
        let filename = try store.save(imageData: sampleImageData())

        let imageURL = store.imageURL(for: filename)
        let thumbnailURL = store.thumbnailURL(for: filename)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))

        let imageSize = try pixelSize(of: imageURL)
        #expect(max(imageSize.width, imageSize.height) <= Int(LocalImageStore.maxPixelSize))
        #expect(imageSize.width > imageSize.height, "Orientation should be preserved")

        let thumbnailSize = try pixelSize(of: thumbnailURL)
        #expect(max(thumbnailSize.width, thumbnailSize.height) <= Int(LocalImageStore.thumbnailPixelSize))
    }

    @Test func smallImagesAreNotUpscaled() throws {
        let filename = try store.save(imageData: sampleImageData(width: 800, height: 600))
        let size = try pixelSize(of: store.imageURL(for: filename))
        #expect(size.width <= 800)
    }

    @Test func deleteRemovesImageAndThumbnail() throws {
        let filename = try store.save(imageData: sampleImageData())
        try store.delete(filename: filename)
        #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: filename).path))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(for: filename).path))
    }

    @Test func deleteOfMissingFileDoesNotThrow() throws {
        try store.delete(filename: "never-existed.jpg")
    }

    @Test func garbageDataThrowsInsteadOfWritingFiles() {
        #expect(throws: (any Error).self) {
            _ = try store.save(imageData: Data("not an image".utf8))
        }
    }

    @Test func filenamesAreUniquePerSave() throws {
        let data = try sampleImageData(width: 400, height: 400)
        let first = try store.save(imageData: data)
        let second = try store.save(imageData: data)
        #expect(first != second)
    }
}
