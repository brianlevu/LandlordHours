import SwiftUI

// MARK: - Mark B geometry and views (shared by the app and the widget extension)
// Source: design/brand/logo/mark-b.svg. See LHLogo.swift for the logo and wordmark.

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
                with: .color(Color(brandHex: BrandHex.drafting)),
                style: StrokeStyle(lineWidth: LHMarkGeometry.draftWidth * s, lineCap: .round, lineJoin: .round)
            )
            context.fill(LHMarkGeometry.plasterPath(scale: s), with: .color(Color(brandHex: BrandHex.plaster)))
            context.stroke(
                LHMarkGeometry.roofPath(scale: s),
                with: .color(Color(brandHex: BrandHex.terracotta)),
                style: StrokeStyle(lineWidth: LHMarkGeometry.roofWidth * s, lineCap: .round)
            )
            context.fill(LHMarkGeometry.doorPath(scale: s), with: .color(Color(brandHex: BrandHex.timber)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

