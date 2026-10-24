import SwiftUI
import UIKit
import CoreHaptics

#if DEBUG
// MARK: - Direction B, Porch Light (DEBUG mock, throwaway)
//
// Spec: AgentScratch/landlordhours/2026-10-24/system-directions/directions.md §2 (Porch Light).
//
//   -LHDirection B                       this mock (required)
//   -LHDirBScreen today|inbox|logtime     which screen (default today)
//   -LHHomeSeed brian|one|eight|reps750   which owner
//   -LHStdState empty|filled              inbox: the empty world or the list
//   -LHSkyTime dawn|day|dusk|night        pin the sky (default: the phone clock)
//   -LHDirBDemo confirm|stage|goal|scrub  scripted run for the videos
//   -LHDirBPreset <hours>                 start the focused rental at this many hours (stage/goal demos)
//   -LHDirBFocus <rental id>              start on this rental
//   -LHTypeSize ax3                       Dynamic Type for captures
//   -LHColorScheme light|dark
//
// Every visible string goes through `P(...)` into DirB.xcstrings.

func P(_ key: String.LocalizationValue) -> String { String(localized: key, table: "DirB") }

struct PorchLaunch {
    enum Screen: String { case today, inbox, logtime }
    let screen: Screen
    let seedID: String
    let state: String
    let demo: String?
    let preset: Double?
    let focus: String?
    let typeSize: DynamicTypeSize?

    static let current: PorchLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard value("-LHDirection")?.uppercased() == "B" else { return nil }
        let size: DynamicTypeSize?
        switch value("-LHTypeSize") {
        case "xxl": size = .xxxLarge
        case "ax3": size = .accessibility3
        case "ax5": size = .accessibility5
        default: size = nil
        }
        return PorchLaunch(screen: Screen(rawValue: value("-LHDirBScreen") ?? "today") ?? .today,
                           seedID: value("-LHHomeSeed") ?? "brian",
                           state: value("-LHStdState") ?? "filled",
                           demo: value("-LHDirBDemo"),
                           preset: value("-LHDirBPreset").flatMap(Double.init),
                           focus: value("-LHDirBFocus"),
                           typeSize: size)
    }()
}

// MARK: - Colour (§2.4, plus the behind-pace fix)

/// Porch Light tokens. Light = cream day ground, dark = plum night ground.
/// Violet appears only where §2.4 defines it (action #5B4C86 / #B7A9E8, night plum ground #1A1530,
/// night sky). Flagged in the report: the brand retired violet.
struct PorchColors {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    static func hex(_ rgb: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, opacity: a)
    }
    private func pick(_ l: UInt32, _ d: UInt32) -> Color { Self.hex(dark ? d : l) }

    var ground: Color { pick(0xFBF3E6, 0x1A1530) }
    var surface: Color { pick(0xFFF9F0, 0x241D3E) }
    var surfaceInner: Color { pick(0xF4EADA, 0x2E2650) }
    var ink: Color { pick(0x1A1530, 0xF6F1E8) }
    var textSecondary: Color { pick(0x4F4868, 0xC9C0DC) }
    var textTertiary: Color { pick(0x6A6380, 0xA59CBC) }
    var action: Color { pick(0x5B4C86, 0xB7A9E8) }
    var onAction: Color { pick(0xFFFFFF, 0x1A1530) }
    var glow: Color { Self.hex(0xE8A33D) }
    var glowInk: Color { pick(0x8F5A0A, 0xF0C27B) }
    var positive: Color { glowInk }
    /// Behind pace. §2.4's storm slate did not read as a warning (critic, 2026-10-24); amber is the
    /// brand. Ember: a brick red-orange, carried with a word ("Behind") and a glyph, never colour alone.
    var behind: Color { pick(0xA8391B, 0xFF9C7E) }
    var behindSurface: Color { pick(0xF8DDD2, 0x4A2430) }
    var destructive: Color { pick(0xB04A3C, 0xE4786A) }
    var rose: Color { pick(0x9E3A5B, 0xF08BAA) }
    var border: Color { pick(0xE6DCCB, 0x3A3158) }
    var tagWash: Color { pick(0xF1E4CF, 0x352C55) }
    var tagInk: Color { pick(0x5A4A2E, 0xE2D6BE) }
}

