import SwiftUI

/// Tilework: 750 tiles, one per hour. 30 across, 25 down. Colour = category, order = chronology.
enum TW {
    static let grout = Color(hex: 0x161B2E)
    static let gold = Color(hex: 0xE3B64B)
    static func glaze(_ c: Category) -> Color {
        switch c {
        case .repairs: Color(hex: 0xF0744A)
        case .renovation: Color(hex: 0xF2C230)
        case .cleaning: Color(hex: 0x3FC8E6)
        case .leasing: Color(hex: 0xD56BE0)
        case .tenant: Color(hex: 0x4F8BFF)
        case .bookkeeping: Color(hex: 0xA4D64A)
        case .travel: Color(hex: 0x2FD1B8)
        case .inspections: Color(hex: 0x8FA6D6)
        case .legal: Color(hex: 0xC9CFE0)
        case .supplies: Color(hex: 0xE5A06E)
        case .management: Color(hex: 0x5CD68A)
        }
    }
    /// Deterministic chronology of categories, weighted like a real year.
    static let sequence: [Category] = {
        var rng = SeededRNG(seed: 42)
        let weights: [(Category, Int)] = [(.repairs, 26), (.leasing, 14), (.cleaning, 14), (.renovation, 10), (.tenant, 9),
                                          (.bookkeeping, 8), (.travel, 7), (.inspections, 4), (.legal, 3), (.supplies, 3), (.management, 2)]
        let total = weights.map(\.1).reduce(0, +)
        var out: [Category] = []
        var run: Category = .repairs
        var left = 0
        for _ in 0..<750 {
            if left == 0 {   // hours come in runs of the same kind of work (a job, a turnover, a week of books)
                var r = Int(rng.next() % UInt64(total))
                for (c, w) in weights { if r < w { run = c; break }; r -= w }
                left = Int(4 + rng.next() % 11)
            }
            out.append(run)
            left -= 1
        }
        return out
    }()
    static let spouse: Set<Int> = {
        var rng = SeededRNG(seed: 9)
        return Set((0..<750).filter { _ in rng.next() % 100 < 16 })
    }()
}

struct Mosaic: View {
    var laid: Int
    var hollow: Int              // found-but-unconfirmed hours, outlined only
    var dropping: Set<Int> = []  // indices animating in (drawn by overlay)

    var body: some View {
        GeometryReader { g in
            let cols = 30, rows = 25
            let gap: CGFloat = 2
            let t = (g.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            Canvas { ctx, _ in
                for i in 0..<(cols * rows) {
                    let c = i % cols, r = i / cols
                    let rect = CGRect(x: CGFloat(c) * (t + gap), y: CGFloat(r) * (t + gap), width: t, height: t)
                    let tile = Path(roundedRect: rect, cornerRadius: t * 0.18)
                    let cat = TW.sequence[i]
                    if i < laid && !dropping.contains(i) {
                        let glaze = TW.glaze(cat)
                        ctx.fill(tile, with: .linearGradient(Gradient(colors: [glaze.mix(with: .white, by: 0.22), glaze, glaze.mix(with: .black, by: 0.18)]),
                                                            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                        ctx.fill(Path(roundedRect: CGRect(x: rect.minX + t * 0.18, y: rect.minY + t * 0.14, width: t * 0.34, height: t * 0.16), cornerRadius: t * 0.08),
                                 with: .color(.white.opacity(0.45)))
                        if TW.spouse.contains(i) {
                            var notch = Path()
                            notch.move(to: CGPoint(x: rect.maxX, y: rect.maxY - t * 0.42)); notch.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); notch.addLine(to: CGPoint(x: rect.maxX - t * 0.42, y: rect.maxY)); notch.closeSubpath()
                            ctx.fill(notch, with: .color(TW.grout))
                        }
                    } else if i < laid + hollow {
                        ctx.stroke(tile.offsetBy(dx: 0, dy: 0), with: .color(TW.glaze(cat).opacity(0.85)), lineWidth: 1)
                    } else {
                        ctx.stroke(tile, with: .color(.white.opacity(0.12)), lineWidth: 0.7)
                    }
                }
                // Gold grout under the rows holding the 100h and 500h tiles, and the last row
                for threshold in [100, 500, 750] {
                    let r = (threshold - 1) / cols
                    let y = CGFloat(r + 1) * (t + gap) - gap / 2
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: g.size.width, y: y))
                    ctx.stroke(line, with: .color(TW.gold.opacity(threshold <= laid ? 1 : 0.6)), lineWidth: 2.2)
                    let c = (threshold - 1) % cols
                    let rect = CGRect(x: CGFloat(c) * (t + gap), y: CGFloat(r) * (t + gap), width: t, height: t)
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: t * 0.2), with: .color(TW.gold), lineWidth: 1.4)
                }
            }
        }
        .aspectRatio(30.0 / 25.0 * 1.0, contentMode: .fit)
    }

    static func cellRect(_ i: Int, width: CGFloat) -> CGRect {
        let gap: CGFloat = 2
        let t = (width - gap * 29) / 30
        return CGRect(x: CGFloat(i % 30) * (t + gap), y: CGFloat(i / 30) * (t + gap), width: t, height: t)
    }
}

