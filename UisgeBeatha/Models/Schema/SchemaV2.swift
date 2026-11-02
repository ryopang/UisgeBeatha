import Foundation
import SwiftData

/// Schema version 2 (app 2.0): adds synced photos and a few denormalized
/// or attribution fields.
///
/// - `BottlePhoto` (new entity): photo bytes in external storage, so they
///   sync through CloudKit as assets. Replaces files on disk.
/// - `Bottle.photos`, `stockPhotoAttribution`, `lastTastedDate` and
///   `priceMinorUnits`: all optional, so the V1 to V2 migration is
///   lightweight.
/// - `Bottle.userPhotoFilename` is deprecated. It stays so existing files
///   can be moved into `BottlePhoto` rows after the migration.
///
/// Same CloudKit rules as V1: no unique constraints, every attribute
/// optional or defaulted, relationships optional with explicit inverses.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Bottle.self, TastingNote.self, BottlePhoto.self]
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
        /// Where the stock photo came from. The image itself lives in a
        /// `BottlePhoto` of kind "stock"; this is kept for attribution and
        /// so a failed download can be retried.
        var stockPhotoURL: String?
        /// "Photo via Wikimedia Commons" and the like, shown with a stock photo.
        var stockPhotoAttribution: String?
        /// True when `stockPhotoURL` is a photo of the *distillery* (a
        /// Wikipedia lead image), not of this specific bottle — the UI must
        /// label it honestly rather than passing it off as a product shot.
        /// Meaningless when `stockPhotoURL` is nil or `userPhotoFilename` is set.
        var isDistilleryPhoto: Bool = false
        /// Photos live on disk via ImageStore; the database stores filenames only.
        /// Deprecated in V2: photos are `BottlePhoto` rows now. Kept so
        /// the one-time migrator can find and move existing files.
        var userPhotoFilename: String?
        var dateAdded: Date = Date.now
        /// Newest tasting note's date. Denormalized so lists can sort and
        /// search on it without loading every note.
        var lastTastedDate: Date?
        /// Price in the currency's minor units (cents). `purchasePrice`
        /// is a Decimal, which CloudKit mirrors through a Double; this
        /// integer is exact. `Bottle.price` reads and writes both.
        var priceMinorUnits: Int?

        @Relationship(deleteRule: .cascade, inverse: \TastingNote.bottle)
        var notes: [TastingNote]? = []

        @Relationship(deleteRule: .cascade, inverse: \BottlePhoto.bottle)
        var photos: [BottlePhoto]? = []

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
            dateAdded: Date = .now,
            stockPhotoAttribution: String? = nil,
            lastTastedDate: Date? = nil,
            priceMinorUnits: Int? = nil
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
            self.stockPhotoAttribution = stockPhotoAttribution
            self.lastTastedDate = lastTastedDate
            self.priceMinorUnits = priceMinorUnits
            self.notes = []
            self.photos = []
        }
    }

    /// A dated tasting note. One bottle can accumulate many over time.
    ///
    /// CloudKit-forward: all attributes defaulted, the back-reference to the
    /// bottle is optional. The inverse is declared on `Bottle.notes`.
    @Model
    final class TastingNote {
        var id: UUID = UUID()
        var date: Date = Date.now
        var nose: String = ""
        var palate: String = ""
        var finish: String = ""
        var conclusion: String = ""

        var bottle: Bottle?

        init(
            date: Date = .now,
            nose: String = "",
            palate: String = "",
            finish: String = "",
            conclusion: String = ""
        ) {
            self.date = date
            self.nose = nose
            self.palate = palate
            self.finish = finish
            self.conclusion = conclusion
        }
    }

    /// A photo of a bottle. Bytes live in external storage so they sync as
    /// CloudKit assets and never bloat the main store.
    ///
    /// One per kind in v2 (the person's own photo, and a downloaded stock
    /// photo); the primary photo is the newest "user" photo, else the
    /// newest "stock" one. The model allows a gallery later.
    @Model
    final class BottlePhoto {
        var id: UUID = UUID()
        /// "user" or "stock". A string, not an enum, for CloudKit friendliness.
        var kind: String = "user"
        @Attribute(.externalStorage) var imageData: Data?
        @Attribute(.externalStorage) var thumbnailData: Data?
        var dateAdded: Date = Date.now

        var bottle: Bottle?

        init(
            kind: String = "user",
            imageData: Data? = nil,
            thumbnailData: Data? = nil,
            dateAdded: Date = .now
        ) {
            self.kind = kind
            self.imageData = imageData
            self.thumbnailData = thumbnailData
            self.dateAdded = dateAdded
        }
    }
}
