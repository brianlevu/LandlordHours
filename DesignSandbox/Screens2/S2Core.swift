// Screens2 — LandlordHours 2.0 redesign render of the remaining legacy screens (sandbox only).
// Spec: AgentScratch/landlordhours/2026-10-19/redesign-specs.md. Tokens: docs/design/2.0-brand-system.md
// (release/2.0). Everything here is prefixed S2 / LHB so it never collides with the older sandbox lanes.
import SwiftUI
import UIKit
import CoreImage
import CoreText

// MARK: - Brand tokens (release/2.0 AppColors.Hex)

enum LHB {
    static let brand = Color(hex: 0x1E3FA6)
    static let brandDeep = Color(hex: 0x16307F)
    static let plaster = Color(hex: 0xF4EFE6)
    static let timber = Color(hex: 0xE0A458)
    static let terracotta = Color(hex: 0xC8553D)
    static let brass = Color(hex: 0xD9B45A)
    /// Linework on the theme-fixed blueprint hero (both modes).
    static let draftingHero = Color(hex: 0x8FD3FF)
    static let onHeroSecondary = Color(hex: 0xC9D6F5)
    static let onBlueprintSecondary = Color(hex: 0xD6E0FA)
    static let positiveOnHero = Color(hex: 0x7FE3A8)

    static let canvas = Color(light: 0xEEF2FA, dark: 0x0B1230)
    static let card = Color(light: 0xFFFFFF, dark: 0x141C3F)
    static let tertiary = Color(light: 0xF6F8FD, dark: 0x1B2550)
    static let action = Color(light: 0x1E3FA6, dark: 0x8FD3FF)
    static let onAction = Color(light: 0xFFFFFF, dark: 0x0B1230)
    static let actionSurface = Color(light: 0xE3E9FA, dark: 0x182A5C)
    /// Linework on cards and canvases.
    static let drafting = Color(light: 0x8FD3FF, dark: 0x60A8E6)
    static let draftingInk = Color(light: 0x2369B5, dark: 0x60A8E6)
    static let timberInk = Color(light: 0x8A5A1B, dark: 0xF0BE7A)
    static let textPrimary = Color(light: 0x121B33, dark: 0xF2F4FA)
    static let textSecondary = Color(light: 0x4A5068, dark: 0xB4BCD2)
    static let textTertiary = Color(light: 0x5F6983, dark: 0x8A94B2)
    static let border = Color(light: 0xD5DBEA, dark: 0x2A3560)
    static let borderLight = Color(light: 0xE5EAF4, dark: 0x222C55)
    static let positive = Color(light: 0x137A42, dark: 0x4ED48A)
    static let positiveSurface = Color(light: 0xE4F7EB, dark: 0x123A2A)
    static let caution = Color(light: 0x9A560C, dark: 0xFFB454)
    static let cautionSurface = Color(light: 0xFCF0DC, dark: 0x3D2A10)
    static let destructive = Color(light: 0xC1303A, dark: 0xFF7A7A)
    static let destructiveSurface = Color(light: 0xFCE4E5, dark: 0x44181C)
    static let informational = Color(light: 0x4A6392, dark: 0x9BB0D0)
    static let informationalSurface = Color(light: 0xE6ECF6, dark: 0x1E2A4A)
    static let rose = Color(light: 0xB04266, dark: 0xF08BAA)
    static let roseSurface = Color(light: 0xF9E3EA, dark: 0x3A1A28)
}

// MARK: - Motion

enum S2Motion {
    static func collapse(_ reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.86)
    }
    static func snappy(_ reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0)
    }
    static let crossfade = Animation.easeOut(duration: 0.2)
}

// MARK: - Fraunces (bundled variable font, registered at launch)

enum S2Font {
    static func register() {
        guard UIFont.fontNames(forFamilyName: "Fraunces").isEmpty,
              let url = Bundle.main.url(forResource: "Fraunces", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func tag(_ t: String) -> UInt32 { t.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1.value & 0xFF) } }

