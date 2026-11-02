import Foundation

/// Selection and filtering rules for the collection, as pure functions so
/// the split-view and compact layouts agree and tests can cover them.
enum CollectionSelection {
    // MARK: - Persisted selection

    /// `@SceneStorage` holds plain strings, so the selected bottle is stored
    /// as its UUID string. Empty means no selection.
    static func id(fromStored stored: String) -> UUID? {
        UUID(uuidString: stored)
    }

    static func stored(_ id: UUID?) -> String {
        id?.uuidString ?? ""
    }

    /// The selected bottle, or nil when the selection points at a bottle
    /// that no longer exists (deleted here, or removed by a sync merge).
    static func bottle(for id: UUID?, in bottles: [Bottle]) -> Bottle? {
        guard let id else { return nil }
        return bottles.first { $0.id == id }
    }

    // MARK: - Filtering

    /// Every whitespace-separated token must match at least one of: name,
    /// distillery, region name, cask type, status. "islay sherry open"
    /// finds open Islay bottles finished in sherry casks.
    static func matches(_ bottle: Bottle, query: String) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let regionName = RegionCatalog.region(id: bottle.region)?.displayName ?? bottle.region
        let statusName = bottle.status.map { Strings.Status.label(for: $0) } ?? ""
        let fields = [bottle.name, bottle.distilleryName, regionName, bottle.caskType ?? "", statusName]
        return tokens.allSatisfy { token in
            fields.contains { $0.localizedCaseInsensitiveContains(token) }
        }
    }

    /// Search, then region filter (empty = all regions), then sort.
    static func visible(
        _ bottles: [Bottle], query: String, regionID: String, sortKey: CollectionSortKey
    ) -> [Bottle] {
        let filtered = bottles.filter { bottle in
            (regionID.isEmpty || bottle.region == regionID) && matches(bottle, query: query)
        }
        return sortKey.sorted(filtered)
    }
}
