import SwiftUI
import UIKit
import CoreHaptics
import CoreText

#if DEBUG
// MARK: - Direction A, Job Site (DEBUG mock, throwaway)
//
//   -LHDirection A                         turns the mock on
//   -LHDirScreen today|logtime             which screen (default today)
//   -LHHomeSeed brian|one|eight|behind     which owner ("behind" = REPS 206 of 750, the spec's own example)
//   -LHDirPaper kraft|vellum               light canvas variant (default kraft; dark is always blueprint)
//   -LHDirDemo confirm|stage|goal|tape     scripted run for the videos (starts at 2.0s)
//   -LHDirFocus <n>                        start with switcher item n
//   -LHDirScroll bottom                    Today: start scrolled to the end
//
// Spec: AgentScratch/landlordhours/2026-10-24/system-directions/directions.md §1 (Direction A),
// with the critic's amendments (dark first, vellum test, no grain, no planks, no window light,
// no sound, quick picks above the tape). Every string goes through DL(...) (table "DirA").

func DL(_ key: String.LocalizationValue) -> String { String(localized: key, table: "DirA") }

struct DirALaunch {
    enum Screen: String { case today, logtime }
    enum Paper: String { case kraft, vellum }

    let screen: Screen
    let seedID: String
    let paper: Paper
    let demo: String?
    let focusIndex: Int
    let scroll: String?

    static let current: DirALaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard value("-LHDirection")?.uppercased() == "A" else { return nil }
        return DirALaunch(screen: Screen(rawValue: value("-LHDirScreen") ?? "today") ?? .today,
                          seedID: value("-LHHomeSeed") ?? "brian",
                          paper: Paper(rawValue: value("-LHDirPaper") ?? "kraft") ?? .kraft,
                          demo: value("-LHDirDemo"),
                          focusIndex: Int(value("-LHDirFocus") ?? "") ?? 0,
                          scroll: value("-LHDirScroll"))
    }()
}

// MARK: - Tokens (§1.4, measured; vellum re-measured 2026-10-24)

struct DAColors {
    let dark: Bool
    let paper: DirALaunch.Paper

    private func pick(_ l: String, _ d: String) -> Color { Color(hex: dark ? d : l) }

    /// Kraft #E9DFC9 or vellum #EDE8DC by day; blueprint paper by night.
    var canvas: Color { dark ? Color(hex: "0B1230") : Color(hex: paper == .vellum ? "EDE8DC" : "E9DFC9") }
    /// Section container. Plaster on kraft (step 1.16); on vellum plaster only steps 1.07, so vellum uses #F7F4EC (1.11).
    var surface: Color { dark ? Color(hex: "141C3F") : Color(hex: paper == .vellum ? "F7F4EC" : "F4EFE6") }
    var surfaceInner: Color { pick("EFE7D6", "1B2550") }
    var sheet: Color { pick("F4EFE6", "141C3F") }
    var ink: Color { pick("121B33", "F2F4FA") }
    var textSecondary: Color { pick("4A5068", "B4BCD2") }
    var textTertiary: Color { pick("4F5870", "7E88A6") }
    var action: Color { pick("1E3FA6", "8FD3FF") }
    var onAction: Color { pick("FFFFFF", "0B1230") }
    var actionSurface: Color { pick("DCE1F1", "182A5C") }
    var draftingInk: Color { pick("1F5A9C", "60A8E6") }
    var dimensionTrack: Color { dark ? Color(hex: "8FD3FF").opacity(0.30) : Color(hex: "1E3FA6").opacity(0.35) }
    var positive: Color { pick("0C5A30", "4ED48A") }
    var positiveSurface: Color { pick("DDEBD9", "123A2A") }
    var caution: Color { pick("7F4406", "FFB454") }
    var cautionSurface: Color { pick("F2E3C9", "3D2A10") }
    var destructive: Color { pick("A8402C", "E8785F") }
    var terracotta: Color { pick("C8553D", "E8785F") }
    var timberInk: Color { pick("7A4E14", "F0BE7A") }
    var informational: Color { pick("3F5783", "9BB0D0") }
    var informationalSurface: Color { pick("E1E6EF", "1D2A4A") }
    var border: Color { pick("C9BFA8", "2A3560") }
    /// Linework of the model on the paper.
    var linework: Color { pick("1F5A9C", "8FD3FF") }