struct DroppingTile: View {
    var index: Int
    var delay: Double
    var onLand: () -> Void
    @State private var landed = false
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let glaze = TW.glaze(TW.sequence[index])
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [glaze.mix(with: .white, by: 0.22), glaze, glaze.mix(with: .black, by: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: sweep ? 14 : -14)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            )
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(TW.gold.opacity(landed ? 0 : 0.9), lineWidth: 1).padding(-1.5))
            .shadow(color: glaze.opacity(landed ? 0 : 0.9), radius: landed ? 0 : 6)
            .scaleEffect(landed || reduce ? 1 : 1.6)
            .offset(y: landed || reduce ? 0 : -6)
            .opacity(landed ? 1 : (reduce ? 0 : 0.0001))
            .task {
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                if reduce {
                    withAnimation(.easeOut(duration: 0.2)) { landed = true }
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { landed = true }
                }
                onLand()
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.18)) { sweep = true }
            }
    }
}

struct TileworkHero: View {
    @Environment(MockStore.self) private var store
    @State private var laid = 0
    @State private var dropping: [Int] = []
    @State private var tick = 0

    private let top4: [Category] = [.repairs, .leasing, .cleaning, .renovation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(store.hoursLogged))")
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: store.hoursLogged))
                Text("of 750 tiles").font(.title3.weight(.medium)).foregroundStyle(OnHero.secondary)
                Spacer()
            }
            Label(store.pace >= 0 ? "On pace · \(fmtDur(store.pace)) ahead" : "Behind by \(fmtDur(-store.pace))",
                  systemImage: store.pace >= 0 ? "arrow.up.circle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(store.pace >= 0 ? OnHero.positive : OnHero.caution)
                .padding(.top, -6)
            HStack(spacing: 10) {
                ForEach(top4, id: \.self) { c in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(TW.glaze(c)).frame(width: 9, height: 9)
                        Text(c.label).font(.caption.weight(.medium)).foregroundStyle(OnHero.secondary)
                    }
                }
            }
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Mosaic(laid: laid, hollow: store.pending.reduce(0) { $0 + Int(($1.hours ?? 0).rounded()) }, dropping: Set(dropping))
                    ForEach(Array(dropping.enumerated()), id: \.element) { n, i in
                        let r = Mosaic.cellRect(i, width: g.size.width)
                        DroppingTile(index: i, delay: Double(n) * 0.04) { tick += 1 }
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
            .aspectRatio(30.0 / 25.0, contentMode: .fit)
            HStack {
                Label("100", systemImage: "circle.fill").labelStyle(TightLabel())
                Text("·").opacity(0.5)
                Label("500", systemImage: "circle.fill").labelStyle(TightLabel())
                Text("gold rows are the tests").opacity(0.8)
                Spacer()
                Text("1 tile = 1 confirmed hour").opacity(0.8)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(TW.gold)
        }
        .padding(18)
        .background(TW.grout, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: tick)
        .onAppear { laid = Int(store.hoursLogged) }
        .onChange(of: store.hoursLogged) { old, new in
            let from = Int(old), to = Int(new)
            guard to > from else { laid = to; return }
            dropping = Array(from..<to)
            laid = to
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                dropping = []
            }
        }
    }
}
