import SwiftUI

/// One row of the collection list.
struct BottleRowView: View {
    let bottle: Bottle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BottleThumbnailView(bottle: bottle)
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name)
                    .font(.headline)
                Text(bottle.distilleryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    RegionTagView(regionID: bottle.region)
                    StatusPillView(status: bottle.status)
                    Spacer(minLength: 0)
                    if let rating = bottle.rating {
                        RatingStarsView(rating: rating)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
