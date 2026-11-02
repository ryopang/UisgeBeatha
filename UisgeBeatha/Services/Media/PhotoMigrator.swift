import Foundation
import OSLog
import SwiftData

/// One-time move of v1's photo files (Application Support/Photos) into
/// synced `BottlePhoto` rows.
///
/// Lossless by construction:
/// - the stored JPEGs are already downsampled, so they are copied byte for
///   byte, not re-encoded;
/// - a file is deleted only after the row holding its bytes has been saved;
/// - a bottle whose file is missing keeps nothing to migrate, and its dead
///   filename is cleared so it isn't retried forever;
/// - any failure leaves that bottle exactly as it was, to try again next launch.
@MainActor
struct PhotoMigrator {
    var store: LocalImageStore = LocalImageStore()

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "PhotoMigrator")

    /// Returns how many bottles' photos were moved.
    @discardableResult
    func migrate(in context: ModelContext) async -> Int {
        let descriptor = FetchDescriptor<Bottle>(
            predicate: #Predicate { $0.userPhotoFilename != nil }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return 0 }

        var moved = 0
        for bottle in pending {
            guard let filename = bottle.userPhotoFilename, !bottle.isDeleted else { continue }
            let imageURL = store.imageURL(for: filename)
            let thumbnailURL = store.thumbnailURL(for: filename)

            let loaded = await Task.detached(priority: .utility) { () -> (Data?, Data?) in
                (try? Data(contentsOf: imageURL), try? Data(contentsOf: thumbnailURL))
            }.value

            guard let fullData = loaded.0 else {
                // The file is gone; there is nothing left to migrate.
                bottle.userPhotoFilename = nil
                try? context.save()
                continue
            }
            let thumbnailData: Data?
            if let existing = loaded.1 {
                thumbnailData = existing
            } else {
                thumbnailData = await Task.detached(priority: .utility) {
                    try? PhotoEncoder.downsampledJPEG(from: fullData, maxPixelSize: PhotoEncoder.thumbnailPixelSize)
                }.value
            }

            let alreadyHasUserPhoto = bottle.photo(of: .user) != nil
            if !alreadyHasUserPhoto {
                let photo = BottlePhoto(
                    kind: BottlePhotoKind.user.rawValue, imageData: fullData, thumbnailData: thumbnailData
                )
                context.insert(photo)
                photo.bottle = bottle
            }
            bottle.userPhotoFilename = nil
            do {
                try context.save()
                try? store.delete(filename: filename)
                moved += 1
            } catch {
                Self.logger.error("Photo migration failed for \(bottle.name): \(error)")
                context.rollback()
            }
        }
        return moved
    }
}
