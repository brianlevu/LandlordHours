import SwiftUI
import WidgetKit

// MARK: - 2.0 widget views (blueprint style)
//
// Approved design: sandbox-surfaces 92e1bc8 (DesignSandbox/Surfaces/SFWidgets.swift), frames
// ~/AgentScratch/landlordhours/2026-10-19/surfaces-frames-r2. The Home Screen widgets are the Today
// hero in miniature: theme-fixed blueprint paper, the house at its real stage, the SF Rounded
// number and an SF Mono label. Lock Screen accessories are vibrant (the system tints them), so
// they draw in one colour. Every colour comes from BrandHex (Sources/Shared/BrandPalette.swift).
//
// These views are compiled into the widget extension and, for DEBUG capture boards only, into the
// app (WidgetCaptureBoard). They take a `WidgetSurfaceDisplay` and nothing else.

/// How the system is drawing the widget.
enum WidgetLook: Equatable {
    /// Full colour (the default Home Screen).
    case fullColor
    /// iOS tinted / clear Home Screen: the system removes our background and tints the content.
    case accented
}

/// On-blueprint colours (theme-fixed: the widget is blueprint paper in light and dark).
enum WidgetInk {
    static let brand = Color(brandHex: BrandHex.brand)
    static let brandDeep = Color(brandHex: BrandHex.blueprintDeep)
    static let primary = Color.white
    static let secondary = Color(brandHex: BrandHex.onHeroSecondary)
    static let drafting = Color(brandHex: BrandHex.drafting)
    static let positive = Color(brandHex: BrandHex.positiveOnHero)
    static let caution = Color(brandHex: BrandHex.cautionOnHero)

    static func tone(_ tone: WidgetSurfaceDisplay.Tone) -> Color {
        switch tone {
        case .caution: return caution
        case .positive: return positive
        case .neutral: return secondary
        case .drafting: return drafting
        }
    }
}

