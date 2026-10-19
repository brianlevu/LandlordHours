import SwiftUI
import LucideIcons

// MARK: - Design System for LandlordHours
// 2.0 Blueprint brand system. Source of truth: docs/design/2.0-brand-system.md + design/brand/

// MARK: - Colors
//
// LandlordHours 2.0 "Blueprint" palette (docs/design/2.0-brand-system.md §2, locked 2026-10-19).
// Blueprint blue #1E3FA6 is the brand AND the light-mode action colour; dark mode's action is the
// drafting cyan #8FD3FF ("the action colour is always the ink on the paper"). Violet is retired:
// the legacy violet-named tokens below keep their NAMES so existing screens compile, but resolve
// to blueprint-family values. Contrast is recorded in design/brand/contrast.txt and asserted by
// Tests/ColorContrastTests.swift.
//
// Tokens that mean an intent (action, positive, caution, destructive, informational, rose) are
// dynamic: they resolve per light/dark trait, so a bare `AppColors.x` follows the effective
// scheme. Surfaces and neutrals named for light mode stay light-only; the `dark*` tokens are their
// dark counterparts. Prefer `AdaptiveColors` in views.
enum AppColors {
    // MARK: Hex sources (shared by AppColors and AdaptiveColors)
    enum Hex {
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
        static let darkTextTertiary = "7E88A6"
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
    }

    // MARK: - Brand (new in 2.0)
    /// Blueprint blue. Theme-fixed: the hero, the app icon and brand fills. White on it is 9.06:1.
    static let brand = Color(hex: Hex.brand)
    /// Drafting cyan linework (decorative, non-text). Light #8FD3FF; dark steps down to #60A8E6 so
    /// linework never shares a hex with the dark action colour.
    static let drafting = Color.lhDynamic(light: Hex.drafting, dark: Hex.darkDrafting)
    /// SF Mono drafting labels on cards: #2369B5 (5.6:1 on white) / #60A8E6 (6.5:1 on the dark card).
    static let draftingInk = Color.lhDynamic(light: Hex.draftingInk, dark: Hex.darkDrafting)
    /// Timber: the warm material accent (illustration). Not for text — use `timberInk`.
    static let timber = Color(hex: Hex.timber)
    /// Timber as text: #8A5A1B (5.9:1 on white) / #F0BE7A (9.74:1 on the dark card).
    static let timberInk = Color.lhDynamic(light: Hex.timberInk, dark: Hex.darkTimberInk)
    /// Illustration-only materials.
    static let brass = Color(hex: Hex.brass)
    static let terracotta = Color(hex: Hex.terracotta)
    static let plaster = Color(hex: Hex.plaster)

    // MARK: - Light surfaces
    static let background = Color(hex: Hex.canvas)
    static let backgroundSecondary = Color.white
    static let backgroundTertiary = Color(hex: Hex.tertiary)

    // MARK: - Primary (legacy name for the action/brand blue)
    static let primary = Color.lhDynamic(light: Hex.brand, dark: Hex.darkAction)
    static let primaryLight = Color.lhDynamic(light: "5C7FD6", dark: Hex.darkDrafting)
    static let primarySurface = Color.lhDynamic(light: Hex.actionSurface, dark: Hex.darkActionSurface)
    static let primaryDark = Color.lhDynamic(light: Hex.actionPressed, dark: Hex.darkActionPressed)

    // MARK: - Accent palette (legacy names, 2.0 values)
    static let coral = Color.lhDynamic(light: Hex.terracotta, dark: Hex.darkDestructive)   // repair / destructive accent
    static let coralWash = Color.lhDynamic(light: Hex.destructiveSurface, dark: Hex.darkDestructiveSurface)
    static let sage = Color.lhDynamic(light: Hex.positive, dark: Hex.darkPositive)          // success, met, healthy
    static let sageWash = Color.lhDynamic(light: Hex.positiveSurface, dark: Hex.darkPositiveSurface)
    static let honey = Color.lhDynamic(light: Hex.caution, dark: Hex.darkCaution)           // behind pace, needs attention
    static let honeyWash = Color.lhDynamic(light: Hex.cautionSurface, dark: Hex.darkCautionSurface)
    static let sky = Color.lhDynamic(light: Hex.informational, dark: Hex.darkInformational) // informational slate
    static let skyWash = Color.lhDynamic(light: Hex.informationalSurface, dark: Hex.darkInformationalSurface)
    static let rose = Color.lhDynamic(light: Hex.rose, dark: Hex.darkRose)                  // spouse / people
    static let roseWash = Color.lhDynamic(light: Hex.roseSurface, dark: Hex.darkRoseSurface)
    // Former lavender/indigo washes → blueprint tints.
    static let lavenderPanel = Color(hex: "F3F6FD")
    static let lavenderMist = Color(hex: Hex.actionSurface)
    static let lavenderField = Color(hex: "EDF1FB")
    static let skyMist = Color(hex: "E6F4FE")
    static let aquaMist = Color(hex: "F0FDFA")
    static let blueSoft = Color(hex: Hex.drafting)
    static let successDeep = Color(hex: Hex.positive)
    static let indigoMist = Color(hex: Hex.actionSurface)
    static let lavenderSoft = Color(hex: "BFD0F2")
    static let lavenderPale = Color(hex: "F3F6FD")
    static let darkPlum = Color(hex: "101A3E")
    static let darkInk = Color(hex: "0E1636")

