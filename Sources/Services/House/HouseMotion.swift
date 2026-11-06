import Foundation
import CoreGraphics

// MARK: - House motion plan (pure, testable)
//
// Every timing the house views use lives here so the Reduce Motion paths and the concept's limits
// (celebrations under 3 s, backfill sketch-in at most 2.5 s, confirm beam ~180 ms, board 13 frames
// at 30 fps) are unit-tested rather than buried in view code. Specs:
// docs/design/2.0-concepts-blueprint.md §1 "Motion", and the confirm_row note in
// design/blueprint-house/exports/manifest.json.

/// How a change between two keyframes is shown.
enum HouseKeyframeTransition: Equatable, Sendable {
    /// Instant swap (Reduce Motion, or no keyframe change).
    case instant
    /// Crossfade over `duration` seconds.
    case crossfade(duration: Double)
}

/// What a confirm does on the hero. The house only ever grows: a board is shown only when the
/// confirm crosses into a new siding keyframe (the board then becomes that keyframe), so no course
/// appears and then vanishes.
struct HouseConfirmPlan: Equatable, Sendable {
    /// A timber beam flies from the number into the house (~180 ms spring).
    var beam: Bool
    /// The board sequence, shifted by this unit offset onto the new course; nil = no board.
    var boardOffset: CGFloat?
    /// A warm glow pulses on the newest course after landing.
    var glow: Bool
    /// The hero number counts up with a small pop (otherwise it changes in place).
    var countUp: Bool
    /// How the keyframe changes after landing.
    var keyframe: HouseKeyframeTransition
    /// The keyframe the house ends on.
    var target: HouseKeyframe
    /// Where the beam lands and the glow pulses (unit point in the 320 pt camera).
    var anchor: CGPoint

    /// Nothing to show (hours unchanged or removed).
    var isEmpty: Bool { !beam && boardOffset == nil && !glow && !countUp }
}

enum HouseMotion {
    /// The confirm board sequence (manifest `confirm_row`).
    static let confirmFrameCount = 13
    static let confirmFPS: Double = 30
    static var confirmSequenceDuration: Double { Double(confirmFrameCount) / confirmFPS }

    /// Confirm beam: spring(0.32, 0.86) per the concept, landing in ~180 ms.
    static let beamSpringResponse: Double = 0.32
    static let beamSpringDamping: Double = 0.86
    static let beamFlight: Double = 0.18
    /// Glow on the newest course: up in 120 ms, down over 480 ms.
    static let glowIn: Double = 0.12
    static let glowOut: Double = 0.48
    /// Count-up: whole-hour steps over at most this long, with a 1.12 pop.
    static let countUpMax: Double = 0.36
    static let countPopScale: Double = 1.12

    /// Crossfade between keyframes when hours change.
    static let keyframeCrossfade: Double = 0.35
    /// WP-L: the drafting loader hands over to the real house (crossfade), then the number
    /// counts up from 0 over `loadCountUp`.
    static let loadCrossfade: Double = 0.28
    static let loadCountUp: Double = 0.5
    /// The board fades out as its keyframe crossfades in.
    static let boardFadeOut: Double = 0.18

    /// Day-1 backfill: linework sketches in, then the found hours hatch in. Total ≤ 2.5 s.
    static let backfillLeadIn: Double = 0.15
    static let backfillSketchDuration: Double = 0.8
    static let backfillHatchDelay: Double = 0.55     // after the lead-in
    static let backfillHatchDuration: Double = 1.5
    static var backfillTotalDuration: Double { backfillLeadIn + backfillHatchDelay + backfillHatchDuration }
    /// One light tap per this many found hours during the reveal.
    static let backfillHapticStepHours: Double = 50

    /// Milestones: everything settles well under the 3 s celebration cap.
    static let milestoneLeadIn: Double = 0.35
    /// 500h: the roof drops from 12 pt above (spring 0.55 / 0.72) and terracotta fills 600 ms.
    static let roofDropPoints: Double = 12
    static let roofSpringResponse: Double = 0.55
    static let roofSpringDamping: Double = 0.72
    static let roofLandingDelay: Double = 0.38
    static let roofFillDuration: Double = 0.6
    /// 100h: the slab cures over 800 ms.
    static let slabCureDuration: Double = 0.8
    /// Keys moment: the windows light over 1.2 s and the key swings 10 degrees.
    static let windowsLightDuration: Double = 1.2
    static let plaqueDelay: Double = 0.45
    /// Reduce Motion: everything crossfades together in 200 ms.
    static let reducedCrossfade: Double = 0.2

