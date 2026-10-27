import SwiftUI

#if DEBUG
// MARK: - Log time v2, round 3: PROPOSED components (Beam and Object variants)
//
// The owner picked "bold numerals", "crafted object" and "editorial calm" (2026-10-27). These are the
// only new parts; everything else is an existing LH* component or token.
//
//   LHDurationNumerals  the duration in the hero numeral (Fraunces 600 tabular, the Today "165"
//                       face) with SF unit letters: "1 h 30 m". Not a component of its own: a
//                       second sanctioned use of `LHFont.heroNumeral` (amends §1.14 "the one
//                       numeral set in Fraunces").
//   LHDurationBeam      A1: a timber beam on a blueprint ruler. Drag to build; snaps to 15 min with
//                       a selection haptic per step. Drafted (dashed drafting line) = not built yet.
//   LHDurationDial      A2: a blueprint plate (brand blue, drafting rings). One turn = one hour;
//                       the white arc is the minutes, the pips are the whole hours; 15-min detents.
//   LHHouseReadback     the rental's house as the review's object: unlit before; the next stage
//                       drafted in cyan behind it when this log crosses a stage; on Log the stage
//                       fades in (stageFade 0.25) and the windows light (windows 0.40).

// MARK: Numerals

struct LHDurationNumerals: View {
    var hours: Double?
    var size: CGFloat = 84
    var onBrand = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    /// H7: 54 at accessibility sizes, as the Today numeral does.
    private var numeralSize: CGFloat { typeSize.isAccessibilitySize ? min(size, 54) : size }
    private var ink: Color { onBrand ? .white : colors.textPrimary }
    private var unitInk: Color { onBrand ? Color.white.opacity(0.82) : colors.textSecondary }
    private var placeholderInk: Color { onBrand ? Color.white.opacity(0.6) : colors.textTertiary }

    var body: some View {
        let total = LHFormat.minutes(hours)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let total {
                Text("\(total / 60)").font(LHFont.heroNumeral(size: numeralSize)).foregroundStyle(ink)
                    .contentTransition(.numericText(value: Double(total / 60)))
                Text("h").font(.title2.weight(.medium)).foregroundStyle(unitInk)
                Text(String(format: "%02d", total % 60)).font(LHFont.heroNumeral(size: numeralSize)).foregroundStyle(ink)
                    .contentTransition(.numericText(value: Double(total % 60)))
                    .padding(.leading, 6)
                Text("m").font(.title2.weight(.medium)).foregroundStyle(unitInk)
            } else {
                // Not set: the shape of the number stays (0 h 00 m) in the quiet ink, so the space
                // never collapses and the question reads as "fill this in".
                Text("0").font(LHFont.heroNumeral(size: numeralSize)).foregroundStyle(placeholderInk)
                Text("h").font(.title2.weight(.medium)).foregroundStyle(placeholderInk)
                Text("00").font(LHFont.heroNumeral(size: numeralSize)).foregroundStyle(placeholderInk).padding(.leading, 6)
                Text("m").font(.title2.weight(.medium)).foregroundStyle(placeholderInk)
            }
        }
        .tracking(-1.5)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .animation(reduceMotion ? nil : AppAnimation.standard, value: total)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total == nil ? "Time not set" : LHFormat.spokenHours(hours))
    }
}

// MARK: Beam (A1)

struct LHDurationBeam: View {
    var hours: Double
    var interactive = true
    var onChange: (Double) -> Void = { _ in }

    /// r4: 24pt per 15 min (1h = 96pt), so at common values the ruler fills the card on both sides.
    static let pointsPerQuarter: CGFloat = 24
    static let maxHours: Double = 12

