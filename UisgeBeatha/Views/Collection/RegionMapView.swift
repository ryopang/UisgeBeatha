import MapKit
import SwiftData
import SwiftUI

/// Map half of the collection (PRD F4): Scotland framing with one
/// glass-material badge per region at its centroid. Centroid badges only —
/// no polygon overlays in v1.
struct RegionMapView: View {
    let bottles: [Bottle]

    @State private var selectedRegion: WhiskyRegion?

    /// Roughly center 57.2N, -4.5W, span covering Campbeltown to Orkney.
    private static let scotland = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 57.2, longitude: -4.5),
        span: MKCoordinateSpan(latitudeDelta: 4.9, longitudeDelta: 7.0)
    )

    private var countsByRegion: [String: Int] {
        bottles.reduce(into: [:]) { counts, bottle in
            counts[bottle.region, default: 0] += 1
        }
    }

    var body: some View {
        Map(initialPosition: .region(Self.scotland), interactionModes: [.pan, .zoom]) {
            ForEach(RegionCatalog.regions) { region in
                Annotation(
                    region.displayName,
                    coordinate: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude)
                ) {
                    badge(for: region, count: countsByRegion[region.id] ?? 0)
                }
                .annotationTitles(.hidden)
            }
        }
        .sheet(item: $selectedRegion) { region in
            RegionBottlesSheet(
                region: region,
                bottles: bottles.filter { $0.region == region.id }
            )
        }
    }

    private func badge(for region: WhiskyRegion, count: Int) -> some View {
        Button {
            selectedRegion = region
        } label: {
            VStack(spacing: 2) {
                Text(region.displayName)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(count == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(region.accentColor))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(region.accentColor.opacity(count == 0 ? 0.2 : 0.6), lineWidth: 1)
            )
            .opacity(count == 0 ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.Map.badgeLabel(region: region.displayName, count: count))
        .accessibilityIdentifier("region-badge-\(region.id)")
    }
}

/// The bottles of one region, presented from a map badge. Rows push the
/// bottle detail.
private struct RegionBottlesSheet: View {
    let region: WhiskyRegion
    let bottles: [Bottle]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bottles.isEmpty {
                    ContentUnavailableView {
                        Label(Strings.Map.emptyRegionTitle, systemImage: "wineglass")
                    } description: {
                        Text(Strings.Map.emptyRegionMessage(region: region.displayName))
                    }
                } else {
                    List(CollectionSortKey.name.sorted(bottles)) { bottle in
                        NavigationLink {
                            BottleDetailView(bottle: bottle)
                        } label: {
                            BottleRowView(bottle: bottle)
                        }
                    }
                }
            }
            .navigationTitle(region.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Wheel.done) { dismiss() }
                }
            }
        }
    }
}
