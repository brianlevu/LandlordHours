import SwiftUI

// MARK: - Waypoint: route line, heat strip, two-lane bar, spouse dots

/// Jan 1 → Dec 31 route with waypoints at 100h (MP test 3), 500h (MP test 1), 750h (REPS).
struct RouteLine: View {
    var logged: Double
    var expected: Double
    var goal: Double = 750
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduce

    private let stops: [(Double, String, String)] = [(100, "100h", "MP"), (500, "500h", "MP"), (750, "750h", "REPS")]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                let x = { (h: Double) in w * min(h / goal, 1) }
                ZStack(alignment: .leading) {
                    Capsule().fill(LH.fill).frame(height: 8)
                    Capsule().fill(color).frame(width: max(8, x(logged)), height: 8)
                        .animation(Motion.collapse(reduce), value: logged)
                    // Pace marker: dashed, where you should be today.
                    Path { p in
                        p.move(to: CGPoint(x: x(expected), y: 0))
                        p.addLine(to: CGPoint(x: x(expected), y: 26))
                    }
                    .stroke(LH.secondaryText, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(height: 26)
                    // Waypoints
                    ForEach(stops, id: \.0) { s in
                        let reached = logged >= s.0
                        ZStack {
                            Circle().fill(reached ? color : LH.card).frame(width: 12, height: 12)
                            Circle().strokeBorder(reached ? color : LH.secondaryText.opacity(0.6), lineWidth: 2).frame(width: 12, height: 12)
                        }
                        .offset(x: x(s.0) - 6)
                    }
                    // You are here
                    ZStack {
                        Circle().fill(LH.card).frame(width: 18, height: 18)
                        Circle().strokeBorder(color, lineWidth: 3.5).frame(width: 18, height: 18)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(x: x(logged) - 9)
                    .animation(Motion.collapse(reduce), value: logged)
                }
                .frame(height: 26)
            }
            .frame(height: 26)

            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    ForEach(stops, id: \.0) { s in
                        VStack(alignment: s.0 == 750 ? .trailing : .center, spacing: 0) {
                            Text(s.1).font(.caption.weight(.semibold)).monospacedDigit()
                            Text(s.2).font(.caption2.weight(.medium)).foregroundStyle(LH.secondaryText)
                        }
                        .frame(width: 44, alignment: s.0 == 750 ? .trailing : .center)
                        .offset(x: s.0 == 750 ? g.size.width - 44 : g.size.width * s.0 / goal - 22)
                    }
                }
            }
            .frame(height: 30)
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int(logged)) of \(Int(goal)) hours. Waypoints at 100, 500 and 750 hours.")
    }
}

/// 52 weeks; violet in four steps.
struct HeatStrip: View {
    var currentWeek = 42
    static let weeks: [Double] = (0..<52).map { i in
        let v = [3, 5, 2, 6, 4, 7, 1, 5, 8, 3, 6, 4, 9, 5, 2, 7, 6, 3, 8, 5, 4, 6, 10, 7, 3, 5, 6, 2, 9, 4, 6, 7, 3, 8, 5, 6, 4, 11, 7, 5, 9, 6]
        return i < v.count ? Double(v[i]) : 0
    }
    var body: some View {
        GeometryReader { g in
            let gap: CGFloat = 2
            let s = (g.size.width - gap * 51) / 52
            HStack(spacing: gap) {
                ForEach(0..<52, id: \.self) { i in
                    let v = HeatStrip.weeks[i]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i >= currentWeek ? AnyShapeStyle(LH.fill) : AnyShapeStyle(LH.action.opacity(v < 3 ? 0.25 : v < 5 ? 0.5 : v < 8 ? 0.75 : 1)))
                        .frame(width: s, height: s * 1.6)
                }
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}

struct TwoLaneBar: View {
    var share: Double
    var body: some View {
        VStack(spacing: 5) {
            lane(share, LH.action)
            lane(1 - share, LH.secondaryText.opacity(0.45))
        }
        .overlay {
            GeometryReader { g in
                Path { p in
                    p.move(to: CGPoint(x: g.size.width / 2, y: -3))
                    p.addLine(to: CGPoint(x: g.size.width / 2, y: g.size.height + 3))
                }
                .stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            }
        }
        .frame(height: 17)
    }
    private func lane(_ f: Double, _ c: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(LH.fill)
                Capsule().fill(c).frame(width: g.size.width * f)
            }
        }
        .frame(height: 6)
    }
}

struct SpouseRoute: View {
    var me: Double
    var spouse: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(LH.fill).frame(height: 4)
                dot(Ink.rose).offset(x: g.size.width * spouse / 750 - 6)
                dot(LH.action).offset(x: g.size.width * me / 750 - 6)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }
    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12).overlay(Circle().strokeBorder(LH.card, lineWidth: 2))
    }
}

// MARK: - Clayhouse: 12-segment ring, half gauge, pebbles, dual ring