// MARK: - The sky (§2.2), measured

/// Stops are in points from the top of the sky; the sky is drawn to `height`. Every state keeps
/// white text ≥ 4.5:1 down to `deepUntil` (the top of the horizon band), so the numeral and its
/// label ("of 100 hours") always sit on deep sky. Measured (WCAG, sRGB) white vs the lightest
/// colour above the band: day 5.22 · dawn 6.95 · dusk 9.71 · night 14.6 (light); 7.3+ in dark.
enum PorchSky: String, CaseIterable {
    case dawn, day, dusk, night, golden

    static func now(_ date: Date = Date()) -> PorchSky {
        if let f = StdSkyPhase.forced { return PorchSky(rawValue: f.rawValue) ?? .day }
        switch Calendar.current.component(.hour, from: date) {
        case 5..<8: return .dawn
        case 8..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    /// (zenith, deep end at the band top, light just above the horizon, haze at the horizon).
    func palette(dark: Bool) -> [UInt32] {
        switch (self, dark) {
        case (.day, false): return [0x2F62B8, 0x3463B4, 0x8FB8EC, 0xF3E3C9]
        case (.dawn, false): return [0x1E3B78, 0x3C5A8A, 0xD9946E, 0xF6DCBC]
        case (.dusk, false): return [0x182A62, 0x2E4372, 0xD6744A, 0xF4C496]
        case (.night, false): return [0x0E0B1F, 0x2A2250, 0x3E3262, 0x4A3A6E]   // §2.12 night (violet, spec-defined)
        case (.day, true): return [0x163066, 0x24467E, 0x5A7AAE, 0x8C8FA6]       // "evening blue"
        case (.dawn, true): return [0x12224A, 0x26395E, 0x8E5C4E, 0xA97862]
        case (.dusk, true): return [0x0F1840, 0x1F2C54, 0x8C4632, 0xA35E40]
        case (.night, true): return [0x07061A, 0x1A163C, 0x2C2450, 0x352A58]
        case (.golden, false): return [0x233A70, 0x94502E, 0xE89A4E, 0xFBE0B0]
        case (.golden, true): return [0x1A2E60, 0x7A4228, 0xB8703A, 0xC98A52]
        }
    }

    /// Sun (or moon) blob colour, top-right.
    var blob: Color {
        switch self {
        case .night: return Color(white: 1, opacity: 0.06)
        case .golden: return PorchColors.hex(0xFFC070, 0.30)
        case .dusk: return PorchColors.hex(0xFFB080, 0.20)
        default: return PorchColors.hex(0xFFDCA0, 0.20)
        }
    }

    var symbol: String {
        switch self {
        case .dawn, .dusk, .golden: return "sun.horizon"
        case .day: return "sun.max"
        case .night: return "moon.stars"
        }
    }

    /// How much the house art dims under this sky.
    var houseBrightness: Double {
        switch self { case .night: return -0.24; case .dusk: return -0.10; case .dawn: return -0.06; default: return 0 }
    }
}

/// The sky field: one gradient per state stacked and crossfaded (0.9s, bound to the state), two
/// static blurred blobs, stars at night. Never animates otherwise.
struct PorchSkyView: View {
    let sky: PorchSky
    let dark: Bool
    let height: CGFloat
    /// Where the deep part ends (the top of the horizon band, or the bottom of the last sky text).
    let deepUntil: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func gradient(_ s: PorchSky) -> LinearGradient {
        let p = s.palette(dark: dark).map { PorchColors.hex($0) }
        let h = max(height, 1)
        let deep = min(max(deepUntil / h, 0.05), 0.92)
        let light = min(max((height - 35) / h, deep + 0.02), 0.97)
        return LinearGradient(stops: [
            .init(color: p[0], location: 0),
            .init(color: p[1], location: deep),
            .init(color: p[2], location: light),
            .init(color: p[3], location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(PorchSky.allCases, id: \.self) { s in
                gradient(s).opacity(s == sky ? 1 : 0)
            }
            // Blobs stay off the text: the sun sits above and right of the status bar, the second
            // glow on the horizon band (they lightened the zenith under white text by up to 0.6:1).
            Circle().fill(sky.blob).frame(width: 260, height: 260).blur(radius: 70).offset(x: 130, y: -130)
            Circle().fill(sky.blob.opacity(0.8)).frame(width: 200, height: 200).blur(radius: 60).offset(x: -200, y: deepUntil + 10)
            if sky == .night { PorchStars(height: deepUntil).transition(.opacity) }
        }
        .frame(height: height)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: sky)
        .accessibilityHidden(true)
    }
}

/// A fixed star field (seeded, no twinkle).
struct PorchStars: View {
    let height: CGFloat
    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: 7)
            for _ in 0..<70 {
                let x = CGFloat(rng.next() % 1000) / 1000 * size.width
                let y = CGFloat(rng.next() % 1000) / 1000 * min(size.height, height)
                let r = CGFloat(rng.next() % 100) / 100 * 1.1 + 0.4
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.35 + Double(rng.next() % 50) / 100)))
            }
        }
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - The lit house: each window pane of the finished house, found once and cached

