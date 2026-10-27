import SwiftUI
import UIKit

// MARK: - DEBUG hooks for the adaptive captures (compiled to no-ops in Release)
//
//   -LHAdaptiveSelect <n>          select shelf item n (0 = All rentals when there are two or more)
//   -LHAdaptiveRoute detail|log    open the first To confirm item's detail, or Log time, in the pane
//   -LHAdaptiveOrientation landscape|portrait   ask the scene for that orientation (iPad captures)
//   -LHAdaptiveRender duo|ipad     lay the real shell out in off-screen windows at exact sizes and
//                                  write PNGs to Documents/adaptive/ (an agent cannot unfold a
//                                  simulator or size a Stage Manager window): `duo` renders the open
//                                  (951×669, a 24pt division at the centre, door at rest) and propped
//                                  (669×951) layouts @3x; `ipad` renders the §13 window sizes @2x.
//   -LHPaneSystemBar               the must-prove 12 fallback: no compact bridge in the right pane.

enum AdaptiveDebug {
    /// A division the off-screen Duo renders stand in for (the real one comes from `reservedRegions`).
    static func capturedDivision(for size: CGSize) -> PaneDivision? {
        #if DEBUG
        return AdaptiveSnapshotter.division(for: size)
        #else
        return nil
        #endif
    }

    /// The capture shot's size while an off-screen Duo frame renders (the measured size carries the
    /// capture's inset compensation); nil otherwise and in Release.
    static func capturedSize(for size: CGSize) -> CGSize? {
        #if DEBUG
        guard AdaptiveSnapshotter.division(for: size) != nil else { return nil }
        return MainActor.assumeIsolated { AdaptiveSnapshotter.duoShot }
        #else
        return nil
        #endif
    }

    /// The capture shot's top inset while an off-screen Duo frame renders. The render window's
    /// safe area does not settle to the Duo's on a stacked shot (the probe read 62, then 14, then 0
    /// on the iPhone 17 Pro capture sim, so the propped numeral drew under the 24pt status bar, gate
    /// J r2); the shot's own inset stands in. nil otherwise and in Release.
    static func capturedTopInset(for size: CGSize) -> CGFloat? {
        #if DEBUG
        guard AdaptiveSnapshotter.division(for: size) != nil else { return nil }
        return MainActor.assumeIsolated { AdaptiveSnapshotter.duoShotTopInset }
        #else
        return nil
        #endif
    }

    #if DEBUG
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    private static var didSelect = false
    private static var didRoute = false
    private static var didRoot = false

    @MainActor
    static func applySelection(_ selection: AdaptiveSelection, app: AppViewModel) {
        // The off-screen renderer sets each window's own selection and route.
        let shot = AdaptiveSnapshotSelection.args
        let select = shot["select"] ?? (didSelect ? nil : value("-LHAdaptiveSelect"))
        if let n = select.flatMap(Int.init) {
            didSelect = true
            let shelf = HouseShelf.live(app: app, goal: GoalManager.shared.houseGoal, isRecord: GoalManager.shared.goalChoice == .record)
            if shelf.items.indices.contains(n) { selection.selectedID = shelf.items[n].id }
        }
        let routeArg = shot.isEmpty ? (didRoute ? nil : value("-LHAdaptiveRoute")) : shot["route"]
        if let route = routeArg {
            didRoute = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.0))
                switch route {
                case "detail":
                    let inbox = InboxViewModel.live(app: app)
                    inbox.reload()
                    let items = PaneConfirmFilter.items(inbox.visible, rentalID: selection.selectedRentalID)
                    if let first = items.first { selection.open(.suggestion(first.sourceKey)) }
                case "log":
                    NotificationCenter.default.post(name: .openLogSheet, object: LogSheetRoute.log)
                default: break
                }
            }
        }
    }

    @MainActor
    static func onRootAppear() {
        guard !didRoot else { return }
        didRoot = true
        if let o = value("-LHAdaptiveOrientation") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                let mask: UIInterfaceOrientationMask = o == "landscape" ? .landscapeRight : .portrait
                (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
                    .requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { NSLog("ADAPTIVE geometry error: %@", "\($0)") }
            }
        }
        if let kind = value("-LHAdaptiveRender"), !AdaptiveSnapshotter.started {
            AdaptiveSnapshotter.started = true
            Task { @MainActor in await AdaptiveSnapshotter.run(kind: kind) }
        }
    }
    #endif
}

#if DEBUG
// MARK: - Off-screen renderer: the real shell in UIWindows of exact sizes, drawHierarchy

@MainActor
enum AdaptiveSnapshotter {
    static var started = false
    static var windows: [UIWindow] = []
    /// While a Duo frame renders, the window size that stands for the open or propped Duo.
    /// The Duo shot being rendered (its target size), nil otherwise.
    static var duoShot: CGSize?
    static var duoShotTopInset: CGFloat?