struct SegmentRing: View {
    var progress: Double   // 0…1
    var expected: Double   // 0…1
    var color: Color
    var lineWidth: CGFloat = 18
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let seg = 1.0 / 12, gap = 0.012
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let a = Double(i) * seg + gap / 2, b = Double(i + 1) * seg - gap / 2
                Circle().trim(from: a, to: b)
                    .stroke(LH.fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                let fillTo = min(b, progress)
                if fillTo > a {
                    Circle().trim(from: a, to: fillTo)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth + (i == current && pulse ? 2 : 0), lineCap: .round))
                }
            }
            // Pace flag
            Image(systemName: "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(5)
                .background(LH.card, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .offset(y: -1)
                .modifier(OnRing(fraction: expected, inset: 0))
        }
        .rotationEffect(.degrees(-90))
        .onAppear {
            guard !reduce else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.3)) { pulse = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9).delay(0.8)) { pulse = false }
        }
    }
    private var current: Int { min(11, Int(progress * 12)) }
}

/// Places a view on a circle at `fraction` (0 = 12 o'clock after the parent's -90° rotation).
struct OnRing: ViewModifier {
    var fraction: Double
    var inset: CGFloat
    func body(content: Content) -> some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2 - inset
            let ang = fraction * 2 * .pi
            content
                .rotationEffect(.degrees(90))
                .position(x: g.size.width / 2 + r * cos(ang), y: g.size.height / 2 + r * sin(ang))
        }
    }
}

struct HalfGauge: View {
    var value: Double
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().trim(from: 0.5, to: 1).stroke(LH.fill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            Circle().trim(from: 0.5, to: 0.5 + value / 2).stroke(LH.action, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            // 50% tick
            Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 16)
                .offset(y: -1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 84, height: 84)
        .frame(height: 46, alignment: .top)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct Pebbles: View {
    var values: [Double]
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                let v = values[i]
                let d: CGFloat = v == 0 ? 6 : v < 1.5 ? 10 : v < 3 ? 14 : 18
                Ellipse()
                    .fill(RadialGradient(colors: [LH.action.opacity(v == 0 ? 0.15 : 0.55), LH.action.opacity(v == 0 ? 0.25 : 1)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: d))
                    .frame(width: d, height: d * 0.82)
                    .shadow(color: LH.action.opacity(0.25), radius: 1.5, y: 1.5)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

struct DualRing: View {
    var outer: Double
    var inner: Double
    var body: some View {
        ZStack {
            Circle().stroke(LH.fill, lineWidth: 6)
            Circle().trim(from: 0, to: outer).stroke(LH.action, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Circle().stroke(LH.fill, lineWidth: 6).padding(9)
            Circle().trim(from: 0, to: inner).stroke(Ink.rose, style: StrokeStyle(lineWidth: 6, lineCap: .round)).padding(9)
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Inkwell: ruled hour strip, tallies

/// 75 hairline ticks, 10h each; heavier every 100h; 500h and 750h labelled; pace triangle.
struct RuledStrip: View {
    var logged: Double
    var expected: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let n = 75
                let step = size.width / CGFloat(n - 1)
                for i in 0..<n {
                    let h = Double(i + 1) * 10
                    let x = CGFloat(i) * step
                    let major = (i + 1) % 10 == 0 || i == n - 1
                    let filled = h <= logged
                    var p = Path()
                    let len: CGFloat = major ? 22 : 14
                    p.move(to: CGPoint(x: x, y: 22 - len))
                    p.addLine(to: CGPoint(x: x, y: 22))
                    let ink: Color = scheme == .dark ? Color(hex: 0xF2F2F7) : Color(hex: 0x1A1A2E)
                    ctx.stroke(p, with: .color(filled ? ink : ink.opacity(0.22)), lineWidth: filled ? (major ? 2 : 1.4) : (major ? 1.2 : 0.8))
                }
                // pace triangle
                let px = CGFloat(expected / 10 - 1) * step
                var t = Path()
                t.move(to: CGPoint(x: px, y: 25))
                t.addLine(to: CGPoint(x: px - 5, y: 33))
                t.addLine(to: CGPoint(x: px + 5, y: 33))
                t.closeSubpath()
                ctx.fill(t, with: .color(LH.action))
            }
            .frame(height: 34)
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    ForEach([100, 500, 750], id: \.self) { v in
                        Text("\(v)")
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(LH.secondaryText)
                            .frame(width: 30, alignment: v == 750 ? .trailing : .center)
                            .offset(x: v == 750 ? g.size.width - 30 : g.size.width * CGFloat(v / 10 - 1) / 74 - 15)
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int(logged)) of 750 hours, in ten-hour ticks")
    }
}

struct TallyMarks: View {
    var count: Int
    var color: Color = Ink.ink
    var height: CGFloat = 14
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<(count + 4) / 5, id: \.self) { g in
                let n = min(5, count - g * 5)
                Canvas { ctx, size in
                    for i in 0..<min(n, 4) {
                        var p = Path()
                        let x = CGFloat(i) * 4 + 1
                        p.move(to: CGPoint(x: x, y: 1)); p.addLine(to: CGPoint(x: x, y: size.height - 1))
                        ctx.stroke(p, with: .color(color), lineWidth: 1.4)
                    }
                    if n == 5 {
                        var p = Path()
                        p.move(to: CGPoint(x: -1, y: size.height - 2)); p.addLine(to: CGPoint(x: 15, y: 2))
                        ctx.stroke(p, with: .color(color), lineWidth: 1.4)
                    }
                }
                .frame(width: n == 5 ? 15 : CGFloat(n) * 4, height: height)
            }
        }
        .accessibilityLabel("\(count)")
    }
}
