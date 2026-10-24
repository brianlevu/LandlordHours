import SwiftUI

#if DEBUG
// MARK: - Log time with the sun scrubber (§2.6 signature control)
//
// Hours are a sun path: drag the sun along a 240pt arc, 15m per detent (.selection), each whole
// hour .alignment. As hours rise the sheet's own sky brightens from dawn toward noon and the house
// in the header lights windows. 0–8h across the arc (an hour of work is an hour of daylight).
// At AX sizes the arc becomes a horizontal ruler with the same detents.

struct PorchLogTimeSheet: View {
    let seed: PorchSeed
    var demo = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var hours: Double = 1.5
    @State private var note = "Plumber came to fix the kitchen sink"
    @State private var who = 0

    static let maxHours = 8.0
    private var c: PorchColors { PorchColors(scheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var rental: String { seed.std.rentals.rentals.first?.name ?? "" }
    private var quarter: Int { Int((hours * 4).rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 16) {
                    Text(porchHours(hours))
                        .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(c.ink)
                        .contentTransition(.numericText(value: hours))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    if ax { PorchSunRuler(hours: $hours, max: Self.maxHours).padding(.vertical, 4) }
                    noteField
                    valueRows
                    PorchWho(selection: $who)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .background(c.surface)
        .safeAreaInset(edge: .bottom) {
            Button(ax ? P("Log \(porchHours(hours))") : P("Log \(porchHours(hours)) at \(rental)")) { dismiss() }
                .buttonStyle(PorchPrimary())
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                .background(c.surface)
        }
        .sensoryFeedback(trigger: quarter) { _, new in new % 4 == 0 ? .alignment : .selection }
        .onChange(of: quarter) { _, new in PorchHapticLog.mark(new % 4 == 0 ? "scrub \(porchHours(hours)): .alignment" : "scrub \(porchHours(hours)): .selection") }
        .task { if demo { await runDemo() } }
    }

    // MARK: The sheet's own small sky, the house, and the sun path

    private var skyMix: Double { min(hours / 6, 1) }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(P("Fri, Oct 23")).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.92))
                    Text(P("Log time")).font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.28)))
                }
                .buttonStyle(PorchPress())
                .accessibilityLabel(P("Close"))
            }
            .padding(.horizontal, 20).padding(.top, 20)

            if ax {
                PorchHouse(lit: lit, sky: .day, size: 72).padding(.vertical, 8)
            } else {
                PorchSunArc(hours: $hours, max: Self.maxHours, lit: lit)
                    .frame(height: 190)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .background { PorchSheetSky(mix: skyMix, dark: scheme == .dark) }
    }

    private var lit: Int { Int((hours / Self.maxHours * Double(PorchWindows.panes.count)).rounded()) }

    private var noteField: some View {
        TextField(P("What did you do?"), text: $note, axis: .vertical)
            .font(.body).foregroundStyle(c.ink)
            .lineLimit(2...5)
            .padding(14)
            .frame(minHeight: 72, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.surfaceInner))
    }

    private var valueRows: some View {
        VStack(spacing: 0) {
            valueRow(P("Rental"), rental, first: true)
            valueRow(P("Kind of work"), ActivityCategory.repairs.stdLabel)
            valueRow(P("Date"), P("Today"))
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.ground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
    }

    private func valueRow(_ label: String, _ value: String, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(c.border).frame(height: 0.5).padding(.leading, 16) }
            let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text(label).font(.body).foregroundStyle(c.textSecondary)
                if !ax { Spacer(minLength: 8) }
                HStack(spacing: 4) {
                    Text(value).font(.body.weight(.semibold)).foregroundStyle(c.ink)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(c.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
        }
    }

    private func runDemo() async {
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await pause(1.2)
        hours = 0
        await pause(0.6)
        for q in 1...16 { withAnimation(.easeOut(duration: 0.14)) { hours = Double(q) / 4 }; await pause(0.16) }
        await pause(0.5)
        for q in stride(from: 15, through: 6, by: -1) { withAnimation(.easeOut(duration: 0.14)) { hours = Double(q) / 4 }; await pause(0.18) }
        await pause(0.8)
        for q in 7...24 { withAnimation(.easeOut(duration: 0.12)) { hours = Double(q) / 4 }; await pause(0.11) }
        await pause(0.6)
        for q in stride(from: 23, through: 6, by: -1) { withAnimation(.easeOut(duration: 0.12)) { hours = Double(q) / 4 }; await pause(0.09) }
    }
}

/// The sheet sky: dawn → day as hours rise (colours interpolated), deep at the top so the title
/// stays white-on-deep (≥ 4.5:1 at every mix; measured in the frames).
struct PorchSheetSky: View {
    let mix: Double
    let dark: Bool
    var body: some View {
        let a = PorchSky.dawn.palette(dark: dark), b = PorchSky.day.palette(dark: dark)
        let cols = zip(a, b).map { lerp($0, $1, mix) }
        LinearGradient(stops: [
            .init(color: cols[0], location: 0),
            .init(color: cols[1], location: 0.40),
            .init(color: cols[2], location: 0.85),
            .init(color: cols[3], location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .overlay(alignment: .topTrailing) {
            Circle().fill(PorchColors.hex(0xFFDCA0, 0.18 + 0.2 * mix)).frame(width: 200, height: 200).blur(radius: 60).offset(x: 40, y: -40)
        }
        .clipped()
    }

    private func lerp(_ x: UInt32, _ y: UInt32, _ t: Double) -> Color {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) / 255 }
        return Color(red: ch(x, 16) + (ch(y, 16) - ch(x, 16)) * t,
                     green: ch(x, 8) + (ch(y, 8) - ch(x, 8)) * t,
                     blue: ch(x, 0) + (ch(y, 0) - ch(x, 0)) * t)
    }
}

/// The arc: a 240pt semicircle sun path. The sun tracks the finger 1:1 along the path and settles
/// on 15m detents; hour ticks sit on the path; the house sits at the arc's foot, lit by the hours.
struct PorchSunArc: View {
    @Binding var hours: Double
    let max: Double
    let lit: Int
    @State private var dragging = false