    /// Fraunces 500 with opsz/SOFT set, scaled with Dynamic Type relative to .largeTitle. Never under 28pt.
    static func display(_ size: CGFloat, opsz: CGFloat = 96, soft: CGFloat = 30, dts: DynamicTypeSize) -> Font {
        Font(displayUIFont(size, opsz: opsz, soft: soft, dts: dts))
    }

    static func displayUIFont(_ size: CGFloat, opsz: CGFloat = 96, soft: CGFloat = 30, dts: DynamicTypeSize) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: dts.uiCategory)
        let base = UIFontDescriptor(fontAttributes: [.family: "Fraunces"])
        let d = base.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
            NSNumber(value: tag("wght")): 500, NSNumber(value: tag("opsz")): opsz, NSNumber(value: tag("SOFT")): soft,
        ]])
        var f = UIFont(descriptor: d, size: size)
        if f.familyName != "Fraunces" {
            f = UIFont(descriptor: UIFont.systemFont(ofSize: size, weight: .medium).fontDescriptor.withDesign(.serif)!, size: size)
        }
        let scaled = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: f, maximumPointSize: 60, compatibleWith: traits)
        return scaled.pointSize < 28 ? scaled.withSize(28) : scaled
    }
}

extension DynamicTypeSize {
    var uiCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

/// Fraunces tab-root / article title.
struct DisplayTitle: View {
    let text: String
    var size: CGFloat = 34
    /// Width left for the title (screen minus margins and any control beside it).
    var reserve: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let ui = S2Font.displayUIFont(size, dts: dts)
        let avail = UIScreen.main.bounds.width - reserve
        let longest = text.split(separator: " ").map { (String($0) as NSString).size(withAttributes: [.font: ui]).width }.max() ?? 0
        let scale = longest > avail ? avail / longest * 0.97 : 1
        Text(text)
            .font(Font(ui.withSize(ui.pointSize * scale)))
            .foregroundStyle(LHB.textPrimary)
            .lineLimit(3)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Surfaces

struct S2CardModifier: ViewModifier {
    var radius: CGFloat = 20
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var solid
    func body(content: Content) -> some View {
        content
            .background(LHB.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func s2Card(_ radius: CGFloat = 20) -> some View { modifier(S2CardModifier(radius: radius)) }

    /// The one section-header style: 13 semibold caps, +0.3 tracking, secondary.
    func s2Section() -> some View {
        font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.3).foregroundStyle(LHB.textSecondary)
    }

    /// SF Mono drafting label (blueprint surfaces only).
    func drafting(_ color: Color = LHB.draftingHero, size: CGFloat = 11) -> some View {
        font(.system(size: size, weight: .medium, design: .monospaced)).textCase(.uppercase).tracking(1.3).foregroundStyle(color)
    }

    func roundedNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded)).monospacedDigit()
    }
}

struct S2Header<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).s2Section().accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension S2Header where Trailing == EmptyView {
    init(_ title: String) { self.title = title; self.trailing = { EmptyView() } }
}

struct SeeAll: View {
    var label = "See all"
    var body: some View {
        Text(label).font(.subheadline).foregroundStyle(LHB.action)
    }
}

/// Hairline inset to the text column.
struct InsetDivider: View {
    var leading: CGFloat = 16
    var body: some View { Rectangle().fill(LHB.border).frame(height: 0.5).padding(.leading, leading) }
}

// MARK: - Buttons (only four)

struct S2Primary: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(enabled ? LHB.onAction : LHB.textSecondary)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(Capsule().fill(enabled ? LHB.action : LHB.tertiary))
            .overlay(Capsule().strokeBorder(enabled ? Color.clear : LHB.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduce ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Compact primary (44pt, hugs its label) for locked previews.
struct S2PrimaryCompact: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LHB.onAction)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(Capsule().fill(LHB.action))
            .scaleEffect(configuration.isPressed && !reduce ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct S2OnBlueprint: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(LHB.brand)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Color.white))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct S2Tinted: ButtonStyle {
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LHB.action)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(Capsule().fill(LHB.actionSurface))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct S2Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 44pt glass close (as on the confirm sheet).
struct GlassClose: View {
    var systemName = "xmark"
    var label = "Close"
    var action: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var solid
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LHB.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background { if solid { Circle().fill(LHB.card) } }
        .glassEffect(solid ? .identity : .regular.interactive(), in: Circle())
        .accessibilityLabel(label)
    }
}

