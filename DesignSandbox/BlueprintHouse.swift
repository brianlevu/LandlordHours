import SwiftUI

/// The Blueprint house: a chart with a roof. Height is confirmed hours, nothing else.
/// 0–100h pours the foundation, 100–500h raises the walls (timber frame leads the plaster),
/// 500h lands the roof, 750h lights the windows and hangs the key.
struct BlueprintHouse: View {
    var hours: Double
    var roofDrop: CGFloat = 0          // roof landing offset (pt), animated by callers
    var roofFill: Double = 1           // terracotta fill 0…1 during the 500h moment
    var hatchHours: Double = 0         // day-1 backfill: found-but-unconfirmed hours, hatched only
    var linework: Double = 1           // 0…1 trim for the sketch-in
    var glowBand: Double = 0           // 0…1 opacity of the "new course" glow after a confirm
    var showScale = true

    /// Rendered layers (creative-r3 assets, registered + matted) when present; vector fallback otherwise.
    static let useArt = UIImage(named: "bp-house-built") != nil
    static var base: CGFloat { useArt ? 0.885 : 0.90 }
    static var foundationTop: CGFloat { useArt ? 0.83 : 0.84 }
    static var eave: CGFloat { useArt ? 0.47 : 0.42 }
    static var apex: CGFloat { useArt ? 0.05 : 0.14 }

    static func buildY(_ h: Double) -> CGFloat {
        if h <= 0 { return base }
        if h <= 100 { return base - (base - foundationTop) * h / 100 }
        if h <= 500 { return foundationTop - (foundationTop - eave) * (h - 100) / 400 }
        return eave
    }

    var body: some View {
        if BlueprintHouse.useArt { artBody } else { vectorBody }
    }