    private let radius: CGFloat = 120

    var body: some View {
        GeometryReader { g in
            let center = CGPoint(x: g.size.width / 2, y: g.size.height - 14)
            let t = hours / max
            let angle = Double.pi * (1 - t)
            let sun = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y - radius * CGFloat(sin(angle)))
            ZStack(alignment: .topLeading) {
                // Ground line under the arc.
                Rectangle().fill(.white.opacity(0.4)).frame(width: g.size.width, height: 1).offset(y: center.y)
                // The path, and the travelled part.
                Path { p in p.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) }
                    .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 6]))
                Path { p in p.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) }
                    .trim(from: 0, to: CGFloat(t))
                    .stroke(PorchColors.hex(0xFFD58A), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .opacity(hours > 0 ? 1 : 0)
                ForEach(0...Int(max), id: \.self) { h in
                    let a = Double.pi * (1 - Double(h) / max)
                    Circle().fill(.white.opacity(Double(h) <= hours ? 0.95 : 0.5)).frame(width: 5, height: 5)
                        .offset(x: center.x + radius * CGFloat(cos(a)) - 2.5, y: center.y - radius * CGFloat(sin(a)) - 2.5)
                }
                // The house at the foot of the path.
                PorchHouse(lit: lit, sky: .day, size: 104)
                    .offset(x: center.x - 52, y: center.y - 84)
                // The sun.
                ZStack {
                    Circle().fill(PorchColors.hex(0xFFC060, 0.45)).frame(width: 64, height: 64).blur(radius: 10)
                    Circle().fill(RadialGradient(colors: [PorchColors.hex(0xFFF2C8), PorchColors.hex(0xF2B04A)], center: .center, startRadius: 2, endRadius: 16))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                        .scaleEffect(dragging ? 1.12 : 1)
                        .animation(.spring(duration: 0.25, bounce: 0.2), value: dragging)
                }
                .frame(width: 64, height: 64)
                .offset(x: sun.x - 32, y: sun.y - 32)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let dx = v.location.x - center.x, dy = center.y - v.location.y
                        let a = Swift.max(0, Swift.min(Double.pi, atan2(Double(Swift.max(dy, 0)), Double(dx))))
                        let raw = (1 - a / Double.pi) * max
                        hours = (raw * 4).rounded() / 4
                    }
                    .onEnded { _ in dragging = false }
            )
            .accessibilityElement()
            .accessibilityLabel(P("Hours"))
            .accessibilityValue(porchHours(hours))
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: hours = Swift.min(max, hours + 0.25)
                case .decrement: hours = Swift.max(0, hours - 0.25)
                @unknown default: break
                }
            }
        }
    }
}

/// AX sizes: the same control as a horizontal ruler (ticks every 15m, labels every 2h).
struct PorchSunRuler: View {
    @Binding var hours: Double
    let max: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = PorchColors(scheme)
        GeometryReader { g in
            let w = g.size.width - 32
            let x = 16 + w * CGFloat(hours / max)
            ZStack(alignment: .topLeading) {
                Capsule().fill(c.surfaceInner).frame(height: 8).offset(y: 28)
                Capsule().fill(c.glow).frame(width: x, height: 8).offset(y: 28)
                ForEach(0...Int(max * 4), id: \.self) { q in
                    Rectangle().fill(c.textTertiary).frame(width: 1, height: q % 4 == 0 ? 14 : 7)
                        .offset(x: 16 + w * CGFloat(Double(q) / (max * 4)), y: 42)
                }
                Circle().fill(PorchColors.hex(0xF2B04A)).overlay(Circle().strokeBorder(c.ink, lineWidth: 1.5))
                    .frame(width: 44, height: 44).offset(x: x - 22, y: 10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = Swift.max(0, Swift.min(1, (v.location.x - 16) / w))
                hours = (Double(t) * max * 4).rounded() / 4
            })
        }
        .frame(height: 64)
        .accessibilityElement()
        .accessibilityLabel(P("Hours"))
        .accessibilityValue(porchHours(hours))
    }
}

/// Who: Me / Spouse.
struct PorchWho: View {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = PorchColors(scheme)
        HStack(spacing: 0) {
            ForEach([P("Me"), P("Spouse")].indices, id: \.self) { i in
                Button { withAnimation(.spring(duration: 0.25, bounce: 0)) { selection = i } } label: {
                    Text([P("Me"), P("Spouse")][i]).font(.subheadline.weight(.semibold))
                        .foregroundStyle(i == selection ? c.ink : c.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background { if i == selection { Capsule().fill(c.surface).overlay(Capsule().strokeBorder(c.border, lineWidth: 0.5)) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(c.surfaceInner))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
#endif
