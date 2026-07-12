import Foundation

/// One entry of the bundled distillery seed data (Resources/distilleries.json).
/// Reference data, not SwiftData: bottles denormalize the name.
struct Distillery: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let aliases: [String]
    /// Region ID from RegionCatalog.
    let region: String
    let lat: Double
    let lon: Double
    let founded: Int
    let owner: String
    let wikipediaTitle: String

    var id: String { name }
}