    /// Category tag ink. The 2.0 light inks measured 3.6–3.9:1 on their 12% wash over kraft, so the
    /// kraft day shift takes a darker step of each (same hue, ≥ 4.8:1 even on bare kraft). Dark keeps 2.0.
    func tagInk(_ c: ActivityCategory) -> Color {
        if dark { return Color(hex: AppColors.categoryTagInkHex(c).dark) }
        switch c {
        case .repairs: return Color(hex: "734B17")
        case .renovations: return Color(hex: "913625")
        case .management: return Color(hex: "694F00")
        case .leasing: return Color(hex: "175A75")
        case .bookkeeping: return Color(hex: "455A22")
        case .legal: return Color(hex: "1C5592")
        case .travel: return Color(hex: "3F547C")
        case .contractNegotiation: return Color(hex: "86410B")
        case .insurance: return Color(hex: "2F3E7A")
        case .investing: return Color(hex: "54580E")
        case .financing: return Color(hex: "82431F")
        }
    }
    func tagWash(_ c: ActivityCategory) -> Color { tagInk(c).opacity(0.12) }
}

struct DAEnv: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    var c: DAColors { DAColors(dark: scheme == .dark, paper: DirALaunch.current?.paper ?? .kraft) }
}

// MARK: - Type (§1.3)

enum DAFont {
    /// SF Mono 11 medium caps +12%: stamps, ticks, section headers. Scales with caption2.
    static let mono = Font.system(.caption2, design: .monospaced, weight: .medium)
    static let monoTracking: CGFloat = 1.32

    /// Fraunces with its axes set (opsz, wght, SOFT, WONK) and tabular figures.
    static func fraunces(size: CGFloat, opsz: CGFloat, wght: CGFloat, soft: CGFloat = 50, tnum: Bool = true) -> Font {
        Font(frauncesUI(size: size, opsz: opsz, wght: wght, soft: soft, tnum: tnum))
    }

    static func frauncesUI(size: CGFloat, opsz: CGFloat, wght: CGFloat, soft: CGFloat = 50, tnum: Bool = true) -> UIFont {
        logAxesOnce
        let variations: [NSNumber: CGFloat] = [
            NSNumber(value: LHFont.axisTag("wght")): wght,
            NSNumber(value: LHFont.axisTag("opsz")): opsz,
            NSNumber(value: LHFont.axisTag("SOFT")): soft,
            NSNumber(value: LHFont.axisTag("WONK")): 0,
        ]
        var attrs: [UIFontDescriptor.AttributeName: Any] = [
            .family: LHFont.frauncesFamily,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
        ]
        if tnum {
            attrs[.featureSettings] = [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]
        }
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attrs), size: size)
        if font.familyName != LHFont.frauncesFamily {
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        return font
    }

    /// One log line so the capture lane can confirm the axes the bundled TTF exposes.
    private static let logAxesOnce: Void = {
        let f = CTFontCreateWithName("Fraunces" as CFString, 96, nil)
        let axes = (CTFontCopyVariationAxes(f) as? [[String: Any]])?.compactMap { $0[kCTFontVariationAxisNameKey as String] as? String } ?? []
        NSLog("DirA fraunces axes: %@", axes.joined(separator: ","))
    }()
}

// MARK: - The paper (§1.2): no grain (critic); the night shift keeps the 24pt drafting grid

struct DAPaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = DAColors(dark: scheme == .dark, paper: DirALaunch.current?.paper ?? .kraft)
        ZStack {
            c.canvas
            if scheme == .dark {
                Canvas { ctx, size in
                    var p = Path()
                    var x: CGFloat = 0
                    while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += 24 }
                    var y: CGFloat = 0
                    while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += 24 }
                    ctx.stroke(p, with: .color(Color(hex: "8FD3FF").opacity(0.06)), lineWidth: 0.5)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Section container (§1.2): tone step + 0.5pt hairline, radius 20

struct DASection<Content: View>: View {
    @ViewBuilder var content: Content
    private var env = DAEnv()
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(env.c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(env.c.border, lineWidth: 0.5))
    }
}

struct DAHairline: View {
    private var env = DAEnv()
    var body: some View { Rectangle().fill(env.c.border).frame(height: 0.5) }
}

/// "TO CONFIRM · 3" in SF Mono, with a trailing .tertiary link.
struct DASectionHeader: View {
    let title: String
    var trailing: String? = nil
    private var env = DAEnv()
    init(_ title: String, trailing: String? = nil) { self.title = title; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(DAFont.mono).tracking(DAFont.monoTracking)
                .foregroundStyle(env.c.draftingInk)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Button(trailing) {}
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(env.c.action)
                    .buttonStyle(DAPress())
                    .frame(minHeight: 44)
            }
        }
        .frame(minHeight: 16)
    }
}

