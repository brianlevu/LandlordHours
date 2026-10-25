import SwiftUI
import UIKit

#if DEBUG && !WIDGET_EXTENSION
// MARK: - DEBUG widget frames (compiled out of Release and out of the extension)
//
//   -LHSurfaceBoard widget-export -LHWidgetOut <dir>     writes every widget frame as a PNG at 3x
//   -LHSurfaceBoard widget-<family>-<state> [-LHColorScheme dark] [-LHTypeSize xxl|ax3]
//                                                       shows one frame on screen
//
// WidgetKit cannot be hosted in an app, so these draw the PRODUCTION views (WidgetSurfaceViews.swift)
// at the sizes the system gives them and snapshot them through a real window with the appearance
// and Dynamic Type trait set (so the asset catalog's Dark variants and `@ScaledMetric` resolve as
// they do in the extension). The Lock Screen accessory backing is a stand-in (`widgetHarness`).
// Tinted frames sit on a flat mock wallpaper; the system supplies the real tint and material.

enum WidgetFrameFamily: String, CaseIterable {
    case small, medium, large, extraLarge, extraLargePortrait
    case circular, pendingCircular, rectangular, inline

    /// Sizes the system gives on an iPhone 17 Pro (small, medium, large) and an iPad 10th gen
    /// (extra large). `extraLargePortrait` is an assumed size: the iOS 27 SDK documents none.
    var size: CGSize {
        switch self {
        case .small: return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large: return CGSize(width: 364, height: 382)
        case .extraLarge: return CGSize(width: 715, height: 342)
        case .extraLargePortrait: return CGSize(width: 342, height: 715)
        case .circular, .pendingCircular: return CGSize(width: 72, height: 72)
        case .rectangular: return CGSize(width: 160, height: 72)
        case .inline: return CGSize(width: 257, height: 26)
        }
    }

    var hasHousePage: Bool { [.medium, .large, .extraLarge, .extraLargePortrait].contains(self) }
    var isAccessory: Bool { [.circular, .pendingCircular, .rectangular, .inline].contains(self) }
}

enum WidgetSamples {
    static let now = Date(timeIntervalSince1970: 1_792_400_000)

    private static func figure(_ name: String, hours: Double, goal: Double = 750, lit: Bool, behindBy: Double = 0) -> WidgetRentalFigure {
        WidgetRentalFigure(id: name, name: name, hours: hours,
                           stage: stage(hours, goal), lit: lit, behindBy: behindBy)
    }

    /// The five stages by share of the goal, as `CraftStage.stage(hours:goal:)` (the widget never imports it).
    static func stage(_ hours: Double, _ goal: Double) -> String {
        let share = hours / max(goal, 1)
        if share < 0.20 { return "craft_started" }
        if share < 0.47 { return "craft_frame70" }
        if share < 0.60 { return "craft_framing" }
        if share < 1.0 { return "craft_half" }
        return "craft_complete"
    }

    static let rows: [WidgetConfirmRow] = [
        WidgetConfirmRow(key: "a", title: "Plumber visit", rentalName: "Pine Cabin", hours: 2),
        WidgetConfirmRow(key: "b", title: "Tenant walkthrough", rentalName: "Pine Cabin", hours: 1.5),
        WidgetConfirmRow(key: "c", title: "Open house", rentalName: nil, hours: nil, canConfirm: false),
        WidgetConfirmRow(key: "d", title: "Hardware store run", rentalName: "Maple Street", hours: 1),
        WidgetConfirmRow(key: "e", title: "Roof inspection", rentalName: "Maple Street", hours: 3),
    ]

