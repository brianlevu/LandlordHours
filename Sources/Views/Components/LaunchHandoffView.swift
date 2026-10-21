import SwiftUI
import UIKit

// MARK: - Launch hand-off (2.0 surfaces lane)
//
// LaunchScreen.storyboard draws blueprint #1E3FA6 and mark B (112pt, 12pt above the full screen's
// centre). The app's first SwiftUI frame repeats that exactly, then hands off:
//   - to Welcome (already blueprint): the mark lifts and fades; nothing else moves.
//   - to Today: the blueprint sheet shrinks toward the hero and fades as Today appears.
// 300ms ease-out; Reduce Motion: a 200ms crossfade. Never blocks touches.
//
// DEBUG captures: `-LHLaunchFreeze <0...1>` holds the hand-off at that progress.

struct LaunchHandoffOverlay: View {
    enum Destination { case today, welcome }

    let destination: Destination
    @Binding var isFinished: Bool
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The app's own scheme (the overlay sits inside the root, under `preferredColorScheme`).
    @Environment(\.colorScheme) private var colorScheme

    /// Hand-off to LIGHT Today: the blueprint fades to the light canvas, so the status bar flips to
    /// dark ink where both inks pass. Against #1E3FA6 fading over #EEF2FA, white and black are both
    /// ≥4.5:1 only for phases 0.531…0.540; 0.535 is the middle (4.59 / 4.57). White stays above it
    /// before the switch, black above it after (LaunchStatusBarContrastTests sweeps every phase).
    static let statusBarSwitchPhase: CGFloat = 0.535

    /// The blueprint sheet's opacity at phase `p` (0 = the storyboard frame, 1 = settled).
    static func overlayOpacity(_ destination: Destination, _ p: CGFloat) -> Double {
        switch destination {
        case .today: return Double(max(0, 1 - max(0, p - 0.35) / 0.65))
        case .welcome: return Double(max(0, 1 - max(0, p - 0.5) / 0.5))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let p = progress
            ZStack {
                RoundedRectangle(cornerRadius: destination == .today ? 40 * p : 0, style: .continuous)
                    .fill(AppColors.brand)
                    .scaleEffect(destination == .today && !reduceMotion ? 1 - 0.12 * p : 1, anchor: .top)
                LHMark(size: 112)
                    .scaleEffect(destination == .welcome && !reduceMotion ? 1 + 0.4 * p : 1)
                    .opacity(Double(max(0, 1 - p * 1.8)))
                    // Centre of the FULL screen (not the safe area), 12pt up: the storyboard's spot.
                    .position(x: geo.size.width / 2, y: geo.size.height / 2 - 12)
            }
            .opacity(Self.overlayOpacity(destination, p))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: start)
    }

    private func start() {
        // The storyboard's status bar is white (UIStatusBarStyleLightContent); keep it white on the
        // blueprint, and switch to dark ink mid-fade when the destination is light Today.
        LaunchStatusBarWindow.show()
        #if DEBUG
        if let frozen = Self.frozenProgress {
            apply(frozen)
            return
        }
        #endif
        // One frame identical to the storyboard, then step the hand-off ourselves (ease-out), so the
        // status-bar switch lands on the exact phase instead of a guessed time.
        let duration: Double = reduceMotion ? 0.2 : 0.3
        Task { @MainActor in
            let start = Date()
            while true {
                try? await Task.sleep(for: .milliseconds(16))
                let t = min(1, Date().timeIntervalSince(start) / duration)
                let eased = reduceMotion ? t : 1 - (1 - t) * (1 - t) * (1 - t)
                apply(CGFloat(eased))
                if t >= 1 { break }
            }
            LaunchStatusBarWindow.hide()
            isFinished = true
        }
    }

    private func apply(_ p: CGFloat) {
        progress = p
        let darkInk = destination == .today && colorScheme == .light && p >= Self.statusBarSwitchPhase
        LaunchStatusBarWindow.setDarkContent(darkInk)
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

/// A transparent, non-interactive window above the app whose only job is a light status bar while
/// the blueprint hand-off is on screen (black on #1E3FA6 is 2.32:1; white is 9.06:1).
@MainActor
enum LaunchStatusBarWindow {
    private static var window: UIWindow?

    private final class LightStatusBarController: UIViewController {
        var darkContent = false {
            didSet { if darkContent != oldValue { setNeedsStatusBarAppearanceUpdate() } }
        }
        override var preferredStatusBarStyle: UIStatusBarStyle { darkContent ? .darkContent : .lightContent }
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
        w.rootViewController = LightStatusBarController()
        w.isHidden = false
        window = w
    }

    static func setDarkContent(_ dark: Bool) {
        (window?.rootViewController as? LightStatusBarController)?.darkContent = dark
    }

    static func hide() {
        window?.isHidden = true
        window = nil
    }
}
