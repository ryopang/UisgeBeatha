import SwiftUI

/// An original two-ring whisky tasting wheel drawn natively in SwiftUI
/// (PRD F7). Inner ring: 8 flavour categories; outer ring: 3 descriptors
/// per category. Reference-only in v1 — segments are not tappable.
struct TastingWheelView: View {
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
            let outerRadius = min(size.width, size.height) / 2 - 4
            let midRadius = outerRadius * 0.60
            let innerRadius = outerRadius * 0.22
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
                    font: .system(size: 11, weight: .bold),
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
                        font: .system(size: 9, weight: .medium),
                        color: .primary,
                        radially: true
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
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

/// The reference sheet presented from the tasting note editor.
struct TastingWheelSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TastingWheelView()
                        .padding(.horizontal, 12)
                    Text(Strings.Wheel.caption)
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
}

#Preview("Light") {
    TastingWheelSheet()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TastingWheelSheet()
        .preferredColorScheme(.dark)
}
