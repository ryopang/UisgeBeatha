import Foundation

/// Sort keys for the collection list. The last choice persists via AppStorage.
enum CollectionSortKey: String, CaseIterable {
    case name
    case distillery
    case region

    var label: String {
        switch self {
        case .name: Strings.Collection.sortByName
        case .distillery: Strings.Collection.sortByDistillery
        case .region: Strings.Collection.sortByRegion
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
        }
    }

    private func byName(_ lhs: Bottle, _ rhs: Bottle) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
