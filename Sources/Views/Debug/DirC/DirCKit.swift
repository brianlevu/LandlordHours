import SwiftUI
import CoreHaptics

#if DEBUG
// MARK: - Direction C, "The Record" (DEBUG only, throwaway mock for the direction comparison)
//
//   -LHDirection C                          turn the mock on
//   -LHDirCScreen today|logtime              which screen (default today)
//   -LHHomeSeed brian|one|eight              which owner (StdSeed)
//   -LHDirCFocus <rental id>                 start on this rental's page (e.g. lake)
//   -LHDirCStart <hours>                     override the focused rental's logged hours (demos)
//   -LHDirCState holding                     logtime: freeze the hold-to-commit fill at 55%
//   -LHDirCDemo confirm|stage|goal|signature scripted run for the videos (a grey dot shows the finger)
//
// Spec: AgentScratch/landlordhours/2026-10-24/system-directions/directions.md §3 (Direction C).
// Every visible string goes through `C(...)` into the DirC string catalog.
// Haptics are written to stderr as "HAPTIC <t> <kind> — <moment>" so the videos can list them.

func C(_ key: String.LocalizationValue) -> String { String(localized: key, table: "DirC") }

struct DirCLaunch {
    enum Screen: String { case today, logtime }
    let screen: Screen
    let seedID: String
    let focus: String?
    let start: Double?
    let state: String
    let demo: String?

    static let current: DirCLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard value("-LHDirection")?.uppercased() == "C" else { return nil }
        return DirCLaunch(screen: Screen(rawValue: value("-LHDirCScreen") ?? "") ?? .today,
                          seedID: value("-LHHomeSeed") ?? "brian",
                          focus: value("-LHDirCFocus"),
                          start: value("-LHDirCStart").flatMap(Double.init),
                          state: value("-LHDirCState") ?? "",
                          demo: value("-LHDirCDemo"))
    }()
}

// MARK: - Tokens (§3.4). No blue anywhere.

struct DirCPalette {
    let canvas, rule, ink, textSecondary, action, marginRule, onAction, brass, brassInk, positive, rose, surfaceInner, actionWash: Color

    static func make(_ scheme: ColorScheme) -> DirCPalette {
        if scheme == .dark {
            return DirCPalette(canvas: .init(dircHex: 0x111111), rule: .init(dircHex: 0x262626), ink: .init(dircHex: 0xF3EEE3),
                               textSecondary: .init(dircHex: 0xA8A49C), action: .init(dircHex: 0xE06A6A),
                               marginRule: Color(dircHex: 0xE06A6A).opacity(0.7), onAction: .init(dircHex: 0x111111),
                               brass: .init(dircHex: 0xD4B15C), brassInk: .init(dircHex: 0xD4B15C), positive: .init(dircHex: 0x7FBF9A),
                               rose: .init(dircHex: 0xE39AB5), surfaceInner: .init(dircHex: 0x1C1C1C), actionWash: .init(dircHex: 0x2A1818))
        }
        return DirCPalette(canvas: .init(dircHex: 0xF3EEE3), rule: .init(dircHex: 0xD9D2C4), ink: .init(dircHex: 0x141414),
                           textSecondary: .init(dircHex: 0x5C5A55), action: .init(dircHex: 0x8A1C1C),
                           marginRule: .init(dircHex: 0x8A1C1C), onAction: .white,
                           brass: .init(dircHex: 0xB8923A), brassInk: .init(dircHex: 0x7A5A12), positive: .init(dircHex: 0x2E4A3B),
                           rose: .init(dircHex: 0x8C3A5A), surfaceInner: .init(dircHex: 0xEBE5D8), actionWash: .init(dircHex: 0xEADCD0))
    }
}

