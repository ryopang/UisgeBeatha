import Foundation

/// Computed conveniences over the stored fields. None of these are
/// persisted, so they are free to change without a schema version.
extension Bottle {
    // MARK: - Price

    /// What the person paid. Written to both `purchasePrice` (a Decimal,
    /// which CloudKit mirrors through a Double) and `priceMinorUnits` (an
    /// exact integer). Reads prefer the integer, so a price survives a
    /// sync round trip without drifting.
    var price: Decimal? {
        get {
            priceMinorUnits.map { Decimal($0) / 100 } ?? purchasePrice
        }
        set {
            purchasePrice = newValue
            priceMinorUnits = newValue.map(Self.minorUnits(from:))
        }
    }

    /// 89.99 becomes 8999. Rounds half away from zero, like a till.
    static func minorUnits(from price: Decimal) -> Int {
        var scaled = price * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    // MARK: - Photos

    /// Newest photo of a kind.
    func photo(of kind: BottlePhotoKind) -> BottlePhoto? {
        (photos ?? [])
            .filter { $0.kind == kind.rawValue }
            .max { $0.dateAdded < $1.dateAdded }
    }

    /// The photo to show: the person's own, else a downloaded stock photo.
    var primaryPhoto: BottlePhoto? {
        photo(of: .user) ?? photo(of: .stock)
    }

    // MARK: - Tasting

    /// Recomputes `lastTastedDate` from the notes. Call after any note is
    /// added, edited or deleted.
    func refreshLastTasted() {
        lastTastedDate = (notes ?? []).map(\.date).max()
    }
}
