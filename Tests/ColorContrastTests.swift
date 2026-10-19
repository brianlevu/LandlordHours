import XCTest
import SwiftUI
@testable import LandlordHours

/// WCAG contrast checks for the intent tokens (sign-in visual gate, 2026-10-17).
final class ColorContrastTests: XCTestCase {

    private func rgb(_ color: Color, _ style: UIUserInterfaceStyle) -> (CGFloat, CGFloat, CGFloat) {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        return (r, g, b)
    }

    private func luminance(_ c: (CGFloat, CGFloat, CGFloat)) -> Double {
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }

    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let la = luminance(rgb(a, style)), lb = luminance(rgb(b, style))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testOnActionOnActionPassesAAInBothSchemes() {
        let light = contrast(AppColors.onAction, AppColors.action, .light)
        let dark = contrast(AppColors.onAction, AppColors.action, .dark)
        XCTAssertGreaterThanOrEqual(light, 4.5, "light onAction/action = \(light)")
        XCTAssertGreaterThanOrEqual(dark, 4.5, "dark onAction/action = \(dark)")
    }

    func testAdaptiveOnActionOnActionPassesAAInBothSchemes() {
        for (scheme, style) in [(ColorScheme.light, UIUserInterfaceStyle.light), (.dark, .dark)] {
            let colors = AdaptiveColors(colorScheme: scheme)
            let ratio = contrast(colors.onAction, colors.action, style)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(scheme) adaptive onAction/action = \(ratio)")
        }
    }

    func testDestructiveTextPassesOnCards() {
        let light = AdaptiveColors(colorScheme: .light)
        let dark = AdaptiveColors(colorScheme: .dark)
        XCTAssertGreaterThanOrEqual(contrast(light.destructive, light.backgroundSecondary, .light), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(dark.destructive, dark.backgroundSecondary, .dark), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(AppColors.destructive, .white, .light), 4.5)
    }

    func testInformationalTextPassesOnItsSurface() {
        let light = AdaptiveColors(colorScheme: .light)
        let dark = AdaptiveColors(colorScheme: .dark)
        XCTAssertGreaterThanOrEqual(contrast(light.informationalText, light.informationalSurface, .light), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(dark.informationalText, dark.informationalSurface, .dark), 4.5)
    }

    /// Sweep of every text/surface token pair the Settings screen uses, both schemes.
    func testSettingsTextPairsPassAA() {
        for (scheme, style) in [(ColorScheme.light, UIUserInterfaceStyle.light), (.dark, .dark)] {
            let c = AdaptiveColors(colorScheme: scheme)
            let pairs: [(String, Color, Color)] = [
                ("textPrimary/card", c.textPrimary, c.backgroundSecondary),
                ("textSecondary/card", c.textSecondary, c.backgroundSecondary),
                ("textSecondary/page", c.textSecondary, c.background),
                ("textSecondary/tertiary", c.textSecondary, c.backgroundTertiary),
                ("actionText/actionSurface", c.actionText, c.actionSurface),
                ("actionText/card", c.actionText, c.backgroundSecondary),
                ("positiveText/positiveSurface", c.positiveText, c.positiveSurface),
                ("positiveText/card", c.positiveText, c.backgroundSecondary),
                ("onAction/action", c.onAction, c.action),
                ("destructive/card", c.destructive, c.backgroundSecondary),
                ("cautionText/card", c.cautionText, c.backgroundSecondary),
                ("informationalText/informationalSurface", c.informationalText, c.informationalSurface),
            ]
            for (name, fg, bg) in pairs {
                let r = contrast(fg, bg, style)
                XCTAssertGreaterThanOrEqual(r, 4.5, "\(scheme) \(name) = \(String(format: "%.2f", r))")
            }
        }
    }

    func testSecondaryAndCautionTextPassOnCards() {
        for (scheme, style) in [(ColorScheme.light, UIUserInterfaceStyle.light), (.dark, .dark)] {
            let colors = AdaptiveColors(colorScheme: scheme)
            XCTAssertGreaterThanOrEqual(contrast(colors.textSecondary, colors.backgroundSecondary, style), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(colors.cautionText, colors.backgroundSecondary, style), 4.5)
        }
    }
    // MARK: - 2.0 Blueprint brand pairs (design/brand/contrast.txt)