    static func snapshot(
        rentals: [WidgetRentalFigure], hours: Double, goal: Double = 750, required: Double = 600, pending: Int,
        loggedToday: Bool, paceReady: Bool = true, timer: Bool = false, record: Bool = false
    ) -> WidgetSurfaceSnapshot {
        WidgetSurfaceSnapshot(
            updatedAt: now, taxYear: 2026, propertyCount: rentals.count, hours: hours, goal: .reps750, goalHours: goal,
            requiredHoursToDate: required, pendingCount: pending,
            timerStart: timer ? now.addingTimeInterval(-42 * 60) : nil, timerPropertyName: timer ? "Pine Cabin" : nil,
            houseKeyframe: "", stageTitle: rentals.count == 1 ? stageTitle(rentals[0].stage) : "", nextStepLabel: "",
            houseStage: rentals.first?.stage ?? "craft_started", loggedToday: loggedToday, paceReady: paceReady,
            isRecord: record, rentals: rentals, confirmRows: Array(rows.prefix(pending))
        )
    }

    private static func stageTitle(_ stage: String) -> String {
        switch stage {
        case "craft_started": return "Framing started"
        case "craft_frame70": return "Frame going up"
        case "craft_framing": return "Frame finished"
        case "craft_half": return "Roof on, siding going up"
        default: return "House finished"
        }
    }

    // One rental, 212 of 750 hours, behind.
    static let behindLit = snapshot(rentals: [figure("Pine Cabin", hours: 212, lit: true, behindBy: 388)], hours: 212, pending: 3, loggedToday: true)
    static let behindUnlit = snapshot(rentals: [figure("Pine Cabin", hours: 212, lit: false, behindBy: 388)], hours: 212, pending: 3, loggedToday: false)
    static let onPace = snapshot(rentals: [figure("Pine Cabin", hours: 640, lit: false)], hours: 640, pending: 0, loggedToday: false)
    static let met = snapshot(rentals: [figure("Pine Cabin", hours: 768, lit: true)], hours: 768, required: 700, pending: 1, loggedToday: true)
    static let empty = snapshot(rentals: [figure("Pine Cabin", hours: 0, lit: false)], hours: 0, required: 300, pending: 0, loggedToday: false)
    static let paceNotReady = snapshot(rentals: [figure("Pine Cabin", hours: 6, lit: true)], hours: 6, required: 40, pending: 0, loggedToday: true, paceReady: false)
    static let noProperty = snapshot(rentals: [], hours: 0, required: 0, pending: 0, loggedToday: false)
    static let timer = snapshot(rentals: [figure("Pine Cabin", hours: 212, lit: true, behindBy: 388)], hours: 212, pending: 3, loggedToday: true, timer: true)
    /// Three rentals: 312 hours across them, 2 behind their own pace.
    static let allThree = snapshot(
        rentals: [figure("Pine Cabin", hours: 212, lit: true, behindBy: 388), figure("Maple Street", hours: 74, lit: false, behindBy: 526),
                  figure("Lakeview", hours: 26, lit: false, behindBy: 574)],
        hours: 312, pending: 5, loggedToday: true)
    static let allOnPace = snapshot(
        rentals: [figure("Pine Cabin", hours: 640, lit: true), figure("Maple Street", hours: 610, lit: true)], hours: 1250, pending: 0, loggedToday: true)
    /// Eight rentals: the skyline shows the most behind, the number says all eight.
    static let allEight: WidgetSurfaceSnapshot = {
        var figures: [WidgetRentalFigure] = []
        for n in 1...8 {
            let hours = Double(n) * 30
            figures.append(figure("Rental \(n)", hours: hours, lit: n % 3 == 0, behindBy: 600 - hours))
        }
        return snapshot(rentals: figures, hours: 1080, pending: 5, loggedToday: true)
    }()

    static let all: [(name: String, snapshot: WidgetSurfaceSnapshot)] = [
        ("behind-lit", behindLit), ("behind-unlit", behindUnlit), ("on-pace", onPace), ("goal-met", met), ("empty", empty),
        ("pace-not-ready", paceNotReady), ("no-rental", noProperty), ("timer", timer), ("three-rentals", allThree),
        ("all-on-pace", allOnPace), ("eight-rentals", allEight),
    ]
}

/// One widget frame: the production view on the page the system draws behind it.
struct WidgetFrameView: View {
    let family: WidgetFrameFamily
    let snapshot: WidgetSurfaceSnapshot
    var look: WidgetLook = .fullColor
    var scheme: ColorScheme = .light

