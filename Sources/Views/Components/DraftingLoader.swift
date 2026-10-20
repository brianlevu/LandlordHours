import SwiftUI

// MARK: - Progressive loading (WP-L)
//
// The app never blocks on loading. The screen renders at once from local data; only the part
// that waits on data shows a placeholder:
// - `PlaceholderBar` stands in for a number (a soft rounded bar).
// - `DraftingLoader` stands in for a picture: the Blueprint drafting line sketching the coming
//   shape (the house, a chart line, a report page) in a gentle loop, until the data lands and the
//   caller crossfades to the real thing.
// No spinners, no full-screen skeletons.

/// What the drafting line sketches. Each shape is drawn in a unit square and scaled to fit.
enum DraftingSketch: Equatable, Sendable {
    /// The Blueprint house silhouette (traced from the house linework, same 320 pt camera as
    /// `HouseArtView`), with the real linework revealed faintly behind the pen.
    case house
    /// A sparkline, for charts.
    case chart
    /// A report page: outline, folded corner, text lines and a small bar chart.
    case document
}

/// The surface the line sits on. It picks the drafting tint (brand tokens).
enum DraftingSurface: Equatable, Sendable {
    /// The theme-fixed blueprint hero: #8FD3FF in light and dark.
    case blueprint
    /// A light/dark page or card: #2369B5 in light, #60A8E6 in dark.
    case adaptive

    func lineHex(for scheme: ColorScheme) -> String {
        switch self {
        case .blueprint: return HouseTokens.Hex.drafting
        case .adaptive: return scheme == .dark ? HouseTokens.Hex.darkDrafting : HouseTokens.Hex.draftingInk
        }
    }

    func line(for scheme: ColorScheme) -> Color { Color(hex: lineHex(for: scheme)) }

    /// Fill for `PlaceholderBar`: a soft tint of the surface, never a grey slab.
    func placeholderFill(for scheme: ColorScheme) -> Color {
        switch self {
        case .blueprint: return Color.white.opacity(0.16)
        case .adaptive: return scheme == .dark ? Color.white.opacity(0.10) : Color(hex: HouseTokens.Hex.draftingInk).opacity(0.09)
        }
    }
}

/// The loop's timing. Pure so tests (and captures) can sample it.
enum DraftingLoaderTiming {
    /// One loop: the pen draws the shape, the line holds a beat, the tail lifts away, a rest.
    static let cycle: Double = 2.8
    static let drawEnd: Double = 1.55
    static let holdEnd: Double = 1.85
    static let eraseEnd: Double = 2.55

    /// The visible span of the line at `time` seconds into the loop: (from, to) in 0...1.
    static func trim(at time: Double) -> (from: CGFloat, to: CGFloat) {
        let t = time.truncatingRemainder(dividingBy: cycle)
        if t < drawEnd {
            return (0, CGFloat(easeInOut(t / drawEnd)))
        } else if t < holdEnd {
            return (0, 1)
        } else if t < eraseEnd {
            return (CGFloat(easeIn((t - holdEnd) / (eraseEnd - holdEnd))), 1)
        }
        return (1, 1)
    }

    /// Reduce Motion: no drawing, only a slow opacity breath between 0.55 and 0.9.
    static func pulse(at time: Double) -> Double {
        let phase = (time.truncatingRemainder(dividingBy: 2.4)) / 2.4
        return 0.725 + 0.175 * sin(phase * 2 * .pi)
    }

    private static func easeInOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    private static func easeIn(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x * x
    }
}

/// The sketching drafting line, sized to its container (keeps the sketch's aspect ratio).
///
/// Accessibility: one element, "Loading" plus what is loading (e.g. "Loading your hours"). It
/// never announces progress on its own, so VoiceOver does not chatter while it loops.
/// Reduce Motion: the full sketch, static, with a slow opacity breath.
struct DraftingLoader: View {
    var sketch: DraftingSketch = .house
    var surface: DraftingSurface = .adaptive
    /// What is loading, read after "Loading" ("your hours" → "Loading your hours").
    var subject: String? = nil
    var lineWidth: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = surface.line(for: colorScheme)
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if sketch == .house {
                    // The real linework, faint, rising with the pen: the shape of what's coming.
                    HouseLineworkImage(name: "bp_house_k00_lot_lines")
                        .foregroundStyle(tint)
                        .opacity(reduceMotion ? 0.22 : 0.26)
                        .mask {
                            HouseRisingMask(progress: reduceMotion ? 1 : DraftingLoaderTiming.trim(at: time).to * (1 - DraftingLoaderTiming.trim(at: time).from))
                        }
                }
                DraftingSketchShape(sketch: sketch)
                    .stroke(tint.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if reduceMotion {
                    DraftingSketchShape(sketch: sketch)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .opacity(DraftingLoaderTiming.pulse(at: time))
                } else {
                    let span = DraftingLoaderTiming.trim(at: time)
                    DraftingSketchShape(sketch: sketch)
                        .trim(from: span.from, to: span.to)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .shadow(color: tint.opacity(0.55), radius: 3)
                }
            }
        }
        .aspectRatio(DraftingSketchShape.aspectRatio(for: sketch), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subject.map { "Loading \($0)" } ?? "Loading")
        .accessibilityIdentifier("drafting.loader")
    }
}

