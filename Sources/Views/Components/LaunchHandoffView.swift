import SwiftUI
import UIKit

// MARK: - Launch hand-off (v2, standard §H.5; plan package B)
//
// LaunchScreen.storyboard draws `LaunchBackground` (= `pageTop`: #EAE3D7 light, #0B1230 dark) and
// the mono mark B in `textPrimary` per appearance (`LaunchMark`, 112pt, 12pt above the full
// screen's centre). The app's first SwiftUI frame repeats that exactly, then crossfades (`reveal`,
// 0.22 ease-out) into whatever the root shows: Welcome (whose dusk/night page starts at `pageTop`)
// or the restored tab. Nothing scales or moves, so there is no blueprint flash and no seam: the
// launch colour is the first screen's own top colour in both appearances.
//
// The status bar follows the appearance (`UIStatusBarStyleDefault` in Info.plist): dark ink on the
// dusk page, light ink at night, so no status-bar window is needed for the hand-off.
//
// Reduce Motion: the same crossfade (opacity only). Never blocks touches.
// DEBUG captures: `-LHLaunchFreeze <0...1>` holds the hand-off at that progress.

struct LaunchHandoffOverlay: View {
    enum Destination { case today, welcome }

    let destination: Destination
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0

    /// The overlay's opacity at phase `p` (0 = the storyboard frame, 1 = settled). The same curve
    /// for both destinations: the colour under it is `pageTop` either way.
    static func overlayOpacity(_ destination: Destination, _ p: CGFloat) -> Double {
        Double(max(0, min(1, 1 - p)))
    }

    /// One frame identical to the storyboard before the fade starts.
    static let holdBeforeReveal: Duration = .milliseconds(80)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LaunchFrame()
                    // Centre of the FULL screen (not the safe area), 12pt up: the storyboard's spot.
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .opacity(Self.overlayOpacity(destination, progress))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await run() }
    }

    @MainActor private func run() async {
        #if DEBUG
        if let frozen = Self.frozenProgress {
            progress = frozen
            return
        }
        #endif
        try? await Task.sleep(for: Self.holdBeforeReveal)
        withAnimation(AppAnimation.reveal) { progress = 1 }
        try? await Task.sleep(for: .milliseconds(260))
        isFinished = true
    }

    #if DEBUG
    static let frozenProgress: CGFloat? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHLaunchFreeze"), args.indices.contains(i + 1),
              let value = Double(args[i + 1]) else { return nil }
        return CGFloat(min(max(value, 0), 1))
    }()
    #endif
}

/// The storyboard frame in SwiftUI: `pageTop` and the `LaunchMark` asset (the same vector the
/// storyboard draws, Any and Dark), 112pt, 12pt above the full screen's centre.
struct LaunchFrame: View {
    @Environment(\.colorScheme) private var colorScheme

    static let markSide: CGFloat = 112
    static let markLift: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AdaptiveColors(colorScheme: colorScheme).pageTop
                Image("LaunchMark")
                    .resizable()
                    .frame(width: Self.markSide, height: Self.markSide)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2 - Self.markLift)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A transparent, non-interactive window above the app that pins the status-bar style for a DEBUG
/// capture board (`SurfaceCaptureBoard`). v2: the launch no longer needs it (the status bar follows
/// the appearance on the dusk/night launch colour); `.default` unless a caller asks for dark ink.
@MainActor
enum LaunchStatusBarWindow {
    private static var window: UIWindow?

    private final class StatusBarController: UIViewController {
        var darkContent = false {
            didSet { if darkContent != oldValue { setNeedsStatusBarAppearanceUpdate() } }
        }
        override var preferredStatusBarStyle: UIStatusBarStyle { darkContent ? .darkContent : .default }
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
    }

    static func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .normal + 1
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = false
        w.rootViewController = StatusBarController()
        w.isHidden = false
        window = w
    }

    static func setDarkContent(_ dark: Bool) {
        (window?.rootViewController as? StatusBarController)?.darkContent = dark
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}
