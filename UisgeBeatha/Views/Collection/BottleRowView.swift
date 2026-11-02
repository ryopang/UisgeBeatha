import SwiftUI

/// One row of the collection list.
struct BottleRowView: View {
    let bottle: Bottle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At an accessibility Dynamic Type size, the name alone can run to
    /// two or three lines — a truncated distillery name squeezed against a
    /// region pill on the same line (the compact layout below) wraps
    /// awkwardly and reads badly at that scale, measured on-device via the
    /// simulator's accessibility XXXL setting. Stacking everything
    /// vertically instead gives each element room to actually be legible.
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BottleThumbnailView(bottle: bottle)
                .modifier(ZoomSource(id: bottle.id))
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name)
                    .font(.headline)
                if isAccessibilitySize {
                    Text(bottle.distilleryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    RegionTagView(regionID: bottle.region)
                    if let rating = bottle.rating {
                        RatingStarsView(rating: rating)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(bottle.distilleryName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // Inline with the distillery line rather than its
                        // own row — a single small tag stranded alone on a
                        // full line reads as wasted space at this scale.
                        // Status (sealed/open/finished) isn't shown here at
                        // all; it's one tap away in the detail view and a
                        // swipe action from this row.
                        RegionTagView(regionID: bottle.region)
                    }
                }
            }
            Spacer(minLength: 0)
            if !isAccessibilitySize, let rating = bottle.rating {
                RatingStarsView(rating: rating)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
