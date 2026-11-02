import SwiftUI

/// Display-only half-step star rating. The adjustable version is
/// `RatingControl`.
struct RatingStarsView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbolName(at: index))
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.accentColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.Accessibility.rating(rating))
    }

    private func symbolName(at index: Int) -> String {
        let remainder = rating - Double(index)
        if remainder >= 1 { return "star.fill" }
        if remainder >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

#Preview {
    VStack {
        RatingStarsView(rating: 3.5)
        RatingStarsView(rating: 5)
        RatingStarsView(rating: 0.5)
    }
    .padding()
}
