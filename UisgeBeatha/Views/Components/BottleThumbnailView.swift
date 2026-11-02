import SwiftUI

/// Row thumbnail with the PRD's fallback chain: user photo, else stock
/// photo, else region-colored monogram.
///
/// The user photo comes from `ThumbnailCache`: a hit is read synchronously
/// in `init` (no placeholder flash while scrolling back up a long list),
/// a miss is decoded off the main actor.
struct BottleThumbnailView: View {
    let bottle: Bottle
    private let baseSize: CGFloat
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat

    @Environment(\.imageStore) private var imageStore
    @State private var userImage: UIImage?

    init(bottle: Bottle, size: CGFloat = 48) {
        self.bottle = bottle
        baseSize = size
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
        let cached = bottle.userPhotoFilename.flatMap { ThumbnailCache.shared.image(forKey: $0) }
        _userImage = State(initialValue: cached)
    }

    private var size: CGFloat { min(scaledSize, baseSize * 1.75) }

    var body: some View {
        content
            .task(id: bottle.userPhotoFilename) {
                guard let filename = bottle.userPhotoFilename else {
                    userImage = nil
                    return
                }
                userImage = await ThumbnailCache.shared.load(
                    key: filename, from: imageStore.thumbnailURL(for: filename)
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if bottle.userPhotoFilename != nil, let userImage {
            Image(uiImage: userImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
                .accessibilityHidden(true)
        } else if bottle.userPhotoFilename == nil,
                  let urlString = bottle.stockPhotoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                MonogramThumbnail(name: bottle.name, regionID: bottle.region, size: baseSize)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
        } else {
            MonogramThumbnail(name: bottle.name, regionID: bottle.region, size: baseSize)
        }
    }
}