    private var artBody: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let by = BlueprintHouse.buildY(hours)
            let hy = BlueprintHouse.buildY(hatchHours)
            let lines = Image(uiImage: UIImage(named: "bp-house-lines")!).resizable().scaledToFit()
            let frame = Image(uiImage: UIImage(named: "bp-house-frame") ?? UIImage(named: "bp-house-built")!).resizable().scaledToFit()
            let built = Image(uiImage: UIImage(named: "bp-house-built")!).resizable().scaledToFit()
            ZStack(alignment: .topLeading) {
                lines
                    .mask(BottomMask(y: 1 - linework))
                    .opacity(hours >= 500 && roofFill >= 1 ? 0.55 : 1)
                if hatchHours > hours {
                    // Suggestions: hatched in drafting cyan, never solid.
                    built.opacity(0.14).mask(FeatherMask(y: hy, feather: 0.02))
                    Hatch()
                        .stroke(BP.suggested, lineWidth: 1.6)
                        .mask(built)
                        .mask(FeatherMask(y: hy, feather: 0.015))
                }
                if hours > 100 && hours < 500 {
                    frame.mask(FeatherMask(y: max(BlueprintHouse.eave, by - 0.09), feather: 0.035))
                        .mask(TopCut(y: BlueprintHouse.eave))
                }
                built.mask(FeatherMask(y: by, feather: 0.028))
                if hours >= 500 {
                    ZStack {
                        frame.mask(TopCut(y: BlueprintHouse.eave, keepAbove: true))
                        built.mask(TopCut(y: BlueprintHouse.eave, keepAbove: true))
                            .opacity(roofFill)
                    }
                    .offset(y: roofDrop)
                }
                Rectangle()
                    .fill(LinearGradient(colors: [BP.timber.opacity(0), BP.window, BP.timber.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.72, height: max(4, s * 0.02))
                    .blur(radius: 3)
                    .position(x: s * 0.5, y: s * by)
                    .opacity(glowBand)
                if showScale { DraftingScale(hours: hours).opacity(linework) }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("House built to \(Int(hours)) of 750 confirmed hours")
    }

    private var vectorBody: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let by = BlueprintHouse.buildY(hours)
            let hy = BlueprintHouse.buildY(hatchHours)
            ZStack(alignment: .topLeading) {
                // Ground shadow
                Ellipse().fill(.black.opacity(0.22)).blur(radius: 6)
                    .frame(width: s * 0.8, height: s * 0.05)
                    .position(x: s * 0.5, y: s * 0.915)

                // Hatched found hours (backfill): never solid
                if hatchHours > hours {
                    Hatch()
                        .stroke(BP.drafting.opacity(0.55), lineWidth: 1)
                        .mask(HouseBody().fill())
                        .mask(BottomMask(y: hy))
                }

                // Timber frame leads the plaster by a storey's sliver
                if hours > 100 {
                    Studs()
                        .stroke(BP.timber, style: StrokeStyle(lineWidth: max(1.5, s * 0.008), lineCap: .square))
                        .mask(BottomMask(y: max(0.42, by - 0.07)))
                }

                // Built layer
                BuiltHouse(lit: hours >= 750)
                    .mask(BottomMask(y: by))

                // Glow on the newest course
                Rectangle()
                    .fill(LinearGradient(colors: [BP.timber.opacity(0), BP.window, BP.timber.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.66, height: max(4, s * 0.02))
                    .blur(radius: 3)
                    .position(x: s * 0.5, y: s * by)
                    .opacity(glowBand)

                // Roof (from 500h)
                if hours >= 500 {
                    Roof(fill: roofFill)
                        .offset(y: roofDrop)
                }

                // Linework, always on top so the unbuilt storeys stay visible
                HouseLines()
                    .trim(from: 0, to: linework)
                    .stroke(BP.drafting, style: StrokeStyle(lineWidth: max(1, s * 0.005), lineCap: .round, lineJoin: .round))
                    .opacity(hours >= 500 && roofFill >= 1 ? 0.35 : 0.95)

                if showScale { DraftingScale(hours: hours).opacity(linework) }

                // Key on the door at 750h
                if hours >= 750 {
                    Image(systemName: "key.fill")
                        .font(.system(size: s * 0.05, weight: .bold))
                        .foregroundStyle(BP.brass)
                        .rotationEffect(.degrees(-30))
                        .position(x: s * 0.64, y: s * 0.76)
                }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("House built to \(Int(hours)) of 750 confirmed hours")
    }
}

/// Soft construction wipe: opaque below `y`, fading to clear over `feather` above it.
/// Applied on top of the render's own alpha, so the reveal follows the house silhouette.
struct FeatherMask: View, @MainActor Animatable {
    var y: CGFloat
    var feather: CGFloat
    // Animate the edge position itself (geometry), never the gradient: interpolating gradient
    // stops crossfades two masks and momentarily hides built plaster.
    var animatableData: CGFloat {
        get { y }
        set { y = newValue }
    }
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, (y - feather) * h))
                LinearGradient(colors: [.clear, .black.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: feather * 1.2 * h)
                Color.black
            }
            .frame(width: g.size.width, height: h, alignment: .top)
            .clipped()
        }
    }
}

/// Keeps everything below `y` (or above it with keepAbove).
struct TopCut: View {
    var y: CGFloat
    var keepAbove = false
    var body: some View {
        GeometryReader { g in
            Rectangle()
                .frame(height: keepAbove ? g.size.height * y : g.size.height * (1 - y))
                .frame(maxHeight: .infinity, alignment: keepAbove ? .top : .bottom)
        }
    }
}

struct BottomMask: View {
    var y: CGFloat
    var body: some View {
        GeometryReader { g in
            Rectangle()
                .frame(height: max(0, g.size.height * (1 - y)))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Geometry (unit square)

private func P(_ x: CGFloat, _ y: CGFloat, _ r: CGRect) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
private func R(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ r: CGRect) -> CGRect {
    CGRect(x: r.minX + x0 * r.width, y: r.minY + y0 * r.height, width: (x1 - x0) * r.width, height: (y1 - y0) * r.height)
}

struct HouseBody: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRect(R(0.14, 0.84, 0.86, 0.90, r))
        p.addRect(R(0.18, 0.42, 0.82, 0.84, r))
        return p
    }
}

struct Studs: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0.18
        while x <= 0.821 {
            p.move(to: P(x, 0.42, r)); p.addLine(to: P(x, 0.84, r)); x += 0.053
        }
        for y in [0.42, 0.63, 0.84] as [CGFloat] { p.move(to: P(0.18, y, r)); p.addLine(to: P(0.82, y, r)) }
        return p
    }
}