/// Our own switch with a visible off track (InboxSwitchStyle).
struct S2Switch: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? LHB.action : (scheme == .dark ? Color(hex: 0x39446E) : Color(hex: 0xC7CEDD)))
                        .frame(width: 51, height: 31)
                    Circle().fill(configuration.isOn ? LHB.onAction : Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .frame(width: 27, height: 27).padding(2)
                }
                .animation(reduce ? nil : .easeInOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Categories (3D tool tiles)

enum S2Cat: String, CaseIterable, Identifiable {
    case repairs, management, leasing, bookkeeping, legal, travel, renovations
    case investing, financing, insurance, negotiation
    var id: String { rawValue }

    static let grid: [S2Cat] = [.repairs, .renovations, .management, .leasing, .bookkeeping, .legal, .travel]
    static let more: [S2Cat] = [.investing, .financing, .insurance, .negotiation]

    var label: String {
        switch self {
        case .repairs: "Repairs"
        case .management: "Management"
        case .leasing: "Leasing"
        case .bookkeeping: "Bookkeeping"
        case .legal: "Legal"
        case .travel: "Travel"
        case .renovations: "Renovation"
        case .investing: "Investing"
        case .financing: "Financing"
        case .insurance: "Insurance"
        case .negotiation: "Negotiation"
        }
    }

    var tool: String {
        switch self {
        case .repairs: "repairs"
        case .management: "management"
        case .leasing: "showing"
        case .bookkeeping: "bookkeeping"
        case .legal: "legal"
        case .negotiation: "negotiation"
        case .insurance: "insurance"
        case .investing: "investing"
        case .financing: "financing"
        case .travel: "travel"
        case .renovations: "renovation"
        }
    }

    /// Each category has its own ink, taken from its tool's colour, so bars and labels match the icon.
    var ink: Color {
        switch self {
        case .repairs: Color(light: 0x8A5A1B, dark: 0xF0BE7A)       // timber wrench
        case .renovations: Color(light: 0xB4432E, dark: 0xF09A84)   // terracotta roller
        case .management: Color(light: 0x8C6A00, dark: 0xF2CF5B)    // amber clipboard
        case .leasing: Color(light: 0x1B6C8C, dark: 0x7CC6E4)       // harbour blue (matches onboarding lane)
        case .bookkeeping: Color(light: 0x56702A, dark: 0xB5D07A)   // moss ledger
        case .legal: Color(light: 0x2369B5, dark: 0x60A8E6)         // drafting-ink deed
        case .travel: Color(light: 0x4A6392, dark: 0x9BB0D0)        // slate truck
        case .negotiation: Color(light: 0xB0560F, dark: 0xF5A867)   // orange speech bubbles
        case .insurance: Color(light: 0x2F3E7A, dark: 0x9FB0EE)     // navy shield
        case .investing: Color(light: 0x6E7412, dark: 0xD3D46A)     // olive-gold coins
        case .financing: Color(light: 0x8F4A22, dark: 0xE9A27B)     // copper key
        }
    }

    var wash: Color { ink.opacity(0.14) }

    /// Every category has a 3D tool render now (r4); no symbol stand-ins.
    var symbol: String? { nil }
}

struct ToolTile: View {
    let cat: S2Cat?
    var size: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(cat?.wash ?? LHB.tertiary)
            .frame(width: size, height: size)
            .overlay {
                if let cat, let sym = cat.symbol {
                    Image(systemName: sym).font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(cat.ink).symbolRenderingMode(.hierarchical)
                } else if let cat {
                    Image("bp_tool_\(cat.tool)_\(size > 40 ? 56 : 36)").resizable().scaledToFit().padding(size * 0.08)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(LHB.drafting, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .padding(size * 0.22)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Properties: seal + mini house

struct S2Property: Identifiable, Hashable {
    let id: String
    var name: String
    var address: String
    var longStays: Bool = true
    var hours: Double
    var entries: Int = 0
    var last: String = "Oct 16"
    var liveHere = false
    var aliases: [String] = []
    /// Creation order. The seal colour cycles through the 5 palettes by this, so neighbours differ
    /// and a property keeps its colour (it never moves in creation order).
    var order: Int = 0

    var kindLabel: String { longStays ? "Long stays" : "A few nights" }
    /// Same words with non-breaking spaces, so a meta line never wraps "A / few nights".
    var kindMeta: String { kindLabel.replacingOccurrences(of: " ", with: "\u{00A0}") }
    /// Initials of the first two words, skipping "The", "A" and "An".
    var monogram: String {
        let skip: Set<String> = ["the", "a", "an"]
        let words = name.split(separator: " ")
            .filter { $0.first?.isLetter == true && !skip.contains($0.lowercased()) }
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String((words.first ?? Substring(name)).prefix(2)).uppercased()
    }
}

enum SealPalette: Int, CaseIterable {
    case blueprint, timber, terracotta, brass, slate
    var ink: Color {
        switch self {
        case .blueprint: Color(light: 0x1E3FA6, dark: 0x8FD3FF)
        case .timber: Color(light: 0x8A5A1B, dark: 0xF0BE7A)
        case .terracotta: Color(light: 0xB4432E, dark: 0xF09A84)
        case .brass: Color(light: 0x7A5E1E, dark: 0xE8C877)
        case .slate: Color(light: 0x4A6392, dark: 0x9BB0D0)
        }
    }
    /// Stable FNV-1a hash of the property id: the model never stores a colour.
    static func forID(_ id: String) -> SealPalette {
        var h: UInt32 = 2166136261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return SealPalette(rawValue: Int(h % 5))!
    }
}

struct PropertySeal: View {
    var monogram: String
    var palette: SealPalette
    var size: CGFloat = 40
    var dashed = false

    init(_ p: S2Property, size: CGFloat = 40) {
        monogram = p.monogram; palette = SealPalette(rawValue: p.order % 5)!; self.size = size
    }
    init(monogram: String, palette: SealPalette = .blueprint, size: CGFloat = 40, dashed: Bool = false) {
        self.monogram = monogram; self.palette = palette; self.size = size; self.dashed = dashed
    }

    var body: some View {
        let ink = dashed ? LHB.textTertiary : palette.ink
        ZStack {
            Circle().fill(ink.opacity(dashed ? 0.06 : 0.14))
            if dashed {
                Circle().strokeBorder(ink.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                Circle().strokeBorder(ink.opacity(0.4), lineWidth: 1)
                Circle().strokeBorder(ink.opacity(0.22), lineWidth: 0.5).padding(3)
            }
            Text(monogram)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - House art (ported from release/2.0 HouseArtView)

enum S2House {
    static let keys = ["k00_lot", "k01_slab", "k02_frame010", "k03_frame020", "k04_frame030", "k05_frame040", "k06_frame050",
                       "k07_frame060", "k08_frame070", "k09_frame080", "k10_frame090", "k11_frame100", "k12_roof",
                       "k13_siding020", "k14_siding040", "k15_siding060", "k16_siding080", "k17_siding100", "k18_finished"]

    /// HouseProgress.keyframe(for:) — floor rule, one absolute scale.
    static func keyframe(_ raw: Double) -> String {
        let h = max(0, raw)
        if h < 100 { return keys[0] }
        if h < 500 {
            let slot = Int(((h - 100) / 400 * 10).rounded(.down))
            return slot <= 0 ? keys[1] : keys[1 + min(slot, 9)]
        }
        if h <= 750 {
            if h == 750 { return keys[17] }
            let slot = Int(((h - 500) / 250 * 5).rounded(.down))
            return slot <= 0 ? keys[12] : keys[12 + min(slot, 5)]
        }
        return keys[18]
    }

    /// The property mini-house is pinned to the 500h material-participation line (owner decision):
    /// it tops out at "roof on".
    static func propertyKeyframe(_ h: Double) -> String { keyframe(min(h, 500)) }

    static let ctx = CIContext()
    nonisolated(unsafe) static var cache: [String: UIImage] = [:]

    static func linework(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard let src = UIImage(named: name), let cg = src.cgImage,
              let m = CIFilter(name: "CIColorMatrix"), let clamp = CIFilter(name: "CIColorClamp") else { return nil }
        m.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 2.4), forKey: "inputAVector")
        clamp.setValue(m.outputImage, forKey: kCIInputImageKey)
        guard let out = clamp.outputImage, let r = ctx.createCGImage(out, from: CIImage(cgImage: cg).extent) else { return nil }
        let img = UIImage(cgImage: r, scale: src.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
        cache[name] = img
        return img
    }
}

struct HouseArt: View {
    let key: String
    var lineColor: Color = LHB.draftingHero
    /// The drafted future house. Full strength on heroes; faint on the 48pt mini-house so the
    /// built stage (lot vs poured slab vs frame vs roof) is what reads at that size.
    var lineOpacity: Double = 1
    var body: some View {
        ZStack {
            Image(decorative: "bp_house_\(key)_built").resizable().interpolation(.high).scaledToFit()
            if let l = S2House.linework("bp_house_\(key)_lines") {
                Image(uiImage: l).renderingMode(.template).resizable().interpolation(.high).scaledToFit().foregroundStyle(lineColor)
                    .opacity(lineOpacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Property's own hours on the 500h ladder, on a plaster tile. Always paired with an hours label.
struct PropertyHouse: View {
    let hours: Double
    var size: CGFloat = 48
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Blueprint tile (as on Today): the plaster slab and timber frame read against blue,
        // where a plaster tile swallowed the slab. Linework is fainter at mini size.
        S2Paper(radius: size * 0.28)
            .frame(width: size, height: size)
            .overlay {
                HouseArt(key: S2House.propertyKeyframe(hours), lineColor: LHB.draftingHero, lineOpacity: size < 80 ? 0 : 0.8)
                    .scaleEffect(1.18)
                    .offset(y: -size * 0.02)
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The mini-house stage in words (default wording; "212h of 500h" only for a per-property goal).
func houseStage(_ h: Double) -> String {
    if h < 1 { return "An empty lot" }
    if h < 100 { return "Breaking ground" }
    if h < 140 { return "Foundation poured" }
    if h < 500 { return "Frame going up" }
    return "Roof on"
}

/// "212h of 500h" — neutral, never "failing". Past the line: "520h · roof's on".
func houseLine(_ h: Double) -> String {
    h >= 500 ? "\(Int(h))h · roof’s on" : "\(Int(h))h of 500h"
}

// MARK: - Loading (never spinners)

struct PlaceholderBar: View {
    var width: CGFloat? = 120
    var height: CGFloat = 14
    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(LHB.border.opacity(0.7))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityLabel("Loading")
    }
}

/// A 1–2pt drafting line that draws itself left to right, then restarts. Reduce Motion: static line.
struct DraftingLine: View {
    var color: Color = LHB.draftingInk
    var lineWidth: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let p = reduce ? 1 : CGFloat((t.truncatingRemainder(dividingBy: 1.6)) / 1.6)
            GeometryReader { g in
                Path { $0.move(to: .init(x: 0, y: g.size.height / 2)); $0.addLine(to: .init(x: g.size.width, y: g.size.height / 2)) }
                    .trim(from: reduce ? 0 : max(0, p - 0.55), to: p)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .frame(height: max(2, lineWidth))
        .opacity(reduce ? 0.6 : 1)
        .accessibilityHidden(true)
    }
}

/// A drafting outline (page or house) that draws itself in. Reduce Motion: drawn, still.
struct DraftingLoader: View {
    enum Kind { case document, house }
    var kind: Kind = .document
    var color: Color = LHB.draftingHero
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let p = reduce ? 1 : min(1, CGFloat(t.truncatingRemainder(dividingBy: 2.0)) / 1.5)
            ZStack {
                outline.stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                outline.trim(from: 0, to: p).stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                details.trim(from: 0, to: max(0, p * 1.3 - 0.3)).stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .aspectRatio(kind == .document ? 0.77 : 1, contentMode: .fit)
        .accessibilityLabel(kind == .document ? "Drawing your record" : "Loading")
    }

    private var outline: some Shape {
        kind == .document ? AnyShape(DocOutline()) : AnyShape(HouseOutline())
    }
    private var details: some Shape {
        kind == .document ? AnyShape(DocLines()) : AnyShape(HouseDetails())
    }
}

struct DocOutline: Shape {
    func path(in r: CGRect) -> Path { Path(roundedRect: r.insetBy(dx: 2, dy: 2), cornerRadius: 4) }
}
struct DocLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let x0 = r.minX + r.width * 0.14, x1 = r.maxX - r.width * 0.14
        p.move(to: .init(x: x0, y: r.minY + r.height * 0.14)); p.addLine(to: .init(x: x0 + (x1 - x0) * 0.55, y: r.minY + r.height * 0.14))
        for i in 0..<7 {
            let y = r.minY + r.height * (0.3 + Double(i) * 0.085)
            p.move(to: .init(x: x0, y: y)); p.addLine(to: .init(x: i % 3 == 2 ? x0 + (x1 - x0) * 0.7 : x1, y: y))
        }
        return p
    }
}
struct HouseOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: .init(x: x + w * 0.18, y: y + h * 0.86))
        p.addLine(to: .init(x: x + w * 0.18, y: y + h * 0.48))
        p.addLine(to: .init(x: x + w * 0.5, y: y + h * 0.2))
        p.addLine(to: .init(x: x + w * 0.82, y: y + h * 0.48))
        p.addLine(to: .init(x: x + w * 0.82, y: y + h * 0.86))
        p.closeSubpath()
        return p
    }
}
struct HouseDetails: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.addRect(CGRect(x: x + w * 0.42, y: y + h * 0.62, width: w * 0.16, height: h * 0.24))
        p.addRect(CGRect(x: x + w * 0.62, y: y + h * 0.55, width: w * 0.12, height: h * 0.1))
        p.move(to: .init(x: x + w * 0.08, y: y + h * 0.86)); p.addLine(to: .init(x: x + w * 0.92, y: y + h * 0.86))
        return p
    }
}

// MARK: - Blueprint paper

struct S2Paper: View {
    var radius: CGFloat = 24
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2447B5), LHB.brand, Color(hex: 0x18348C)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Canvas { c, s in
                    var p = Path(); let step: CGFloat = 22
                    var x: CGFloat = 0; while x <= s.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: s.height)); x += step }
                    var y: CGFloat = 0; while y <= s.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: s.width, y: y)); y += step }
                    c.stroke(p, with: .color(LHB.draftingHero.opacity(0.12)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - THE locked preview

enum LockSize { case page, card, row }

enum PaywallContext: Equatable {
    case export, secondProperty(String?), todayUnlock, settings
}

/// Real content renders; its first block stays sharp; below the fold it blurs under a canvas fade,
/// with one line and one "Unlock Pro" capsule centred on top.
struct LockedPreview<Content: View>: View {
    let size: LockSize
    let line: String
    /// What stays active while locked (Brian's paywall law): "Pine Cabin keeps tracking. Nothing is lost."
    let keeps: String
    /// Sharp height from the top (page/card).
    var fold: CGFloat = 120
    var unlocked = false
    var surface: Color = LHB.canvas
    var onUnlock: () -> Void = {}
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts

    private var radius: CGFloat { unlocked ? 0 : (size == .row ? 4 : 10) }

    var body: some View {
        switch size {
        case .row: row
        default: block
        }
    }

    private var block: some View {
        ZStack(alignment: .top) {
            content()
                .blur(radius: radius)
                .mask(alignment: .top) { VStack(spacing: 0) { Color.clear.frame(height: unlocked ? 0 : fold); Color.black } }
                .accessibilityHidden(!unlocked)
            content()
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.black.frame(height: fold)
                        if !unlocked { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16) }
                        Color.clear
                    }
                }
                .opacity(unlocked ? 0 : 1)
            if !unlocked {
                GeometryReader { g in
                    VStack(spacing: 0) {
                        Color.clear.frame(height: fold)
                        LinearGradient(colors: [surface.opacity(0), surface.opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 48)
                        surface.opacity(0.85)
                    }
                    .overlay(alignment: .top) {
                        cta.frame(width: g.size.width).padding(.top, fold + min(150, max(24, (g.size.height - fold - 110) / 2)))
                    }
                }
                .allowsHitTesting(true)
                .transition(.opacity)
            }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3), value: unlocked)
    }

    private var cta: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LHB.textPrimary)
                Text(keeps)
                    .font(.footnote)
                    .foregroundStyle(LHB.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            Button(action: onUnlock) { Label("Unlock Pro", systemImage: "lock.fill") }
                .buttonStyle(S2PrimaryCompact())
                .accessibilityIdentifier("lock.unlock")
        }
        .accessibilityElement(children: .contain)
    }

    private var row: some View {
        VStack(spacing: 0) {
            content().blur(radius: unlocked ? 0 : 4).opacity(unlocked ? 1 : 0.6)
                .accessibilityHidden(!unlocked)
            if !unlocked {
                let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                        Text(keeps).font(.footnote).foregroundStyle(LHB.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onUnlock) { Label("Unlock Pro", systemImage: "lock.fill") }
                        .buttonStyle(S2PrimaryCompact()).fixedSize()
                        .accessibilityIdentifier("lock.unlock")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3), value: unlocked)
    }
}

