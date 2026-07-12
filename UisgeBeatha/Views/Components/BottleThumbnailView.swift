import SwiftUI

/// Row thumbnail with the PRD's fallback chain: user photo, else stock
/// photo, else region-colored monogram.
struct BottleThumbnailView: View {
    let bottle: Bottle
    var size: CGFloat = 48

    @Environment(\.imageStore) private var imageStore

    var body: some View {
        if let filename = bottle.userPhotoFilename,
           let image = UIImage(contentsOfFile: imageStore.thumbnailURL(for: filename).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
                .accessibilityHidden(true)
        } else if let urlString = bottle.stockPhotoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                MonogramThumbnail(name: bottle.name, regionID: bottle.region, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
        } else {
            MonogramThumbnail(name: bottle.name, regionID: bottle.region, size: size)
        }
    }
}
