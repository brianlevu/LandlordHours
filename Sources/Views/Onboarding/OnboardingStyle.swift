import SwiftUI

// MARK: - Onboarding tokens and the one component set
//
// One pill, one outline pill, one card, one link on every step (consistency audit). Colours are
// the 2.0 intent tokens from `AppColors.Hex`, resolved per trait so a subtree that overrides the
// colour scheme (the blueprint band) resolves them correctly.

enum OnbColor {
    private typealias H = AppColors.Hex
    static let canvas = Color.lhDynamic(light: H.canvas, dark: H.darkCanvas)
    static let card = Color.lhDynamic(light: H.card, dark: H.darkCard)
    static let tertiary = Color.lhDynamic(light: H.tertiary, dark: H.darkTertiary)
    static let action = AppColors.action
    static let onAction = AppColors.onAction
    static let actionSurface = Color.lhDynamic(light: H.actionSurface, dark: H.darkActionSurface)
    static let draftingInk = AppColors.draftingInk
    static let timberInk = AppColors.timberInk
    static let textPrimary = Color.lhDynamic(light: H.textPrimary, dark: H.darkTextPrimary)
    static let textSecondary = Color.lhDynamic(light: H.textSecondary, dark: H.darkTextSecondary)
    static let textTertiary = Color.lhDynamic(light: H.textTertiary, dark: H.darkTextTertiary)
    static let border = Color.lhDynamic(light: H.border, dark: H.darkBorder)
    static let positive = Color.lhDynamic(light: H.positive, dark: H.darkPositive)
    /// People / spouse only.
    static let rose = Color.lhDynamic(light: H.rose, dark: H.darkRose)
    static let roseSurface = Color.lhDynamic(light: H.roseSurface, dark: H.darkRoseSurface)
    static let informational = Color.lhDynamic(light: H.informational, dark: H.darkInformational)
    static let brand = AppColors.brand
}

enum OnbMotion {
    /// Header morph between steps (spring 0.5 / 0.85). Reduce Motion: a short cross-fade.
    static func morph(_ reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85) }
    /// Progress dimension line (0.35 / 0.9).
    static func progress(_ reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9) }
    /// In-flow reveal (notes, chips): the shipped `flow` spring.
    static func flow(_ reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : AppAnimation.flow }
}

extension View {
    /// SF Mono drafting label: 11pt medium caps, +12% tracking.
    func onbDrafting(_ color: Color) -> some View {
        self.font(AppTypography.drafting)
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// Press feedback: scale 0.97, 120 ms ease-out.
struct OnbPressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppAnimation.feedback, value: configuration.isPressed)
    }
}

/// Blueprint pill on white (dark: cyan on navy). Full width, 52pt.
struct OnbPrimaryPill: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(enabled ? OnbColor.onAction : OnbColor.textTertiary)
            .background(enabled ? OnbColor.action : OnbColor.tertiary, in: Capsule())
            .overlay { if !enabled { Capsule().strokeBorder(OnbColor.border, lineWidth: 1) } }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppAnimation.feedback, value: configuration.isPressed)
    }
}

/// Outlined pill of equal weight (the real "Not now").
struct OnbOutlinePill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(OnbColor.action)
            .overlay(Capsule().strokeBorder(OnbColor.action, lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppAnimation.feedback, value: configuration.isPressed)
    }
}

/// White pill on blueprint (both modes).
struct OnbHeroPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(OnbColor.brand)
            .background(HouseTokens.onHeroPrimary, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppAnimation.feedback, value: configuration.isPressed)
    }
}

/// The one text link.
struct OnbLink: ButtonStyle {
    var color: Color = OnbColor.action
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct OnbTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

struct OnbTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Cyan drafting dimension line: end stops, one tick per step, the drawn part grows with `trim`.
struct OnbDimensionLine: View {
    var total: Int
    var value: Int
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, mid = g.size.height / 2
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: w, y: mid)) }
                    .stroke(HouseTokens.drafting.opacity(0.28), lineWidth: 1.5)
                Path { p in p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: w, y: mid)) }
                    .trim(from: 0, to: CGFloat(value) / CGFloat(max(total, 1)))
                    .stroke(HouseTokens.drafting, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach(0...max(total, 1), id: \.self) { i in
                    Rectangle()
                        .fill(HouseTokens.drafting.opacity(i <= value ? 1 : 0.35))
                        .frame(width: 1.5, height: i == 0 || i == total ? 12 : 7)
                        .position(x: w * CGFloat(i) / CGFloat(max(total, 1)), y: mid)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(value) of \(total)")
    }
}
