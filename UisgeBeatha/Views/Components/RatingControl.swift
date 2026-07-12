import SwiftUI

/// Large tappable 0–5 star rating in half steps (PRD F5). Tap or drag to
/// set; VoiceOver adjusts in half-star increments.
struct RatingControl: View {
    @Binding var rating: Double?
    var starSize: CGFloat = 36
    var spacing: CGFloat = 8

    private var totalWidth: CGFloat { starSize * 5 + spacing * 4 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbolName(at: index))
                    .font(.system(size: starSize))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { rating = value(atX: $0.location.x) }
                .onEnded { rating = value(atX: $0.location.x) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.Detail.ratingSection)
        .accessibilityValue(rating.map(Strings.Accessibility.rating) ?? Strings.Accessibility.unrated)
        .accessibilityAdjustableAction { direction in
            let current = rating ?? 0
            switch direction {
            case .increment:
                rating = min(5, current + 0.5)
            case .decrement:
                rating = max(0.5, current - 0.5)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("RatingControl")
    }

    private func value(atX x: CGFloat) -> Double {
        let fraction = min(max(x / totalWidth, 0), 1)
        let halfSteps = (fraction * 10).rounded(.up)
        return min(5, max(0.5, halfSteps / 2))
    }

    private func symbolName(at index: Int) -> String {
        let remainder = (rating ?? 0) - Double(index)
        if remainder >= 1 { return "star.fill" }
        if remainder >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

#Preview {
    @Previewable @State var rating: Double? = 3.5
    RatingControl(rating: $rating)
        .padding()
}