    @State private var dragStart: Double?
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    // Vertical layout: ticks 4–18, beam 20–46, reading line 0–50, labels centred at 64.
    private static let beamY: CGFloat = 20, beamH: CGFloat = 26, labelY: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let perHour = Self.pointsPerQuarter * 4
            let origin = cx - CGFloat(hours) * perHour
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let full = CGRect(x: origin, y: Self.beamY, width: CGFloat(Self.maxHours) * perHour, height: Self.beamH)
                    ctx.stroke(Path(roundedRect: full, cornerRadius: 6), with: .color(colors.drafting),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    let built = CGRect(x: origin, y: Self.beamY, width: CGFloat(hours) * perHour, height: Self.beamH)
                    if built.width > 0 {
                        ctx.fill(Path(roundedRect: built, cornerRadius: 6), with: .color(colors.timber))
                        for gy in [Self.beamY + 9, Self.beamY + 17] {
                            var p = Path(); p.move(to: CGPoint(x: built.minX + 6, y: gy)); p.addLine(to: CGPoint(x: built.maxX - 6, y: gy))
                            ctx.stroke(p, with: .color(colors.timberInk.opacity(0.28)), lineWidth: 1)
                        }
                    }
                    for q in 0...Int(Self.maxHours * 4) {
                        let x = origin + CGFloat(q) * Self.pointsPerQuarter
                        guard x > -20, x < size.width + 20 else { continue }
                        let hour = q % 4 == 0
                        var p = Path(); p.move(to: CGPoint(x: x, y: Self.beamY - (hour ? 16 : 8))); p.addLine(to: CGPoint(x: x, y: Self.beamY - 2))
                        ctx.stroke(p, with: .color(colors.draftingInk.opacity(hour ? 1 : 0.6)), lineWidth: hour ? 1.5 : 1)
                        if hour || q % 2 == 0 {
                            let label = q == 0 ? "0" : (hour ? "\(q / 4)h" : "")
                            if !label.isEmpty {
                                ctx.draw(Text(label).font(.caption).foregroundStyle(colors.textSecondary),
                                         at: CGPoint(x: x, y: Self.labelY), anchor: .center)
                            }
                        }
                    }
                }
                // The reading line spans the ticks and the beam only; the labels stay clear of it.
                Capsule().fill(colors.action).frame(width: 3, height: 52).position(x: cx, y: 26)
                Image(systemName: "arrowtriangle.down.fill").font(.caption2).foregroundStyle(colors.action)
                    .position(x: cx, y: 0).accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: 76)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2).onChanged { v in
            guard interactive else { return }
            if dragStart == nil { dragStart = hours }
            let raw = (dragStart ?? 0) - Double(v.translation.width / (Self.pointsPerQuarter * 4))
            let snapped = min(max(0, (raw * 4).rounded() / 4), Self.maxHours)
            if snapped != hours { onChange(snapped) }
        }.onEnded { _ in dragStart = nil })
        .sensoryFeedback(.selection, trigger: hours)
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(LHFormat.spokenHours(hours))
        .accessibilityAdjustableAction { dir in
            guard interactive else { return }
            onChange(min(max(0, hours + (dir == .increment ? 0.25 : -0.25)), Self.maxHours))
        }
        .accessibilityIdentifier("logv2.beam")
    }
}

// MARK: Dial (A2)

struct LHDurationDial: View {
    var hours: Double
    var isSet = true
    var interactive = true
    var side: CGFloat = 248
    var onChange: (Double) -> Void = { _ in }

    @State private var lastAngle: Double?
    @State private var minutesAccum: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    /// Drafting cyan, the ink on the blue paper (the dark-mode action token, fixed on the plate).
    private let cyan = AdaptiveColors(colorScheme: .dark).action

    private var minutes: Int { LHFormat.minutes(hours) ?? 0 }
    private var arc: Double { Double(minutes % 60) / 60 }
    private var wholeHours: Int { minutes / 60 }