struct Hatch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = -r.height
        while x < r.width {
            p.move(to: CGPoint(x: r.minX + x, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + x + r.height, y: r.minY)); x += 7
        }
        return p
    }
}

/// All outlines, drawn in drafting cyan, plus dimension marks.
struct HouseLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRect(R(0.14, 0.84, 0.86, 0.90, r))             // foundation
        p.addRect(R(0.18, 0.42, 0.82, 0.84, r))             // walls
        p.move(to: P(0.18, 0.63, r)); p.addLine(to: P(0.82, 0.63, r))   // floor
        p.move(to: P(0.12, 0.42, r)); p.addLine(to: P(0.50, 0.14, r)); p.addLine(to: P(0.88, 0.42, r))   // roof
        p.addRect(R(0.66, 0.18, 0.73, 0.31, r))             // chimney
        for w in [R(0.25, 0.47, 0.38, 0.58, r), R(0.62, 0.47, 0.75, 0.58, r), R(0.25, 0.68, 0.38, 0.79, r)] {
            p.addRect(w); p.move(to: CGPoint(x: w.midX, y: w.minY)); p.addLine(to: CGPoint(x: w.midX, y: w.maxY))
            p.move(to: CGPoint(x: w.minX, y: w.midY)); p.addLine(to: CGPoint(x: w.maxX, y: w.midY))
        }
        p.addRect(R(0.56, 0.67, 0.68, 0.84, r))             // door
        p.move(to: P(0.52, 0.665, r)); p.addLine(to: P(0.78, 0.665, r))   // porch roof
        p.move(to: P(0.53, 0.665, r)); p.addLine(to: P(0.53, 0.84, r))
        p.move(to: P(0.77, 0.665, r)); p.addLine(to: P(0.77, 0.84, r))
        // Dimension line on the right
        p.move(to: P(0.93, 0.14, r)); p.addLine(to: P(0.93, 0.90, r))
        for y in [0.14, 0.42, 0.63, 0.84, 0.90] as [CGFloat] { p.move(to: P(0.915, y, r)); p.addLine(to: P(0.945, y, r)) }
        return p
    }
}

struct BuiltHouse: View {
    var lit: Bool
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            ZStack(alignment: .topLeading) {
                Path { $0.addRect(R(0.14, 0.84, 0.86, 0.90, r)) }.fill(BP.concrete)
                Path { $0.addRect(R(0.14, 0.84, 0.86, 0.855, r)) }.fill(.white.opacity(0.25))
                // walls with siding
                Path { $0.addRect(R(0.18, 0.42, 0.82, 0.84, r)) }.fill(BP.plaster)
                Path { $0.addRect(R(0.70, 0.42, 0.82, 0.84, r)) }.fill(BP.plasterShade.opacity(0.55))
                Path { p in
                    var y: CGFloat = 0.45
                    while y < 0.84 { p.move(to: P(0.18, y, r)); p.addLine(to: P(0.82, y, r)); y += 0.03 }
                }.stroke(BP.plasterShade, lineWidth: 0.6)
                Path { $0.addRect(R(0.18, 0.62, 0.82, 0.64, r)) }.fill(BP.timber)
                // windows
                ForEach(0..<3, id: \.self) { i in
                    let w = [R(0.25, 0.47, 0.38, 0.58, r), R(0.62, 0.47, 0.75, 0.58, r), R(0.25, 0.68, 0.38, 0.79, r)][i]
                    Path { $0.addRect(w.insetBy(dx: -2, dy: -2)) }.fill(BP.slate)
                    Path { $0.addRect(w) }.fill(lit ? BP.window : BP.glass)
                    Path { p in
                        p.move(to: CGPoint(x: w.midX, y: w.minY)); p.addLine(to: CGPoint(x: w.midX, y: w.maxY))
                        p.move(to: CGPoint(x: w.minX, y: w.midY)); p.addLine(to: CGPoint(x: w.maxX, y: w.midY))
                    }.stroke(BP.slate, lineWidth: 1.5)
                    if !lit {
                        Path { p in p.move(to: CGPoint(x: w.minX + 3, y: w.maxY - 3)); p.addLine(to: CGPoint(x: w.minX + w.width * 0.45, y: w.minY + 3)) }
                            .stroke(.white.opacity(0.25), lineWidth: 2)
                    }
                }
                // door + porch
                Path { $0.addRect(R(0.56, 0.67, 0.68, 0.84, r)) }.fill(BP.timberDark)
                Path { $0.addEllipse(in: R(0.655, 0.75, 0.665, 0.76, r)) }.fill(BP.brass)
                Path { $0.addRect(R(0.52, 0.655, 0.78, 0.672, r)) }.fill(BP.timber)
                Path { p in p.addRect(R(0.528, 0.672, 0.538, 0.84, r)); p.addRect(R(0.762, 0.672, 0.772, 0.84, r)) }.fill(BP.timber)
                Path { $0.addRect(R(0.50, 0.835, 0.80, 0.85, r)) }.fill(BP.timberDark)
            }
        }
    }
}

