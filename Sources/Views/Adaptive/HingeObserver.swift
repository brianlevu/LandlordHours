import SwiftUI

// MARK: - HingeObserver: `duoUnfold` is keyed to the hinge and nothing else (§1.27 Motion, §B.3)
//
// iOS 27.1 `onHingeChange(isEnabled:_:)` (SwiftUICore; `DeviceHinge.status` .closed / .partiallyOpen
// / .fullyOpen). Closed → open runs the door clock 0 → 1 over 0.80 s; open → closed runs it back over
// 0.50 s; Reduce Motion is a 0.20 s crossfade with no leaf turn. It never runs on a resize, an
// arrangement change, a scene change or a cold launch already open (the first report, with no
// previous hinge, only records the state). An iPad has no hinge, so it never runs there.
// `UIHingeInteraction` is the UIKit fallback named in the standard; on 27.1 the SwiftUI modifier
// is available wherever a hinge exists, so the fallback is not wired (must-prove 2 decides).

extension DoorClock {
    /// Runs t to `target` linearly over `duration` (the clock drives every layer as a pure function).
    func run(to target: Double, duration: Double) {
        runner?.cancel()
        let start = t
        let began = Date()
        runner = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let u = min(1, Date().timeIntervalSince(began) / max(duration, 0.01))
                self?.t = start + (target - start) * u
                if u >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// A touch during the unfold jumps the door to its end (the layout is live from frame 0).
    func finish() {
        runner?.cancel()
        runner = nil
        if t > 0 && t < 1 { t = 1 }
    }
}

struct HingeDoorModifier: ViewModifier {
    @ObservedObject var clock: DoorClock
    var isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange(isEnabled: isEnabled) { old, new in
                guard let before = old.hinge?.status, let after = new.hinge?.status, before != after else { return }
                let wasClosed = before == .closed
                let isClosed = after == .closed
                if wasClosed && !isClosed {
                    if reduceMotion {
                        clock.t = 1
                    } else {
                        clock.t = 0
                        clock.run(to: 1, duration: 0.80)
                    }
                } else if !wasClosed && isClosed {
                    if reduceMotion { clock.t = 1 } else { clock.run(to: 0, duration: 0.50) }
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Plays `duoUnfold` on the door clock when the Duo's hinge opens or closes (never otherwise).
    func duoUnfold(_ clock: DoorClock, isEnabled: Bool) -> some View {
        modifier(HingeDoorModifier(clock: clock, isEnabled: isEnabled))
    }
}