    // MARK: - Semantic (legacy names)
    static let success = sage
    static let warning = honey
    static let error = Color.lhDynamic(light: Hex.destructive, dark: Hex.darkDestructive)

    // MARK: - Intent aliases (new UI uses these)
    //
    // Light: white on blueprint #1E3FA6 = 9.06:1. Dark: navy #0B1230 on cyan #8FD3FF = 11.31:1.
    static let actionLightHex = Hex.brand
    static let actionDarkHex = Hex.darkAction
    static let onActionLightHex = "FFFFFF"
    static let onActionDarkHex = Hex.darkOnAction
    static let action = Color.lhDynamic(light: actionLightHex, dark: actionDarkHex)
    static let actionSurface = primarySurface
    static let actionPressed = primaryDark
    static let onAction = Color.lhDynamic(light: onActionLightHex, dark: onActionDarkHex)
    static let positive = sage
    static let positiveSurface = sageWash
    static let caution = honey
    static let cautionSurface = honeyWash
    /// #C1303A: 5.6:1 on white, 4.63:1 on its own wash. Dark #FF7A7A: 6.56:1 on the dark card.
    static let destructiveLightHex = Hex.destructive
    static let destructive = Color.lhDynamic(light: destructiveLightHex, dark: Hex.darkDestructive)
    static let destructiveSurface = coralWash
    static let informational = sky
    static let informationalSurface = skyWash
    static let informationalTextLightHex = Hex.informational
    static let informationalText = Color.lhDynamic(light: informationalTextLightHex, dark: Hex.darkInformational)
    static let cautionTextLightHex = Hex.caution
    static let positiveTextLightHex = Hex.positive

    // MARK: - Reports goal palettes (legacy names, blueprint values)
    static let reportsAccent = primary
    static let reportsAccentSoft = Color.lhDynamic(light: "5C7FD6", dark: Hex.darkDrafting)
    static let reportsAccentWash = primarySurface
    static let mpAccent = draftingInk
    static let mpAccentSoft = Color(hex: Hex.drafting)
    static let mpAccentWash = Color.lhDynamic(light: "E6F2FC", dark: "16304F")
    static let successGreen = sage
    static let successGreenLight = Color.lhDynamic(light: "2FA866", dark: Hex.darkPositive)
    static let successGreenSoft = Color(hex: "7FDDA6")
    static let successGreenWash = sageWash
    static let cautionText = Color.lhDynamic(light: Hex.caution, dark: Hex.darkCaution)
    static let repairOrange = Color(hex: Hex.terracotta)
    static let dataBlue = Color(hex: "60A8E6")
    static let dataBlueDeep = Color(hex: "2369B5")
    static let dataRed = Color(hex: "C1303A")
    static let dataEmerald = Color(hex: "2FA866")
    static let dataPink = Color(hex: "B04266")

    // MARK: - Celebration palette (former purples → blueprint night)
    static let celebrationDeepPurple = Color(hex: Hex.blueprintPaper)
    static let celebrationPurple = Color(hex: Hex.brand)
    static let celebrationIndigo = Color(hex: "2A4FBF")
    static let celebrationLavender = Color(hex: Hex.darkDrafting)
    static let celebrationNightPurple = Color(hex: "101A3E")

