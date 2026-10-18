import SwiftUI

/// Porchlight: your street, lit by your hours. 15 lamps x 50h; windows show recent work at a property.
enum PL {
    static let lampLit = Color(hex: 0xFFE5A3)
    static let windowLit = Color(hex: 0xFFC861)
    static let asphaltLight = Color(hex: 0x3C4257)
    static let asphaltDark = Color(hex: 0x232838)
    static let groundAutumn = Color(hex: 0xC9A86A)
    static let brick = Color(hex: 0xD95F43)
    static let pine = Color(hex: 0x2E8B6B)
}

struct StreetScene: View {
    var hours: Double
    var litWindows: [String: Int]            // property key → lit windows (0…4)
    var lampHalo: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    private var night: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let groundY = h * 0.80
            ZStack(alignment: .topLeading) {
                // Sky by clock: 9:41 → Dawn in light; dark mode shows Night.
                LinearGradient(colors: night ? [Color(hex: 0x0C1738), Color(hex: 0x263468)] : [Color(hex: 0xF9A86E), Color(hex: 0xFBE3D0)],
                               startPoint: .top, endPoint: .bottom)
                if night {
                    Stars().frame(width: w, height: groundY)
                    Circle().fill(Color(hex: 0xF4F1E0)).frame(width: 34, height: 34)
                        .overlay(Circle().fill(Color(hex: 0x0C1738)).frame(width: 30, height: 30).offset(x: 9, y: -5))
                        .position(x: w * 0.84, y: h * 0.18)
                } else {
                    Circle().fill(Color(hex: 0xFFF1D6)).frame(width: 64, height: 64).blur(radius: 1)
                        .shadow(color: Color(hex: 0xFFD7A0), radius: 30)
                        .position(x: w * 0.80, y: h * 0.42)
                }
                // Far hills
                Hills().fill(night ? Color(hex: 0x1D2A55) : Color(hex: 0xE9A27E).opacity(0.65))
                    .frame(width: w, height: h * 0.30).position(x: w / 2, y: groundY - h * 0.12)
                Hills(phase: 1.7).fill(night ? Color(hex: 0x16214A) : Color(hex: 0xD98C6C).opacity(0.7))
                    .frame(width: w, height: h * 0.22).position(x: w / 2, y: groundY - h * 0.06)
                // Ground + sidewalk + street
                Rectangle().fill(night ? PL.groundAutumn.mix(with: .black, by: 0.45) : PL.groundAutumn)
                    .frame(width: w, height: h - groundY).position(x: w / 2, y: groundY + (h - groundY) / 2)
                Rectangle().fill(night ? Color(hex: 0x3A3F55) : Color(hex: 0xE6DCCB))
                    .frame(width: w, height: 8).position(x: w / 2, y: groundY + 4)
                Rectangle().fill(night ? PL.asphaltDark : PL.asphaltLight)
                    .frame(width: w, height: h * 0.10).position(x: w / 2, y: h - h * 0.05)
                Path { p in
                    var x: CGFloat = 8
                    while x < w { p.move(to: .init(x: x, y: h - h * 0.05)); p.addLine(to: .init(x: x + 14, y: h - h * 0.05)); x += 30 }
                }.stroke(Color.white.opacity(night ? 0.35 : 0.6), lineWidth: 2)

                // Trees
                Tree(night: night).frame(width: 46, height: 70).position(x: w * 0.08, y: groundY - 33)
                Tree(night: night, tone: Color(hex: 0xC2603A)).frame(width: 38, height: 58).position(x: w * 0.54, y: groundY - 27)
                Tree(night: night, tone: Color(hex: 0xE09A3E)).frame(width: 42, height: 64).position(x: w * 0.95, y: groundY - 30)

                // Houses
                PLHouse(kind: .cabin, paint: PL.pine, lit: litWindows["pine"] ?? 0, night: night)
                    .frame(width: w * 0.30, height: h * 0.40)
                    .position(x: w * 0.30, y: groundY - h * 0.20)
                PLHouse(kind: .duplex, paint: PL.brick, lit: litWindows["oak"] ?? 0, night: night)
                    .frame(width: w * 0.32, height: h * 0.44)
                    .position(x: w * 0.75, y: groundY - h * 0.22)

                // Lamps: 15 x 50h, tall at 100 (lamp 2) and 500 (lamp 10)
                let lit = Int(hours / 50)
                let partial = (hours - Double(lit) * 50) / 50
                ForEach(0..<15, id: \.self) { i in
                    let x = w * (0.035 + CGFloat(i) * 0.0665)
                    let tall = i == 1 || i == 9
                    Lamp(state: i < lit ? 1 : (i == lit ? partial : 0), tall: tall, night: night, halo: lampHalo)
                        .frame(width: 22, height: tall ? 70 : 54)
                        .position(x: x, y: groundY + 6 - (tall ? 35 : 27))
                }
            }
        }
        .clipped()
    }
}