/// Light status-bar text while a blue hero sits under the status bar (paywall), dark otherwise.
@MainActor @Observable final class S2StatusBar {
    static let shared = S2StatusBar()
    var overHero = false
}

// MARK: - Undo toast

struct UndoToast: View {
    let text: String
    var action = "Undo"
    @Environment(\.accessibilityReduceTransparency) private var solid
    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(LHB.textPrimary).lineLimit(2)
            Text("·").foregroundStyle(LHB.textTertiary)
            Button(action) {}.font(.subheadline.weight(.semibold)).foregroundStyle(LHB.action)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .background { if solid { Capsule().fill(LHB.card) } }
        .glassEffect(solid ? .identity : .regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension AnyTransition {
    /// In 220ms, out 180ms.
    static var toast: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).animation(.easeOut(duration: 0.22)),
                    removal: .opacity.animation(.easeIn(duration: 0.18)))
    }
}

/// "1h 30m".
func hm(_ h: Double) -> String {
    let t = Int((h * 60).rounded()); let hh = t / 60, mm = t % 60
    if mm == 0 { return "\(hh)h" }
    if hh == 0 { return "\(mm)m" }
    return "\(hh)h \(mm)m"
}

/// Scroll edge under the status bar: content fades into the canvas instead of colliding with the clock.
struct TopEdgeFade: View {
    var body: some View {
        // A zero-height anchor on the safe-area line; the gradient hangs above it (over the
        // status bar) and 18pt below it. Overlays aren't clipped, so it reaches the screen top.
        Color.clear.frame(maxWidth: .infinity).frame(height: 0)
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [.init(color: LHB.canvas, location: 0), .init(color: LHB.canvas, location: 0.78), .init(color: LHB.canvas.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
                    .offset(y: 18)
            }
            .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
