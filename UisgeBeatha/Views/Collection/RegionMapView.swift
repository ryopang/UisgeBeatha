import MapKit
import SwiftData
import SwiftUI

/// Map half of the collection (PRD F4): Scotland framing with one
/// glass-material badge per region at its centroid. Centroid badges only —
/// no polygon overlays in v1.
struct RegionMapView: View {
    let bottles: [Bottle]
    /// When set (the regular-width split layout, where a sidebar list sits
    /// beside the map) tapping a badge filters that list instead of
    /// presenting a sheet, and tapping the same badge again clears it.
    var filteredRegionID: Binding<String>?

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
        // Flat, POI-free base map so region badges are the only thing
        // competing for attention.
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {}
        .overlay(alignment: .top) {
            summaryPanel
                .padding(.top, 8)
        }
        .sheet(item: $selectedRegion) { region in
            RegionBottlesSheet(
                region: region,
                bottles: bottles.filter { $0.region == region.id }
            )
        }
    }

    /// A quick "how many bottles do I own" glance — just the total, kept to
    /// one small floating pill rather than a fuller stats view.
    private var summaryPanel: some View {
        Label(Strings.Map.summary(count: bottles.count), systemImage: "wineglass")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .accessibilityElement(children: .combine)
    }

    private func select(_ region: WhiskyRegion) {
        if let filteredRegionID {
            filteredRegionID.wrappedValue = filteredRegionID.wrappedValue == region.id ? "" : region.id
        } else {
            selectedRegion = region
        }
    }

    private func badge(for region: WhiskyRegion, count: Int) -> some View {
        Button {
            select(region)
        } label: {
            VStack(spacing: 3) {
                Text("\(count)")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(minWidth: 30, minHeight: 30)
                    .background(
                        count == 0 ? AnyShapeStyle(.gray) : AnyShapeStyle(region.badgeFillColor),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(-4)
                            .opacity(filteredRegionID?.wrappedValue == region.id ? 1 : 0)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                Text(region.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thickMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .opacity(count == 0 ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.Map.badgeLabel(region: region.displayName, count: count))
        .accessibilityAddTraits(filteredRegionID?.wrappedValue == region.id ? .isSelected : [])
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
        // A sheet can't present another sheet from a view beneath it, so
        // editors opened from a detail pushed in here need their own router.
        .editorRouting()
    }
}