struct DAPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// `.primary`: 52 capsule, action / onAction. On iOS 26 the caller uses .glassProminent instead.
struct DAPrimaryStyle: ButtonStyle {
    private var env = DAEnv()
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(env.c.onAction)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(env.c.action, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Tag (§1.6: category tag on its category wash)

struct DATag: View {
    let text: String
    let ink: Color
    let wash: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(wash))
    }
}

// MARK: - The dimension line (§1.5)

struct DAPace: Equatable {
    /// Hours logged.
    let logged: Double
    /// Goal, or nil for a record-only rental (no plumb marker, no goal label).
    let goal: Double?
    /// Hours a steady pace would have by today.
    let expected: Double?
    var behind: Bool { guard let expected else { return false }; return logged + 0.001 < expected }
    var scaleMax: Double { goal ?? max(50, (logged / 50).rounded(.up) * 50) }
    var tickStep: Double { scaleMax <= 100 ? 10 : 50 }
    var milestones: [Double] {
        guard let goal else { return [] }
        if goal >= 750 { return [100, 500] }
        if goal >= 500 { return [100] }
        return [50]
    }
}

/// The logged portion as an animatable shape: 3pt, square caps, from the left end.
private struct DAFillShape: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * min(max(fraction, 0), 1), y: rect.midY))
        return p
    }
}

struct DADimensionLine: View {
    let pace: DAPace
    /// Draws the labels and the plumb marker; the medium widget would pass false.
    var labelled = true
    private var env = DAEnv()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(pace: DAPace, labelled: Bool = true) { self.pace = pace; self.labelled = labelled }

    private var fraction: Double { min(pace.logged / pace.scaleMax, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                let y: CGFloat = 30
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        let c = env.c
                        // Track, 1pt, with ticks every 50h (10h on a 100h goal), 4pt.
                        var track = Path()
                        track.move(to: CGPoint(x: 0, y: y)); track.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(track, with: .color(c.dimensionTrack), style: StrokeStyle(lineWidth: 1, lineCap: .square))
                        var ticks = Path()
                        var h = pace.tickStep
                        while h < pace.scaleMax - 0.01 {
                            let x = size.width * h / pace.scaleMax
                            ticks.move(to: CGPoint(x: x, y: y - 2)); ticks.addLine(to: CGPoint(x: x, y: y + 2))
                            h += pace.tickStep
                        }
                        // Milestone ticks run 8pt so 100 and 500 read as marks, not just counts.
                        for m in pace.milestones {
                            let x = size.width * m / pace.scaleMax
                            ticks.move(to: CGPoint(x: x, y: y - 4)); ticks.addLine(to: CGPoint(x: x, y: y + 4))
                        }
                        ctx.stroke(ticks, with: .color(c.dimensionTrack), style: StrokeStyle(lineWidth: 1, lineCap: .square))
                        // Drafting arrowheads at both ends: two 45° strokes, 6pt, square caps, plus the extension lines.
                        var heads = Path()
                        let a: CGFloat = 6 * 0.7071
                        heads.move(to: CGPoint(x: a, y: y - a)); heads.addLine(to: CGPoint(x: 0, y: y)); heads.addLine(to: CGPoint(x: a, y: y + a))
                        heads.move(to: CGPoint(x: size.width - a, y: y - a)); heads.addLine(to: CGPoint(x: size.width, y: y)); heads.addLine(to: CGPoint(x: size.width - a, y: y + a))
                        heads.move(to: CGPoint(x: 0, y: y - 8)); heads.addLine(to: CGPoint(x: 0, y: y + 8))
                        heads.move(to: CGPoint(x: size.width, y: y - 8)); heads.addLine(to: CGPoint(x: size.width, y: y + 8))
                        ctx.stroke(heads, with: .color(c.action), style: StrokeStyle(lineWidth: 1, lineCap: .square))
                    }
                    DAFillShape(fraction: fraction)
                        .stroke(env.c.action, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                        .frame(width: w, height: y * 2)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.60, bounce: 0), value: fraction)
                    if labelled, let expected = pace.expected {
                        plumb(expected: expected, width: w, y: y)
                    }
                }
            }
            .frame(height: 40)
            if labelled { labels }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    /// The plumb marker: 8pt inverted triangle above the line at today's expected position,
    /// terracotta ink when behind, positive when on or ahead. "PACE" names it (critic: must read as behind in 5s).
    private func plumb(expected: Double, width: CGFloat, y: CGFloat) -> some View {
        let x = width * min(expected / pace.scaleMax, 1)
        let ink = pace.behind ? env.c.destructive : env.c.positive
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: 0, y: 7)); p.closeSubpath()
            }
            .fill(ink)
            .offset(x: x, y: y - 10)
            Path { p in p.move(to: CGPoint(x: x, y: y - 3)); p.addLine(to: CGPoint(x: x, y: y + 3)) }
                .stroke(ink, lineWidth: 1)
            Text(DL("PACE \(Int(expected.rounded()))"))
                .font(DAFont.mono).tracking(DAFont.monoTracking)
                .foregroundStyle(ink)
                .fixedSize()
                .alignmentGuide(.leading) { d in d.width / 2 }
                .position(x: min(max(x, 40), width - 40), y: 9)
        }
        .frame(width: width, height: y * 2, alignment: .topLeading)
    }

    private var labels: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                label("0").position(x: 5, y: 8)
                ForEach(pace.milestones, id: \.self) { m in
                    label("\(Int(m))").position(x: w * m / pace.scaleMax, y: 8)
                }
                label(pace.goal.map { "\(Int($0))" } ?? DL("\(Int(pace.scaleMax))h")).position(x: w - 12, y: 8)
            }
        }
        .frame(height: 16)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(DAFont.mono).foregroundStyle(env.c.draftingInk).monospacedDigit().fixedSize()
    }

    private var accessibility: String {
        var s = DL("\(Int(pace.logged)) hours")
        if let goal = pace.goal { s += DL(" of \(Int(goal))") }
        if let e = pace.expected { s += pace.behind ? DL(", behind pace of \(Int(e))") : DL(", on or ahead of pace") }
        return s
    }
}