extension Color {
    init(dircHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct DirCColors: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    var p: DirCPalette { DirCPalette.make(scheme) }
}

enum DirCFont {
    static func hero(_ ax: Bool) -> Font { .system(size: ax ? 132 : 120, weight: .regular, design: .serif) }
    static let heroLabel = Font.system(.title3, design: .serif).italic()
    static let smallCaps = Font.system(.footnote, design: .serif).weight(.semibold).smallCaps()
    static let stamp = Font.system(.caption2, design: .monospaced).weight(.medium)
    static let drumCentre = Font.system(size: 56, weight: .regular, design: .serif)
}

enum DirCMotion {
    static let odometer = Animation.spring(duration: 0.40, bounce: 0)
    static let ringProgress = Animation.spring(duration: 0.60, bounce: 0)
    static let segment = Animation.spring(duration: 0.25, bounce: 0)
    static let slideOut = Animation.spring(duration: 0.30, bounce: 0)
    static let collapse = Animation.spring(duration: 0.25, bounce: 0)
    static let seal = Animation.spring(duration: 0.30, bounce: 0.15)   // the one allowed overshoot
    static let release = Animation.easeOut(duration: 0.20)
    static let engrave = Animation.easeOut(duration: 0.60)
}

enum DirCFormat {
    /// Ledger figures: "12", "65.5", "12.25".
    static func figure(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
    /// Drum and button: "1h 30m", "2h", "45m".
    static func hours(_ v: Double) -> String {
        let minutes = Int((v * 60).rounded()), h = minutes / 60, m = minutes % 60
        if h == 0 { return C("\(m)m") }
        if m == 0 { return C("\(h)h") }
        return C("\(h)h \(m)m")
    }
}

// MARK: - Haptics (same state as the animation; also written to stderr for the video notes)

enum DirCHaptic {
    static let t0 = Date()
    static func log(_ kind: String, _ moment: String) {
        let line = String(format: "HAPTIC %.2fs %@ — %@\n", Date().timeIntervalSince(t0), kind, moment)
        FileHandle.standardError.write(Data(line.utf8))
    }
}

/// Goal reached: a heavy transient, then a short decaying press (Core Haptics). Once a year per goal.
final class DirCPressHaptic {
    static let shared = DirCPressHaptic()
    private var engine: CHHapticEngine?

    func play() {
        DirCHaptic.log("custom(press: heavy transient + 0.3s decay)", "goal reached, seal pressed")
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine(); try engine?.start() }
            let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 1), .init(parameterID: .hapticSharpness, value: 0.55)], relativeTime: 0)
            let press = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.7), .init(parameterID: .hapticSharpness, value: 0.25)],
                relativeTime: 0.02, duration: 0.3)
            let decay = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 1), .init(relativeTime: 0.3, value: 0)], relativeTime: 0.02)
            let pattern = try CHHapticPattern(events: [tap, press], parameterCurves: [decay])
            try engine?.makePlayer(with: pattern).start(atTime: 0)
        } catch {
            DirCHaptic.log("custom-failed", error.localizedDescription)
        }
    }
}

// MARK: - The ruled page: pitch, lift, and a layout that keeps every block on the rules

private struct DirCPitchKey: EnvironmentKey { static let defaultValue: CGFloat = 32 }
private struct DirCMarginKey: EnvironmentKey { static let defaultValue: CGFloat = 56 }

extension EnvironmentValues {
    /// Distance between rules (32pt at the default text size; scales with .body).
    var dircPitch: CGFloat { get { self[DirCPitchKey.self] } set { self[DirCPitchKey.self] = newValue } }
    /// x of the oxblood margin rule (56pt; 72pt at accessibility sizes, where the date stamp grows).
    var dircMargin: CGFloat { get { self[DirCMarginKey.self] } set { self[DirCMarginKey.self] = newValue } }
}

/// Stacks blocks so each one occupies a whole number of rule pitches, bottom-aligned in its slot:
/// whatever a block's natural height, its last baseline lands on a rule.
struct DirCRuledStack: Layout {
    var pitch: CGFloat

    private func snap(_ h: CGFloat) -> CGFloat { h < 0.5 ? 0 : max(1, ceil((h - 0.5) / pitch)) * pitch }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 402
        let h = subviews.reduce(CGFloat(0)) { $0 + snap($1.sizeThatFits(.init(width: w, height: nil)).height) }
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for s in subviews {
            let size = s.sizeThatFits(.init(width: bounds.width, height: nil))
            let slot = snap(size.height)
            s.place(at: CGPoint(x: bounds.minX, y: y + slot - size.height), anchor: .topLeading,
                    proposal: .init(width: bounds.width, height: size.height))
            y += slot
        }
    }
}

/// A block whose last text baseline sits on the rule at its bottom (lifted 1/8 pitch so descenders
/// clear the rule). The block is a whole number of pitches tall, counting only what sits above the
/// baseline; descenders hang below like ink. `fixed` keeps the block at `pitches` even when display
/// type rises above it.
struct DirCRuleLine<Content: View>: View {
    var pitches: Int = 1
    var fixed = false
    @ViewBuilder var content: Content
    @Environment(\.dircPitch) private var pitch

    var body: some View {
        DirCBaselineSlot(pitch: pitch, pitches: pitches, fixed: fixed) { content }
    }
}

struct DirCBaselineSlot: Layout {
    var pitch: CGFloat
    var pitches: Int
    var fixed: Bool
    private var lift: CGFloat { pitch / 8 }