    // MARK: - Logo artwork palette (mark B)
    static let logoCanvas = Color(hex: Hex.brand)
    static let logoWaveLightStart = Color(hex: Hex.drafting)
    static let logoWaveMidStart = Color(hex: Hex.plaster)
    static let logoWaveMidEnd = Color(hex: Hex.plaster)
    static let logoWaveStrongStart = Color(hex: Hex.terracotta)
    static let logoWaveDeepStart = Color(hex: Hex.brand)
    static let logoWaveDeepEnd = Color(hex: Hex.blueprintPaper)

    // MARK: - Neutrals (light)
    static let charcoal = Color(hex: Hex.textPrimary)    // headlines, primary text
    static let ink = Color(hex: "2B3450")                // secondary text
    static let slate = Color(hex: Hex.textSecondary)     // captions, inactive labels
    static let mist = Color(hex: Hex.textTertiary)       // placeholders, tertiary
    static let cloud = Color(hex: Hex.border)            // borders, dividers
    static let snow = Color(hex: Hex.tertiary)           // inputs, subtle surfaces

    // Legacy aliases for backward compatibility
    static let textPrimary = charcoal
    static let textSecondary = slate
    static let textTertiary = mist
    static let border = cloud
    static let borderLight = Color(hex: Hex.borderLight)
    static let info = sky

    // MARK: - Dark Theme Colors
    static let darkBackground = Color(hex: Hex.darkCanvas)
    static let darkBackgroundSecondary = Color(hex: Hex.darkCard)
    static let darkBackgroundTertiary = Color(hex: Hex.darkTertiary)
    static let darkPrimarySurface = Color(hex: Hex.darkActionSurface)

    static let darkPrimary = Color(hex: Hex.darkAction)
    static let darkSuccess = Color(hex: Hex.darkPositive)
    static let darkWarning = Color(hex: Hex.darkCaution)
    static let darkError = Color(hex: Hex.darkDestructive)

    // Dark accent washes (for jelly icon containers)
    static let darkCoralWash = Color(hex: Hex.darkDestructiveSurface)
    static let darkSageWash = Color(hex: Hex.darkPositiveSurface)
    static let darkHoneyWash = Color(hex: Hex.darkCautionSurface)
    static let darkSkyWash = Color(hex: Hex.darkInformationalSurface)
    static let darkRoseWash = Color(hex: Hex.darkRoseSurface)

    static let darkTextPrimary = Color(hex: Hex.darkTextPrimary)
    static let darkTextSecondary = Color(hex: Hex.darkTextSecondary)
    static let darkTextTertiary = Color(hex: Hex.darkTextTertiary)
    /// Secondary text that sits directly on the dark canvas (9.68:1 on #0B1230).
    static let darkTextSecondaryOnCanvasHex = Hex.darkTextSecondary

    static let darkBorder = Color(hex: Hex.darkBorder)
}

