import CoreData
import Foundation
import SwiftData

/// Housekeeping that keeps a synced collection tidy: finishing the v1 photo
/// migration, filling derived fields, merging duplicates and retrying
/// stock photo downloads that failed.
///
/// Everything here is safe to run repeatedly and in any order, and nothing
/// blocks the UI: the heavy parts (file reads, image encoding, network)
/// happen off the main actor, and only small saves touch the main context.
@MainActor
final class StoreMaintenance {
    private let importer: StockPhotoImporter
    private var dedupeTask: Task<Void, Never>?
    private var remoteChangeTask: Task<Void, Never>?
    private let defaults: UserDefaults

    private static let attemptsKey = "stockPhotoImportAttempts"
    /// Don't hammer a host that refused: one retry a day per bottle.
    static let retryInterval: TimeInterval = 24 * 60 * 60
    static let maxImportsPerRun = 20

    init(importer: StockPhotoImporter = StockPhotoImporter(), defaults: UserDefaults = .standard) {
        self.importer = importer
        self.defaults = defaults
    }

    /// The full pass, run at launch.
    func runAll(in context: ModelContext, photoMigrator: PhotoMigrator = PhotoMigrator()) async {
        await photoMigrator.migrate(in: context)
        Self.backfillDerivedFields(in: context)
        _ = try? BottleDeduplicator.mergeDuplicates(in: context)
        await retryStockPhotoImports(in: context)
    }

    // MARK: - Derived fields

    /// `priceMinorUnits` and `lastTastedDate` are new in V2. Bottles saved
    /// by v1 have neither, so fill them from the fields they derive from.
    @discardableResult
    static func backfillDerivedFields(in context: ModelContext) -> Int {
        guard let bottles = try? context.fetch(FetchDescriptor<Bottle>()) else { return 0 }
        var changed = 0
        for bottle in bottles {
            var touched = false
            if bottle.priceMinorUnits == nil, let price = bottle.purchasePrice {
                bottle.priceMinorUnits = Bottle.minorUnits(from: price)
                touched = true
            }
            if bottle.lastTastedDate == nil, let latest = (bottle.notes ?? []).map(\.date).max() {
                bottle.lastTastedDate = latest
                touched = true
            }
            if touched { changed += 1 }
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    // MARK: - Stock photos

    /// Bottles that remember a stock photo URL but hold no photo at all
    /// (a v1 bottle, or a download that failed) get one downloaded.
    func retryStockPhotoImports(in context: ModelContext, now: Date = .now) async {
        guard let bottles = try? context.fetch(FetchDescriptor<Bottle>()) else { return }
        var attempts = defaults.dictionary(forKey: Self.attemptsKey) as? [String: Date] ?? [:]
        var started = 0

        for bottle in bottles where Self.needsStockPhoto(bottle) {
            guard started < Self.maxImportsPerRun, let urlString = bottle.stockPhotoURL else { break }
            let key = bottle.id.uuidString
            if let last = attempts[key], now.timeIntervalSince(last) < Self.retryInterval { continue }
            attempts[key] = now
            started += 1
            await importer.importPhoto(from: urlString, for: bottle, in: context)
        }
        defaults.set(attempts, forKey: Self.attemptsKey)
    }

    static func needsStockPhoto(_ bottle: Bottle) -> Bool {
        guard let url = bottle.stockPhotoURL, !url.isEmpty, !bottle.isDeleted else { return false }
        return (bottle.photos ?? []).isEmpty
    }

    // MARK: - Remote changes

    /// Merges duplicates shortly after the store reports remote changes
    /// (and when the app returns to the foreground). Debounced, so a burst
    /// of sync activity causes one pass.
    func scheduleDedupe(in context: ModelContext, delay: Duration = .seconds(1)) {
        dedupeTask?.cancel()
        dedupeTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            _ = try? BottleDeduplicator.mergeDuplicates(in: context)
        }
    }

    func observeRemoteChanges(in context: ModelContext) {
        guard remoteChangeTask == nil else { return }
        remoteChangeTask = Task {
            for await _ in NotificationSignal.stream(for: .NSPersistentStoreRemoteChange) {
                self.scheduleDedupe(in: context)
            }
        }
    }
}
