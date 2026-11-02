import Foundation
import SwiftData

/// Merges bottles that sync (or two offline devices) left duplicated.
///
/// Duplicate detection is a fetch, never a unique constraint, because
/// CloudKit mirroring doesn't support constraints. Two devices adding the
/// same barcode while offline therefore both succeed locally, and this
/// reconciles them once they meet.
///
/// Every device runs the same rule and picks the same survivor (oldest
/// `dateAdded`, ties broken by id), so concurrent merges converge instead
/// of fighting. Notes and photos are re-parented, never copied, so nothing
/// is duplicated or lost.
@MainActor
enum BottleDeduplicator {
    /// Returns how many duplicate bottles were merged away.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> Int {
        let bottles = try context.fetch(FetchDescriptor<Bottle>())
        return try mergeDuplicates(among: bottles, in: context)
    }

    @discardableResult
    static func mergeDuplicates(among bottles: [Bottle], in context: ModelContext) throws -> Int {
        var groups: [String: [Bottle]] = [:]
        for bottle in bottles {
            // Canonical form, so a legacy 12-digit UPC-A and its 13-digit
            // EAN are recognised as the same bottle.
            guard let raw = bottle.barcode, let key = Barcode.normalized(raw) else { continue }
            groups[key, default: []].append(bottle)
        }

        var removed = 0
        for (key, group) in groups where group.count > 1 {
            let ordered = group.sorted { lhs, rhs in
                lhs.dateAdded == rhs.dateAdded
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.dateAdded < rhs.dateAdded
            }
            let survivor = ordered[0]
            for duplicate in ordered.dropFirst() {
                absorb(duplicate, into: survivor, context: context)
                context.delete(duplicate)
                removed += 1
            }
            survivor.barcode = key
            keepNewestPhotoOfEachKind(on: survivor, context: context)
            survivor.refreshLastTasted()
        }
        if removed > 0 {
            try context.save()
        }
        return removed
    }

    /// Moves everything worth keeping from `duplicate` onto `survivor`.
    /// The survivor's own values win; gaps are filled from the duplicate.
    private static func absorb(_ duplicate: Bottle, into survivor: Bottle, context: ModelContext) {
        for note in Array(duplicate.notes ?? []) {
            note.bottle = survivor
        }
        for photo in Array(duplicate.photos ?? []) {
            photo.bottle = survivor
        }

        if survivor.abv == nil { survivor.abv = duplicate.abv }
        if survivor.ageStatement == nil { survivor.ageStatement = duplicate.ageStatement }
        if (survivor.caskType ?? "").isEmpty { survivor.caskType = duplicate.caskType }
        if survivor.price == nil, let price = duplicate.price {
            survivor.price = price
            survivor.currencyCode = duplicate.currencyCode
        }
        if survivor.purchaseDate == nil { survivor.purchaseDate = duplicate.purchaseDate }
        if survivor.status == nil { survivor.status = duplicate.status }
        if survivor.rating == nil { survivor.rating = duplicate.rating }
        if survivor.stockPhotoURL == nil {
            survivor.stockPhotoURL = duplicate.stockPhotoURL
            survivor.stockPhotoAttribution = duplicate.stockPhotoAttribution
            survivor.isDistilleryPhoto = duplicate.isDistilleryPhoto
        }
    }

    /// One photo per kind in v2. After a merge the survivor can hold two
    /// "user" photos; keep the newest and drop the rest.
    private static func keepNewestPhotoOfEachKind(on bottle: Bottle, context: ModelContext) {
        let byKind = Dictionary(grouping: bottle.photos ?? [], by: \.kind)
        for photos in byKind.values where photos.count > 1 {
            let newest = photos.max { $0.dateAdded < $1.dateAdded }
            for photo in photos where photo !== newest {
                context.delete(photo)
            }
        }
    }
}