extension Color {
    /// A color that resolves per trait collection (light/dark), so static tokens such as
    /// `AppColors.onAction` follow the effective scheme, including `.preferredColorScheme`.
    static func lhDynamic(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            UIColor(lhHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(lhHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Color Scheme Aware Colors
struct AdaptiveColors {
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }
    private func pick(_ light: String, _ dark: String) -> Color { Color(hex: isDark ? dark : light) }
    private typealias H = AppColors.Hex

    // Surfaces
    var background: Color { pick(H.canvas, H.darkCanvas) }
    var backgroundSecondary: Color { pick(H.card, H.darkCard) }
    var backgroundTertiary: Color { pick(H.tertiary, H.darkTertiary) }
    var primarySurface: Color { pick(H.actionSurface, H.darkActionSurface) }

    // Brand (new in 2.0)
    var brand: Color { AppColors.brand }
    /// Decorative linework (non-text).
    var drafting: Color { pick(H.drafting, H.darkDrafting) }
    /// SF Mono drafting labels on cards / canvas.
    var draftingInk: Color { pick(H.draftingInk, H.darkDrafting) }
    var timber: Color { AppColors.timber }
    var timberInk: Color { pick(H.timberInk, H.darkTimberInk) }

    // Legacy names
    var primary: Color { pick(H.brand, H.darkAction) }
    var success: Color { positive }
    var warning: Color { caution }
    var error: Color { destructive }

    // Intents
    var action: Color { pick(AppColors.actionLightHex, AppColors.actionDarkHex) }
    var onAction: Color { pick(AppColors.onActionLightHex, AppColors.onActionDarkHex) }
    var actionSurface: Color { primarySurface }
    var positive: Color { pick(H.positive, H.darkPositive) }
    var positiveSurface: Color { pick(H.positiveSurface, H.darkPositiveSurface) }
    var caution: Color { pick(H.caution, H.darkCaution) }
    var cautionSurface: Color { pick(H.cautionSurface, H.darkCautionSurface) }
    var destructive: Color { pick(H.destructive, H.darkDestructive) }
    var destructiveSurface: Color { pick(H.destructiveSurface, H.darkDestructiveSurface) }
    var informational: Color { pick(H.informational, H.darkInformational) }
    var informationalSurface: Color { pick(H.informationalSurface, H.darkInformationalSurface) }
    /// Action-coloured TEXT on actionSurface or cards: 7.47:1 / 8.48:1.
    var actionText: Color { action }
    var positiveText: Color { positive }
    var informationalText: Color { informational }
    var cautionText: Color { caution }

    // Legacy accent names → intents
    var coral: Color { pick(H.terracotta, H.darkDestructive) }
    var sage: Color { positive }
    var honey: Color { caution }
    var sky: Color { informational }
    var rose: Color { pick(H.rose, H.darkRose) }

    var coralWash: Color { destructiveSurface }
    var sageWash: Color { positiveSurface }
    var honeyWash: Color { cautionSurface }
    var skyWash: Color { informationalSurface }
    var roseWash: Color { pick(H.roseSurface, H.darkRoseSurface) }

    // Text
    var textPrimary: Color { pick(H.textPrimary, H.darkTextPrimary) }
    var textSecondary: Color { pick(H.textSecondary, H.darkTextSecondary) }
    var textTertiary: Color { pick(H.textTertiary, H.darkTextTertiary) }
    /// Secondary text placed straight on the page canvas (not on a card).
    var textSecondaryOnCanvas: Color { textSecondary }

    /// Hairline (decorative; cards separate by fill).
    var border: Color { pick(H.border, H.darkBorder) }

    /// Glass effect background for tab bar, overlays
    var glass: Color { isDark ? AppColors.darkBackground.opacity(0.85) : Color.white.opacity(0.85) }
}

// MARK: - Appearance Preference
enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Match device"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }

    var confirmationText: String {
        switch self {
        case .system: return "Saved - following device"
        case .light: return "Saved - light mode"
        case .dark: return "Saved - dark mode"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private let storageKey = "LandlordHours.appearancePreference"

    @Published var preference: AppAppearancePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: storageKey)
        }
    }

    var preferredColorScheme: ColorScheme? {
        preference.preferredColorScheme
    }

    static var forcedColorSchemeFromLaunchArguments: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHColorScheme"),
              args.indices.contains(index + 1) else {
            return nil
        }

        switch args[index + 1].lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHResetAppearancePreference") {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        #endif
        let raw = UserDefaults.standard.string(forKey: storageKey)
        preference = raw.flatMap(AppAppearancePreference.init(rawValue:)) ?? .system
    }
}

// MARK: - Typography
//
// 2.0 type system (docs/design/2.0-brand-system.md §3):
// - SF Pro for body and UI, scaled with Dynamic Type through text styles.
// - SF Pro Rounded with tabular digits for numbers (hours, counts, progress).
// - SF Mono (`design: .monospaced`) for drafting labels: eyebrows, ticks, "2026 · REPS GOAL".
// - Fraunces (bundled, SIL OFL 1.1, Sources/Resources/Fonts) for display text at 28pt and up ONLY:
//   tab titles, Welcome, milestones. Never in lists, never on numbers or tax lines, never in the PDF.
//   Prefer `.lhDisplayFont(_:)`, which also sets the optical size and SOFT axes and follows
//   Dynamic Type; the `AppTypography.largeTitle/headline` Font tokens are the simple fallback.
enum AppTypography {
    // Fraunces display (≥28pt; Dynamic Type via relativeTo:)
    static let display = LHFont.fraunces(LHDisplayStyle.display)
    static let headlineLarge = LHFont.fraunces(LHDisplayStyle.largeTitle)
    static let headline = LHFont.fraunces(LHDisplayStyle.title)

    // SF Pro body / UI (text styles, so they follow Dynamic Type)
    static let subheadline = Font.system(.body, design: .default, weight: .semibold)  // 17 semibold
    static let body = Font.system(.subheadline, design: .default)                    // 15
    static let bodyLarge = Font.system(.body, design: .default)                      // 17
    static let bodySmall = Font.system(.footnote, design: .default)                  // 13
    static let caption = Font.system(.caption, design: .default, weight: .medium)    // 12
    static let footnote = Font.system(.footnote, design: .default)                   // 13