extension Color {
    func mix(with other: Color, by t: Double) -> Color {
        let a = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let b = UIColor(other).cgColor.components ?? [0, 0, 0, 1]
        func c(_ i: Int) -> Double { Double(a[min(i, a.count - 1)]) * (1 - t) + Double(b[min(i, b.count - 1)]) * t }
        return Color(.sRGB, red: c(0), green: c(1), blue: c(2), opacity: 1)
    }
}

struct Stars: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: 7)
            for _ in 0..<60 {
                let x = CGFloat(rng.next() % 1000) / 1000 * size.width
                let y = CGFloat(rng.next() % 1000) / 1000 * size.height * 0.8
                let r = CGFloat(rng.next() % 3 + 1) * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.7)))
            }
        }
    }
}

struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 }
}

struct Hills: Shape {
    var phase: CGFloat = 0
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for i in 0...40 {
            let x = r.minX + r.width * CGFloat(i) / 40
            let y = r.minY + r.height * (0.35 + 0.3 * sin(CGFloat(i) / 40 * .pi * 2.2 + phase) * 0.8)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Tree: View {
    var night: Bool
    var tone: Color = Color(hex: 0xD9822B)
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Rectangle().fill(Color(hex: 0x6B4A2E)).frame(width: 4, height: h * 0.35).position(x: w / 2, y: h * 0.82)
                Circle().fill(night ? tone.mix(with: .black, by: 0.5) : tone).frame(width: w, height: w).position(x: w / 2, y: w / 2 + 2)
                Circle().fill((night ? tone.mix(with: .black, by: 0.62) : tone.mix(with: .black, by: 0.15))).frame(width: w * 0.55, height: w * 0.55)
                    .position(x: w * 0.68, y: w * 0.62)
            }
        }
    }
}

enum PLKind { case cabin, duplex }

struct PLHouse: View {
    var kind: PLKind
    var paint: Color
    var lit: Int
    var night: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let wallTop = h * (kind == .cabin ? 0.42 : 0.36)
            let roofColor = night ? Color(hex: 0x1A1F33) : Color(hex: 0x3A3550)
            let body = night ? paint.mix(with: .black, by: 0.45) : paint
            ZStack(alignment: .topLeading) {
                // long soft shadow to the right
                Path { p in
                    p.move(to: .init(x: w * 0.9, y: h)); p.addLine(to: .init(x: w * 1.25, y: h)); p.addLine(to: .init(x: w * 1.05, y: wallTop + h * 0.15)); p.addLine(to: .init(x: w * 0.9, y: wallTop + h * 0.15))
                }.fill(.black.opacity(night ? 0.18 : 0.10))
                // wall, two-tone cel shading
                Rectangle().fill(body).frame(width: w * 0.8, height: h - wallTop).position(x: w * 0.5, y: wallTop + (h - wallTop) / 2)
                Rectangle().fill(.black.opacity(0.14)).frame(width: w * 0.22, height: h - wallTop).position(x: w * 0.79, y: wallTop + (h - wallTop) / 2)
                if kind == .cabin {
                    Path { p in var y = wallTop + 6; while y < h { p.move(to: .init(x: w * 0.1, y: y)); p.addLine(to: .init(x: w * 0.9, y: y)); y += 7 } }
                        .stroke(.black.opacity(0.12), lineWidth: 1)
                }
                // roof
                Path { p in
                    p.move(to: .init(x: w * 0.02, y: wallTop + 2))
                    p.addLine(to: .init(x: w * 0.5, y: kind == .cabin ? h * 0.02 : h * 0.08))
                    p.addLine(to: .init(x: w * 0.98, y: wallTop + 2)); p.closeSubpath()
                }.fill(roofColor)
                // 2x2 windows (cabin) / 2x2 per unit (duplex)
                let cols: [CGFloat] = kind == .cabin ? [0.30, 0.62] : [0.20, 0.38, 0.62, 0.80]
                let rows: [CGFloat] = kind == .cabin ? [0.55, 0.74] : [0.48, 0.66]
                let ww = w * (kind == .cabin ? 0.16 : 0.12), wh = h * (kind == .cabin ? 0.13 : 0.12)
                ForEach(0..<(cols.count * rows.count), id: \.self) { i in
                    let c = cols[i % cols.count], r = rows[i / cols.count]
                    let on = i < lit
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(on ? PL.windowLit : (night ? Color(hex: 0x111628) : Color(hex: 0x3C4257)))
                        .frame(width: ww, height: wh)
                        .shadow(color: on ? PL.windowLit.opacity(0.9) : .clear, radius: on ? 8 : 0)
                        .position(x: w * c, y: h * r)
                        .animation(.easeOut(duration: 0.32).delay(Double(i) * 0.12), value: lit)
                }
                // door(s)
                ForEach(kind == .cabin ? [0.46] : [0.29, 0.71], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 1.5).fill(night ? Color(hex: 0x2A1E16) : Color(hex: 0x5B3A26))
                        .frame(width: w * 0.11, height: h * 0.19).position(x: w * x, y: h - h * 0.095)
                    Circle().fill(PL.lampLit).frame(width: 4, height: 4)
                        .shadow(color: PL.lampLit, radius: night ? 6 : 2)
                        .position(x: w * x + w * 0.08, y: h - h * 0.21)
                }
            }
        }
    }
}

