import SwiftUI

/// A whisky-producing region. `Bottle.region` stores the `id`.
struct WhiskyRegion: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let country: String
    /// Accent used for tags, map badges, and placeholder monograms.
    /// Mid-tone values chosen to read against both light and dark backgrounds.
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    /// Map badge placement.
    let latitude: Double
    let longitude: Double
    let blurb: String

    var accentColor: Color {
        Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }
}

/// The single source of truth for region definitions.
///
/// Hard rule (PRD section 5): every picker, tag, map badge, and sort
/// comparator renders from this catalog. Nothing switches over region cases.
/// World-whisky expansion later means adding entries here, not editing views.
enum RegionCatalog {
    /// v1 ships exactly Scotland's six regions, in canonical display order.
    static let regions: [WhiskyRegion] = [
        WhiskyRegion(
            id: "highland",
            displayName: "Highland",
            country: "Scotland",
            colorRed: 0.357, colorGreen: 0.553, colorBlue: 0.722,
            latitude: 57.30, longitude: -4.45,
            blurb: "Scotland's largest region, from gentle heathery malts to coastal bruisers."
        ),
        WhiskyRegion(
            id: "lowland",
            displayName: "Lowland",
            country: "Scotland",
            colorRed: 0.388, colorGreen: 0.635, colorBlue: 0.294,
            latitude: 55.70, longitude: -3.80,
            blurb: "Soft, grassy, and gentle; the traditional home of triple distillation."
        ),
        WhiskyRegion(
            id: "islay",
            displayName: "Islay",
            country: "Scotland",
            colorRed: 0.333, colorGreen: 0.482, colorBlue: 0.514,
            latitude: 55.78, longitude: -6.15,
            blurb: "Peat smoke, sea spray, and medicine; the island of big flavours."
        ),
        WhiskyRegion(
            id: "speyside",
            displayName: "Speyside",
            country: "Scotland",
            colorRed: 0.820, colorGreen: 0.604, colorBlue: 0.184,
            latitude: 57.45, longitude: -3.25,
            blurb: "The densest cluster of distilleries on earth; orchard fruit and honey."
        ),
        WhiskyRegion(
            id: "islands",
            displayName: "Islands",
            country: "Scotland",
            colorRed: 0.486, colorGreen: 0.435, colorBlue: 0.690,
            latitude: 57.27, longitude: -6.22,
            blurb: "From Arran to Orkney: maritime malts as varied as the isles themselves."
        ),
        WhiskyRegion(
            id: "campbeltown",
            displayName: "Campbeltown",
            country: "Scotland",
            colorRed: 0.722, colorGreen: 0.349, colorBlue: 0.373,
            latitude: 55.43, longitude: -5.60,
            blurb: "Once the whisky capital of the world; briny, oily, and characterful."
        ),
    ]

    /// Fast lookup by region ID.
    private static let regionsByID: [String: WhiskyRegion] =
        Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })

    static func region(id: String) -> WhiskyRegion? {
        regionsByID[id]
    }

    /// Stable ordering index for sort comparators; unknown IDs sort last.
    static func sortIndex(of id: String) -> Int {
        regions.firstIndex { $0.id == id } ?? regions.count
    }
}