    static func celebrationSettleDuration(_ celebration: HouseCelebration, reduceMotion: Bool) -> Double {
        if reduceMotion { return reducedCrossfade }
        switch celebration {
        case .stage(.foundation100): return milestoneLeadIn + slabCureDuration + plaqueDelay
        case .stage(.roof500): return milestoneLeadIn + roofLandingDelay + roofFillDuration + plaqueDelay
        case .stage(.keys750), .goalMet: return milestoneLeadIn + windowsLightDuration + plaqueDelay
        }
    }

    static func keyframeTransition(from old: HouseKeyframe, to new: HouseKeyframe, reduceMotion: Bool) -> HouseKeyframeTransition {
        guard old != new, !reduceMotion else { return .instant }
        return .crossfade(duration: keyframeCrossfade)
    }

    /// The plan for a confirm that moves the house from `oldHours` to `newHours`.
    static func confirmPlan(oldHours: Double, newHours: Double, reduceMotion: Bool) -> HouseConfirmPlan {
        let old = HouseProgress.keyframe(for: oldHours)
        let new = HouseProgress.keyframe(for: newHours)
        guard newHours > oldHours else {
            return HouseConfirmPlan(beam: false, boardOffset: nil, glow: false, countUp: false,
                                    keyframe: .instant, target: new, anchor: new.courseAnchor)
        }
        if reduceMotion {
            // No flight, no board, no pulse; the number and the house change in place.
            return HouseConfirmPlan(beam: false, boardOffset: nil, glow: false, countUp: false,
                                    keyframe: .instant, target: new, anchor: new.courseAnchor)
        }
        let crosses = old != new
        return HouseConfirmPlan(
            beam: true,
            boardOffset: crosses ? new.confirmBoardOffset : nil,
            glow: true,
            countUp: true,
            keyframe: keyframeTransition(from: old, to: new, reduceMotion: false),
            target: new,
            anchor: new.courseAnchor
        )
    }

    /// Confirm board frame names in play order.
    static let confirmFrameNames: [String] = (0..<confirmFrameCount).map { String(format: "bp_confirm_row_%02d", $0) }

    /// Linework alpha gain. The exported linework carries strokes at 0.36 alpha (fill 0.08), which
    /// measured 2.2:1 on the blueprint card. ×2.4 lifts strokes to ~0.86 (#8FD3FF ≈ 4.5:1 on
    /// #1E3FA6, the concept's ~4.3:1) and the ghost fill to ~0.19.
    static let lineworkAlphaGain: Double = 2.4
}

// MARK: - v2: the crafted house's motion (standard §H.6, §B.2, §B.3; plan package 0a)
//
// Two moves, in this order, then stillness: the 39-piece timber drop, then the windows coming on.
// `CraftHouseView` (package A) plays what `CraftMotion.plan` returns; the stage-motion choice lives
// in the one switch below, so no view keeps its own copy of the rule.

/// How a stage change is shown.
enum CraftStageMotion: Equatable, Sendable {
    /// No stage change.
    case none
    /// The pre-rendered framing clip: fade in over the still, play, crossfade to `craft_framing`.
    case timberDrop
    /// A 0.25 s crossfade with a 0.97 → 1 scale settle (a 0.15 s crossfade under Reduce Motion).
    case stageFade
}

/// What one log or confirm does to the hero.
struct CraftMotionPlan: Equatable, Sendable {
    var from: CraftStage
    var to: CraftStage
    var stageMotion: CraftStageMotion
    /// The windows fade on (the first log of the day for the shown rental).
    var windowsOn: Bool
    /// Seconds from the start of the plan until the windows start to fade on.
    var windowsDelay: Double
    /// The windows' fade length (linear under Reduce Motion).
    var windowsDuration: Double
    /// The build clip is dimmed to the unlit still's mean luma while the windows are held dark.
    var holdsWindowsDarkThroughDrop: Bool
    /// The one wood-knock haptic as the last timber lands (kept under Reduce Motion).
    var knock: Bool

    /// Total seconds until the hero is still again.
    var totalDuration: Double {
        let stageEnd: Double
        switch stageMotion {
        case .none: stageEnd = 0
        case .timberDrop: stageEnd = CraftMotion.dropFadeIn + CraftMotion.dropClip + CraftMotion.dropCrossfade
        case .stageFade: stageEnd = CraftMotion.stageFadeDuration
        }
        return max(stageEnd, windowsOn ? windowsDelay + windowsDuration : 0)
    }