    private func height(_ above: CGFloat) -> CGFloat {
        let base = pitch * CGFloat(pitches)
        return fixed ? base : max(base, ceil((above + lift - 0.5) / pitch) * pitch)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 402
        guard let s = subviews.first else { return CGSize(width: w, height: pitch * CGFloat(pitches)) }
        let d = s.dimensions(in: .init(width: w, height: nil))
        return CGSize(width: w, height: height(d[VerticalAlignment.lastTextBaseline]))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let s = subviews.first else { return }
        let d = s.dimensions(in: .init(width: bounds.width, height: nil))
        let above = d[VerticalAlignment.lastTextBaseline]
        s.place(at: CGPoint(x: bounds.minX, y: bounds.minY + height(above) - lift - above), anchor: .topLeading,
                proposal: .init(width: bounds.width, height: d.height))
    }
}

/// Line spacing that puts every wrapped line of `style` on its own rule.
struct DirCRuled: ViewModifier {
    let style: UIFont.TextStyle
    @Environment(\.dircPitch) private var pitch
    func body(content: Content) -> some View {
        content.lineSpacing(max(0, pitch - UIFont.preferredFont(forTextStyle: style).lineHeight))
    }
}

extension View {
    func dircRuled(_ style: UIFont.TextStyle) -> some View { modifier(DirCRuled(style: style)) }
}

/// One ledger line: the margin column (right-aligned against the margin rule) and the body column.
struct DirCLedgerLine<Margin: View, Main: View>: View {
    @ViewBuilder var margin: Margin
    @ViewBuilder var main: Main
    @Environment(\.dircMargin) private var marginX

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            margin
                .frame(width: max(0, marginX - 18), alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12).padding(.trailing, 6)
            main
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12).padding(.trailing, 20)
        }
    }
}

struct DirCNoMargin: View {
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}

extension DirCLedgerLine where Margin == DirCNoMargin {
    init(@ViewBuilder main: () -> Main) { self.init(margin: { DirCNoMargin() }, main: main) }
}

/// Rules every pitch, starting one pitch below the block's top, extended `overscan` past both ends.
struct DirCRules: View {
    var overscan: CGFloat = 0
    var firstRule: Int = 1
    @Environment(\.dircPitch) private var pitch
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let rule = DirCPalette.make(scheme).rule
        Canvas { ctx, size in
            var y = pitch * CGFloat(firstRule) + overscan
            var path = Path()
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y - 0.25)); path.addLine(to: CGPoint(x: size.width, y: y - 0.25))
                y += pitch
            }
            ctx.stroke(path, with: .color(rule), lineWidth: 0.5)
        }
        .padding(.vertical, -overscan)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The page under everything: paper, plus the full-height margin rule (under the status bar and the tab bar).
struct DirCPaper: View {
    @Environment(\.dircMargin) private var marginX
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = DirCPalette.make(scheme)
        p.canvas
            .overlay(alignment: .topLeading) {
                Rectangle().fill(p.marginRule).frame(width: 1).offset(x: marginX - 0.5)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The margin rule on its own (for drawing above a block that covers the paper).
struct DirCMarginRule: View {
    @Environment(\.dircMargin) private var marginX
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(DirCPalette.make(scheme).marginRule).frame(width: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .offset(x: marginX - 0.5)
            .allowsHitTesting(false)
    }
}

// MARK: - The engraving: mark B's house, 1pt hairline, drawn stage by stage

/// Stage 0: the ground line. 1: foundation. 2: walls. 3: roof and chimney. 4: door and windows. 5: hatching (complete).
struct DirCHouseLayer: Shape {
    let stage: Int

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 48, sy = rect.height / 40
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var p = Path()
        switch stage {
        case 0:
            p.move(to: pt(0, 39.5)); p.addLine(to: pt(48, 39.5))
        case 1:
            p.move(to: pt(5, 39.5)); p.addLine(to: pt(5, 35)); p.addLine(to: pt(43, 35)); p.addLine(to: pt(43, 39.5))
        case 2:
            p.move(to: pt(8, 35)); p.addLine(to: pt(8, 19))
            p.move(to: pt(40, 35)); p.addLine(to: pt(40, 19))
        case 3:
            p.move(to: pt(4, 21)); p.addLine(to: pt(24, 4)); p.addLine(to: pt(44, 21))
            p.move(to: pt(32, 11)); p.addLine(to: pt(32, 5)); p.addLine(to: pt(36, 5)); p.addLine(to: pt(36, 14.5))
        case 4:
            p.move(to: pt(21, 35)); p.addLine(to: pt(21, 25)); p.addLine(to: pt(27, 25)); p.addLine(to: pt(27, 35))
            p.addRect(CGRect(origin: pt(12, 22), size: CGSize(width: 5 * sx, height: 5 * sy)))
            p.addRect(CGRect(origin: pt(31, 22), size: CGSize(width: 5 * sx, height: 5 * sy)))
        default:
            // Engraver's hatching under the eaves and on the roof face.
            for i in 0..<5 {
                let x = 11 + CGFloat(i) * 3.2
                p.move(to: pt(x, 19)); p.addLine(to: pt(x + 5, 13.5 - CGFloat(i) * 0.2))
            }
            for i in 0..<3 {
                let y = 30 + CGFloat(i) * 1.6
                p.move(to: pt(9.5, y)); p.addLine(to: pt(19.5, y))
            }
        }
        return p
    }
}

struct DirCEngraving: View {
    let stage: Int
    var ink: Color
    var lineWidth: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // The engraver's underdrawing: what is still to come, as a faint dotted pencil line.
            ForEach(0...4, id: \.self) { s in
                DirCHouseLayer(stage: s)
                    .stroke(ink.opacity(0.28), style: StrokeStyle(lineWidth: 0.5, lineCap: .round, dash: [1, 2]))
                    .opacity(s <= stage ? 0 : 1)
            }
            ForEach(0...5, id: \.self) { s in
                DirCHouseLayer(stage: s)
                    .trim(from: 0, to: s <= stage ? 1 : 0)
                    .stroke(ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : DirCMotion.engrave.delay(Double(max(0, s - 1)) * 0.0), value: stage)
            }
        }
        .accessibilityHidden(true)
    }

    static func stage(logged: Double, target: Int?) -> Int {
        guard let target, target > 0 else { return 5 }
        let p = logged / Double(target)
        if p >= 1 { return 5 }
        if p >= 0.75 { return 4 }
        if p >= 0.5 { return 3 }
        if p >= 0.25 { return 2 }
        return logged > 0 ? 1 : 0
    }
}