    static let duoOpen = CGSize(width: 951, height: 669)
    static let duoPropped = CGSize(width: 669, height: 951)
    /// The assumed fold band (frame + margins) until a device read (must-prove 1).
    static let foldBand: CGFloat = 24

    nonisolated static func division(for size: CGSize) -> PaneDivision? {
        // The Duo shot being rendered; the measured size may drift by the capture's inset
        // compensation for a frame or two, so match within a band and split at the shot's centre.
        guard let shot = MainActor.assumeIsolated({ duoShot }),
              abs(size.width - shot.width) < 30, abs(size.height - shot.height) < 30 else { return nil }
        if shot.width > shot.height {
            return PaneDivision(rect: CGRect(x: (shot.width - foldBand) / 2, y: 0, width: foldBand, height: size.height))
        }
        return PaneDivision(rect: CGRect(x: 0, y: (shot.height - foldBand) / 2, width: size.width, height: foldBand))
    }

    struct Shot {
        let name: String
        let size: CGSize
        let category: UIContentSizeCategory
        let args: [String: String]
        var insets = UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        var duo = false
    }

    static func run(kind: String) async {
        try? await Task.sleep(for: .seconds(4))   // the seeds land and the inbox loads first
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("adaptive")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scale: CGFloat = kind == "duo" ? 3 : scene.screen.scale
        let L = UIContentSizeCategory.large, XXL = UIContentSizeCategory.extraExtraLarge, AX3 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        var shots: [Shot] = []
        if kind == "duo" {
            for (cat, sfx) in [(L, ""), (XXL, "-XXL"), (AX3, "-AX3")] {
                shots.append(Shot(name: "duo-open-3rentals\(sfx)", size: duoOpen, category: cat, args: ["select": "3"], duo: true))
                shots.append(Shot(name: "duo-open-allrentals\(sfx)", size: duoOpen, category: cat, args: ["select": "0"], duo: true))
            }
            shots.append(Shot(name: "duo-open-detail", size: duoOpen, category: L, args: ["select": "3", "route": "detail"], duo: true))
            shots.append(Shot(name: "duo-open-logtime", size: duoOpen, category: L, args: ["select": "3", "route": "log"], duo: true))
            shots.append(Shot(name: "duo-open-zerologged", size: duoOpen, category: L, args: ["select": "2"], duo: true))
            // Propped: the bottom inset is the capture sim's own (34; the Duo's propped insets are
            // must-prove 4), so no negative compensation fights the stacked layout.
            let propped = UIEdgeInsets(top: 24, left: 0, bottom: 34, right: 0)
            shots.append(Shot(name: "duo-propped", size: duoPropped, category: L, args: ["select": "3"], insets: propped, duo: true))
            shots.append(Shot(name: "duo-propped-allrentals", size: duoPropped, category: L, args: ["select": "0"], insets: propped, duo: true))
            shots.append(Shot(name: "duo-propped-AX3", size: duoPropped, category: AX3, args: ["select": "3"], insets: propped, duo: true))
        } else {
            let sizes: [(String, CGSize)] = [
                ("sm-799x1000", CGSize(width: 799, height: 1000)), ("sm-800x1000", CGSize(width: 800, height: 1000)),
                ("sm-1000x644", CGSize(width: 1000, height: 644)), ("sm-1000x645", CGSize(width: 1000, height: 645)),
                ("sm-700x900", CGSize(width: 700, height: 900)),
                ("mini-744x1133", CGSize(width: 744, height: 1133)), ("mini-1133x744", CGSize(width: 1133, height: 744)),
                ("pro11-834x1210", CGSize(width: 834, height: 1210)), ("air13-1032x1376", CGSize(width: 1032, height: 1376)),
                ("air13-1376x1032", CGSize(width: 1376, height: 1032)), ("tile23-11in-790x820", CGSize(width: 790, height: 820)),
            ]
            // The device's own insets (iPadOS 27 on the 10th gen: top 32, bottom 25), so a render
            // matches a real window of that size on this iPad.
            let own = scene.windows.first { $0.isKeyWindow }?.safeAreaInsets ?? UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
            let padInsets = UIEdgeInsets(top: own.top, left: 0, bottom: own.bottom, right: 0)
            for (name, size) in sizes {
                shots.append(Shot(name: "ipad-\(name)", size: size, category: L, args: ["select": "3"], insets: padInsets))
            }
            for (cat, sfx) in [(L, "L"), (XXL, "XXL"), (AX3, "AX3")] {
                for (state, select) in [("3rentals", "3"), ("allrentals", "0")] {
                    shots.append(Shot(name: "ipad10-landscape-\(state)-\(sfx)", size: CGSize(width: 1180, height: 820), category: cat,
                                      args: ["select": select], insets: padInsets))
                }
            }
            shots.append(Shot(name: "ipad10-landscape-detail-L", size: CGSize(width: 1180, height: 820), category: L,
                              args: ["select": "3", "route": "detail"], insets: padInsets))
            shots.append(Shot(name: "ipad10-landscape-logtime-L", size: CGSize(width: 1180, height: 820), category: L,
                              args: ["select": "3", "route": "log"], insets: padInsets))
        }
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            for shot in shots {
                duoShot = shot.duo ? shot.size : nil
                duoShotTopInset = shot.duo ? shot.insets.top : nil
                AdaptiveSnapshotSelection.args = shot.args
                let w = makeWindow(size: shot.size, dark: dark, category: shot.category, insets: shot.insets, scene: scene)
                // The scene's own insets can move once the window lays out (a status bar or home bar
                // arrives late); settle the compensation, then wait for the content.
                for _ in 0..<3 {
                    try? await Task.sleep(for: .seconds(0.4))
                    settleInsets(w, target: shot.insets)
                }
                try? await Task.sleep(for: .seconds(shot.args["route"] == nil ? 2.0 : 3.2))
                snap(w, size: shot.size, scale: scale, to: dir.appendingPathComponent("\(shot.name)-\(tag).png"))
                writePanes(w, size: shot.size, to: dir.appendingPathComponent("\(shot.name)-\(tag).panes.json"))
                w.isHidden = true
                windows.removeAll { $0 === w }
                duoShot = nil
                duoShotTopInset = nil
            }
        }
        try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
        NSLog("ADAPTIVE_RENDER_DONE %@", dir.path)
    }

    private static func makeWindow(size: CGSize, dark: Bool, category: UIContentSizeCategory, insets: UIEdgeInsets,
                                   scene: UIWindowScene) -> UIWindow {
        let app = AppModelHost.shared.viewModel
        let root = ContentView()
            .environmentObject(app)
            .environmentObject(CategoryManager.shared)
            .environmentObject(AppearanceManager.shared)
        let hc = UIHostingController(rootView: AnyView(root))
        hc.overrideUserInterfaceStyle = dark ? .dark : .light
        hc.traitOverrides.preferredContentSizeCategory = category
        hc.safeAreaRegions = .all
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(origin: .zero, size: size)
        w.windowLevel = .normal - 1
        w.rootViewController = hc
        w.isHidden = false
        // The capture device's safe areas: additional insets make up the difference between what
        // this scene gives the root (its status bar, its home bar) and the target device's.
        hc.view.layoutIfNeeded()
        let sys = hc.view.safeAreaInsets
        hc.additionalSafeAreaInsets = insets - sys
        windows.append(w)
        return w
    }

    private static func settleInsets(_ w: UIWindow, target: UIEdgeInsets) {
        guard let hc = w.rootViewController else { return }
        let sys = hc.view.safeAreaInsets - hc.additionalSafeAreaInsets
        let want = target - sys
        if want != hc.additionalSafeAreaInsets { hc.additionalSafeAreaInsets = want }
    }

    private static func snap(_ w: UIWindow, size: CGSize, scale: CGFloat, to url: URL) {
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            _ = w.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        try? img.pngData()?.write(to: url)
    }

    /// The `<frame>.panes.json` sidecar (NOTES §13): panes, gap and bar rects in points.
    private static func writePanes(_ w: UIWindow, size: CGSize, to url: URL) {
        let division = division(for: size)
        let split = LayoutMode.resolve(previous: nil, size: size, division: division, live: false)
        var bar: [CGFloat] = []
        if let tabBar = findTabBar(in: w) {
            let r = tabBar.convert(tabBar.bounds, to: w)
            bar = [r.minX, r.minY, r.width, r.height]
        }
        let rect: (CGRect) -> [CGFloat] = { [$0.minX, $0.minY, $0.width, $0.height] }
        let inset = w.rootViewController?.view.safeAreaInsets ?? .zero
        let json: [String: Any] = [
            "insets": [inset.top, inset.left, inset.bottom, inset.right],
            "mode": "\(split.mode)",
            "panes": split.mode == .compact ? [rect(CGRect(origin: .zero, size: size))] : [rect(split.first), rect(split.second)],
            "gap": split.mode == .compact ? [] : rect(split.gap),
            "bar": bar,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0 { return bar }
        for sub in view.subviews { if let bar = findTabBar(in: sub) { return bar } }
        return nil
    }
}

private extension UIEdgeInsets {
    static func - (a: UIEdgeInsets, b: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(top: a.top - b.top, left: a.left - b.left, bottom: a.bottom - b.bottom, right: a.right - b.right)
    }
}

/// Per-shot selection for the snapshot windows (read when the shell's work pane appears).
@MainActor
enum AdaptiveSnapshotSelection {
    static var args: [String: String] = [:]
}
#endif