    /// Every text pair the brand system defines, both schemes, at WCAG AA (4.5:1).
    func testBlueprintTextPairsPassAA() {
        for (scheme, style) in [(ColorScheme.light, UIUserInterfaceStyle.light), (.dark, .dark)] {
            let c = AdaptiveColors(colorScheme: scheme)
            let surfaces: [(String, Color)] = [("card", c.backgroundSecondary), ("canvas", c.background)]
            let inks: [(String, Color)] = [
                ("textPrimary", c.textPrimary),
                ("textSecondary", c.textSecondary),
                ("textTertiary", c.textTertiary),
                ("action", c.action),
                ("positive", c.positive),
                ("caution", c.caution),
                ("destructive", c.destructive),
                ("informational", c.informational),
                ("timberInk", c.timberInk),
                ("draftingInk", c.draftingInk),
                ("rose", c.rose),
            ]
            for (surfaceName, surface) in surfaces {
                for (inkName, ink) in inks {
                    let r = contrast(ink, surface, style)
                    XCTAssertGreaterThanOrEqual(r, 4.5, "\(scheme) \(inkName) on \(surfaceName) = \(String(format: "%.2f", r))")
                }
            }
            let onSurfaces: [(String, Color, Color)] = [
                ("onAction/action", c.onAction, c.action),
                ("action/actionSurface", c.action, c.actionSurface),
                ("positive/positiveSurface", c.positive, c.positiveSurface),
                ("caution/cautionSurface", c.caution, c.cautionSurface),
                ("destructive/destructiveSurface", c.destructive, c.destructiveSurface),
                ("informational/informationalSurface", c.informational, c.informationalSurface),
                ("textSecondary/tertiary", c.textSecondary, c.backgroundTertiary),
                ("textTertiary/tertiary (placeholders on inputs)", c.textTertiary, c.backgroundTertiary),
                ("legacy mist/card", AppColors.mist, c.backgroundSecondary),
                ("legacy slate/card", AppColors.slate, c.backgroundSecondary),
            ]
            for (name, fg, bg) in onSurfaces {
                let r = contrast(fg, bg, style)
                XCTAssertGreaterThanOrEqual(r, 4.5, "\(scheme) \(name) = \(String(format: "%.2f", r))")
            }
        }
    }

    /// White on the theme-fixed blueprint (hero, brand fills): 9.06:1.
    func testWhiteOnBlueprintBrand() {
        XCTAssertGreaterThanOrEqual(contrast(.white, AppColors.brand, .light), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(.white, AppColors.brand, .dark), 4.5)
    }

    /// The locked hexes from docs/design/2.0-brand-system.md: blueprint light action, cyan dark action.
    func testLockedBrandHexes() {
        XCTAssertEqual(hex(AppColors.brand, .light), "1E3FA6")
        XCTAssertEqual(hex(AppColors.brand, .dark), "1E3FA6")
        XCTAssertEqual(hex(AppColors.action, .light), "1E3FA6")
        XCTAssertEqual(hex(AppColors.action, .dark), "8FD3FF")
        XCTAssertEqual(hex(AppColors.drafting, .dark), "60A8E6")
        XCTAssertEqual(hex(AppColors.timber, .light), "E0A458")
        XCTAssertEqual(hex(AdaptiveColors(colorScheme: .dark).action, .dark), "8FD3FF")
        XCTAssertEqual(hex(AdaptiveColors(colorScheme: .light).action, .light), "1E3FA6")
    }

    /// Dark linework must never share a hex with the dark action colour.
    func testDarkDraftingIsDistinctFromDarkAction() {
        let c = AdaptiveColors(colorScheme: .dark)
        XCTAssertNotEqual(hex(c.drafting, .dark), hex(c.action, .dark))
    }

    /// Violet is retired: no legacy violet-named token may resolve to a purple hue.
    func testVioletIsRetired() {
        let tokens: [(String, Color)] = [
            ("primary", AppColors.primary), ("primaryLight", AppColors.primaryLight),
            ("primarySurface", AppColors.primarySurface), ("primaryDark", AppColors.primaryDark),
            ("reportsAccent", AppColors.reportsAccent), ("reportsAccentSoft", AppColors.reportsAccentSoft),
            ("mpAccent", AppColors.mpAccent), ("mpAccentSoft", AppColors.mpAccentSoft),
            ("celebrationPurple", AppColors.celebrationPurple), ("lavenderSoft", AppColors.lavenderSoft),
            ("logoCanvas", AppColors.logoCanvas), ("darkPrimary", AppColors.darkPrimary),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, color) in tokens {
                let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                resolved.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
                let degrees = h * 360
                XCTAssertFalse(sat > 0.15 && degrees > 240 && degrees < 330, "\(name) is violet/purple (\(Int(degrees))°)")
            }
        }
    }

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> String {
        let (r, g, b) = rgb(color, style)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
