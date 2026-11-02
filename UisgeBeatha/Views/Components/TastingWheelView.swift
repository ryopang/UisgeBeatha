import SwiftUI

/// Where a point lands on the wheel. Pure geometry, shared by the drawing
/// code's proportions and the tap handler, and unit tested.
nonisolated enum WheelGeometry {
    /// Ring proportions as fractions of the outer radius.
    static let innerFraction: CGFloat = 0.22
    static let midFraction: CGFloat = 0.60
    /// Space kept clear around the outer edge.
    static let margin: CGFloat = 4

    /// The word under `point` in a wheel drawn in `size`: a descriptor on
    /// the outer ring, a category name on the inner ring, nil in the hub or
    /// outside the wheel. Categories run clockwise from 12 o'clock.
    static func word(at point: CGPoint, in size: CGSize) -> String? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = min(size.width, size.height) / 2 - margin
        let midRadius = outerRadius * midFraction
        let innerRadius = outerRadius * innerFraction

        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= innerRadius, radius <= outerRadius else { return nil }

        // atan2 with a downward y axis already runs clockwise; shift so 0
        // is 12 o'clock.
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }

        let categories = WheelVocabulary.categories
        let categorySweep = 360 / CGFloat(categories.count)
        let categoryIndex = min(Int(degrees / categorySweep), categories.count - 1)
        let category = categories[categoryIndex]
        if radius < midRadius { return category.name }

        let descriptorSweep = categorySweep / CGFloat(category.descriptors.count)
        let offset = degrees - CGFloat(categoryIndex) * categorySweep
        let descriptorIndex = min(Int(offset / descriptorSweep), category.descriptors.count - 1)
        return category.descriptors[descriptorIndex]
    }
}

/// An original two-ring whisky tasting wheel drawn natively in SwiftUI
/// (PRD F7). Inner ring: 8 flavour categories; outer ring: 3 descriptors
/// per category. When `onSelect` is set, tapping a segment reports its
/// word; the wheel itself stays a reference otherwise.
struct TastingWheelView: View {
    /// Called with the tapped descriptor, or category name for the inner
    /// ring. nil makes the wheel reference-only.
    var onSelect: ((String) -> Void)?

