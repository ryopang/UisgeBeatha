import SwiftUI

/// Shared design tokens for the app's small set of custom-drawn surfaces —
/// cards, floating pill labels, the bottle hero photo. System components
/// (Form, List, Menu, .bordered/.borderedProminent buttons) already carry
/// their own iOS 26 Liquid Glass styling and are left alone; these tokens
/// exist only where SwiftUI has no opinion of its own, so the app's few
/// custom surfaces read as one consistent language rather than N one-offs.
enum Theme {
    /// One radius per role, not one per view.
    enum Radius {
        /// Small inline imagery inside a card (e.g. the distillery thumbnail).
        static let inline: CGFloat = 12
        /// Custom card backgrounds (facts grid, distillery card, tasting note).
        static let card: CGFloat = 16
        /// The bottle hero photo — the one surface that's meant to look
        /// like it's resting above the page.
        static let hero: CGFloat = 24
    }

    /// Weight ladder: regular / semibold / bold. `.medium` (500) is
    /// deliberately never used — a label either reads as plain body text or
    /// as clearly emphasized; there's no in-between weight in this app.
    enum Weight {
        static let emphasis: Font.Weight = .semibold
    }

    /// Colors the asset catalog can't express because they depend on
    /// another color rather than on appearance alone.
    enum Palette {
        /// Text on a solid accent fill. White on the dark-mode accent
        /// `#DE8230` is only 2.9:1, so dark mode uses near-black `#1A1206`
        /// (about 7:1). Light mode keeps white on `#A75A17` (5.1:1).
        static let onAccent = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x1A / 255, green: 0x12 / 255, blue: 0x06 / 255, alpha: 1)
                : .white
        })

        /// Fill behind white digits for a map badge with no bottles. A
        /// muted grey that still gives the digits more than 4.5:1 in both
        /// appearances; dimming the whole badge with opacity instead would
        /// drag the text below contrast.
        static let emptyBadgeFill = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.36, alpha: 1)
                : UIColor(white: 0.40, alpha: 1)
        })
    }

    /// Motion principles (PRD section 8.4): explain a change, stay fast
    /// (150 to 250 ms), never overshoot, never block input.
    enum Motion {
        static let quick = Animation.snappy(duration: 0.2)
        static let press = Animation.snappy(duration: 0.15)
        /// Scale while a control is pressed.
        static let pressedScale: CGFloat = 0.96
    }
}

extension View {
    /// The app's one custom "card": flat, tinted with the secondary
    /// background material, `Theme.Radius.card` corners. No shadow — shadow
    /// is reserved for `heroShadow()`, never cards, buttons, or text.
    func cardBackground() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    /// A small floating pill label — a proactive hint or toast over live
    /// content (the camera feed, a just-opened detail view). System
    /// material capsule, no border, no color beyond the text itself.
    func pillLabel() -> some View {
        font(.subheadline.weight(Theme.Weight.emphasis))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
    }

    /// The single "product shadow" in the app, reserved for the bottle hero
    /// photo alone — the one place elevation should draw the eye.
    func heroShadow() -> some View {
        shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}