    // SF Mono drafting labels (11pt; uppercase + .tracking(1.3) at the call site)
    static let drafting = Font.system(.caption2, design: .monospaced, weight: .medium)
    static let label = drafting

    // SF Pro Rounded numbers, tabular. The hero numeral scales via `.lhHeroNumberFont()` (capped so
    // it stays inside the ring); `ringNumber` is decorative and fixed; metrics scale.
    /// Default-size hero numeral. Views use `.lhHeroNumberFont()`, which scales it with
    /// Dynamic Type relative to .largeTitle (capped at `LHFont.heroNumberMaxSize`).
    static let heroNumber = Font.system(size: LHFont.heroNumberBaseSize, weight: .bold, design: .rounded).monospacedDigit()
    static let ringNumber = Font.system(size: 46, weight: .bold, design: .rounded).monospacedDigit()
    static let metric = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let number = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()

    // Buttons
    static let buttonLarge = Font.system(.body, design: .default, weight: .semibold)     // 17
    static let button = Font.system(.callout, design: .default, weight: .semibold)       // 16
    static let buttonSmall = Font.system(.footnote, design: .default, weight: .semibold) // 13

    // Names kept for existing call sites
    static let largeTitle = headlineLarge
    static let title1 = headline
    static let title2 = Font.system(.title2, design: .default, weight: .semibold)        // 22
    static let title3 = Font.system(.title3, design: .default, weight: .semibold)        // 20
}

/// Fraunces display styles. Every case is ≥28pt: Fraunces is never used below that.
enum LHDisplayStyle: CaseIterable {
    /// 34 / 500, opsz 144, SOFT 50 — Welcome, milestones.
    case display
    /// 34 / 500, opsz 96 — tab titles.
    case largeTitle
    /// 28 / 500, opsz 72 — section display (Today's header greeting).
    case title

    var size: CGFloat {
        switch self {
        case .display, .largeTitle: return 34
        case .title: return 28
        }
    }

    var weight: CGFloat { 500 }

    var opticalSize: CGFloat {
        switch self {
        case .display: return 144
        case .largeTitle: return 96
        case .title: return 72
        }
    }

    var softness: CGFloat {
        switch self {
        case .display: return 50
        case .largeTitle, .title: return 30
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .display, .largeTitle: return .largeTitle
        case .title: return .title
        }
    }

    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .display, .largeTitle: return .largeTitle
        case .title: return .title1
        }
    }
}

enum LHFont {
    /// Family name of the bundled variable font (Sources/Resources/Fonts/Fraunces.ttf, UIAppFonts).
    static let frauncesFamily = "Fraunces"
    /// Minimum point size Fraunces may be used at.
    static let frauncesMinimumSize: CGFloat = 28

    static var isFrauncesAvailable: Bool {
        !UIFont.fontNames(forFamilyName: frauncesFamily).isEmpty
    }

    /// Simple Font token: Fraunces at the style's size, scaled relative to its text style.
    /// Falls back to New York (the system serif) if the font failed to register.
    static func fraunces(_ style: LHDisplayStyle) -> Font {
        guard isFrauncesAvailable else {
            return Font.system(style.textStyle, design: .serif, weight: .medium)
        }
        return Font.custom(frauncesFamily, size: style.size, relativeTo: style.textStyle).weight(.medium)
    }

    /// Fraunces with its variation axes set (wght, opsz, SOFT), scaled for a content size category.
    static func frauncesUIFont(_ style: LHDisplayStyle, contentSize: UIContentSizeCategory = .large) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
        let metrics = UIFontMetrics(forTextStyle: style.uiTextStyle)
        let base = UIFontDescriptor(fontAttributes: [.family: frauncesFamily])
        let variations: [NSNumber: CGFloat] = [
            NSNumber(value: axisTag("wght")): style.weight,
            NSNumber(value: axisTag("opsz")): style.opticalSize,
            NSNumber(value: axisTag("SOFT")): style.softness,
        ]
        let descriptor = base.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations
        ])
        let font = UIFont(descriptor: descriptor, size: style.size)
        guard font.familyName == frauncesFamily else {
            let serif = UIFont.systemFont(ofSize: style.size, weight: .medium)
            let fallback = serif.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: style.size) } ?? serif
            return metrics.scaledFont(for: fallback, compatibleWith: traits)
        }
        let scaled = metrics.scaledFont(for: font, compatibleWith: traits)
        // Smaller Dynamic Type settings never take Fraunces under its 28pt floor.
        return scaled.pointSize < frauncesMinimumSize ? scaled.withSize(frauncesMinimumSize) : scaled
    }

    /// Hero hours numeral: 56pt at the default size, scaled like .largeTitle, never above 80pt.
    static let heroNumberBaseSize: CGFloat = 56
    static let heroNumberMaxSize: CGFloat = 80

    static func heroNumberSize(contentSize: UIContentSizeCategory) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
        let scaled = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: heroNumberBaseSize, compatibleWith: traits)
        return min(scaled, heroNumberMaxSize)
    }

    static func axisTag(_ tag: String) -> UInt32 {
        tag.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1.value & 0xFF) }
    }
}