    var isEmpty: Bool { stageMotion == .none && !windowsOn }
}

enum CraftMotion {
    // Timings (seconds). Spec: §H.6 and the §B.2 tokens.
    /// The clip fades in over the still.
    static let dropFadeIn: Double = 0.20
    /// The clip: 60 frames at 30 fps.
    static let dropClip: Double = 2.0
    /// The clip crossfades to `craft_framing`.
    static let dropCrossfade: Double = 0.30
    /// `stageFade`: crossfade with a 0.97 → 1 scale settle.
    static let stageFadeDuration: Double = 0.25
    static let stageFadeStartScale: Double = 0.97
    /// Reduce Motion: no clip, no scale; the still crossfades.
    static let reducedStageCrossfade: Double = 0.15
    /// `windowsOn`: the lit still fades over the unlit one (and the spill pool with it).
    static let windowsFade: Double = 0.40
    /// Without a drop the windows start this long after the still settles.
    static let windowsAfterSettle: Double = 0.30
    /// `rentalSlide`: 0.30 spring, bounce 0; a 0.20 fade under Reduce Motion.
    static let rentalSlide: Double = 0.30
    static let reducedRentalFade: Double = 0.20
    /// The lit clip held dark through a first-of-day drop, multiplied to the unlit still's mean luma.
    static let clipDimNight: Double = 0.66
    static let clipDimDusk: Double = 0.76

    /// The one switch: which motion carries a stage change from `old` to `new` (§H.6, "one log, two
    /// or more stages"). The house never plays the stages in between: any change that ends at
    /// `framing` from an earlier stage plays the drop (its fade-in covers the jump); every other
    /// change is one `stageFade`. Lower hours (a delete) never play the drop.
    static func stageMotion(from old: CraftStage, to new: CraftStage) -> CraftStageMotion {
        switch (old, new) {
        case _ where old == new: return .none
        case (.started, .framing), (.frame70, .framing): return .timberDrop
        default: return .stageFade
        }
    }

    /// The plan for a save that moves the shown rental from `oldHours` to `newHours` against `goal`.
    /// - Parameters:
    ///   - wasLit: the windows were lit before the save (hours already logged today).
    ///   - isLit: the windows are lit after it (`TodayWindowState.loggedToday`).
    ///   - dropAlreadyPlayed: this rental already played its drop for this stage (once per stage per
    ///     rental); the change is then a `stageFade`.
    static func plan(oldHours: Double, newHours: Double, goal: Double,
                     wasLit: Bool, isLit: Bool,
                     reduceMotion: Bool, dropAlreadyPlayed: Bool = false) -> CraftMotionPlan {
        let from = CraftStage.stage(hours: oldHours, goal: goal)
        let to = CraftStage.stage(hours: newHours, goal: goal)
        var motion = stageMotion(from: from, to: to)
        if motion == .timberDrop && (dropAlreadyPlayed || reduceMotion) { motion = .stageFade }
        let windowsOn = isLit && !wasLit
        let settle: Double
        switch motion {
        case .none: settle = 0
        case .timberDrop: settle = dropFadeIn + dropClip + dropCrossfade
        case .stageFade: settle = reduceMotion ? reducedStageCrossfade : stageFadeDuration
        }
        // After a drop the windows fade on straight after the crossfade; otherwise 0.30 s after the
        // still settles.
        let delay = motion == .timberDrop ? settle : settle + windowsAfterSettle
        let isDrop = motion == .timberDrop
        // Reduce Motion keeps the knock when the drop would have played (the still crossfades).
        let wouldDrop = stageMotion(from: from, to: to) == .timberDrop && !dropAlreadyPlayed
        return CraftMotionPlan(
            from: from, to: to, stageMotion: motion,
            windowsOn: windowsOn,
            windowsDelay: windowsOn ? delay : 0,
            windowsDuration: windowsOn ? windowsFade : 0,
            holdsWindowsDarkThroughDrop: isDrop && windowsOn,
            knock: wouldDrop
        )
    }

    /// The build clip's brightness multiplier: 1 when the windows are lit, else the unlit still's mean luma.
    static func clipDim(windowsLit: Bool, dark: Bool) -> Double {
        windowsLit ? 1 : (dark ? clipDimNight : clipDimDusk)
    }
}
