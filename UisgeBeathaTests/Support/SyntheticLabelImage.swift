import UIKit

/// Renders a plain mockup of a bottle label as a `UIImage` — a title line
/// (distillery name), medium lines (expression/age), and small print (ABV,
/// volume) at realistic relative sizes. Lets the L2 Vision configuration
/// (customWords, minimumTextHeightFraction, no-correction pass) be tested
/// against *real* Vision recognition without needing photos of actual
/// bottles, which weren't available when this was built — see
/// docs/label-scan-plan.md §0.1. Not a substitute for real photos (no
/// curved glass, glare, or lighting variation), but it does exercise the
/// real Vision request pipeline end to end, which hand-typed OCR-output
/// fixtures (LabelParserAccuracyTests) never touch.
enum SyntheticLabelImage {
    struct Line {
        let text: String
        /// Point size, chosen relative to a label's real typographic
        /// hierarchy: ~44 for the distillery name, ~30 for an
        /// expression/age line, ~16–18 for ABV/volume small print.
        let fontSize: CGFloat
        let weight: UIFont.Weight

        init(_ text: String, fontSize: CGFloat, weight: UIFont.Weight = .semibold) {
            self.text = text
            self.fontSize = fontSize
            self.weight = weight
        }
    }

    static func render(lines: [Line], size: CGSize = CGSize(width: 900, height: 1400)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            var y: CGFloat = 80
            for line in lines {
                let font = UIFont.systemFont(ofSize: line.fontSize, weight: line.weight)
                let attributed = NSAttributedString(string: line.text, attributes: [
                    .font: font,
                    .foregroundColor: UIColor.black,
                ])
                let textSize = attributed.size()
                let x = max(24, (size.width - textSize.width) / 2)
                attributed.draw(at: CGPoint(x: x, y: y))
                y += textSize.height + line.fontSize * 0.55
            }
        }
    }
}
