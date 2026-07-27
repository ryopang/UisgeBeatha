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
}

/// A whisky bottle in the collection.
///
/// Schema is CloudKit-forward (PRD section 5): no unique constraints,
/// every attribute optional or defaulted, relationships optional with an
/// explicit inverse. Duplicate barcode detection is a fetch, never a constraint.
@Model
final class Bottle {
    var id: UUID = UUID()
    var name: String = ""
    /// Denormalized distillery name; matched against seed data when possible.
    var distilleryName: String = ""
    /// Region ID from RegionCatalog (e.g. "islay").
    var region: String = ""
    /// Not shown in v1 UI; exists for world-whisky expansion.
    var country: String = "Scotland"
    /// EAN-13 / UPC-A digits.
    var barcode: String?
    var abv: Double?
    /// nil means NAS (no age statement).
    var ageStatement: Int?
    var caskType: String?
    var purchasePrice: Decimal?
    /// Not shown in v1 UI; exists for expansion.
    var currencyCode: String = "USD"
    var purchaseDate: Date?
    /// nil means "not filled in". A new bottle has no status until someone
    /// says otherwise — defaulting every scan to Sealed was asserting
    /// something the app had no way of knowing.
    var status: BottleStatus?
    /// 0.0 to 5.0 in 0.5 steps.
    var rating: Double?
    var stockPhotoURL: String?
    /// True when `stockPhotoURL` is a photo of the *distillery* (a
    /// Wikipedia lead image), not of this specific bottle — the UI must
    /// label it honestly rather than passing it off as a product shot.
    /// Meaningless when `stockPhotoURL` is nil or `userPhotoFilename` is set.
    var isDistilleryPhoto: Bool = false
    /// Photos live on disk via ImageStore; the database stores filenames only.
    var userPhotoFilename: String?
    var dateAdded: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TastingNote.bottle)
    var notes: [TastingNote]? = []

    init(
        name: String = "",
        distilleryName: String = "",
        region: String = "",
        country: String = "Scotland",
        barcode: String? = nil,
        abv: Double? = nil,
        ageStatement: Int? = nil,
        caskType: String? = nil,
        purchasePrice: Decimal? = nil,
        currencyCode: String = "USD",
        purchaseDate: Date? = nil,
        status: BottleStatus? = nil,
        rating: Double? = nil,
        stockPhotoURL: String? = nil,
        isDistilleryPhoto: Bool = false,
        userPhotoFilename: String? = nil,
        dateAdded: Date = .now
    ) {
        self.name = name
        self.distilleryName = distilleryName
        self.region = region
        self.country = country
        self.barcode = barcode
        self.abv = abv
        self.ageStatement = ageStatement
        self.caskType = caskType
        self.purchasePrice = purchasePrice
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.status = status
        self.rating = rating
        self.stockPhotoURL = stockPhotoURL
        self.isDistilleryPhoto = isDistilleryPhoto
        self.userPhotoFilename = userPhotoFilename
        self.dateAdded = dateAdded
        self.notes = []
    }
}