/// The finished house's window panes (34 in bp_house_k18_finished_built), each a small mask placed
/// by a unit rect. Ordered ground floor first, left to right, so lighting reads bottom-up.
enum PorchWindows {
    static let houseImage = HouseKeyframe.k18_finished.builtImageName

    struct Pane: Identifiable {
        let id: Int
        let unit: CGRect
        let mask: UIImage
    }

    private static var cached: [Pane]?

    static var panes: [Pane] {
        if let cached { return cached }
        let found = extract()
        cached = found
        return found
    }

    private static func extract() -> [Pane] {
        guard let mask = StdWindowGlow.mask(for: houseImage)?.cgImage else { return [] }
        let w = mask.width, h = mask.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        var seen = [Bool](repeating: false, count: w * h)
        var comps: [[Int]] = []
        for start in 0..<(w * h) where px[start * 4 + 3] > 128 && !seen[start] {
            var stack = [start]; seen[start] = true; var pts: [Int] = []
            while let p = stack.popLast() {
                pts.append(p)
                let x = p % w, y = p / w
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let n = ny * w + nx
                    if !seen[n] && px[n * 4 + 3] > 128 { seen[n] = true; stack.append(n) }
                }
            }
            if pts.count >= 40 { comps.append(pts) }
        }
        var panes: [(CGRect, UIImage)] = []
        for pts in comps {
            var minX = w, minY = h, maxX = 0, maxY = 0
            for p in pts { let x = p % w, y = p / w; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            let cw = maxX - minX + 1, ch = maxY - minY + 1
            var cpx = [UInt8](repeating: 0, count: cw * ch * 4)
            for p in pts {
                let x = p % w - minX, y = p / w - minY
                let i = (y * cw + x) * 4
                cpx[i] = 255; cpx[i + 1] = 255; cpx[i + 2] = 255; cpx[i + 3] = 255
            }
            guard let cctx = CGContext(data: &cpx, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let img = cctx.makeImage() else { continue }
            // Bitmap memory runs top-down (row 0 = the image's top), as StdWindowGlow relies on.
            let unit = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                              width: CGFloat(cw) / CGFloat(w), height: CGFloat(ch) / CGFloat(h))
            panes.append((unit, UIImage(cgImage: img, scale: 1, orientation: .up)))
        }
        // Ground floor first (larger y), then left to right.
        let sorted = panes.sorted { a, b in
            let fa = a.0.midY > 0.6 ? 0 : 1, fb = b.0.midY > 0.6 ? 0 : 1
            return fa != fb ? fa < fb : a.0.minX < b.0.minX
        }
        return sorted.enumerated().map { Pane(id: $0.offset, unit: $0.element.0, mask: $0.element.1) }
    }
}

