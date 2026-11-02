import Foundation

/// Sort keys for the collection list. The last choice persists via AppStorage.
enum CollectionSortKey: String, CaseIterable {
    case name
    case distillery
    case region
    case lastTasted

    var label: String {
        switch self {
        case .name: Strings.Collection.sortByName
        case .distillery: Strings.Collection.sortByDistillery
        case .region: Strings.Collection.sortByRegion
        case .lastTasted: Strings.Collection.sortByLastTasted
        }
    }

    /// Region order comes from RegionCatalog, never from the raw strings.
    func sorted(_ bottles: [Bottle]) -> [Bottle] {
        switch self {
        case .name:
            bottles.sorted { byName($0, $1) }
        case .distillery:
            bottles.sorted {
                let comparison = $0.distilleryName.localizedCaseInsensitiveCompare($1.distilleryName)
                return comparison == .orderedSame ? byName($0, $1) : comparison == .orderedAscending
            }
        case .region:
            bottles.sorted {
                let lhs = RegionCatalog.sortIndex(of: $0.region)
                let rhs = RegionCatalog.sortIndex(of: $1.region)
                return lhs == rhs ? byName($0, $1) : lhs < rhs
            }
        case .lastTasted:
            // Most recently tasted first; never-tasted bottles last, by name.
            bottles.sorted {
                switch ($0.lastTastedDate, $1.lastTastedDate) {
                case let (lhs?, rhs?): lhs == rhs ? byName($0, $1) : lhs > rhs
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): byName($0, $1)
                }
            }
        }
    }

    private func byName(_ lhs: Bottle, _ rhs: Bottle) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
