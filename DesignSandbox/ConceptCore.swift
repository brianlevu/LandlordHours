// Round 3 concepts (creative-r3/concepts.md). Launch arg: -LHConcept blueprint|porchlight|tilework
import SwiftUI

enum LHConcept: String {
    case none, blueprint, porchlight, tilework
    static let current: LHConcept =
        UserDefaults.standard.string(forKey: "LHConcept").flatMap(LHConcept.init(rawValue:)) ?? .none

    var canvas: Color? {
        switch self {
        case .blueprint: Color(light: 0xEEF2FA, dark: 0x0B1230)
        case .porchlight: Color(light: 0xF3F5FA, dark: 0x0B0F24)
        case .tilework: Color(light: 0xF5F2EC, dark: 0x0F1220)
        case .none: nil
        }
    }
    var card: Color? {
        switch self {
        case .blueprint: Color(light: 0xFFFFFF, dark: 0x141C3F)
        case .porchlight: Color(light: 0xFFFFFF, dark: 0x161B33)
        case .tilework: Color(light: 0xFFFFFF, dark: 0x1C2136)
        case .none: nil
        }
    }
}

/// Text colours for words sitting on a saturated hero surface (blueprint blue, night sky, grout).
/// Concept spec greens/ambers (#1E9E5A, #C9741A) are below 4.5:1 on white, so light cards keep the
/// round-2 AA tokens and only the dark hero surfaces use the bright variants.
enum OnHero {
    static let positive = Color(hex: 0x4ED48A)   // 5.6:1 on #1E3FA6, 9.7:1 on #161B2E
    static let caution = Color(hex: 0xFFB454)    // 5.9:1 on #1E3FA6
    static let secondary = Color.white.opacity(0.78)
}

enum BP {
    static let blueprint = Color(hex: 0x1E3FA6)
    static let blueprintDeep = Color(hex: 0x16307F)
    static let drafting = Color(hex: 0x8FD3FF)
    static let timber = Color(hex: 0xE0A458)
    static let timberDark = Color(hex: 0xB97D3A)
    static let terracotta = Color(hex: 0xC8553D)
    static let terracottaDark = Color(hex: 0x9E3F2C)
    static let plaster = Color(hex: 0xF4EFE6)
    static let plasterShade = Color(hex: 0xDCD3C3)
    static let brass = Color(hex: 0xD9B45A)
    static let window = Color(hex: 0xFFD27A)
    static let glass = Color(hex: 0x2B3B66)
    static let slate = Color(hex: 0x5A6B8C)
    static let concrete = Color(hex: 0xA7AFBF)

    /// Materials list for category washes.
    static func material(_ c: Category) -> Color {
        switch c {
        case .repairs: Color(hex: 0xB86A3F)       // copper
        case .renovation: Color(hex: 0xC8553D)    // terracotta
        case .cleaning: Color(hex: 0x3B6FE0)      // cobalt
        case .leasing: Color(hex: 0x7A4BAE)       // plum
        case .tenant: Color(hex: 0x5A6B8C)        // slate
        case .bookkeeping: Color(hex: 0x4E8A5C)   // moss
        case .travel: Color(hex: 0x2E6B4F)        // pine
        case .inspections: Color(hex: 0x4A5068)   // graphite
        case .legal: Color(hex: 0x8C6F3F)         // sand, deepened for glyph contrast
        case .supplies: Color(hex: 0xB97D3A)      // timber, deepened
        case .management: Color(hex: 0x2E6B4F)
        }
    }
    static func tool(_ c: Category) -> String {
        switch c {
        case .repairs: "wrench.adjustable"
        case .renovation: "paintbrush.pointed"
        case .cleaning: "bubbles.and.sparkles"
        case .leasing: "key.horizontal"
        case .tenant: "phone"
        case .bookkeeping: "book.closed"
        case .travel: "car.side"
        case .inspections: "list.clipboard"
        case .legal: "folder"
        case .supplies: "shippingbox"
        case .management: "building.2"
        }
    }
}

/// Faint drafting grid on blueprint paper.
struct BlueprintPaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2347B3), BP.blueprint, BP.blueprintDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                let minor: CGFloat = 12
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)); x += minor }
                var y: CGFloat = 0
                while y < size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)); y += minor }
                ctx.stroke(p, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
                var q = Path()
                x = 0
                while x < size.width { q.move(to: .init(x: x, y: 0)); q.addLine(to: .init(x: x, y: size.height)); x += minor * 5 }
                y = 0
                while y < size.height { q.move(to: .init(x: 0, y: y)); q.addLine(to: .init(x: size.width, y: y)); y += minor * 5 }
                ctx.stroke(q, with: .color(.white.opacity(0.09)), lineWidth: 0.6)
            }
        }
    }
}

/// White pill on a saturated surface (concept rule: violet never sits on blueprint/grout).
struct HeroPill: ButtonStyle {
    var text: Color = BP.blueprint
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(text)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Concept art lookup (creative-r3/assets via import_art_r3.py).
func conceptImage(_ name: String) -> Image? {
    UIImage(named: name).map { Image(uiImage: $0) }
}
