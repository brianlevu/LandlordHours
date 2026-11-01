import SwiftUI
import UIKit

#if DEBUG
// MARK: - DEBUG captures for `duoUnfold` (compiled out of Release)
//
//   -LHSurfaceBoard unfold-door
//
// A simulator cannot unfold, so the door is captured by holding the clock at fixed instants and
// rendering off-screen windows at the Duo's sizes with `drawHierarchy` @3x: held open 951×669 (a
// vertical fold) and propped 669×951 (the fold across), dusk and night, default and XXL, the swing
// at t 0, 0.1, 0.2, 0.3, 0.42, 0.5, 0.6, 0.76, 1 and the Reduce Motion crossfade at 0, 0.5, 1.
// Frames go to Documents/unfold/ with a DONE marker.
//
// What is drawn is `UnfoldCapture.composition`. Once package J's two-pane layout is in the build it
// registers the real shell there (docs/plans/duo-integration.md); until then a fixture stands in: the
// production house (`CraftHouseView`, `half`, lit) on the page in the house pane and `UnfoldLight`
// over a plain card in the work pane. The fixture has no door leaf (that is J's `FrontDoor`).

enum UnfoldCapture {
    /// The view to capture for a posture, driven by `clock`. nil = the fixture.
    static var composition: ((FoldPosture, UnfoldClock) -> AnyView)?

    static let openSize = CGSize(width: 951, height: 669)
    static let proppedSize = CGSize(width: 669, height: 951)
    /// The assumed fold band until a device read (§1.27 must-prove 1). Captures only.
    static let assumedBand: CGFloat = 24

    static let swingSteps: [Double] = [0, 0.1, 0.2, 0.3, 0.42, 0.5, 0.6, 0.76, 1]
    static let crossfadeSteps: [Double] = [0, 0.5, 1]
}

/// The board: a status line while the renderer runs off-screen.
struct UnfoldCaptureBoard: View {
    @State private var done = false

    var body: some View {
        Text(verbatim: done ? "unfold frames written" : "rendering unfold frames…")
            .font(.footnote)
            .task {
                await UnfoldRenderer.run()
                done = true
            }
    }
}

@MainActor
enum UnfoldRenderer {
    private static var windows: [UIWindow] = []

    static func run() async {
        try? await Task.sleep(for: .seconds(1.5))
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("unfold")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let postures: [(FoldPosture, CGSize, String)] = [(.open, UnfoldCapture.openSize, "open"),
                                                         (.propped, UnfoldCapture.proppedSize, "propped")]
        for dark in [false, true] {
            for (category, sfx) in [(UIContentSizeCategory.large, "L"), (.extraExtraLarge, "XXL")] {
                for (posture, size, name) in postures {
                    let clock = UnfoldClock()
                    let insets = posture == .open ? UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
                                                  : UIEdgeInsets(top: 24, left: 0, bottom: 34, right: 0)
                    let w = makeWindow(posture: posture, clock: clock, size: size, dark: dark, category: category,
                                       insets: insets, scene: scene)
                    try? await Task.sleep(for: .seconds(1.6))
                    let steps = UnfoldCapture.swingSteps.map { ($0, UnfoldStyle.swing, "swing") }
                        + UnfoldCapture.crossfadeSteps.map { ($0, UnfoldStyle.crossfade, "rm") }
                    for (t, style, tag) in steps {
                        clock.hold(t: t, style: style)
                        try? await Task.sleep(for: .milliseconds(180))
                        let file = String(format: "%@-%@-%@-%@-t%03d.png", name, dark ? "night" : "dusk", sfx, tag, Int((t * 100).rounded()))
                        snap(w, size: size, to: dir.appendingPathComponent(file))
                    }
                    w.isHidden = true
                    windows.removeAll { $0 === w }
                }
            }
        }
        try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
        NSLog("UNFOLD_RENDER_DONE %@", dir.path)
    }

    private static func makeWindow(posture: FoldPosture, clock: UnfoldClock, size: CGSize, dark: Bool,
                                   category: UIContentSizeCategory, insets: UIEdgeInsets, scene: UIWindowScene) -> UIWindow {
        let content = UnfoldCapture.composition?(posture, clock) ?? AnyView(UnfoldFixture(posture: posture, clock: clock))
        let root = content
            .safeAreaPadding(EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right))
            .frame(width: size.width, height: size.height)
        let hc = UIHostingController(rootView: root)
        hc.overrideUserInterfaceStyle = dark ? .dark : .light
        hc.traitOverrides.horizontalSizeClass = .compact
        hc.traitOverrides.verticalSizeClass = .regular
        hc.traitOverrides.preferredContentSizeCategory = category
        hc.safeAreaRegions = []
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(origin: .zero, size: size)
        w.windowLevel = .normal - 1
        w.rootViewController = hc
        w.isHidden = false
        windows.append(w)
        return w
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

/// Stand-in composition until package J's layout is in the build: the production house on the page,
/// and the work pane's light over a plain card. Not a layout; only the door's light is under test.
private struct UnfoldFixture: View {
    let posture: FoldPosture
    @ObservedObject var clock: UnfoldClock
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let band = UnfoldCapture.assumedBand
        Group {
            if posture == .open {
                HStack(spacing: 0) { house; Color.clear.frame(width: band); work }
            } else {
                VStack(spacing: 0) { house; Color.clear.frame(height: band); work }
            }
        }
        .background { LHPage() }
    }

    private var house: some View {
        CraftHouseView(stage: .half, windowsLit: true, side: posture == .open ? 290 : 220)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var work: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(colors.backgroundSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                UnfoldLight(pose: clock.pose, edge: posture.workPaneFoldEdge ?? .leading,
                            veil: Color.black.opacity(colorScheme == .dark ? 0.78 : 0.70))
            }
    }
}
#endif
