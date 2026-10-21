import SwiftUI
import UIKit

// MARK: - Brand palette (shared by the app and the widget extension)
//
// The 2.0 Blueprint token hexes (docs/design/2.0-brand-system.md §2). The single source for every
// target: `AppColors.Hex` is an alias of this enum, and the widget extension reads the same values,
// so no surface keeps its own palette. Add a token here, never inline in a view.
enum BrandHex {
    // Brand + materials (theme-fixed)
    static let brand = "1E3FA6"            // blueprint
    static let blueprintPaper = "0B1230"   // dark canvas
    static let timber = "E0A458"
    static let brass = "D9B45A"
    static let terracotta = "C8553D"
    static let plaster = "F4EFE6"

    // Light
    static let canvas = "EEF2FA"
    static let card = "FFFFFF"
    static let tertiary = "F6F8FD"
    static let actionSurface = "E3E9FA"
    static let actionPressed = "16307F"
    static let drafting = "8FD3FF"
    static let draftingInk = "2369B5"
    static let timberInk = "8A5A1B"
    static let textPrimary = "121B33"
    static let textSecondary = "4A5068"
    static let textTertiary = "5F6983"
    static let border = "D5DBEA"
    static let borderLight = "E5EAF4"
    static let positive = "137A42"
    static let positiveSurface = "E4F7EB"
    static let caution = "9A560C"
    static let cautionSurface = "FCF0DC"
    static let destructive = "C1303A"
    static let destructiveSurface = "FCE4E5"
    static let informational = "4A6392"
    static let informationalSurface = "E6ECF6"
    static let rose = "B04266"
    static let roseSurface = "F9E3EA"

    // Dark
    static let darkCanvas = "0B1230"
    static let darkCard = "141C3F"
    static let darkTertiary = "1B2550"
    static let darkAction = "8FD3FF"
    static let darkOnAction = "0B1230"
    static let darkActionSurface = "182A5C"
    static let darkActionPressed = "BFE6FF"
    static let darkDrafting = "60A8E6"
    static let darkTimberInk = "F0BE7A"
    static let darkTextPrimary = "F2F4FA"
    static let darkTextSecondary = "B4BCD2"
    static let darkTextTertiary = "8A94B2"  // brand doc 7E88A6 lifted: 4.18:1 on the dark input fill
    static let darkBorder = "2A3560"
    static let darkPositive = "4ED48A"
    static let darkPositiveSurface = "123A2A"
    static let darkCaution = "FFB454"
    static let darkCautionSurface = "3D2A10"
    static let darkDestructive = "FF7A7A"
    static let darkDestructiveSurface = "44181C"
    static let darkInformational = "9BB0D0"
    static let darkInformationalSurface = "1E2A4A"
    static let darkRose = "F08BAA"
    static let darkRoseSurface = "3A1A28"

    // Theme-fixed text on the blueprint hero, widgets and Siri snippet (white is the primary).
    static let blueprintDeep = "16307F"
    static let onHeroSecondary = "C9D6F5"   // 6.4:1 on #1E3FA6
    static let positiveOnHero = "7FE3A8"    // 6.8:1 on #1E3FA6
    static let cautionOnHero = "FFB454"     // 5.2:1 on #1E3FA6

    // Toast (surfaces lane): light = card, dark = tertiary.
    static let toastSurface = "FFFFFF"
    static let darkToastSurface = "1B2550"
    // Decorative week bars (charts), not text.
    static let chartBar = "1E3FA6"
    static let darkChartBar = "60A8E6"
}

extension Color {
    /// A colour from a `BrandHex` value ("RRGGBB").
    init(brandHex hex: String) {
        self.init(uiColor: UIColor(brandHex: hex))
    }

    /// A light/dark token resolved per trait collection.
    static func brandDynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(brandHex: dark) : UIColor(brandHex: light) })
    }
}

extension UIColor {
    convenience init(brandHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