    var body: some View {
        let display = WidgetSurfaceDisplay(snapshot: snapshot)
        ZStack {
            background
            content(display)
        }
        .frame(width: family.size.width, height: family.size.height)
        .clipped()
        .ignoresSafeArea()
        .widgetTypeCap()
        .environment(\.widgetFrozenNow, WidgetSamples.now)
        .environment(\.widgetHarness, true)
    }

    @ViewBuilder private var background: some View {
        if look == .accented {
            // Mock of the tinted Home Screen: the system removes our background and tints the content.
            LinearGradient(colors: [Color(brandHex: "3A5C7A"), Color(brandHex: "24384C")], startPoint: .top, endPoint: .bottom)
        } else if family.isAccessory {
            // The Lock Screen wallpaper behind vibrant accessories (mock).
            LinearGradient(colors: [Color(brandHex: "4D79A3"), Color(brandHex: "24435A")], startPoint: .top, endPoint: .bottom)
        } else {
            WidgetPage(withHouse: family.hasHousePage)
        }
    }

    @ViewBuilder private func content(_ display: WidgetSurfaceDisplay) -> some View {
        switch family {
        case .small: WidgetSmallView(display: display, look: look)
        case .medium: WidgetMediumView(display: display, look: look)
        case .large: WidgetLargeView(display: display, look: look)
        case .extraLarge: WidgetExtraLargeView(display: display, look: look)
        case .extraLargePortrait: WidgetExtraLargePortraitView(display: display, look: look)
        case .circular: WidgetCircularHoursView(display: display)
        case .pendingCircular: WidgetCircularPendingView(display: display)
        case .rectangular: WidgetRectangularView(display: display).padding(.horizontal, 8)
        case .inline: WidgetInlineView(display: display).foregroundStyle(.white).font(.subheadline.weight(.semibold))
        }
    }
}

