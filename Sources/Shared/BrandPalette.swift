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

    // Today page (crafted house): the house is shown at dusk, so the page is a warm dusk-tinted
    // neutral in light and deep navy in dark. Vertical gradient top -> mid (behind the hero) -> bottom.
    static let duskTop = "EAE3D7"
    static let duskMid = "D8CFC0"
    static let duskBottom = "E8E0D3"
    static let darkNightTop = "0B1230"
    static let darkNightBottom = "080C1D"
    /// The warm light that spills from the windows onto the lot (hue ~35, soft). Same hue both modes.
    static let spill = "E9A558"
    static let spillOpacity = 0.34
    static let darkSpillOpacity = 0.12
    /// Behind-pace text on the dusk page: 4.65:1 on the darkest page step (#D8CFC0). Dark: 7.4:1 on the night page.
    static let behind = "9A3624"
    static let darkBehind = "F08A70"
    /// Positive text on the dusk page (the standard positive #137A42 is 3.5:1 there): 5.4:1 on #D8CFC0.
    static let positiveOnPage = "0C5A30"
    /// Cool backlight behind the lot at night, so the silhouette reads against the page.
    static let darkBacklight = "5E86D6"
    /// Edge of a grouped container on the dusk page (the card #F4EFE6 is only 1.19:1 on the page).
    static let pageCardEdge = "A3966F"
    /// The same edge on the night page (§H.4 `pageCardEdge` dark).
    static let darkPageCardEdge = "2A3560"
    /// The rental chip's hairline on the dusk page (§H.8; drawn at 0.8 opacity). Dark: white 0.14.
    static let heroChipHairline = "C9BFA8"
    /// Page dots under the house (§H.8): the current dot is `textPrimary`, the rest this at 0.5.
    static let heroDot = "8A8FA3"
    static let darkHeroDot = "5D6788"
    /// §1.27 DU11: the work pane's card edge on the night page in two-pane and stacked windows
    /// (dark only; light keeps `pageCardEdge`). 2.02:1 on the night room away from the warm pool.
    static let duoNightCardEdge = "3C4675"

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