private struct LHDisplayFontModifier: ViewModifier {
    let style: LHDisplayStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(Font(LHFont.frauncesUIFont(style, contentSize: dynamicTypeSize.lhContentSizeCategory)))
    }
}

private struct LHHeroNumberFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .font(.system(size: LHFont.heroNumberSize(contentSize: dynamicTypeSize.lhContentSizeCategory),
                          weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

extension View {
    /// SF Pro Rounded tabular hero numeral that follows Dynamic Type (relative to .largeTitle, capped).
    func lhHeroNumberFont() -> some View {
        modifier(LHHeroNumberFontModifier())
    }

    /// Fraunces display text (≥28pt) with optical size + SOFT axes, following Dynamic Type.
    func lhDisplayFont(_ style: LHDisplayStyle = .largeTitle) -> some View {
        modifier(LHDisplayFontModifier(style: style))
    }
}

extension DynamicTypeSize {
    var lhContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

// MARK: - Spacing
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    static let tabContentBottomInset: CGFloat = 176
    static let floatingTabBarReservedHeight: CGFloat = 132
}

// MARK: - Corner Radius
enum AppCornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Animation
enum AppAnimation {
    static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
    static let standard = SwiftUI.Animation.easeInOut(duration: 0.24)
    static let smooth = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let feedback = SwiftUI.Animation.easeOut(duration: 0.12)
    static let reveal = SwiftUI.Animation.easeOut(duration: 0.22)
    static let flow = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let bouncy = SwiftUI.Animation.spring(response: 0.32, dampingFraction: 0.86)

    // Specific presets from design system
    static let ringProgress = SwiftUI.Animation.spring(response: 0.7, dampingFraction: 0.82)
    static let pillPop = SwiftUI.Animation.spring(response: 0.26, dampingFraction: 0.82)
    static let logoEntrance = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.86)
}

// MARK: - Hours Formatting
enum AppFormat {
    /// Consistent hours display across the app: "1.5h", "10.0h"
    static func hours(_ value: Double) -> String {
        String(format: "%.1f", value) + "h"
    }

    /// Whole hours for large ring displays: "142"
    static func hoursWhole(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Custom Category Model
struct CustomCategory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var countsForREPS: Bool
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, iconName: String, colorHex: String, countsForREPS: Bool = true) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.countsForREPS = countsForREPS
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        iconName = try c.decode(String.self, forKey: .iconName)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        countsForREPS = try c.decode(Bool.self, forKey: .countsForREPS)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

// MARK: - Category Manager
class CategoryManager: ObservableObject {
    static let shared = CategoryManager()

    @Published var customCategories: [CustomCategory] = []

    private var userDefaultsKey: String { UserScope.key("customCategories") }
    
    let defaultCategories: [(name: String, icon: String, color: String, countsForREPS: Bool)] = [
        ("Repairs & Maintenance", "wrench.fill", "8B5CF6", true),
        ("Property Management", "building.2.fill", "34D399", true),
        ("Leasing & Tenant Relations", "key.fill", "60A5FA", true),
        ("Bookkeeping & Financial", "calculator", "FBBF24", true),
        ("Legal & Compliance", "doc.badge.gearshape", "F472B6", true),
        ("Insurance & Claims", "shield.fill", "A78BFA", true),
        ("Travel to Property", "car.fill", "3B82F6", true),
        ("Renovations & Improvements", "hammer.fill", "EF4444", true),
    ]
    
    var allCategories: [CustomCategory] {
        let defaults = defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) }
        return defaults + customCategories
    }
    
    init() {
        loadCategories()
    }
    
    func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let categories = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            customCategories = categories
        }
    }
    
    func saveCategories() {
        if let data = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        saveCategories()
    }
    
    func deleteCategory(_ category: CustomCategory) {
        customCategories.removeAll { $0.id == category.id }
        saveCategories()
    }
    
    func updateCategory(_ category: CustomCategory) {
        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
            saveCategories()
        }
    }

    func resetForSignOut() {
        customCategories = []
    }

    func resetForDataReset() {
        customCategories = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Available Icons and Colors
let availableCategoryIcons = [
    "house.fill", "building.2.fill", "building.fill", "key.fill",
    "wrench.fill", "hammer.fill", "paintbrush.fill", "drop.fill",
    "car.fill", "bus.fill", "airplane", "tram.fill",
    "doc.text.fill", "doc.badge.gearshape", "folder.fill",
    "phone.fill", "bubble.left.fill", "envelope.fill",
    "dollarsign.circle.fill", "creditcard.fill", "banknote.fill",
    "chart.bar.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill",
    "shield.fill", "lock.fill", "eye.fill", "camera.fill",
    "person.fill", "person.2.fill", "calendar", "clock.fill",
    "star.fill", "heart.fill", "flag.fill", "tag.fill",
    "megaphone.fill", "lightbulb.fill", "gearshape.fill"
]

let availableCategoryColors = [
    "8B5CF6", "A78BFA", "7C3AED",
    "34D399", "10B981", "059669",
    "60A5FA", "3B82F6", "1D4ED8",
    "FBBF24", "F59E0B", "D97706",
    "F472B6", "EC4899", "DB2777",
    "EF4444", "DC2626", "B91C1C",
    "F97316", "EA580C", "C2410C",
    "6B7280", "4B5563", "374151"
]

// MARK: - UIFont Rounded Extension
extension UIFont {
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

// MARK: - View Modifier for Adaptive Colors
struct AdaptiveColorModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var isSecondary: Bool = false
    var isTertiary: Bool = false

    func body(content: Content) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        content
            .foregroundColor(
                isTertiary ? colors.textTertiary :
                isSecondary ? colors.textSecondary :
                colors.textPrimary
            )
    }
}