enum WidgetFrameExporter {
    /// Draws `view` in a real window with the appearance and Dynamic Type set, returns a 3x PNG.
    @MainActor
    static func png(_ view: some View, size: CGSize, scheme: ColorScheme, content: UIContentSizeCategory) -> Data? {
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.traitOverrides.preferredContentSizeCategory = content
        host.view.frame = CGRect(origin: .zero, size: size)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: CGPoint(x: -4000, y: -4000), size: size)
        window.rootViewController = host
        window.isHidden = false
        // A window on the iPhone scene inherits the Dynamic Island and home indicator insets; a
        // widget has none, so cancel them.
        let inset = window.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: -inset.top, left: -inset.left, bottom: -inset.bottom, right: -inset.right)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        if ProcessInfo.processInfo.environment["WIDGET_DEBUG_INSETS"] != nil || ProcessInfo.processInfo.arguments.contains("-LHWidgetDebug") {
            let line = "host=\(host.view.safeAreaInsets) window=\(window.safeAreaInsets) frame=\(host.view.frame) bounds=\(host.view.bounds)\n"
            if let dir = ProcessInfo.processInfo.arguments.firstIndex(of: "-LHWidgetOut").map({ ProcessInfo.processInfo.arguments[$0 + 1] }) {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("insets.txt")
                let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try? (old + line).write(to: url, atomically: true, encoding: .utf8)
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        return image.pngData()
    }

    static func name(_ family: WidgetFrameFamily, _ state: String, _ look: WidgetLook, _ scheme: ColorScheme, _ size: String) -> String {
        "\(family.rawValue)-\(state)\(look == .accented ? "-tinted" : "")-\(scheme == .dark ? "dark" : "light")-\(size).png"
    }

    /// Every frame the hand-off lists. Returns the file names written.
    @MainActor
    static func exportAll(to dir: URL) async -> [String] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [String] = []
        // The first draw of a fresh window can come out blank: warm it up with a throwaway frame.
        _ = png(WidgetFrameView(family: .small, snapshot: WidgetSamples.behindLit), size: WidgetFrameFamily.small.size, scheme: .light, content: .large)
        try? await Task.sleep(for: .milliseconds(300))
        func write(_ family: WidgetFrameFamily, _ state: String, _ snapshot: WidgetSurfaceSnapshot,
                   look: WidgetLook = .fullColor, scheme: ColorScheme, size: String, category: UIContentSizeCategory) async {
            let view = WidgetFrameView(family: family, snapshot: snapshot, look: look, scheme: scheme)
            guard let data = png(view, size: family.size, scheme: scheme, content: category) else { return }
            let file = name(family, state, look, scheme, size)
            try? data.write(to: dir.appendingPathComponent(file))
            written.append(file)
            await Task.yield()
        }
        let sizes: [(String, UIContentSizeCategory)] = [("default", .large), ("xxl", .extraExtraExtraLarge), ("ax3", .accessibilityExtraLarge)]
        let homeStates: [WidgetFrameFamily: [String]] = [
            .small: ["behind-lit", "on-pace", "goal-met", "empty", "no-rental", "timer", "three-rentals", "pace-not-ready"],
            .medium: ["behind-lit", "behind-unlit", "on-pace", "goal-met", "empty", "no-rental", "timer", "three-rentals", "all-on-pace", "pace-not-ready", "eight-rentals"],
            .large: ["behind-lit", "behind-unlit", "on-pace", "three-rentals", "eight-rentals", "no-rental", "empty", "goal-met", "timer", "pace-not-ready"],
            .extraLarge: ["behind-lit", "behind-unlit", "three-rentals", "eight-rentals", "on-pace", "goal-met", "empty", "no-rental", "timer", "pace-not-ready"],
            .extraLargePortrait: ["behind-lit", "behind-unlit", "three-rentals", "eight-rentals", "on-pace", "goal-met", "empty", "no-rental", "timer", "pace-not-ready"],
        ]
        let byName = Dictionary(uniqueKeysWithValues: WidgetSamples.all.map { ($0.name, $0.snapshot) })
        for scheme in [ColorScheme.light, .dark] {
            for (sizeName, category) in sizes {
                for (family, states) in homeStates {
                    for state in states {
                        guard let snapshot = byName[state] else { continue }
                        await write(family, state, snapshot, scheme: scheme, size: sizeName, category: category)
                    }
                }
            }
            // Tinted and clear Home Screen: the mark in the house's slot, white inks. The same in
            // light and dark (the system supplies the tint), so written once.
            for family in [WidgetFrameFamily.small, .medium, .large] where scheme == .light {
                await write(family, "behind-lit", WidgetSamples.behindLit, look: .accented, scheme: scheme, size: "default", category: .large)
            }
            // Lock Screen accessories (vibrant: the system tints them), the states that change words.
            for state in ["behind-lit", "on-pace", "goal-met", "empty", "no-rental", "timer", "three-rentals"] where scheme == .light {
                guard let snapshot = byName[state] else { continue }
                for family in [WidgetFrameFamily.circular, .pendingCircular, .rectangular, .inline] {
                    // The to-confirm circular ignores the timer, so its timer frame would repeat behind-lit.
                    if family == .pendingCircular, state == "timer" { continue }
                    await write(family, state, snapshot, scheme: scheme, size: "default", category: .large)
                }
            }
        }
        return written
    }
}

struct WidgetExportBoard: View {
    @State private var status = "Exporting widget frames…"

    var body: some View {
        Text(status).font(.footnote).padding()
            .task {
                let args = ProcessInfo.processInfo.arguments
                let out: URL
                if let i = args.firstIndex(of: "-LHWidgetOut"), args.indices.contains(i + 1) {
                    out = URL(fileURLWithPath: args[i + 1], isDirectory: true)
                } else {
                    out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("widget-frames", isDirectory: true)
                }
                let written = await WidgetFrameExporter.exportAll(to: out)
                try? "\(written.count)\n".write(to: out.appendingPathComponent("DONE.txt"), atomically: true, encoding: .utf8)
                status = "Wrote \(written.count) frames to \(out.path)"
            }
    }
}
#endif
