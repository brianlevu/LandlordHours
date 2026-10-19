import SwiftUI

// MARK: - LandlordHours 2.0 logo — mark B "half drawn, half built"
//
// Source: design/brand/logo/mark-b.svg (1024 grid, translate(10 -11.5) for optical centring) and
// design/brand/icon/icon-b-1024.png (the approved app icon). A house elevation on blueprint blue:
// foundation, left wall, left roof slope and door are built (plaster / terracotta / timber); the
// right slope, upper right wall and window are still drafting-cyan linework.
// Brand rules: docs/design/2.0-brand-system.md §5.

/// The mark's geometry in the 1024 design grid (already optically centred).
enum LHMarkGeometry {
    static let grid: CGFloat = 1024
    static let offset = CGSize(width: 10, height: -11.5)
    static let draftWidth: CGFloat = 26
    static let roofWidth: CGFloat = 66

    static func point(_ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> CGPoint {
        CGPoint(x: (x + offset.width) * scale, y: (y + offset.height) * scale)
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(origin: point(x, y, scale: scale), size: CGSize(width: w * scale, height: h * scale))
    }

    /// Drawn (cyan) linework: right roof slope, right wall edge, window. Stroke these.
    static func draftPath(scale s: CGFloat) -> Path {
        var p = Path()
        p.move(to: point(512, 232, scale: s)); p.addLine(to: point(836, 486, scale: s))
        p.move(to: point(770, 436, scale: s)); p.addLine(to: point(770, 700, scale: s))
        p.addRoundedRect(in: rect(588, 540, 120, 96, scale: s), cornerSize: CGSize(width: 12 * s, height: 12 * s))
        return p
    }

    /// Built plaster: slab, left wall, right wall to the course. Fill.
    static func plasterPath(scale s: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect(222, 808, 580, 40, scale: s), cornerSize: CGSize(width: 10 * s, height: 10 * s))
        p.addRect(rect(250, 470, 262, 342, scale: s))
        p.addRect(rect(512, 690, 258, 122, scale: s))
        return p
    }

    /// Built terracotta roof slope (left). Stroke with `roofWidth`.
    static func roofPath(scale s: CGFloat) -> Path {
        var p = Path()
        p.move(to: point(512, 232, scale: s)); p.addLine(to: point(188, 486, scale: s))
        return p
    }

    /// Timber door. Fill.
    static func doorPath(scale s: CGFloat) -> Path {
        var p = Path()
        p.move(to: point(382, 683, scale: s))
        p.addArc(center: point(429, 683, scale: s), radius: 47 * s,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: point(476, 812, scale: s))
        p.addLine(to: point(382, 812, scale: s))
        p.closeSubpath()
        return p
    }
}

/// Single-colour mark (template): tint with `.foregroundStyle`. For widgets, the Dynamic Island
/// and anywhere the mark sits on a system surface. Mirrors logo/mark-b-mono.svg.
struct LHMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let s = side / LHMarkGeometry.grid
        var p = Path()
        let round = StrokeStyle(lineWidth: LHMarkGeometry.draftWidth * s, lineCap: .round, lineJoin: .round)
        p.addPath(LHMarkGeometry.draftPath(scale: s).strokedPath(round))
        p.addPath(LHMarkGeometry.plasterPath(scale: s))
        p.addPath(LHMarkGeometry.roofPath(scale: s)
            .strokedPath(StrokeStyle(lineWidth: LHMarkGeometry.roofWidth * s, lineCap: .round)))
        p.addPath(LHMarkGeometry.doorPath(scale: s))
        let dx = rect.minX + (rect.width - side) / 2
        let dy = rect.minY + (rect.height - side) / 2
        return p.applying(CGAffineTransform(translationX: dx, y: dy))
    }
}

/// The full-colour mark on a transparent background (for blueprint surfaces such as the hero).
struct LHMark: View {
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / LHMarkGeometry.grid
            context.stroke(
                LHMarkGeometry.draftPath(scale: s),
                with: .color(Color(hex: AppColors.Hex.drafting)),
                style: StrokeStyle(lineWidth: LHMarkGeometry.draftWidth * s, lineCap: .round, lineJoin: .round)
            )
            context.fill(LHMarkGeometry.plasterPath(scale: s), with: .color(AppColors.plaster))
            context.stroke(
                LHMarkGeometry.roofPath(scale: s),
                with: .color(AppColors.terracotta),
                style: StrokeStyle(lineWidth: LHMarkGeometry.roofWidth * s, lineCap: .round)
            )
            context.fill(LHMarkGeometry.doorPath(scale: s), with: .color(AppColors.timber))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - App-icon tile (self-contained, any size)
/// The mark on its blueprint tile — the in-app twin of the app icon. The name is kept from 1.x so
/// existing call sites (splash, sign-in, onboarding) pick up the new mark.
struct WaveHouseIcon: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            AppColors.brand
            LHMark(size: size)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Logo (mark + wordmark)
struct LHLogo: View {
    var size: CGFloat = 80
    var showText: Bool = true
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: size * 0.2) {
            WaveHouseIcon(size: size)
                .shadow(color: AppColors.brand.opacity(0.22), radius: size * 0.12, y: size * 0.05)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
            if showText {
                LHWordmark(fontSize: max(size * 0.28, 17))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
            }
        }
        .onAppear {
            if animated && !reduceMotion {
                withAnimation(AppAnimation.logoEntrance.delay(0.1)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }
}

// MARK: - Compact Logo (for headers, nav bars)
struct LHCompactLogo: View {
    var size: CGFloat = 32

    var body: some View {
        WaveHouseIcon(size: size)
            .shadow(color: AppColors.brand.opacity(0.18), radius: size * 0.1, y: size * 0.04)
    }
}

// MARK: - Wordmark (text-only logo)
/// "Landlord" in ink + "Hours" in the action colour (blueprint in light, cyan in dark), per
/// logo/wordmark.svg. Fraunces 600 at 28pt and up; below that SF Pro semibold (the brand rule
/// keeps Fraunces off small text).
struct LHWordmark: View {
    var fontSize: CGFloat = 28

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var font: Font {
        if fontSize >= LHFont.frauncesMinimumSize && LHFont.isFrauncesAvailable {
            return Font.custom(LHFont.frauncesFamily, size: fontSize).weight(.semibold)
        }
        return Font.system(size: fontSize, weight: .semibold, design: .default)
    }

    var body: some View {
        (Text("Landlord").foregroundColor(colors.textPrimary)
         + Text("Hours").foregroundColor(colors.action))
            .font(font)
            .accessibilityLabel("LandlordHours")
    }
}

// MARK: - Previews
#Preview("Logo Sizes") {
    VStack(spacing: 40) {
        LHLogo(size: 120, showText: true, animated: true)

        HStack(spacing: 24) {
            WaveHouseIcon(size: 64)
            WaveHouseIcon(size: 48)
            LHCompactLogo(size: 32)
            LHMarkShape().fill(AppColors.brand).frame(width: 48, height: 48)
        }

        LHWordmark(fontSize: 34)
    }
    .padding()
    .background(AppColors.background)
}