/// Blueprint paper with the faint drafting grid (the hero's surface).
struct WidgetBlueprintPaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [WidgetInk.brand, WidgetInk.brandDeep], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let step: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                context.stroke(path, with: .color(WidgetInk.drafting.opacity(0.07)), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The house at the snapshot's keyframe (pre-composited in WidgetAssets.xcassets).
struct WidgetHouse: View {
    let keyframe: String
    var body: some View {
        Image(decorative: "wg_house_\(keyframe)")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}

/// When `frozenNow` is set (captures), the timer draws a fixed "0:42"; otherwise it ticks.
private struct WidgetFrozenNowKey: EnvironmentKey { static let defaultValue: Date? = nil }
/// True only on the DEBUG capture board, which has no WidgetKit host to draw accessory backgrounds.
private struct WidgetHarnessKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var widgetFrozenNow: Date? {
        get { self[WidgetFrozenNowKey.self] }
        set { self[WidgetFrozenNowKey.self] = newValue }
    }
    var widgetHarness: Bool {
        get { self[WidgetHarnessKey.self] }
        set { self[WidgetHarnessKey.self] = newValue }
    }
}

/// The timer's elapsed time: live in the widget, fixed in captures.
struct WidgetElapsedText: View {
    let start: Date
    @Environment(\.widgetFrozenNow) private var frozenNow

    var body: some View {
        if let frozenNow {
            Text(WidgetSurfaceDisplay.elapsedText(from: start, to: frozenNow))
        } else {
            Text(start, style: .timer)
        }
    }
}

private extension Text {
    /// SF Mono drafting label: caps, +12% tracking.
    func draftingLabel(_ color: Color, size: CGFloat = 10) -> some View {
        self.font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(size * 0.12)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    func heroNumber(_ size: CGFloat) -> Text {
        self.font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
    }
}

// MARK: - Home Screen

struct WidgetSmallView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor

    private var isNoProperty: Bool { display.state == .noProperty }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let house = side * (isNoProperty ? 0.52 : 0.57)
            ZStack(alignment: .topLeading) {
                houseArt
                    .frame(width: house, height: house)
                    .position(x: geo.size.width - house / 2 - 2,
                              y: isNoProperty ? 12 + house / 2 : side * 0.25 + house / 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(display.smallLabel).draftingLabel(labelColor)
                    content
                }
                .padding(14)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        switch display.state {
        case .noProperty:
            Spacer(minLength: 0)
            Text("Add a rental to start counting.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetInk.primary)
                .lineLimit(3)
                .frame(maxWidth: 120, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        case .timer:
            if let start = display.snapshot.timerStart {
                WidgetElapsedText(start: start)
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(WidgetInk.primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            if let s = display.status { statusLine(s) }
        default:
            Text(display.number)
                .heroNumber(36)
                .foregroundStyle(WidgetInk.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top, 4)
                .widgetAccentable()
            Text(display.goalText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondary)
            Spacer(minLength: 0)
            if let s = display.status { statusLine(s) }
        }
    }

    private func statusLine(_ s: WidgetSurfaceDisplay.Status) -> some View {
        // Two lines allowed: "Nothing confirmed yet" doesn't fit one line of a small widget.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: s.symbol).font(.system(size: 11, weight: .bold))
            Text(s.text).lineLimit(2).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(look == .accented ? WidgetInk.primary : WidgetInk.tone(s.tone))
    }

    @ViewBuilder private var houseArt: some View {
        if look == .accented {
            LHMarkShape().fill(WidgetInk.primary.opacity(0.9)).padding(18).offset(y: 6).widgetAccentable()
        } else {
            WidgetHouse(keyframe: display.snapshot.houseKeyframe).opacity(display.state == .timer ? 0.55 : 1)
        }
    }

    private var secondary: Color { look == .accented ? WidgetInk.primary.opacity(0.7) : WidgetInk.secondary }
    private var labelColor: Color { look == .accented ? WidgetInk.primary.opacity(0.7) : WidgetInk.drafting }
}

struct WidgetMediumView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor

    var body: some View {
        GeometryReader { geo in
            let house = geo.size.height * 0.975
            ZStack(alignment: .topLeading) {
                houseArt
                    .frame(width: house, height: house)
                    .position(x: geo.size.width - house / 2 - 2, y: geo.size.height / 2 + 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(display.mediumLabel).draftingLabel(labelColor)
                    content
                }
                .padding(16)
                .frame(width: geo.size.width * 0.56, height: geo.size.height, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if display.state == .noProperty {
            Text("Add a rental to start counting.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetInk.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 0)
            if let pill = display.pill { pillView(pill) }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if display.state == .timer, let start = display.snapshot.timerStart {
                    WidgetElapsedText(start: start)
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(WidgetInk.primary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(display.timerPropertyName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                } else {
                    Text(display.number).heroNumber(40).foregroundStyle(WidgetInk.primary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text(display.goalText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
            if let s = statusForMedium {
                HStack(spacing: 4) {
                    Image(systemName: s.symbol).font(.system(size: 11, weight: .bold))
                    Text(s.text).lineLimit(1).minimumScaleFactor(0.8)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(look == .accented ? WidgetInk.primary : WidgetInk.tone(s.tone))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if let pill = display.pill {
                pillView(pill)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.stageLine.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetInk.primary)
                    Text(display.stageLine.next)
                        .font(.system(size: 12))
                        .foregroundStyle(secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }

    /// The timer's status line says "Timer running" (the property is beside the number).
    private var statusForMedium: WidgetSurfaceDisplay.Status? {
        if display.state == .timer { return .init(symbol: "timer", text: "Timer running", tone: .drafting) }
        return display.status
    }

    /// The one tappable thing: a white pill on blueprint (a Link, so it opens its own place).
    private func pillView(_ pill: WidgetSurfaceDisplay.Pill) -> some View {
        Link(destination: pill.url) {
            HStack(spacing: 5) {
                Image(systemName: pill.symbol).font(.system(size: 11, weight: .bold))
                Text(pill.text).lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(look == .accented ? WidgetInk.primary : WidgetInk.brand)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(Capsule().fill(look == .accented ? WidgetInk.primary.opacity(0.18) : WidgetInk.primary))
        }
        .widgetAccentable()
    }

    @ViewBuilder private var houseArt: some View {
        if look == .accented {
            LHMarkShape().fill(WidgetInk.primary.opacity(0.9)).padding(30).widgetAccentable()
        } else {
            WidgetHouse(keyframe: display.snapshot.houseKeyframe).opacity(display.state == .timer ? 0.55 : 1)
        }
    }

    private var secondary: Color { look == .accented ? WidgetInk.primary.opacity(0.7) : WidgetInk.secondary }
    private var labelColor: Color { look == .accented ? WidgetInk.primary.opacity(0.7) : WidgetInk.drafting }
}

// MARK: - Lock Screen (vibrant: one colour, the system tints it)

/// The accessory's circle backing: the system's in a widget, a stand-in on the capture board.
struct WidgetAccessoryBacking: View {
    @Environment(\.widgetHarness) private var harness
    var body: some View {
        if harness {
            Circle().fill(Color.black.opacity(0.22))
        } else {
            AccessoryWidgetBackground()
        }
    }
}

struct WidgetCircularHoursView: View {
    let display: WidgetSurfaceDisplay

    var body: some View {
        ZStack {
            WidgetAccessoryBacking()
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 5).padding(6)
            Circle()
                .trim(from: 0, to: display.state == .noProperty ? 0 : display.progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
                .widgetAccentable()
            VStack(spacing: 0) {
                face
                LHMarkShape().fill(Color.white).frame(width: 15, height: 15)
            }
            .foregroundStyle(Color.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.hoursFace.accessibilityLabel)
    }

    @ViewBuilder private var face: some View {
        let f = display.hoursFace
        if display.state == .timer, let start = display.snapshot.timerStart {
            WidgetElapsedText(start: start)
                .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: 52)
        } else if let symbol = f.symbol {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold))
        } else {
            Text(f.text).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: 52)
        }
    }
}

struct WidgetCircularPendingView: View {
    let display: WidgetSurfaceDisplay

    var body: some View {
        let f = display.pendingFace
        ZStack {
            WidgetAccessoryBacking()
            VStack(spacing: 1) {
                if let symbol = f.symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(f.text)
                    .font(.system(size: f.isLarge ? 22 : 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color.white)
            .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(f.accessibilityLabel)
    }
}

struct WidgetRectangularView: View {
    let display: WidgetSurfaceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                LHMarkShape().fill(Color.white).frame(width: 14, height: 14)
                Text(display.rectangularTitle).font(.system(size: 13, weight: .semibold))
            }
            .widgetAccentable()
            headline
                .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(display.rectangularLine)
                .font(.system(size: 13))
                .opacity(0.9)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var headline: some View {
        if display.state == .timer, let start = display.snapshot.timerStart {
            HStack(spacing: 0) {
                WidgetElapsedText(start: start)
                Text(" · \(display.timerPropertyName)")
            }
        } else {
            Text(display.rectangularHeadline(elapsed: ""))
        }
    }
}

struct WidgetInlineView: View {
    let display: WidgetSurfaceDisplay
    @Environment(\.widgetFrozenNow) private var frozenNow

    var body: some View {
        // Inline widgets draw one Text + one image; a live timer would need its own Text, so the
        // timer shows the minutes at the last refresh (the timeline refreshes every minute while it runs).
        let elapsed = display.snapshot.timerStart.map { WidgetSurfaceDisplay.elapsedText(from: $0, to: frozenNow ?? Date()) } ?? ""
        Label(display.inlineText(elapsed: elapsed), systemImage: display.inlineSymbol)
    }
}