/// The finished house, lit from within: `lit` panes glow warm, the rest are dark glass. Each pane
/// fades in (easeOut 0.60, staggered 60ms by the caller's lit count) when it turns on.
struct PorchHouse: View {
    let lit: Int
    var intensity: Double = 1
    let sky: PorchSky
    var porchLight = false
    var size: CGFloat = 180
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let panes = PorchWindows.panes
        ZStack(alignment: .topLeading) {
            Image(decorative: PorchWindows.houseImage).resizable().interpolation(.high).scaledToFit()
                .brightness(sky.houseBrightness)
                .saturation(sky == .night ? 0.75 : 1)
                .frame(width: size, height: size)
            ForEach(panes) { pane in
                let on = pane.id < lit
                ZStack {
                    Image(uiImage: pane.mask).renderingMode(.template).resizable()
                        .foregroundStyle(PorchColors.hex(0x2B2740, 0.92))
                    Image(uiImage: pane.mask).renderingMode(.template).resizable()
                        .foregroundStyle(PorchColors.hex(0xFFE7A6))
                        .opacity(on ? 1 : 0)
                    Image(uiImage: pane.mask).renderingMode(.template).resizable()
                        .foregroundStyle(PorchColors.hex(0xFFC060))
                        .blur(radius: 3)
                        .opacity(on ? 0.75 + 0.25 * intensity : 0)
                        .blendMode(.plusLighter)
                }
                .frame(width: pane.unit.width * size, height: pane.unit.height * size)
                .offset(x: pane.unit.minX * size, y: pane.unit.minY * size)
                .animation(reduceMotion ? .easeOut(duration: 0.30) : .easeOut(duration: 0.60).delay(Double(max(0, pane.id - (lit - 4))) * 0.06), value: on)
            }
            // Porch light (stage advance): glow radius 0 → 48pt, easeOut 0.60.
            Circle()
                .fill(RadialGradient(colors: [PorchColors.hex(0xFFD58A, 0.95), PorchColors.hex(0xE8A33D, 0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 48 / 180))
                .frame(width: size * 96 / 180, height: size * 96 / 180)
                .scaleEffect(porchLight ? 1 : 0.2)
                .opacity(porchLight ? 1 : 0)
                .blendMode(.plusLighter)
                .offset(x: size * 0.565 - size * 48 / 180, y: size * 0.585 - size * 48 / 180)
                .animation(.easeOut(duration: 0.60), value: porchLight)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - The seed, as Porch Light reads it

struct PorchFocus: Equatable {
    let id: String
    let name: String
    let hours: Double
    /// nil = record only, no target.
    let target: Int?
    let rentalIDs: [String]
}

enum PorchPace: Equatable {
    case behind(gap: Int, weekly: Int)
    case ahead(by: Int)
    case reached
    case record
}

enum PorchYear {
    /// Fri Oct 23, 2026 is "today" for every seed.
    static let dayOfYear = 296.0
    static let fraction = dayOfYear / 365
    static let daysLeft = 69.0
}

extension PorchFocus {
    var progress: Double { target.map { min(hours / Double($0), 1) } ?? min(hours / 100, 1) }

    var pace: PorchPace {
        guard let target else { return .record }
        if hours >= Double(target) { return .reached }
        let expected = Double(target) * PorchYear.fraction
        if hours + 0.5 < expected {
            let weekly = Int(((Double(target) - hours) / (PorchYear.daysLeft / 7)).rounded(.up))
            return .behind(gap: Int((expected - hours).rounded()), weekly: weekly)
        }
        return .ahead(by: Int((hours - expected).rounded()))
    }

    /// Lit panes: a pane per 1/34 of the goal (record-only rentals: of 100h).
    func litPanes(_ total: Int) -> Int {
        guard hours > 0 else { return 0 }
        return max(1, Int((progress * Double(total)).rounded()))
    }

    /// Cumulative hours from Jan 1 to today, as fractions (0…1 of the year, 0…1 of `hours`).
    /// Seeded by the rental id so each rental keeps its own shape: a slow start, a busy summer.
    var curve: [(t: Double, v: Double)] {
        var rng = SplitMix(seed: UInt64(abs(id.hashValue % 9973)) + 11)
        _ = rng.next()
        var raw: [Double] = [0]
        let months = 10
        for m in 0..<months {
            let base = [0.4, 0.5, 0.8, 0.9, 1.2, 1.4, 1.5, 1.3, 1.1, 0.9][m]
            let jitter = 0.6 + Double(rng.next() % 80) / 100
            raw.append(raw.last! + base * jitter)
        }
        let total = raw.last ?? 1
        return raw.enumerated().map { i, v in (PorchYear.fraction * Double(i) / Double(months), v / total) }
    }
}

struct PorchSeed {
    let std: StdSeed
    var focuses: [PorchFocus] {
        let r = std.rentals
        var out: [PorchFocus] = []
        if let shared = r.sharedTarget {
            out.append(PorchFocus(id: "all", name: P("All rentals"), hours: r.totalHours, target: shared, rentalIDs: r.rentals.map(\.id)))
        }
        for rental in r.rentals {
            let target: Int?
            switch rental.target {
            case .own(let t): target = t
            case .counts: target = r.sharedTarget
            case .record: target = nil
            }
            out.append(PorchFocus(id: rental.id, name: rental.name, hours: rental.hours, target: target, rentalIDs: [rental.id]))
        }
        return out
    }
}

// MARK: - Haptics (Core Haptics for the two rare moments)

@MainActor
final class PorchHaptics {
    static let shared = PorchHaptics()
    private var engine: CHHapticEngine?

    private func ready() -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if engine == nil { engine = try? CHHapticEngine(); try? engine?.start() }
        return engine
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine = ready(), let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    /// Stage advance: a soft transient, then 0.4s of warm continuous at 0.3.
    func stage() {
        PorchHapticLog.mark("stage: soft transient + 0.4s continuous 0.3")
        play([
            CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 0.5), .init(parameterID: .hapticSharpness, value: 0.2)], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 0.3), .init(parameterID: .hapticSharpness, value: 0.1)], relativeTime: 0.05, duration: 0.4),
        ])
    }

    /// Goal reached: a rising swell, then a final soft tap.
    func goal() {
        PorchHapticLog.mark("goal: rising swell 0.1–0.6s + soft tap 0.65s")
        var events: [CHHapticEvent] = []
        for i in 0..<6 {
            let t = 0.1 + Double(i) * 0.09
            events.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [.init(parameterID: .hapticIntensity, value: Float(0.25 + 0.1 * Double(i))), .init(parameterID: .hapticSharpness, value: 0.15)],
                                        relativeTime: t, duration: 0.09))
        }
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 0.6), .init(parameterID: .hapticSharpness, value: 0.25)], relativeTime: 0.65))
        play(events)
    }
}

