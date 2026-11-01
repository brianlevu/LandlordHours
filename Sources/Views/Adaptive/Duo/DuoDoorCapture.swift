import SwiftUI
import UIKit

#if DEBUG
// MARK: - DEBUG captures for `duoUnfold` on the real shell (compiled out of Release)
//
//   -LHDuoDoorRender     (with the adaptive seeds, e.g. -LHMockScenario emptyMainTabs
//                        -LHSeedSuggestions inbox -LHCraftSeed craft -LHCraftWindows lit)
//
// A simulator cannot unfold, so the door is captured by holding the clock at fixed instants and
// rendering the real shell (`ContentView`) in off-screen windows at the Duo's sizes with
// `drawHierarchy` @3x, the fold standing in through `AdaptiveSnapshotter.duoShot` exactly as the
// `-LHAdaptiveRender duo` frames do: held open 951×669 (3 rentals at L and XXL, All rentals at L) and
// propped 669×951 (3 rentals at L and XXL), dusk and night; the swing at t 0, 0.1, 0.2, 0.3, 0.42,
// 0.5, 0.6, 0.76, 1 and the Reduce Motion crossfade at 0, 0.5, 1. Frames go to Documents/duodoor/
// with a DONE marker.

@MainActor
enum DuoDoorCapture {
    /// While a frame renders, the clock every `DuoDoorRoot` follows (held at one instant).
    static var heldClock: UnfoldClock?
    private static var started = false
    private static var windows: [UIWindow] = []

    static let swingSteps: [Double] = [0, 0.1, 0.2, 0.3, 0.42, 0.5, 0.6, 0.76, 1]
    static let crossfadeSteps: [Double] = [0, 0.5, 1]

    static func startIfRequested() async {
        guard !started, ProcessInfo.processInfo.arguments.contains("-LHDuoDoorRender") else { return }
        started = true
        await run()
    }

    private struct Pose {
        let name: String
        let size: CGSize
        let category: UIContentSizeCategory
        let select: String
        let insets: UIEdgeInsets
    }

    private static func run() async {
        try? await Task.sleep(for: .seconds(4))   // the seeds land and the inbox loads first
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("duodoor")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let open = AdaptiveSnapshotter.duoOpen, propped = AdaptiveSnapshotter.duoPropped
        let L = UIContentSizeCategory.large, XXL = UIContentSizeCategory.extraExtraLarge
        let openInsets = UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        let proppedInsets = UIEdgeInsets(top: 24, left: 0, bottom: 34, right: 0)
        let poses = [
            Pose(name: "door-open-3rentals", size: open, category: L, select: "3", insets: openInsets),
            Pose(name: "door-open-3rentals-XXL", size: open, category: XXL, select: "3", insets: openInsets),
            Pose(name: "door-open-allrentals", size: open, category: L, select: "0", insets: openInsets),
            Pose(name: "door-propped", size: propped, category: L, select: "3", insets: proppedInsets),
            Pose(name: "door-propped-XXL", size: propped, category: XXL, select: "3", insets: proppedInsets),
        ]
        let steps: [(Double, UnfoldStyle, String)] = swingSteps.map { ($0, .swing, "swing") }
            + crossfadeSteps.map { ($0, .crossfade, "rm") }
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            for pose in poses {
                let clock = UnfoldClock()
                heldClock = clock
                AdaptiveSnapshotter.duoShot = pose.size
                AdaptiveSnapshotter.duoShotTopInset = pose.insets.top
                AdaptiveSnapshotSelection.args = ["select": pose.select]
                let w = makeWindow(size: pose.size, dark: dark, category: pose.category, insets: pose.insets, scene: scene)
                for _ in 0..<3 {
                    try? await Task.sleep(for: .seconds(0.4))
                    settleInsets(w, target: pose.insets)
                }
                try? await Task.sleep(for: .seconds(2.0))
                for (t, style, kind) in steps {
                    clock.hold(t: t, style: style)
                    try? await Task.sleep(for: .milliseconds(250))
                    let file = String(format: "%@-%@-%@-t%03d.png", pose.name, tag, kind, Int((t * 100).rounded()))
                    snap(w, size: pose.size, to: dir.appendingPathComponent(file))
                }
                w.isHidden = true
                windows.removeAll { $0 === w }
                AdaptiveSnapshotter.duoShot = nil
                AdaptiveSnapshotter.duoShotTopInset = nil
                heldClock = nil
            }
        }
        try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
        NSLog("DUO_DOOR_RENDER_DONE %@", dir.path)
    }

    private static func makeWindow(size: CGSize, dark: Bool, category: UIContentSizeCategory, insets: UIEdgeInsets,
                                   scene: UIWindowScene) -> UIWindow {
        let root = ContentView()
            .environmentObject(AppModelHost.shared.viewModel)
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
        hc.view.layoutIfNeeded()
        hc.additionalSafeAreaInsets = minus(insets, hc.view.safeAreaInsets)
        windows.append(w)
        return w
    }

    private static func settleInsets(_ w: UIWindow, target: UIEdgeInsets) {
        guard let hc = w.rootViewController else { return }
        let sys = minus(hc.view.safeAreaInsets, hc.additionalSafeAreaInsets)
        let want = minus(target, sys)
        if want != hc.additionalSafeAreaInsets { hc.additionalSafeAreaInsets = want }
    }

    private static func minus(_ a: UIEdgeInsets, _ b: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(top: a.top - b.top, left: a.left - b.left, bottom: a.bottom - b.bottom, right: a.right - b.right)
    }

    private static func snap(_ w: UIWindow, size: CGSize, to url: URL) {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 3
        f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            _ = w.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        try? img.pngData()?.write(to: url)
    }
}
#endif
