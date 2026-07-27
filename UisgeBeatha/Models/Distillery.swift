import Foundation

/// One entry of the bundled distillery seed data (Resources/distilleries.json).
/// Reference data, not SwiftData: bottles denormalize the name.
/// `nonisolated`: pure value data referenced from off-main-actor contexts
/// (LabelScanResult, the label-scan parsing pipeline) — without this its
/// Equatable/Hashable conformance is implicitly main-actor-isolated by the
/// project's default isolation, which those contexts can't use.
nonisolated struct Distillery: Codable, Identifiable, Hashable, Sendable {
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
