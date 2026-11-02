import SwiftUI

/// Large tappable 0–5 star rating in half steps (PRD F5). Tap or drag to
/// set; VoiceOver adjusts in half-star increments.
struct RatingControl: View {
    @Binding var rating: Double?
    var spacing: CGFloat = 8

    /// Stars grow with Dynamic Type, capped so five of them always fit
    /// across a phone at accessibility sizes.
    @ScaledMetric(relativeTo: .title) private var scaledStarSize: CGFloat
    private let baseStarSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rating: Binding<Double?>, starSize: CGFloat = 36, spacing: CGFloat = 8) {
        _rating = rating
        self.spacing = spacing
        baseStarSize = starSize
        _scaledStarSize = ScaledMetric(wrappedValue: starSize, relativeTo: .title)
    }

    private var starSize: CGFloat { min(scaledStarSize, baseStarSize * 1.3) }
    private var totalWidth: CGFloat { starSize * 5 + spacing * 4 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbolName(at: index))
                    .font(.system(size: starSize))
                    .foregroundStyle(Color.accentColor)
            }
        }
        // The stars bounce when the rating is set; under Reduce Motion the
        // haptic and the changed glyphs are the feedback.
        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : rating)
        .contentShape(Rectangle())
        // Tap sets the rating directly. Scrubbing needs a deliberate
        // horizontal drag: the old zero-distance drag claimed every touch
        // that started on the stars, so scrolling the detail page with a
        // thumb resting there silently changed the rating.
        .onTapGesture { location in
            rating = value(atX: location.x)
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    rating = value(atX: drag.location.x)
                }
        )
        .sensoryFeedback(.selection, trigger: rating)
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
