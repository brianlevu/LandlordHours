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
