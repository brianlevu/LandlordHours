import SwiftUI

/// The one lot scene that lives in the blueprint band on every step. It never cuts: each step only
/// changes which layers are lit, and the root animates them with the header morph.
/// All positions are unit coordinates of the production 320pt keyframe camera.
struct OnbScene: View {
    let flow: OnbFlow
    var step: OnbStep
    @Environment(\.accessibilityReduceMotion) private var reduce

    // Measured on the k00 lot render: lot diamond and where the stake stands.
    static let stakeBase = CGPoint(x: 0.62, y: 0.79)
    /// Drafting-scale heights for 100 / 500 / 750 (slab top, eaves, ridge) in the finished linework.
    static let tickY: [Int: CGFloat] = [100: 0.775, 500: 0.43, 750: 0.17]

    private var upgrade: Bool { flow.cohort == .upgrade }
    private var upgradeKeyframe: HouseKeyframe { HouseProgress.keyframe(for: flow.upgradeHours) }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack(alignment: .topLeading) {
                houseLayers
                if step == .goal { scale(s).transition(.opacity) }
                if step == .welcome && !upgrade {
                    Text("Here's what you'll build")
                        .drafting(HouseTokens.drafting)
                        .fixedSize()
                        .position(x: s * 0.5, y: s * 0.885)
                        .transition(.opacity)
                }
                if showsScanLine { scanLine(s, label: s > 180).transition(.opacity) }
                hats(s)
                if flow.stakeDropped { stake(s).transition(reduce ? .opacity : .asymmetric(insertion: .offset(y: -s * 0.3).combined(with: .opacity), removal: .opacity)) }
                if step == .staked { plaque(s).transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom))) }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(a11y)
    }

    // MARK: House layers

    @ViewBuilder private var houseLayers: some View {
        ZStack {
            if upgrade {
                ZStack {
                    Image(decorative: upgradeKeyframe.builtImageName).resizable().interpolation(.high).scaledToFit()
                    HouseLineworkView(keyframe: upgradeKeyframe, canvas: .blueprintHero)
                        .opacity(step == .calendar ? 0.3 : 1)
                }
            } else {
                // Welcome: the finished house as drafting linework only ("here's what you'll build").
                // From step 1 the lot is there and construction begins. Nothing built is ever taken down.
                // The finished house's full drawing is the k00 linework layer (k18's lines are empty:
                // everything is built by then).
                ZStack {
                    Image(decorative: HouseKeyframe.k00_lot.builtImageName).resizable().interpolation(.high).scaledToFit()
                        .opacity(step == .welcome ? 0 : 1)
                    HouseLineworkView(keyframe: .k00_lot, canvas: .blueprintHero)
                        .opacity([.property, .notify, .staked].contains(step) ? 0.45 : (step == .calendar ? 0.3 : 1))
                }

            }
            if step == .staked && flow.scanDone && flow.foundHours > 0 && !upgrade {
                HouseHatchedView(keyframe: .k01_slab, subtracting: .k00_lot, canvas: .blueprintHero)
                    .transition(.opacity)
            }
            if hatchKeyframe != nil {
                ZStack {
                    ForEach(Array(hatchFrames.enumerated()), id: \.offset) { i, k in
                        HouseHatchedView(keyframe: k, subtracting: upgrade ? upgradeKeyframe : .k00_lot, canvas: .blueprintHero)
                            .opacity(i + 1 == hatchLevel ? 1 : 0)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var hatchFrames: [HouseKeyframe] { upgrade ? [.k08_frame070, .k10_frame090, .k12_roof] : [.k01_slab, .k06_frame050, .k11_frame100] }
    private var hatchLevel: Int { step == .calendar ? flow.calendarRows : 0 }
    private var hatchKeyframe: HouseKeyframe? { hatchLevel > 0 ? hatchFrames[hatchLevel - 1] : nil }

    // MARK: Step 1 · drafting scale (100 · 500 · 750); the chosen tick lights cyan

    private func scale(_ s: CGFloat) -> some View {
        let lit: Int? = flow.goalHours
        let x: CGFloat = 0.13
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: s * x, y: s * 0.12)); p.addLine(to: CGPoint(x: s * x, y: s * 0.86))
                for (_, y) in Self.tickY { p.move(to: CGPoint(x: s * (x - 0.025), y: s * y)); p.addLine(to: CGPoint(x: s * (x + 0.025), y: s * y)) }
            }
            .stroke(HouseTokens.drafting.opacity(0.55), lineWidth: 1)
            ForEach([100, 500, 750], id: \.self) { h in
                let on = lit == h
                let y = Self.tickY[h]!
                Text("\(h)")
                    .font(.system(size: 11, weight: on ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(on ? HouseTokens.drafting : .white.opacity(0.62))
                    .fixedSize()
                    .position(x: s * (x - 0.07), y: s * y)
                // Guide from the lit tick across the drawing: where this goal tops out.
                Path { p in p.move(to: CGPoint(x: s * (x + 0.03), y: s * y)); p.addLine(to: CGPoint(x: s * 0.94, y: s * y)) }
                    .trim(from: 0, to: on ? 1 : 0)
                    .stroke(HouseTokens.drafting, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .opacity(on ? 0.9 : 0)
                Triangle()
                    .fill(HouseTokens.drafting)
                    .frame(width: 8, height: 7)
                    .rotationEffect(.degrees(-90))
                    .position(x: s * (x + 0.045), y: s * y)
                    .opacity(on ? 1 : 0)
            }
        }
    }

    // MARK: Backfill line (non-blocking; runs while the user answers)

    private var showsScanLine: Bool {
        flow.calendar == .allowed && !flow.scanDone && [.calendar, .who, .property, .notify, .staked].contains(step)
    }

    private func scanLine(_ s: CGFloat, label: Bool) -> some View {
        let pts = [CGPoint(x: 0.04, y: 0.69), CGPoint(x: 0.5, y: 0.915), CGPoint(x: 0.96, y: 0.69)]
        return ZStack(alignment: .topLeading) {
            Path { p in p.addLines(pts.map { CGPoint(x: $0.x * s, y: $0.y * s) }) }
                .stroke(HouseTokens.drafting.opacity(0.22), lineWidth: 2)
            Path { p in p.addLines(pts.map { CGPoint(x: $0.x * s, y: $0.y * s) }) }
                .trim(from: 0, to: reduce ? 1 : flow.scanProgress)
                .stroke(HouseTokens.drafting, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .opacity(reduce ? 0.6 : 1)
            Text("Looking back 90 days")
                .drafting(HouseTokens.drafting)
                .fixedSize()
                .opacity(label ? 1 : 0)
                .position(x: s * 0.80, y: s * 0.16)
        }
    }

    // MARK: Step 3 · the crew (one hard hat, two for "my spouse and me")

    @ViewBuilder private func hats(_ s: CGFloat) -> some View {
        let crew = [.who, .property, .notify, .staked].contains(step) && !upgrade
        let two = flow.who == .both
        ZStack(alignment: .topLeading) {
            HardHat(color: Color(hex: 0xF2C14E))
                .frame(width: s * 0.115, height: s * 0.075)
                .position(x: s * 0.40, y: s * 0.775)
                .opacity(crew ? 1 : 0)
            HardHat(color: Color(hex: 0xF08A4B))
                .frame(width: s * 0.115, height: s * 0.075)
                .position(x: s * 0.50, y: s * 0.80)
                .opacity(crew && two ? 1 : 0)
                .scaleEffect(crew && two ? 1 : 0.85, anchor: .bottom)
        }
    }

    // MARK: Step 4 · the stake (drops on "Stake it", flag unfurls with the name)

    private func stake(_ s: CGFloat) -> some View {
        let base = Self.stakeBase
        let postH = s * 0.19
        return ZStack(alignment: .topLeading) {
            Ellipse().fill(.black.opacity(0.22))
                .frame(width: s * 0.06, height: s * 0.018)
                .position(x: s * base.x, y: s * base.y)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [HouseTokens.timberLight, HouseTokens.timberDark], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(3, s * 0.014), height: postH)
                .position(x: s * base.x, y: s * base.y - postH / 2)
            Color.clear.frame(width: 1, height: 1)
                .overlay(alignment: .leading) {
                    Flag(name: flow.name.isEmpty ? "Oak Street duplex" : flow.name)
                        .frame(height: s * 0.085)
                        .fixedSize()
                        .scaleEffect(x: flow.flagOpen ? 1 : 0.05, y: 1, anchor: .leading)
                        .opacity(flow.flagOpen ? 1 : 0)
                }
                .position(x: s * base.x + max(3, s * 0.014) / 2, y: s * base.y - postH + s * 0.045)
        }
    }

    // MARK: Step 6 · brass plaque with the goal

    private func plaque(_ s: CGFloat) -> some View {
        GoalPlaque(text: flow.goalHours.map(String.init) ?? "Record", small: flow.goalHours == nil)
            .frame(width: s * 0.22, height: s * 0.16)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            .position(x: s * 0.27, y: s * 0.80)
    }

    private var a11y: String {
        switch step {
        case .welcome: "The finished house, drawn as a blueprint. Nothing built yet."
        case .goal: "An empty lot with the house drawn over it. Scale marks at 100, 500 and 750 hours."
        case .staked: "Your lot, staked with \(flow.name.isEmpty ? "your rental" : flow.name)."
        default: flow.stakeDropped ? "Your lot, staked with \(flow.name)." : "An empty lot with the house drawn over it."
        }
    }
}

struct Flag: View {
    let name: String
    var maxTextWidth: CGFloat? = nil
    var body: some View {
        HStack(spacing: 0) {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x121B33))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
                .padding(.leading, 7).padding(.trailing, 4)
                .padding(.vertical, 2)
                .frame(maxHeight: .infinity)
                .background(Color(hex: 0xF4EFE6))
            PennantTail().fill(Color(hex: 0xF4EFE6)).frame(width: 9)
        }
        .overlay(alignment: .leading) { Rectangle().fill(HouseTokens.timberDark).frame(width: 2) }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1.5)
        .dynamicTypeSize(.large)           // drawn into the scene; the sheet carries the readable copy
    }
}

