import SwiftUI
import UIKit

// MARK: - UnfoldClock: the door clock, driven by the hinge (standard §B.3 `duoUnfold`, §1.27 Motion)
//
// Holds t (0 shut … 1 open and lit, the state at rest) and the run's style. The rules are
// `UnfoldDoor`'s (pure, tested); this class only applies them over time on a `CADisplayLink`, so the
// door advances once per display frame (must-prove 10: no hitches), never on a sleeping task.
//
// `.unfoldDoor(_:posture:)` connects it to SwiftUI's `onHingeChange` (iOS 27.1). The listener is
// always on wherever a hinge exists: the fold that hides the inner display and the unfold that shows
// it are exactly the events that arrive while the window changes size and mode, so gating the
// listener on the current layout would miss them. Below iOS 27.1, and on every device without a
// hinge, nothing ever moves the clock: t stays 1 and the door is simply open and lit.

@MainActor
final class UnfoldClock: ObservableObject {
    @Published private(set) var t: Double
    @Published private(set) var style: UnfoldStyle = .swing

    /// The last hinge state reported, and when (nil until the first report).
    private(set) var hinge: HingeStatus?
    private(set) var lastHingeEvent: Date?

    private var move: UnfoldMove?
    private var began: CFTimeInterval = 0
    private var link: CADisplayLink?

    init(t: Double = 1) { self.t = min(max(t.isFinite ? t : 1, 0), 1) }

    /// Every door layer's value now.
    var pose: DoorPose { DoorPose(t: t, style: style) }
    /// The same for a hero with no door (framing stages, the "All rentals" skyline).
    func pose(hasDoor: Bool) -> DoorPose { DoorPose(t: t, style: style, hasDoor: hasDoor) }

    var isRunning: Bool { move != nil }

    // MARK: Events

    /// A hinge report. The first one only records the state (a cold launch already open plays nothing).
    func hingeChanged(from old: HingeStatus?, to new: HingeStatus?, reduceMotion: Bool, now: Date = Date()) {
        hinge = new
        lastHingeEvent = now
        guard let move = UnfoldDoor.move(from: old, to: new, reduceMotion: reduceMotion, current: t) else { return }
        run(move)
    }

    /// A touch: a door mid-run jumps to open (the layout is live from frame 0).
    func finish() {
        guard let end = UnfoldDoor.touch(current: t) else { return }
        stop()
        t = end
        style = .swing
    }

    /// A fold that shows the door short of open with no run, long after the last hinge event, settles lit.
    func settleIfStranded(posture: FoldPosture, now: Date = Date()) {
        let since = lastHingeEvent.map { now.timeIntervalSince($0) }
        guard UnfoldDoor.isStranded(current: t, running: isRunning, posture: posture, secondsSinceHingeEvent: since) else { return }
        stop()
        t = 1
        style = .swing
    }

    // MARK: Running

    func run(_ move: UnfoldMove) {
        stop()
        style = move.style
        t = move.from
        self.move = move
        began = CACurrentMediaTime()
        let proxy = DisplayLinkProxy { [weak self] in self?.tick() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func tick() {
        guard let move else { stop(); return }
        let elapsed = CACurrentMediaTime() - began
        t = move.value(at: elapsed)
        if move.isFinished(at: elapsed) {
            stop()
            if t >= 1 { style = .swing }
        }
    }

    private func stop() {
        link?.invalidate()
        link = nil
        move = nil
    }

    #if DEBUG
    /// Captures only: hold the clock at one instant of a run.
    func hold(t: Double, style: UnfoldStyle) {
        stop()
        self.t = min(max(t, 0), 1)
        self.style = style
    }
    #endif
}

/// `CADisplayLink` retains its target; the proxy keeps the clock free to go away (it invalidates the
/// link when a run ends or a new one starts).
private final class DisplayLinkProxy: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) { self.action = action }

    @objc func step() {
        MainActor.assumeIsolated { action() }
    }
}

// MARK: - The hinge listener

extension View {
    /// Plays `duoUnfold` on `clock` when the hinge opens or closes, and settles a door left short of
    /// open on a fold. `posture` is the window's (`FoldPosture.resolve`). A touch mid-run finishes it.
    func unfoldDoor(_ clock: UnfoldClock, posture: FoldPosture) -> some View {
        modifier(UnfoldHingeModifier(clock: clock, posture: posture))
    }
}

private struct UnfoldHingeModifier: ViewModifier {
    @ObservedObject var clock: UnfoldClock
    let posture: FoldPosture

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(HingeListener { old, new in
                clock.hingeChanged(from: old, to: new, reduceMotion: reduceMotion)
            })
            .simultaneousGesture(TapGesture().onEnded { clock.finish() }, including: clock.isRunning ? .all : .none)
            .task(id: posture) {
                // Must-prove 3: if the open event is missed while the window changes display, the door
                // must not stay shut over a lit fold. Checked a few times after the posture lands.
                guard posture.hostsDoor else { return }
                for _ in 0..<3 {
                    try? await Task.sleep(for: .seconds(UnfoldDoor.strandedAfter))
                    if Task.isCancelled { return }
                    clock.settleIfStranded(posture: posture)
                }
            }
    }
}

/// `onHingeChange` on iOS 27.1, mapped to `HingeStatus`; nothing below it.
private struct HingeListener: ViewModifier {
    let action: (HingeStatus?, HingeStatus?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { old, new in
                action(Self.status(old.hinge), Self.status(new.hinge))
            }
        } else {
            content
        }
    }

    @available(iOS 27.1, *)
    private static func status(_ hinge: DeviceHinge?) -> HingeStatus? {
        guard let s = hinge?.status else { return nil }
        if s == .closed { return .closed }
        if s == .fullyOpen { return .fullyOpen }
        return .partiallyOpen
    }
}
