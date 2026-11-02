import Foundation
import SwiftData

/// Reads and writes a bottle's photos as `BottlePhoto` rows.
///
/// Photo bytes live in the model (external storage) so they sync with the
/// rest of the collection. Encoding happens off the main actor; only the
/// final insert touches the context.
@MainActor
enum BottlePhotos {
    /// Encodes `data` and stores it as the bottle's photo of `kind`,
    /// replacing any existing one of that kind. The old row is deleted only
    /// after the new one is built, so a failed encode keeps the old photo.
    @discardableResult
    static func set(
        _ data: Data, kind: BottlePhotoKind, for bottle: Bottle, in context: ModelContext
    ) async throws -> BottlePhoto {
        let encoded = try await PhotoEncoder.encodeOffMain(data)
        return try store(encoded, kind: kind, for: bottle, in: context)
    }

    /// The synchronous half of `set`, for callers that have already
    /// encoded. Also what tests use.
    @discardableResult
    static func store(
        _ encoded: EncodedPhoto, kind: BottlePhotoKind, for bottle: Bottle, in context: ModelContext
    ) throws -> BottlePhoto {
        // The encode can take a moment; the bottle may have been deleted.
        guard !bottle.isDeleted, bottle.modelContext != nil else {
            throw PhotoError.bottleGone
        }
        let photo = BottlePhoto(
            kind: kind.rawValue, imageData: encoded.full, thumbnailData: encoded.thumbnail
        )
        context.insert(photo)
        for existing in bottle.photos ?? [] where existing.kind == kind.rawValue {
            context.delete(existing)
        }
        photo.bottle = bottle
        try context.save()
        return photo
    }

    /// Removes every photo of `kind`. Other kinds take over as primary.
    static func remove(_ kind: BottlePhotoKind, from bottle: Bottle, in context: ModelContext) throws {
        for photo in bottle.photos ?? [] where photo.kind == kind.rawValue {
            context.delete(photo)
        }
        try context.save()
    }

    enum PhotoError: Error {
        case bottleGone
    }
}