struct Lamp: View {
    var state: Double       // 0 off, 0<x<1 warming (partial 50h), 1 lit
    var tall: Bool
    var night: Bool
    var halo: CGFloat
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                if state > 0 {
                    Circle()
                        .fill(RadialGradient(colors: [PL.lampLit.opacity(state >= 1 ? (night ? 0.75 : 0.55) : 0.22), .clear], center: .center, startRadius: 1, endRadius: tall ? 26 : 20))
                        .frame(width: tall ? 52 : 40, height: tall ? 52 : 40)
                        .scaleEffect(halo)
                        .position(x: w / 2, y: 5)
                }
                Rectangle().fill(night ? Color(hex: 0x4A5070) : PL.asphaltLight).frame(width: tall ? 3 : 2.2, height: h - 6).position(x: w / 2, y: h / 2 + 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(state >= 1 ? PL.lampLit : (state > 0 ? PL.lampLit.opacity(0.35) : (night ? Color(hex: 0x4A5070) : PL.asphaltLight)))
                    .frame(width: tall ? 10 : 8, height: tall ? 10 : 8)
                    .position(x: w / 2, y: 5)
                if tall {
                    Rectangle().fill(night ? Color(hex: 0x4A5070) : PL.asphaltLight).frame(width: 12, height: 2).position(x: w / 2, y: 11)
                }
            }
        }
    }
}

struct PorchlightHero: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @State private var shown: Double = 0
    @State private var lit: [String: Int] = ["pine": 1, "oak": 2]
    @State private var halo: CGFloat = 1
    @State private var windowTick = 0
    @State private var lampTick = 0

    var body: some View {
        ZStack(alignment: StreetSceneArt.available ? .topTrailing : .topLeading) {
            if StreetSceneArt.available {
                StreetSceneArt(hours: shown, litWindows: lit, lampHalo: halo)
            } else {
                StreetScene(hours: shown, litWindows: lit, lampHalo: halo)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(store.hoursLogged))")
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: store.hoursLogged))
                    Text("of 750h").font(.headline).opacity(0.75)
                }
                Label(store.pace >= 0 ? "On pace · \(fmtDur(store.pace)) ahead" : "Behind by \(fmtDur(-store.pace))",
                      systemImage: store.pace >= 0 ? "arrow.up.circle.fill" : "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(scheme == .dark ? (store.pace >= 0 ? OnHero.positive : OnHero.caution) : (store.pace >= 0 ? LH.positive : LH.caution))
                Text("\(Int(store.hoursLogged / 50)) of 15 lamps lit")
                    .font(.footnote).opacity(0.75)
                    .contentTransition(.numericText(value: store.hoursLogged))
            }
            .foregroundStyle(scheme == .dark ? .white : Color(hex: 0x1B1A2E))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(14)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: windowTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: lampTick)
        .onAppear { shown = store.hoursLogged }
        .onChange(of: store.hoursLogged) { old, new in
            Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))     // let a sheet finish dismissing
            let add = Int((new - old).rounded())
            withAnimation(reduce ? .easeInOut(duration: 0.2) : nil) { lit["pine"] = min(4, (lit["pine"] ?? 0) + max(1, add)) }
            windowTick += 1
            if Int(new / 50) > Int(old / 50) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(reduce ? 0 : 550))
                    lampTick += 1
                    if reduce { shown = new; return }
                    halo = 0.9
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { shown = new; halo = 1 }
                }
            } else {
                shown = new
            }
            }
        }
    }
}
