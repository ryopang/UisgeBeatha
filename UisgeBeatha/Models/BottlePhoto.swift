import Foundation
import SwiftData

/// The current schema's photo model. See `SchemaV2`.
typealias BottlePhoto = SchemaV2.BottlePhoto

/// Which photo a `BottlePhoto` row is.
enum BottlePhotoKind: String, Sendable {
    /// Taken or chosen by the person. Always wins as the primary photo.
    case user
    /// Downloaded once from a lookup or search, never hotlinked.
    case stock
}
