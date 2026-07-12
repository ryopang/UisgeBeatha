import SwiftUI

/// Small capsule naming a bottle's region, colored from RegionCatalog.
struct RegionTagView: View {
    let regionID: String

    var body: some View {
        if let region = RegionCatalog.region(id: regionID) {
            Text(region.displayName)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(region.accentColor)
                .background(region.accentColor.opacity(0.16), in: Capsule())
        }
    }
}

#Preview {
    VStack {
        ForEach(RegionCatalog.regions) { region in
            RegionTagView(regionID: region.id)
        }
    }
    .padding()
}