/// Prints each haptic with its time when -LHStdMotionLog is set (the videos can't carry haptics).
enum PorchHapticLog {
    static let start = Date()
    static func mark(_ what: String) {
        guard ProcessInfo.processInfo.arguments.contains("-LHStdMotionLog") else { return }
        print(String(format: "[haptic %.2fs] %@", Date().timeIntervalSince(start), what))
    }
}

// MARK: - Small shared pieces

/// "2h", "30m", "1h 30m".
func porchHours(_ v: Double?) -> String { StdFormat.hours(v) }

struct PorchPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// `.primary`: 52pt capsule, action fill.
struct PorchPrimary: ButtonStyle {
    /// On the sky the violet capsule's edge measured 1.4:1 against day blue; there it is a white
    /// capsule with action ink instead (edge ≥ 4.5:1, label 7.1:1).
    var onSky = false
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let c = PorchColors(scheme)
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(onSky ? PorchColors.hex(0x5B4C86) : c.onAction)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(onSky ? PorchColors.hex(0xFFF9F0) : c.action))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Glass over the sky (controls over content, §2.13): iOS 26 glass, earlier a material capsule.
/// A 30% dim under the glass keeps white text ≥ 4.5:1 over every sky (measured in the frames).
struct PorchSkyGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(Capsule().fill(Color.black.opacity(0.30)))
                .glassEffect(.clear, in: .capsule)
        } else {
            content.background(Capsule().fill(.ultraThinMaterial)).background(Capsule().fill(Color.black.opacity(0.30)))
        }
    }
}

/// Day header, section headers: sentence case `.subheadline.semibold` (§2.3: no mono eyebrows).
struct PorchSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var onTrailing: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let c = PorchColors(scheme)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if let trailing {
                Button(trailing, action: onTrailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(c.action)
                    .frame(minHeight: 44)
                    .buttonStyle(PorchPress())
            }
        }
        .frame(minHeight: 28)
    }
}
#endif
