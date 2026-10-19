import Foundation

// MARK: - House motion plan (pure, testable)
//
// Every timing the house views use lives here so the Reduce Motion paths and the concept's limits
// (celebrations under 3 s, backfill sketch-in at most 2.5 s, confirm board 13 frames at 30 fps) are
// unit-tested rather than buried in view code. Specs: docs/design/2.0-concepts-blueprint.md §1
// "Motion", and the confirm_row note in design/blueprint-house/exports/manifest.json.

/// How a change between two keyframes is shown.
enum HouseKeyframeTransition: Equatable, Sendable {
    /// Instant swap (Reduce Motion, or no keyframe change).
    case instant
    /// Crossfade over `duration` seconds.
    case crossfade(duration: Double)
}

/// What a confirm does on the hero.
enum HouseConfirmPlan: Equatable, Sendable {
    /// No visible change and no haptic (zero or negative hours).
    case none
    /// Play the 13-frame board overlay, light haptic at settle, then update the keyframe if needed.
    case boardSequence(frames: Int, fps: Double, thenKeyframe: HouseKeyframeTransition)
    /// No board: the keyframe change (if any) crossfades; light haptic. Used when the house has
    /// no built course for the board to land on yet (lot, slab, low frame) or the house is finished.
    case crossfadeOnly(HouseKeyframeTransition)
    /// Reduce Motion: no board, keyframe swaps instantly, haptic still fires.
    case instantSwap
}

enum HouseMotion {
    /// The confirm board sequence (manifest `confirm_row`).
    static let confirmFrameCount = 13
    static let confirmFPS: Double = 30
    static var confirmSequenceDuration: Double { Double(confirmFrameCount) / confirmFPS }

    /// Crossfade between keyframes when hours change.
    static let keyframeCrossfade: Double = 0.35
    /// The board fades out after it settles and the house has taken the course.
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
    /// 750h: the windows light over 1.2 s.
    static let windowsLightDuration: Double = 1.2
    static let plaqueDelay: Double = 0.45
    /// Reduce Motion: everything crossfades together over 200 ms.
    static let reducedCrossfade: Double = 0.2

    static func milestoneSettleDuration(_ milestone: HouseMilestone, reduceMotion: Bool) -> Double {
        if reduceMotion { return reducedCrossfade }
        switch milestone {
        case .foundation100: return milestoneLeadIn + slabCureDuration + plaqueDelay
        case .roof500: return milestoneLeadIn + roofLandingDelay + roofFillDuration + plaqueDelay
        case .keys750: return milestoneLeadIn + windowsLightDuration + plaqueDelay
        }
    }

    static func keyframeTransition(from old: HouseKeyframe, to new: HouseKeyframe, reduceMotion: Bool) -> HouseKeyframeTransition {
        guard old != new, !reduceMotion else { return .instant }
        return .crossfade(duration: keyframeCrossfade)
    }

    /// The plan for a confirm that moves the house from `oldHours` to `newHours`.
    static func confirmPlan(oldHours: Double, newHours: Double, reduceMotion: Bool) -> HouseConfirmPlan {
        guard newHours > oldHours else { return .none }
        if reduceMotion { return .instantSwap }
        let old = HouseProgress.keyframe(for: oldHours)
        let new = HouseProgress.keyframe(for: newHours)
        let then = keyframeTransition(from: old, to: new, reduceMotion: false)
        if old.supportsConfirmBoard {
            return .boardSequence(frames: confirmFrameCount, fps: confirmFPS, thenKeyframe: then)
        }
        return .crossfadeOnly(then)
    }

    /// Confirm board frame names in play order.
    static let confirmFrameNames: [String] = (0..<confirmFrameCount).map { String(format: "bp_confirm_row_%02d", $0) }
}
