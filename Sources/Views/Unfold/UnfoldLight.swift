import SwiftUI

// MARK: - UnfoldLight: the work pane lights from the fold outward (standard §B.3 `duoUnfold` "Pane")
//
// A dark veil over the work pane whose edge travels away from the fold over t 0.12–0.76. The fold is
// at the pane's leading edge when the Duo is held open and at its top edge when it is propped, so the
// light always enters from the door's side (`FoldPosture.workPaneFoldEdge`). Under Reduce Motion the
// veil does not wipe: the whole veil fades out with the crossfade. At rest it draws nothing.
//
// The veil's colour and strength are art constants the caller passes (package J's `DoorArt.veilDusk`
// at 0.70, `DoorArt.veilNight` at 0.78), so this view keeps no hex of its own.

struct UnfoldLight: View {
    let pose: DoorPose
    let edge: FoldEdge
    /// The veil at full strength, opacity included.
    let veil: Color

    var body: some View {
        if pose.drawsVeil {
            let r = pose.paneReveal
            veil
                .opacity(pose.veilOpacity)
                .mask {
                    LinearGradient(stops: Self.stops(reveal: r),
                                   startPoint: edge == .leading ? .leading : .top,
                                   endPoint: edge == .leading ? .trailing : .bottom)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Clear from the fold to the wipe's soft edge, then the veil. The edge is 30% of the pane wide
    /// and runs off the far side as `reveal` reaches 1.
    static func stops(reveal r: Double) -> [Gradient.Stop] {
        let clearTo = max(0, min(1, r * 1.3 - 0.3))
        let veilFrom = max(clearTo, min(1, r * 1.3))
        return [.init(color: .clear, location: 0),
                .init(color: .clear, location: clearTo),
                .init(color: .black, location: veilFrom)]
    }
}

/// `UnfoldLight` that follows the clock itself, so only this overlay redraws on each frame of a run
/// (the layout that owns the clock holds it without observing it).
struct UnfoldLightOverlay: View {
    @ObservedObject var clock: UnfoldClock
    let edge: FoldEdge
    let veil: Color

    var body: some View {
        UnfoldLight(pose: clock.pose, edge: edge, veil: veil)
    }
}