/// The paths the drafting line follows, in a unit rect scaled to the view.
struct DraftingSketchShape: Shape {
    var sketch: DraftingSketch

    static func aspectRatio(for sketch: DraftingSketch) -> CGFloat {
        switch sketch {
        case .house: return 1
        case .chart: return 2.6
        case .document: return 0.78
        }
    }

    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        switch sketch {
        case .house:
            // Silhouette traced from bp_house_k00_lot_lines (the full house), then the front
            // corner and eave so the pen reads as a house, not a blob.
            let outline = Self.houseOutline
            path.move(to: point(outline[0].0, outline[0].1))
            for p in outline.dropFirst() { path.addLine(to: point(p.0, p.1)) }
            path.closeSubpath()
            path.move(to: point(0.1672, 0.4234))
            path.addLine(to: point(0.4203, 0.5250))
            path.addLine(to: point(0.4266, 0.2406))
            path.move(to: point(0.4203, 0.5250))
            path.addLine(to: point(0.4047, 0.7953))
            path.move(to: point(0.4203, 0.5250))
            path.addLine(to: point(0.6891, 0.3922))
        case .chart:
            let values: [CGFloat] = [0.62, 0.70, 0.55, 0.66, 0.48, 0.58, 0.40, 0.52, 0.36, 0.30, 0.42, 0.24, 0.30, 0.16, 0.22, 0.10]
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) / CGFloat(values.count - 1)
                let p = point(x, v * 0.9 + 0.05)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        case .document:
            path.move(to: point(0.08, 0.04))
            path.addLine(to: point(0.70, 0.04))
            path.addLine(to: point(0.92, 0.20))
            path.addLine(to: point(0.92, 0.96))
            path.addLine(to: point(0.08, 0.96))
            path.closeSubpath()
            path.move(to: point(0.70, 0.04))
            path.addLine(to: point(0.70, 0.20))
            path.addLine(to: point(0.92, 0.20))
            for (i, width) in [0.46, 0.66, 0.58, 0.66].enumerated() {
                let y = 0.18 + CGFloat(i) * 0.09
                path.move(to: point(0.18, y))
                path.addLine(to: point(0.18 + width * 0.82 - (i == 0 ? 0.1 : 0), y))
            }
            path.move(to: point(0.18, 0.86))
            path.addLine(to: point(0.82, 0.86))
            for (i, h) in [0.10, 0.18, 0.14, 0.24].enumerated() {
                let x = 0.26 + CGFloat(i) * 0.15
                path.move(to: point(x, 0.86))
                path.addLine(to: point(x, 0.86 - h))
            }
        }
        return path
    }

    static let houseOutline: [(CGFloat, CGFloat)] = [
        (0.1453, 0.3906), (0.2391, 0.2422), (0.2422, 0.2188), (0.2578, 0.2109), (0.2766, 0.1781),
        (0.4266, 0.2406), (0.5766, 0.1734), (0.5859, 0.2141), (0.6328, 0.2891), (0.6453, 0.2938),
        (0.6484, 0.3672), (0.6891, 0.3922), (0.6922, 0.4984), (0.7484, 0.5359), (0.7484, 0.5578),
        (0.7391, 0.7172), (0.5891, 0.7734), (0.5234, 0.7516), (0.4047, 0.7953), (0.1703, 0.6703),
        (0.1672, 0.4234), (0.1453, 0.4078),
    ]
}

/// A soft rounded bar that stands in for a number until it is final. Breathes gently (opacity
/// only, so it is fine under Reduce Motion). Decorative: the container says what is loading.
struct PlaceholderBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var surface: DraftingSurface = .adaptive

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let breath = 0.82 + 0.18 * DraftingLoaderTiming.pulse(at: context.date.timeIntervalSinceReferenceDate)
            RoundedRectangle(cornerRadius: min(height / 2, 10), style: .continuous)
                .fill(surface.placeholderFill(for: colorScheme))
                .opacity(breath)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

#Preview("Drafting loaders") {
    VStack(spacing: 24) {
        ZStack {
            HouseBlueprintPaper()
            DraftingLoader(sketch: .house, surface: .blueprint, subject: "your hours").padding(24)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        HStack(spacing: 24) {
            DraftingLoader(sketch: .chart).frame(height: 80)
            DraftingLoader(sketch: .document).frame(height: 120)
        }
        PlaceholderBar(width: 120, height: 40)
    }
    .padding()
}
