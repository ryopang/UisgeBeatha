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

    /// The region's base hue, for fills and tints (the 16% capsule behind
    /// a tag, the monogram tile). Not for text: measured against its own
    /// tint on a light background, every region fell short of WCAG AA,
    /// Speyside badly (about 2:1).
    var accentColor: Color {
        Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }

    /// Text and glyphs drawn in the region color over its own tint:
    /// darkened 40% in light mode and lightened 25% in dark mode, which
    /// puts all six regions at 4.8:1 or better (WCAG AA) in both. Plain
    /// values are captured so the dynamic provider touches no
    /// actor-isolated state.
    var textColor: Color {
        let (red, green, blue) = (colorRed, colorGreen, colorBlue)
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(
                    red: red + (1 - red) * 0.25,
                    green: green + (1 - green) * 0.25,
                    blue: blue + (1 - blue) * 0.25,
                    alpha: 1
                )
            }
            return UIColor(red: red * 0.6, green: green * 0.6, blue: blue * 0.6, alpha: 1)
        })
    }

    /// A solid fill behind white text (the map's count badges). Darkened in
    /// both modes so white digits stay at 6:1 or better; the base hue
    /// left Speyside at 2.5:1.
    var badgeFillColor: Color {
        Color(red: colorRed * 0.6, green: colorGreen * 0.6, blue: colorBlue * 0.6)
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
