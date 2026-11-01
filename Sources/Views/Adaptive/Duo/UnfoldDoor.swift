import Foundation

// MARK: - UnfoldDoor: `duoUnfold` as pure logic (standard §B.2 `duoDoor`, §B.3, §1.27 Motion)
//
// The door clock t runs 0 (door shut, work pane dark) → 1 (door open, pane lit; the state at rest
// everywhere). It moves on a hinge event and nothing else: never on a resize, an arrangement change,
// a scene change or a cold launch already open, so an iPad never plays it.
//
//   closed → partiallyOpen / fullyOpen   t → 1, linear, 0.80 s (the rest of it when t is mid-run)
//   open → closed                        t → 0, linear, 0.50 s (its share when mid-run)
//   Reduce Motion, either way            a 0.20 s crossfade between the closed and the lit end state
//   partiallyOpen ↔ fullyOpen            nothing (the door does not replay as the hinge widens)
//   a touch while 0 < t < 1              t = 1 (the layout is live and hit-testable from frame 0)
//   a fold with t < 1 and no run ≥ 1 s   t = 1 (`isStranded`: a missed open event never leaves the
//                                        work pane veiled; must-prove 3), also on returning to the
//                                        foreground
//   no fold, hinge known closed          t = 0 (`restsShut`: the next unfold plays from shut)
//
// `DoorPose` turns t into each layer's value: the leaf turns over t 0–0.42 (78°, darkening 0.12, a
// 0.35 shadow), the hall and step light rise over 0.05–0.50, the work pane's veil wipes away from the
// fold over 0.12–0.76, each an ease-out cubic of t over its own window. Under Reduce Motion the open
// door layer fades in over the closed still and the veil fades out: no leaf turn, no wipe.

enum UnfoldStyle: Equatable, Sendable {
    /// The door swings and the pane lights from the fold outward.
    case swing
    /// Reduce Motion: a crossfade from the closed state to the lit end state.
    case crossfade
}

/// One run of the door clock.
struct UnfoldMove: Equatable, Sendable {
    let from: Double
    let to: Double
    let duration: Double
    let style: UnfoldStyle

    /// t after `elapsed` seconds: linear (`duoDoor` is `.linear`; the easing lives in each layer).
    func value(at elapsed: Double) -> Double {
        guard duration > 0, elapsed.isFinite else { return to }
        let u = min(max(elapsed / duration, 0), 1)
        return from + (to - from) * u
    }

    func isFinished(at elapsed: Double) -> Bool { elapsed >= duration }
}

enum UnfoldDoor {
    /// `duoDoor`: 0.80 s open, 0.50 s back on fold, 0.20 s crossfade under Reduce Motion.
    static let openDuration: Double = 0.80
    static let closeDuration: Double = 0.50
    static let reducedDuration: Double = 0.20
    /// How long a fold may show a door short of open with no run before it settles lit.
    static let strandedAfter: Double = 1.0

    /// The run a hinge change starts, or nil when it moves nothing.
    /// - Parameters:
    ///   - old: the hinge before the change; nil on the first report (a cold launch).
    ///   - new: the hinge after it; nil when the scene has no hinge.
    ///   - current: the clock now (a fold or unfold may interrupt a run).
    static func move(from old: HingeStatus?, to new: HingeStatus?, reduceMotion: Bool, current: Double) -> UnfoldMove? {
        guard let old, let new, old != new, old.isOpen != new.isOpen else { return nil }
        let t = current.isFinite ? min(max(current, 0), 1) : 0
        let target: Double = new.isOpen ? 1 : 0
        guard t != target else { return nil }
        if reduceMotion {
            return UnfoldMove(from: t, to: target, duration: reducedDuration, style: .crossfade)
        }
        let full = new.isOpen ? openDuration : closeDuration
        return UnfoldMove(from: t, to: target, duration: full * abs(target - t), style: .swing)
    }

    /// A touch during a run jumps the door to its end; nil when there is nothing to finish.
    static func touch(current: Double) -> Double? {
        guard current.isFinite, current > 0, current < 1 else { return nil }
        return 1
    }

    /// True when a fold shows the door short of open with nothing running to open it, for long
    /// enough that the open event was missed. `secondsSinceHingeEvent` nil = no event seen yet.
    static func isStranded(current: Double, running: Bool, posture: FoldPosture, secondsSinceHingeEvent: Double?) -> Bool {
        guard posture.hostsDoor, !running, current < 1 else { return false }
        guard let since = secondsSinceHingeEvent else { return true }
        return since >= strandedAfter
    }

    /// True when the door should rest shut without a run: the window is on a display with no fold and
    /// the hinge is known to be closed (the outer display). Never on a cold launch (no report yet).
    static func restsShut(posture: FoldPosture, hinge: HingeStatus?, running: Bool) -> Bool {
        !running && !posture.hostsDoor && hinge == .closed
    }

    /// Ease-out cubic of `t` over its own window [a, b].
    static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = min(max((t - a) / (b - a), 0), 1)
        return 1 - pow(1 - u, 3)
    }
}

/// Every door layer's value at one instant. A still at any t and the live motion are the same thing.
struct DoorPose: Equatable, Sendable {
    /// The leaf's turn, 0 (shut) … 1 (open, 78°).
    let leafTurn: Double
    /// The hall behind the door and the light on the step, 0 … 1.
    let doorLight: Double
    /// How far the work pane's veil has wiped away from the fold, 0 … 1.
    let paneReveal: Double
    /// The open-door layer (hall, step light, turned leaf) over the house's own closed door.
    let doorLayerOpacity: Double
    /// The veil's own opacity multiplier (the crossfade fades it; the swing wipes it).
    let veilOpacity: Double

    /// The leaf turns this far about its hinge edge (`rotation3DEffect`, perspective 2.2).
    static let leafAngle: Double = 78
    static let leafDarkening: Double = 0.12
    static let leafShadowOpacity: Double = 0.35

    var leafAngleDegrees: Double { -Self.leafAngle * leafTurn }
    var leafDarken: Double { -Self.leafDarkening * leafTurn }
    var leafShadow: Double { Self.leafShadowOpacity * leafTurn }

    /// True while any part of the work pane is still veiled.
    var drawsVeil: Bool { paneReveal < 1 && veilOpacity > 0 }
    var isAtRest: Bool { !drawsVeil && leafTurn >= 1 && doorLight >= 1 }

    static let rest = DoorPose(t: 1, style: .swing)

    /// - Parameter hasDoor: false for the framing stages and "All rentals" (the skyline): the pane
    ///   light still plays, the door layer draws nothing.
    init(t rawT: Double, style: UnfoldStyle, hasDoor: Bool = true) {
        let t = rawT.isFinite ? min(max(rawT, 0), 1) : 1
        switch style {
        case .swing:
            leafTurn = UnfoldDoor.ease(t, 0.0, 0.42)
            doorLight = UnfoldDoor.ease(t, 0.05, 0.50)
            paneReveal = UnfoldDoor.ease(t, 0.12, 0.76)
            doorLayerOpacity = hasDoor ? 1 : 0
            veilOpacity = 1
        case .crossfade:
            leafTurn = 1
            doorLight = 1
            paneReveal = 0                     // no wipe: the whole veil fades

            doorLayerOpacity = hasDoor ? t : 0
            veilOpacity = 1 - t
        }
    }
}
