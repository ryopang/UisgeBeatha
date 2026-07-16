import SwiftUI

/// One row of the collection list.
struct BottleRowView: View {
    let bottle: Bottle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BottleThumbnailView(bottle: bottle)
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(bottle.distilleryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // Inline with the distillery line rather than its own
                    // row — a single small tag stranded alone on a full
                    // line reads as wasted space. Status (sealed/open/
                    // finished) isn't shown here at all; it's one tap away
                    // in the detail view and a swipe action from this row.
                    RegionTagView(regionID: bottle.region)
                }
            }
            Spacer(minLength: 0)
            if let rating = bottle.rating {
                RatingStarsView(rating: rating)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
