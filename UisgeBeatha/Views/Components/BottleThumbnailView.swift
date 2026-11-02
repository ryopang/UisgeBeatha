import SwiftUI

/// Row thumbnail with the PRD's fallback chain: the bottle's primary photo
/// (the person's own, else a downloaded stock photo), else a region-colored
/// monogram. Stock photos are stored locally, never hotlinked.
///
/// The decoded image comes from `ThumbnailCache`: a hit is read
/// synchronously in `init` (no placeholder flash while scrolling back up a
/// long list), a miss is decoded off the main actor. The cache key is the
/// photo's id, so a photo changed on another device is a new key and
/// reloads by itself.
struct BottleThumbnailView: View {
    let bottle: Bottle
    private let baseSize: CGFloat
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat

    @State private var image: UIImage?

    init(bottle: Bottle, size: CGFloat = 48) {
        self.bottle = bottle
        baseSize = size
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
        let cached = bottle.primaryPhoto.flatMap { ThumbnailCache.shared.image(forKey: $0.id.uuidString) }
        _image = State(initialValue: cached)
    }

    private var size: CGFloat { min(scaledSize, baseSize * 1.75) }

    var body: some View {
        content
            .task(id: bottle.primaryPhoto?.id) {
                guard let photo = bottle.primaryPhoto, let data = photo.thumbnailData else {
                    image = nil
                    return
                }
                image = await ThumbnailCache.shared.load(key: photo.id.uuidString, data: data)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
                .accessibilityHidden(true)
        } else {
            MonogramThumbnail(name: bottle.name, regionID: bottle.region, size: baseSize)
        }
    }
}
