import SwiftUI

/// The app's prominent button: a solid accent capsule with `onAccent` text.
///
/// The system `.borderedProminent` style draws white text, which fails
/// contrast on the dark-mode accent (2.9:1). This keeps the same shape and
/// weight but uses `Theme.Palette.onAccent`, and gives a pressed state that
/// respects Reduce Motion.
struct AccentProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(Theme.Weight.emphasis))
            .foregroundStyle(Theme.Palette.onAccent)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(Color.accentColor, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentProminentButtonStyle {
    static var accentProminent: AccentProminentButtonStyle { AccentProminentButtonStyle() }
}

/// Keeps a control's own look and only adds the press feedback (scale
/// 0.96) from the motion spec. Under Reduce Motion the scale is dropped.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
}