private struct PennantTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

struct HardHat: View {
    var color: Color
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Ellipse().fill(.black.opacity(0.2)).frame(width: w, height: h * 0.3).position(x: w / 2, y: h * 0.92)
                Path { p in
                    p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.78), radius: w * 0.34, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                Capsule().fill(color.opacity(0.9)).frame(width: w, height: h * 0.16).position(x: w / 2, y: h * 0.8)
                Capsule().fill(.white.opacity(0.35)).frame(width: w * 0.08, height: h * 0.32).position(x: w * 0.5, y: h * 0.56)
            }
        }
        .accessibilityHidden(true)
    }
}

struct GoalPlaque: View {
    var text: String
    var small = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [HouseTokens.brassLight, HouseTokens.brass, HouseTokens.brassDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(HouseTokens.brassEngrave.opacity(0.45), lineWidth: 1.2)
                .padding(5)
            GeometryReader { g in
                VStack(spacing: -1) {
                    Text(text)
                        .font(.system(size: g.size.width * (small ? 0.17 : 0.27), weight: .heavy, design: .serif))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(small ? "BOOK" : "HOURS")
                        .font(.system(size: max(6, g.size.width * 0.07), weight: .bold))
                        .tracking(1.4)
                }
                .foregroundStyle(HouseTokens.brassEngrave.opacity(0.88))
                .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
                .frame(width: g.size.width * 0.8)
                .position(x: g.size.width * 0.5, y: g.size.height * 0.5)
            }
        }
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
    }
}