// MARK: - The brass seal (100 HOURS · 2026)

struct DirCSeal: View {
    let threshold: Int
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 96

    var body: some View {
        let p = DirCPalette.make(scheme)
        let d = min(size, 96)   // an object on the page, not text: it keeps its size (VoiceOver reads the label)
        ZStack {
            Circle().fill(p.brass.opacity(scheme == .dark ? 0.14 : 0.16))
            Circle().strokeBorder(p.brass, lineWidth: 1.5)
            Circle().strokeBorder(p.brass, lineWidth: 0.5).padding(6)
            VStack(spacing: 3) {
                DirCEngraving(stage: 5, ink: p.brassInk, lineWidth: 0.9).frame(width: d * 0.30, height: d * 0.25)
                Text(C("\(threshold) HOURS")).font(.system(size: d * 0.105, weight: .semibold, design: .monospaced))
                    .foregroundStyle(p.brassInk).fixedSize()
                Text(verbatim: "2026").font(.system(size: d * 0.105, weight: .medium, design: .monospaced))
                    .foregroundStyle(p.brassInk)
            }
        }
        .frame(width: d, height: d)
        .rotationEffect(.degrees(-8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(C("Seal: \(threshold) hours, 2026"))
    }
}

// MARK: - The year line: thresholds as brass hairline circles, the total as an ink dot

struct DirCYearLine: View {
    let logged: Double
    let target: Int
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dircPitch) private var pitch

    private var marks: [Int] { [100, 500, 750].filter { $0 <= target } }

    var body: some View {
        let p = DirCPalette.make(scheme)
        GeometryReader { geo in
            let w = geo.size.width
            let lineY = pitch * 0.30
            let x: (Double) -> CGFloat = { CGFloat(min($0, Double(target)) / Double(target)) * w }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(p.ink).frame(width: w, height: 1).offset(y: lineY - 0.5)
                // Quarter ticks: where the engraving gains its walls, roof and door.
                ForEach([0.25, 0.5, 0.75], id: \.self) { f in
                    Rectangle().fill(p.ink.opacity(0.45)).frame(width: 0.5, height: 6)
                        .offset(x: w * f - 0.25, y: lineY - 3)
                }
                ForEach(marks, id: \.self) { m in
                    let reached = logged >= Double(m)
                    ZStack {
                        Circle().fill(p.brass).opacity(reached ? 1 : 0)
                        Circle().strokeBorder(p.brass, lineWidth: 1)
                    }
                    .frame(width: 10, height: 10)
                    .offset(x: x(Double(m)) - 5, y: lineY - 5)
                    .animation(DirCMotion.seal, value: reached)
                    Text(verbatim: "\(m)").font(DirCFont.stamp).foregroundStyle(p.brassInk).monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .fixedSize()
                        .frame(width: 60, alignment: m == target ? .trailing : .center)
                        .offset(x: m == target ? x(Double(m)) - 60 + 5 : x(Double(m)) - 30, y: lineY + 6)
                }
                Circle().fill(p.ink).frame(width: 6, height: 6)
                    .offset(x: x(logged) - 3, y: lineY - 3)
                    .animation(DirCMotion.ringProgress, value: logged)
            }
        }
        .frame(height: pitch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(C("\(DirCFormat.figure(logged)) of \(target) hours"))
    }
}
#endif