    /// Labels scale with Dynamic Type. The wheel's segments are fixed
    /// shapes, so very large sizes are better served by the list
    /// alternative in `TastingWheelSheet`.
    @ScaledMetric(relativeTo: .caption) private var categoryFontSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) private var descriptorFontSize: CGFloat = 9

    struct Category: Identifiable {
        let name: String
        let descriptors: [String]
        let color: Color
        var id: String { name }
    }

    /// Mid-tone hues chosen to hold up on both light and dark backgrounds.
    static let categories: [Category] = [
        Category(name: Strings.Wheel.smoky, descriptors: Strings.Wheel.smokyDescriptors, color: Color(red: 0.45, green: 0.44, blue: 0.50)),
        Category(name: Strings.Wheel.fruity, descriptors: Strings.Wheel.fruityDescriptors, color: Color(red: 0.83, green: 0.48, blue: 0.22)),
        Category(name: Strings.Wheel.floral, descriptors: Strings.Wheel.floralDescriptors, color: Color(red: 0.65, green: 0.48, blue: 0.72)),
        Category(name: Strings.Wheel.malty, descriptors: Strings.Wheel.maltyDescriptors, color: Color(red: 0.71, green: 0.58, blue: 0.32)),
        Category(name: Strings.Wheel.woody, descriptors: Strings.Wheel.woodyDescriptors, color: Color(red: 0.55, green: 0.40, blue: 0.26)),
        Category(name: Strings.Wheel.spicy, descriptors: Strings.Wheel.spicyDescriptors, color: Color(red: 0.78, green: 0.33, blue: 0.27)),
        Category(name: Strings.Wheel.sweet, descriptors: Strings.Wheel.sweetDescriptors, color: Color(red: 0.80, green: 0.60, blue: 0.16)),
        Category(name: Strings.Wheel.maritime, descriptors: Strings.Wheel.maritimeDescriptors, color: Color(red: 0.30, green: 0.55, blue: 0.65)),
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - WheelGeometry.margin
            let midRadius = outerRadius * WheelGeometry.midFraction
            let innerRadius = outerRadius * WheelGeometry.innerFraction
            let categories = Self.categories
            let categorySweep = Angle.degrees(360.0 / Double(categories.count))

            for (index, category) in categories.enumerated() {
                let start = Angle.degrees(-90) + categorySweep * Double(index)

                // Inner ring: category segment.
                let segment = annulusSegment(
                    center: center, innerRadius: innerRadius, outerRadius: midRadius,
                    start: start, sweep: categorySweep
                )
                context.fill(segment, with: .color(category.color))
                context.stroke(segment, with: .style(.background), lineWidth: 2)

                drawLabel(
                    category.name, context: context, center: center,
                    radius: (innerRadius + midRadius) / 2,
                    angle: start + categorySweep / 2,
                    font: .system(size: categoryFontSize, weight: .bold),
                    color: .white
                )

                // Outer ring: descriptor segments in fading shades.
                let descriptorSweep = categorySweep / Double(category.descriptors.count)
                for (descriptorIndex, descriptor) in category.descriptors.enumerated() {
                    let descriptorStart = start + descriptorSweep * Double(descriptorIndex)
                    let shade = category.color.opacity(0.75 - Double(descriptorIndex) * 0.2)
                    let outerSegment = annulusSegment(
                        center: center, innerRadius: midRadius, outerRadius: outerRadius,
                        start: descriptorStart, sweep: descriptorSweep
                    )
                    context.fill(outerSegment, with: .color(shade))
                    context.stroke(outerSegment, with: .style(.background), lineWidth: 2)

                    drawLabel(
                        descriptor, context: context, center: center,
                        radius: (midRadius + outerRadius) / 2,
                        angle: descriptorStart + descriptorSweep / 2,
                        font: .system(size: descriptorFontSize, weight: .semibold),
                        color: .primary,
                        radially: true
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if let onSelect {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            if let word = WheelGeometry.word(at: location, in: proxy.size) {
                                onSelect(word)
                            }
                        }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.Wheel.accessibilitySummary)
    }

    private func annulusSegment(
        center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat,
        start: Angle, sweep: Angle
    ) -> Path {
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: start + sweep, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: start + sweep, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Draws text at the given polar position: tangentially for the wide
    /// inner segments, radially (spoke-like) for the narrow outer ones.
    /// Flipped where needed so labels never read upside down.
    private func drawLabel(
        _ text: String, context: GraphicsContext, center: CGPoint,
        radius: CGFloat, angle: Angle, font: Font, color: Color,
        radially: Bool = false
    ) {
        let position = CGPoint(
            x: center.x + radius * cos(angle.radians),
            y: center.y + radius * sin(angle.radians)
        )
        let normalized = (angle.degrees + 360).truncatingRemainder(dividingBy: 360)
        var rotation: Angle
        if radially {
            rotation = angle
            if normalized > 90 && normalized < 270 {
                rotation += .degrees(180)
            }
        } else {
            rotation = angle + .degrees(90)
            if normalized > 0 && normalized < 180 {
                rotation += .degrees(180)
            }
        }

        var labelContext = context
        labelContext.translateBy(x: position.x, y: position.y)
        labelContext.rotate(by: rotation)
        labelContext.draw(
            Text(text).font(font).foregroundStyle(color),
            at: .zero, anchor: .center
        )
    }
}

/// The wheel sheet presented from the tasting note editor: the wheel, plus
/// an accessible list of the same words. With `onSelect`, tapping a word
/// adds it to the note being written.
struct TastingWheelSheet: View {
    var onSelect: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// nil = follow the default: the list when the wheel's small labels
    /// can't scale (accessibility type sizes) or VoiceOver is on.
    @State private var showsListOverride: Bool?

    private var showsList: Bool {
        showsListOverride ?? (dynamicTypeSize.isAccessibilitySize || voiceOverEnabled)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker(Strings.Wheel.layout, selection: Binding(
                        get: { showsList },
                        set: { showsListOverride = $0 }
                    )) {
                        Text(Strings.Wheel.wheelMode).tag(false)
                        Text(Strings.Wheel.listMode).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if showsList {
                        wordList
                    } else {
                        TastingWheelView(onSelect: onSelect)
                            .padding(.horizontal, 12)
                    }
                    Text(onSelect == nil ? Strings.Wheel.caption : Strings.Wheel.tapHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(Strings.Wheel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Wheel.done) { dismiss() }
                }
            }
        }
    }

    /// The same vocabulary as plain buttons: readable at any text size and
    /// fully navigable with VoiceOver.
    private var wordList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(WheelVocabulary.categories, id: \.name) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.name)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(category.descriptors, id: \.self) { word in
                        if let onSelect {
                            Button(word) { onSelect(word) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                        } else {
                            Text(word)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

#Preview("Light") {
    TastingWheelSheet()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TastingWheelSheet()
        .preferredColorScheme(.dark)
}