extension View {
    func adaptiveText(isSecondary: Bool = false, isTertiary: Bool = false) -> some View {
        modifier(AdaptiveColorModifier(isSecondary: isSecondary, isTertiary: isTertiary))
    }

    func adaptiveBackground(_ colorScheme: ColorScheme) -> some View {
        self.background(AdaptiveColors(colorScheme: colorScheme).background)
    }

    func adaptiveCard() -> some View {
        modifier(AdaptiveCardModifier())
    }
}

// MARK: - Adaptive Card Modifier
private struct AdaptiveCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        content
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
    }
}

// MARK: - Aurora Background
/// Atmospheric floating gradient blobs — the signature LandlordHours background effect
struct AuroraBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ZStack {
            colors.background.ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.primary.opacity(colorScheme == .dark ? 0.08 : 0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -100, y: -200)
                .blur(radius: 50)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.sage.opacity(colorScheme == .dark ? 0.06 : 0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 120, y: 100)
                .blur(radius: 50)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.coral.opacity(colorScheme == .dark ? 0.04 : 0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .offset(x: 80, y: -120)
                .blur(radius: 55)
        }
    }
}

// MARK: - Jelly Icon Badge
/// Squircle icon container with glass highlight and colored shadow — the "jelly-glass" system
struct JellyBadge: View {
    let systemName: String
    let color: Color
    var wash: Color? = nil
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            // Jelly-glass squircle container
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(color.opacity(0.8))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.30), location: 0),
                                    .init(color: Color.white.opacity(0.06), location: 0.4),
                                    .init(color: Color.black.opacity(0.04), location: 1.0)
                                ],
                                startPoint: UnitPoint(x: 0.15, y: 0),
                                endPoint: UnitPoint(x: 0.85, y: 1)
                            )
                        )
                )

            // Icon — try Lucide first, fall back to SF Symbol
            if let uiImage = UIImage(lucideId: systemName) {
                Image(uiImage: uiImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.45, height: size * 0.45)
                    .foregroundStyle(AppColors.onAction)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(AppColors.onAction)
            }
        }
        .shadow(color: color.opacity(0.35), radius: size * 0.25, y: size * 0.1)
    }
}
