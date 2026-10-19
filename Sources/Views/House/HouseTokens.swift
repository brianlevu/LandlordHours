import SwiftUI

// MARK: - House tokens
//
// The Blueprint values the house views need (docs/design/2.0-brand-system.md §2). WP-D adds the
// same values to AppColors (brand, drafting, draftingInk, timber, brass, ...); this lane may not
// edit that file, so the house keeps its own copy. After WP-D merges, these can alias AppColors.

enum HouseTokens {
    enum Hex {
        static let blueprint = "1E3FA6"
        static let blueprintDeep = "16307F"
        static let blueprintPaper = "0B1230"
        static let drafting = "8FD3FF"         // linework on the blueprint hero (both modes)
        static let draftingInk = "2369B5"      // linework on light canvases and cards
        static let darkDrafting = "60A8E6"     // linework on dark canvases and cards
        static let timber = "E0A458"
        static let brass = "D9B45A"
        static let brassLight = "F2D78C"
        static let brassDark = "A9833A"
        static let brassEngrave = "5C4316"
        static let onHeroSecondary = "C9D6F5"  // secondary text on blueprint (≥ 6:1)
        static let canvasLight = "EEF2FA"
        static let canvasDark = "0B1230"
        static let cardLight = "FFFFFF"
        static let cardDark = "141C3F"
        static let positiveOnHero = "7FE3A8"
    }

    static let blueprint = Color(hex: Hex.blueprint)
    static let blueprintDeep = Color(hex: Hex.blueprintDeep)
    static let drafting = Color(hex: Hex.drafting)
    static let timber = Color(hex: Hex.timber)
    static let brass = Color(hex: Hex.brass)
    static let brassLight = Color(hex: Hex.brassLight)
    static let brassDark = Color(hex: Hex.brassDark)
    static let brassEngrave = Color(hex: Hex.brassEngrave)
    static let onHeroPrimary = Color.white
    static let onHeroSecondary = Color(hex: Hex.onHeroSecondary)
    static let positiveOnHero = Color(hex: Hex.positiveOnHero)

    static func canvas(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Hex.canvasDark : Hex.canvasLight)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Hex.cardDark : Hex.cardLight)
    }
}

/// The surface the house sits on. It picks the linework tint (manifest house_notes).
enum HouseCanvas: String, Sendable {
    /// The theme-fixed blueprint hero (#1E3FA6): drafting cyan #8FD3FF in light and dark.
    case blueprintHero
    /// A light/dark card or page: #2369B5 in light, #60A8E6 in dark.
    case card

    func lineworkHex(for scheme: ColorScheme) -> String {
        switch self {
        case .blueprintHero: return HouseTokens.Hex.drafting
        case .card: return scheme == .dark ? HouseTokens.Hex.darkDrafting : HouseTokens.Hex.draftingInk
        }
    }

    func linework(for scheme: ColorScheme) -> Color { Color(hex: lineworkHex(for: scheme)) }
}

/// Blueprint paper: the hero surface, with a faint drafting grid. Decorative.
struct HouseBlueprintPaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [HouseTokens.blueprint, HouseTokens.blueprintDeep], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let step: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                context.stroke(path, with: .color(HouseTokens.drafting.opacity(0.07)), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}
