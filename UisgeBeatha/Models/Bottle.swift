import Foundation
import SwiftData

/// Lifecycle of a bottle in the collection.
enum BottleStatus: String, Codable, CaseIterable, Sendable {
    case sealed
    case open
    case finished

    /// The status a bottle moves to when cycled (sealed → open → finished → sealed).
    var next: BottleStatus {
        switch self {
        case .sealed: .open
        case .open: .finished
        case .finished: .sealed
        }
    }

    /// Cycling from an unset status starts at sealed. Deliberately never
    /// cycles *back* to unset — a stray extra tap shouldn't silently blank
    /// a status; clearing is done explicitly in the edit form's picker.
    static func next(after status: BottleStatus?) -> BottleStatus {
        status?.next ?? .sealed
    }

    /// The glyph shown next to the status.
    var symbolName: String {
        switch self {
        case .sealed: "lock.fill"
        case .open: "lock.open.fill"
        case .finished: "checkmark.circle.fill"
        }
    }
}

/// The current schema's bottle model. Views and services use this name;
/// only the schema files know which `SchemaV<N>` it points at.
typealias Bottle = SchemaV2.Bottle
