import SwiftUI

// MARK: - Dormer mark (2.2 brand, approved V3 2026-10-27)
//
// An outlined capital D whose counter is a house-shaped room under a shallow gable. Shared by the
// app and the widget extension. Source of truth: design/brand/dormer/make_dormer_icon.py, which
// writes the same geometry to the app icon (AppIcon.icon + the AppIcon set), the launch mark and
// design/brand/dormer/DormerMarkGeometry.txt. Change the generator, then copy its numbers here.

/// Theme-fixed brand values for the Dormer tile (the in-app twin of the app icon).
enum DormerBrand {
    /// The icon ground: a diagonal blueprint gradient, top-left to bottom-right.
    static let tileTop = "2A4FC0"
    static let tileMid = "1E3FA6"      // = BrandHex.brand
    static let tileBottom = "152E80"
    static let tileMidLocation: CGFloat = 0.55
    /// The display name. Not localized: it is the brand.
    static let name = "Dormer"
}

/// The mark's geometry in the 1024 design grid, placed exactly as on the app icon.
enum DormerMarkGeometry {
    static let grid: CGFloat = 1024

    /// Outer D, clockwise from the stem's top-left: stem top, shoulder, gable point, shoulder, stem bottom.
    static let outer: [CGPoint] = [
        CGPoint(x: 172.96, y: 183.36), CGPoint(x: 655.52, y: 183.36), CGPoint(x: 894.72, y: 470.40),
        CGPoint(x: 655.52, y: 840.64), CGPoint(x: 172.96, y: 840.64),
    ]
    static let outerRadii: [CGFloat] = [45.76, 35.36, 22.88, 35.36, 45.76]

    /// The counter (the room under the gable), same vertex order.
    static let inner: [CGPoint] = [
        CGPoint(x: 343.52, y: 295.68), CGPoint(x: 589.37, y: 295.68), CGPoint(x: 742.66, y: 479.62),
        CGPoint(x: 581.98, y: 728.32), CGPoint(x: 343.52, y: 728.32),
    ]
    static let innerRadii: [CGFloat] = [14.56, 14.56, 10.4, 14.56, 14.56]

    /// The ink's bounding box in the grid (the rounded point stops short of its vertex).
    static let inkBounds = CGRect(x: 172.96, y: 183.36, width: 888.0 - 172.96, height: 840.64 - 183.36)

    /// A closed polygon whose corners are quadratic curves with the vertex as control point, the
    /// same construction as the generator's `corners()`.
    static func roundedPolygon(_ points: [CGPoint], radii: [CGFloat], into path: inout Path,
                               transform: (CGPoint) -> CGPoint) {
        let n = points.count
        for i in 0..<n {
            let p0 = points[(i + n - 1) % n], p1 = points[i], p2 = points[(i + 1) % n]
            let v0 = CGPoint(x: p0.x - p1.x, y: p0.y - p1.y), l0 = hypot(v0.x, v0.y)
            let v2 = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y), l2 = hypot(v2.x, v2.y)
            let r = min(radii[i], l0 / 2, l2 / 2)
            let a = CGPoint(x: p1.x + v0.x / l0 * r, y: p1.y + v0.y / l0 * r)
            let b = CGPoint(x: p1.x + v2.x / l2 * r, y: p1.y + v2.y / l2 * r)
            if i == 0 { path.move(to: transform(a)) } else { path.addLine(to: transform(a)) }
            path.addQuadCurve(to: transform(b), control: transform(p1))
        }
        path.closeSubpath()
    }
}

/// Single-colour Dormer mark (template). Fill it with any style: the counter is wound the other
/// way, so it stays open under the default non-zero fill as well as even-odd.
///
/// `cropped: false` (default) draws in the icon's square grid, so a 60pt frame matches a 60pt
/// app icon. `cropped: true` fits the ink's bounding box to the rect, for lockups beside a wordmark.
struct DormerMarkShape: Shape {
    var cropped = false

    func path(in rect: CGRect) -> Path {
        let source = cropped
            ? DormerMarkGeometry.inkBounds
            : CGRect(x: 0, y: 0, width: DormerMarkGeometry.grid, height: DormerMarkGeometry.grid)
        let s = min(rect.width / source.width, rect.height / source.height)
        let dx = rect.minX + (rect.width - source.width * s) / 2 - source.minX * s
        let dy = rect.minY + (rect.height - source.height * s) / 2 - source.minY * s
        let t: (CGPoint) -> CGPoint = { CGPoint(x: $0.x * s + dx, y: $0.y * s + dy) }
        var p = Path()
        DormerMarkGeometry.roundedPolygon(DormerMarkGeometry.outer, radii: DormerMarkGeometry.outerRadii,
                                          into: &p, transform: t)
        DormerMarkGeometry.roundedPolygon(DormerMarkGeometry.inner.reversed(),
                                          radii: DormerMarkGeometry.innerRadii.reversed(),
                                          into: &p, transform: t)
        return p
    }
}

/// The Dormer app-icon tile at any size: the blueprint gradient with the white mark, clipped to the
/// continuous icon corner. The in-app twin of the app icon (flat; the system adds no glass here).
struct DormerTile: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(brandHex: DormerBrand.tileTop), location: 0),
                    .init(color: Color(brandHex: DormerBrand.tileMid), location: DormerBrand.tileMidLocation),
                    .init(color: Color(brandHex: DormerBrand.tileBottom), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            DormerMarkShape().fill(Color.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .accessibilityHidden(true)
    }
}