// MARK: - The inspection stamp (§1.11 #2): inked on the paper, not stuck on it

/// Rubber-stamp ink: no fill, no shadow, double rule, mono caps, an uneven ink coverage mask
/// and multiply blending in light (screen-like in dark), so it reads as ink pressed into paper.
struct DAStamp: View {
    let lines: [String]
    private var env = DAEnv()
    @Environment(\.colorScheme) private var scheme
    init(lines: [String]) { self.lines = lines }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, s in
                Text(s)
                    .font(.system(size: i == 0 ? 15 : 11, weight: i == 0 ? .bold : .semibold, design: .monospaced))
                    .tracking(i == 0 ? 2.2 : 1.4)
                    .dynamicTypeSize(.large)
            }
        }
        .foregroundStyle(env.c.terracotta)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(env.c.terracotta, lineWidth: 2))
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(env.c.terracotta, lineWidth: 0.75))
        .mask { DAInkMask() }
        .opacity(scheme == .dark ? 0.92 : 0.88)
        .blendMode(scheme == .dark ? .normal : .multiply)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined(separator: ", "))
    }
}

/// Uneven ink: a fixed pseudo-random speckle so the stamp has dropouts, the same on every render.
private struct DAInkMask: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
            ctx.blendMode = .destinationOut
            for _ in 0..<Int(size.width * size.height / 14) {
                let p = CGPoint(x: rnd() * size.width, y: rnd() * size.height)
                let r = 0.4 + rnd() * 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)), with: .color(.black.opacity(0.55 + rnd() * 0.45)))
            }
            // One lighter band where the stamp pressed unevenly.
            ctx.fill(Path(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.16)),
                     with: .color(.black.opacity(0.18)))
        }
    }
}

// MARK: - Haptics: the goal pattern (§1.7, Core Haptics, once a year per goal)

final class DAGoalHaptics {
    static let shared = DAGoalHaptics()
    private var engine: CHHapticEngine?

    func play() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine(); try engine?.start() }
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 0.7)], relativeTime: 0),
                CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 0.4),
                                                                         .init(parameterID: .hapticSharpness, value: 0.3)],
                              relativeTime: 0.1, duration: 0.4),
                CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 1.0),
                                                                        .init(parameterID: .hapticSharpness, value: 0.6)], relativeTime: 0.55),
            ]
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                               controlPoints: [.init(relativeTime: 0.1, value: 0.4), .init(relativeTime: 0.5, value: 0.8)],
                                               relativeTime: 0)
            let player = try engine?.makePlayer(with: CHHapticPattern(events: events, parameterCurves: [curve]))
            try player?.start(atTime: 0)
        } catch {
            NSLog("DirA haptics unavailable: %@", error.localizedDescription)
        }
    }
}

extension View {
    /// Confirm draws the check on (SF Symbols 7 drawOn, iOS 26+); earlier systems fade.
    @ViewBuilder func daDrawOnTransition() -> some View {
        if #available(iOS 26.0, *) { transition(.symbolEffect(.drawOn.byLayer)) } else { transition(.opacity) }
    }
}

/// Scripted demo timing: everything starts at 2.0s so the recorder has a still lead-in.
enum DADemo {
    static func after(_ seconds: Double, _ run: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            run()
        }
    }
}
#endif