struct Roof: View {
    var fill: Double
    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            ZStack(alignment: .topLeading) {
                Path { $0.addRect(R(0.66, 0.18, 0.73, 0.33, r)) }.fill(BP.terracottaDark)
                Path { p in
                    p.move(to: P(0.10, 0.43, r)); p.addLine(to: P(0.50, 0.135, r)); p.addLine(to: P(0.90, 0.43, r)); p.closeSubpath()
                }
                .fill(LinearGradient(colors: [BP.terracotta, BP.terracottaDark], startPoint: .top, endPoint: .bottom))
                .opacity(fill)
                Path { p in
                    for i in 1..<6 {
                        let t = CGFloat(i) / 6
                        let y = 0.135 + (0.43 - 0.135) * t
                        let half = 0.40 * t
                        p.move(to: P(0.50 - half, y, r)); p.addLine(to: P(0.50 + half, y, r))
                    }
                }
                .stroke(.black.opacity(0.14), lineWidth: 1)
                .opacity(fill)
                Path { p in p.move(to: P(0.10, 0.43, r)); p.addLine(to: P(0.90, 0.43, r)) }
                    .stroke(BP.terracottaDark, lineWidth: 3)
                    .opacity(fill)
            }
        }
    }
}

/// Drafting scale down the left edge: ticks at 100 / 500 / 750, cyan triangle at the current height.
struct DraftingScale: View {
    var hours: Double
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            let marks: [(Double, CGFloat)] = [(100, BlueprintHouse.foundationTop), (500, BlueprintHouse.eave), (750, BlueprintHouse.apex)]
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: s * 0.035, y: s * BlueprintHouse.apex)); p.addLine(to: CGPoint(x: s * 0.035, y: s * BlueprintHouse.base))
                    for (_, y) in marks { p.move(to: CGPoint(x: s * 0.01, y: s * y)); p.addLine(to: CGPoint(x: s * 0.06, y: s * y)) }
                }
                .stroke(BP.drafting.opacity(0.8), lineWidth: 1)
                ForEach(marks, id: \.0) { m in
                    Text("\(Int(m.0))")
                        .font(.system(size: max(8, s * 0.034), weight: .semibold, design: .rounded))
                        .foregroundStyle(BP.drafting)
                        .position(x: s * 0.075 + 8, y: s * m.1 - 7)
                }
                Triangle()
                    .fill(BP.drafting)
                    .frame(width: 9, height: 8)
                    .rotationEffect(.degrees(-90))
                    .position(x: s * 0.06 + 5, y: s * BlueprintHouse.buildY(hours))
            }
        }
    }
}

/// Small house silhouette for the Live Activity / thumbnails: cyan outline, built part plaster.
struct HouseGlyph: View {
    var hours: Double
    var body: some View {
        BlueprintHouse(hours: hours, showScale: false)
    }
}