    var body: some View {
        ZStack {
            Circle().fill(AppColors.brand)
            Circle().strokeBorder(cyan.opacity(0.45), lineWidth: 1).padding(12)
            Circle().strokeBorder(cyan.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).padding(52)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2 - 12
                for m in 0..<60 {
                    let a = Double(m) / 60 * 2 * .pi
                    let len: CGFloat = m % 15 == 0 ? 14 : (m % 5 == 0 ? 9 : 4)
                    let p1 = CGPoint(x: c.x + sin(a) * r, y: c.y - cos(a) * r)
                    let p2 = CGPoint(x: c.x + sin(a) * (r - len), y: c.y - cos(a) * (r - len))
                    var p = Path(); p.move(to: p1); p.addLine(to: p2)
                    ctx.stroke(p, with: .color(cyan.opacity(m % 5 == 0 ? 0.9 : 0.45)), lineWidth: m % 15 == 0 ? 2 : 1)
                }
                for (i, label) in ["60", "15", "30", "45"].enumerated() {
                    let a = Double(i) / 4 * 2 * .pi
                    let rr = r - 26
                    ctx.draw(Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.white.opacity(0.85)),
                             at: CGPoint(x: c.x + sin(a) * rr, y: c.y - cos(a) * rr))
                }
            }
            // Minutes of the current hour: the built arc.
            Circle()
                .trim(from: 0, to: arc)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(12)
            // The knob at the arc's end.
            Circle().fill(Color.white).frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .offset(y: -(side / 2 - 12))
                .rotationEffect(.degrees(arc * 360))
                .opacity(interactive ? 1 : 0)
            VStack(spacing: 6) {
                LHDurationNumerals(hours: isSet ? hours : nil, size: 44, onBrand: true)
                HStack(spacing: 5) {
                    ForEach(0..<min(12, max(wholeHours, 0)), id: \.self) { _ in
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                if !isSet {
                    Text("Turn to set").font(.footnote.weight(.semibold)).foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 50)
        }
        .frame(width: side, height: side)
        .animation(AppAnimation.feedback, value: minutes)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            guard interactive else { return }
            let c = CGPoint(x: side / 2, y: side / 2)
            var deg = atan2(Double(v.location.x - c.x), Double(-(v.location.y - c.y))) * 180 / .pi
            if deg < 0 { deg += 360 }
            if let last = lastAngle {
                var d = deg - last
                if d > 180 { d -= 360 }
                if d < -180 { d += 360 }
                minutesAccum = min(max(0, minutesAccum + d / 6), Double(LHDurationBeam.maxHours) * 60)
            } else {
                minutesAccum = Double(minutes)
            }
            lastAngle = deg
            let snapped = (minutesAccum / 15).rounded() * 15 / 60
            if snapped != hours { onChange(snapped) }
        }.onEnded { _ in lastAngle = nil })
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement()
        .accessibilityLabel("Time")
        .accessibilityValue(isSet ? LHFormat.spokenHours(hours) : "Not set")
        .accessibilityAdjustableAction { dir in
            guard interactive else { return }
            onChange(min(max(0, hours + (dir == .increment ? 0.25 : -0.25)), LHDurationBeam.maxHours))
        }
        .accessibilityIdentifier("logv2.dial")
    }
}

// MARK: House read-back

struct LHHouseReadback: View {
    let before: CraftStage
    let after: CraftStage
    let crosses: Bool
    let celebrating: Bool
    var size: CGFloat = 140

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: CraftStage { celebrating && crosses ? after : before }

    private func still(_ stage: CraftStage, lit: Bool) -> some View {
        Image(stage.assetName(lit: lit)).resizable().interpolation(.high).scaledToFit()
    }

    var body: some View {
        ZStack {
            if crosses && !celebrating {
                // What this log adds, drafted in cyan behind the house as it is.
                still(after, lit: false)
                    .colorMultiply(AdaptiveColors(colorScheme: colorScheme).drafting)
                    .opacity(0.6)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            ZStack {
                still(shown, lit: false)
                if colorScheme == .dark {
                    // §1.4 tile recipe, night: the unlit still again with plus-lighter, so the house
                    // reads on the dark card (0.30 roofed, 0.12 framing).
                    still(shown, lit: false).blendMode(.plusLighter)
                        .opacity(shown >= .half ? 0.30 : 0.12)
                }
                // windowsOn: the lit still fades over the unlit one (0.40).
                still(shown, lit: true).opacity(celebrating ? 1 : 0)
                    .animation(reduceMotion ? AppAnimation.windowsReduced : AppAnimation.windows, value: celebrating)
            }
            .id(shown)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.stageFade, value: shown)
        .accessibilityElement()
        .accessibilityLabel(CraftHouseView.accessibilityLabel(stage: shown, lit: celebrating))
        .accessibilityIdentifier("logv2.house")
    }
}
#endif
