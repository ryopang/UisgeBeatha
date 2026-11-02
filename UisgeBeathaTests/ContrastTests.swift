import SwiftUI
import Testing
import UIKit
@testable import UisgeBeatha

/// Phase 5: WCAG AA (4.5:1 for text) for the design tokens, in both
/// appearances. These guard the numbers in PRD section 8.1, so a palette
/// tweak that quietly breaks contrast fails here instead of in review.
@MainActor
struct ContrastTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    private static func rgb(_ color: UIColor, _ style: UIUserInterfaceStyle) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }

    private static func luminance(_ value: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
    }

    private static func ratio(
        _ foreground: (r: Double, g: Double, b: Double), _ background: (r: Double, g: Double, b: Double)
    ) -> Double {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `color` at `opacity` over a flat backdrop.
    private static func blend(
        _ color: (r: Double, g: Double, b: Double), opacity: Double, over backdrop: Double
    ) -> (r: Double, g: Double, b: Double) {
        (
            color.r * opacity + backdrop * (1 - opacity),
            color.g * opacity + backdrop * (1 - opacity),
            color.b * opacity + backdrop * (1 - opacity)
        )
    }

    @Test func textOnAccentMeetsAAInBothAppearances() throws {
        let accent = try #require(UIColor(named: "AccentColor"))
        for style in Self.styles {
            let contrast = Self.ratio(
                Self.rgb(UIColor(Theme.Palette.onAccent), style), Self.rgb(accent, style)
            )
            #expect(contrast >= 4.5, "onAccent on accent, \(style.rawValue): \(contrast)")
        }
    }

    @Test func accentTextOnTheSystemBackgroundMeetsAA() throws {
        let accent = try #require(UIColor(named: "AccentColor"))
        for style in Self.styles {
            let contrast = Self.ratio(
                Self.rgb(accent, style), Self.rgb(.systemBackground, style)
            )
            #expect(contrast >= 4.5, "accent on background, \(style.rawValue): \(contrast)")
        }
    }

    @Test func emptyMapBadgeKeepsItsDigitsReadable() {
        for style in Self.styles {
            let contrast = Self.ratio(
                (1, 1, 1), Self.rgb(UIColor(Theme.Palette.emptyBadgeFill), style)
            )
            #expect(contrast >= 4.5, "white on empty badge, \(style.rawValue): \(contrast)")
        }
    }

    @Test func whiteDigitsOnEveryRegionBadgeMeetAA() {
        for region in RegionCatalog.regions {
            for style in Self.styles {
                let contrast = Self.ratio(
                    (1, 1, 1), Self.rgb(UIColor(region.badgeFillColor), style)
                )
                #expect(contrast >= 4.5, "\(region.id) badge, \(style.rawValue): \(contrast)")
            }
        }
    }

    @Test func regionTextOnItsOwnTintMeetsAAInBothAppearances() {
        for region in RegionCatalog.regions {
            let base = (r: region.colorRed, g: region.colorGreen, b: region.colorBlue)
            for style in Self.styles {
                let backdrop = style == .dark ? 0.0 : 1.0
                let tint = Self.blend(base, opacity: 0.18, over: backdrop)
                let text = Self.rgb(UIColor(region.textColor), style)
                let contrast = Self.ratio(text, tint)
                #expect(contrast >= 4.5, "\(region.id) text, \(style.rawValue): \(contrast)")
            }
        }
    }
}
