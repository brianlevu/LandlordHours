import SwiftUI

/// The confirm board: a 13-frame image sequence (bp_confirm_row_00...12, 30 fps) registered to
/// the hero canvas. A timber board slides into the newest siding course, overshoots once and
/// settles; the last frame is the exact rest position. Drawn over the house art at the same
/// square frame. Plays once per `runID`; calls `onSettle` on the last frame (the caller fires the
/// light haptic and updates the keyframe if a threshold was crossed).
struct ConfirmBuildAnimation: View {
    /// Change this to play the sequence again. nil shows nothing.
    let runID: UUID?
    /// DEBUG/capture: show one frame statically instead of playing.
    var stillFrame: Int? = nil
    var onSettle: () -> Void = {}

    @State private var frame: Int? = nil

    var body: some View {
        ZStack {
            if let index = stillFrame ?? frame {
                Image(decorative: HouseMotion.confirmFrameNames[max(0, min(index, HouseMotion.confirmFrameCount - 1))])
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: runID) {
            guard runID != nil, stillFrame == nil else { return }
            let frameNanos = UInt64(1_000_000_000 / HouseMotion.confirmFPS)
            for index in 0..<HouseMotion.confirmFrameCount {
                frame = index
                try? await Task.sleep(nanoseconds: frameNanos)
                if Task.isCancelled { return }
            }
            onSettle()
        }
    }
}

/// A confirm the hero should show: hours moved from `oldHours` to `newHours`.
struct HouseConfirmEvent: Equatable {
    let id = UUID()
    let oldHours: Double
    let newHours: Double
}
