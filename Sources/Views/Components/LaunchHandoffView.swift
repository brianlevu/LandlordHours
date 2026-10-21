import SwiftUI

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
            .opacity(Double(destination == .today ? max(0, 1 - max(0, p - 0.35) / 0.65) : max(0, 1 - max(0, p - 0.5) / 0.5)))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: start)
    }

    private func start() {
        #if DEBUG
        if let frozen = Self.frozenProgress {
            progress = frozen
            return
        }
        #endif
        // One frame on screen identical to the storyboard, then animate.
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .linear(duration: 0.2) : .easeOut(duration: 0.3)) {
                progress = 1
            } completion: {
                isFinished = true
            }
        }
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
