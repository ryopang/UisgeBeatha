import SwiftUI

/// Placeholder thumbnail: the bottle's initial on its region color.
/// Rows fall back to this when no user or stock photo exists.
struct MonogramThumbnail: View {
    let name: String
    let regionID: String
    var size: CGFloat = 48

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased() ?? "•"
    }

    private var color: Color {
        RegionCatalog.region(id: regionID)?.accentColor ?? .secondary
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        MonogramThumbnail(name: "Lagavulin 16", regionID: "islay")
        MonogramThumbnail(name: "Glenfarclas 105", regionID: "speyside")
        MonogramThumbnail(name: "", regionID: "unknown")
    }
    .padding()
}
