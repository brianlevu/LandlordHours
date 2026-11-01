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

    /// True while a run is on the display link (published, so the touch gesture follows it).
    @Published private(set) var isRunning = false

    private var move: UnfoldMove? { didSet { if isRunning != (move != nil) { isRunning = move != nil } } }
    private var began: CFTimeInterval = 0
    private var link: CADisplayLink?

    init(t: Double = 1) { self.t = min(max(t.isFinite ? t : 1, 0), 1) }

    /// Every door layer's value now.
    var pose: DoorPose { DoorPose(t: t, style: style) }
    /// The same for a hero with no door (framing stages, the "All rentals" skyline).
    func pose(hasDoor: Bool) -> DoorPose { DoorPose(t: t, style: style, hasDoor: hasDoor) }

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

    /// The window's fold changed. Folded onto the outer display with the hinge known closed, the door
    /// rests shut, so the next unfold plays from 0 even if a settle had lit it (a cold launch, with no
    /// hinge report yet, is left lit).
    func postureChanged(to posture: FoldPosture) {
        guard UnfoldDoor.restsShut(posture: posture, hinge: hinge, running: isRunning), t != 0 else { return }
        t = 0
        style = .swing
    }

    // MARK: Running

    func run(_ move: UnfoldMove) {
        stop()
        style = move.style
        t = move.from
        self.move = move
        began = CACurrentMediaTime()
        let proxy = DisplayLinkProxy { [weak self] in
            guard let self else { return false }
            self.tick()
            return true
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
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

/// `CADisplayLink` retains its target; the proxy keeps the clock free to go away. The clock invalidates
/// the link when a run ends or a new one starts; if the clock itself is gone, the proxy does.
private final class DisplayLinkProxy: NSObject {
    /// Returns false once its owner is gone.
    private let action: @MainActor () -> Bool

    init(_ action: @escaping @MainActor () -> Bool) { self.action = action }

    @objc func step(_ link: CADisplayLink) {
        let alive = MainActor.assumeIsolated { action() }
        if !alive { link.invalidate() }
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
    @Environment(\.scenePhase) private var scenePhase

    /// Re-checked whenever the fold changes or the door comes to rest short of open.
    private struct StrandKey: Equatable {
        let posture: FoldPosture
        let idleShort: Bool
    }

    func body(content: Content) -> some View {
        content
            .modifier(HingeListener { old, new in
                clock.hingeChanged(from: old, to: new, reduceMotion: reduceMotion)
            })
            // Any touch mid-run (a tap, the start of a scroll) jumps the door to its end. At rest only
            // the subviews' own gestures run (`.none` would switch off every tap in the app).
            .simultaneousGesture(LongPressGesture(minimumDuration: 0, maximumDistance: .infinity).onEnded { _ in clock.finish() },
                                 including: clock.isRunning ? .all : .subviews)
            .onChange(of: posture) { _, new in clock.postureChanged(to: new) }
            .onChange(of: scenePhase) { _, phase in
                // Back from the background: an unfold that happened meanwhile sent no event here.
                if phase == .active { clock.settleIfStranded(posture: posture) }
            }
            .task(id: StrandKey(posture: posture, idleShort: !clock.isRunning && clock.t < 1)) {
                // Must-prove 3: if the open event is missed while the window changes display, the door
                // must not stay shut over a lit fold.
                guard posture.hostsDoor, !clock.isRunning, clock.t < 1 else { return }
                try? await Task.sleep(for: .seconds(UnfoldDoor.strandedAfter))
                if Task.isCancelled { return }
                clock.settleIfStranded(posture: posture)
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
