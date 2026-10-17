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

    func testSecondaryAndCautionTextPassOnCards() {
        for (scheme, style) in [(ColorScheme.light, UIUserInterfaceStyle.light), (.dark, .dark)] {
            let colors = AdaptiveColors(colorScheme: scheme)
            XCTAssertGreaterThanOrEqual(contrast(colors.textSecondary, colors.backgroundSecondary, style), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(colors.cautionText, colors.backgroundSecondary, style), 4.5)
        }
    }
}
