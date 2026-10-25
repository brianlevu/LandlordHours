import SwiftUI

// MARK: - The interior wall (§1.27 two-pane; DU9, DU10, DU11, DU16)
//
// `InteriorWall` is the work pane's backdrop: the same page gradient as the house pane (so the gap
// or fold has no seam), round-1 A's room showing through by day (dusty, away from the gap; the
// `duo_interior` dusk image), and the door's warm pool at the gap. At night the room is not drawn:
// the navy page with one warm pool, which gives way beside the card edge (DU11 keeps the locked
// `duoNightCardEdge`). `FoldWash` mirrors the same pool ~150pt into the house pane, so the two walls
// meet the same way on the Duo and on iPad (DU9, DU16). `InsideLight` is the veil the unfold wipes
// away from the fold outward (Duo hinge only).

struct InteriorWall: View {
    /// Where the door's light comes from, in this view's unit space (the gap edge).
    var glowCenter = UnitPoint(x: 0, y: 0.38)
    /// false: no page of its own (the caller lays one continuous page under both panes).
    var page = true
    var glow = true
    /// How far outside the leading edge the fold's midline lies (half the gap when the wall is
    /// drawn inside the pane, 0 when it starts at the midline), so both walls share one profile.
    var foldInset: CGFloat = 0
    /// The fold runs across the top edge (stacked): the room fades in from the top, not the leading edge.
    var foldAbove = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { g in
            ZStack {
                if page { LHPage() }
                if !dark {
                    Image("duo_interior")
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                        .saturation(0.45)
                        .blendMode(.multiply)
                        .opacity(0.42)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.18),
                                                     .init(color: .black, location: 0.85)],
                                             startPoint: foldAbove ? .top : .leading, endPoint: foldAbove ? .bottom : .trailing))
                }
                if glow {
                    let horizontal = glowCenter.x < 0.25
                    let len = max(horizontal ? g.size.width : g.size.height, 1)
                    // Distances are measured from the fold's midline (DU9: one profile both sides).
                    let at: (CGFloat) -> CGFloat = { d in min(1, max(0, (d - foldInset) / len)) }
                    let center = horizontal ? UnitPoint(x: -foldInset / len, y: glowCenter.y)
                                            : UnitPoint(x: glowCenter.x, y: -foldInset / len)
                    RadialGradient(colors: [DoorArt.glow(dark: dark), .clear], center: center, startRadius: 0, endRadius: 370)
                        .blendMode(dark ? .plusLighter : .screen)
                        .mask {
                            // Night: full strength in the gap band, 12% from 14pt out (DU11).
                            LinearGradient(stops: dark
                                           ? [.init(color: .black, location: 0), .init(color: .black, location: at(6)),
                                              .init(color: .black.opacity(0.12), location: max(at(14), at(6) + 0.0001)),
                                              .init(color: .black.opacity(0.12), location: 1)]
                                           : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                           startPoint: horizontal ? .leading : .top, endPoint: horizontal ? .trailing : .bottom)
                        }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The door's light leaking back across the gap onto the house pane, the same colour and strength
/// as the interior wall at the gap, fading within ~150pt (DU10, DU16).
struct FoldWash: View {
    var center = UnitPoint(x: 1, y: 0.38)
    /// The axis the gap lies across: `.horizontal` = the gap is the trailing edge, `.vertical` = the bottom.
    var foldAxis: Axis = .horizontal

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { g in
            // ~150pt across the pane, and tall enough to reach the top of a tall iPad wall, so the
            // wash rises toward the fold at y = 60pt on every two-pane window (DU10, DU16).
            let along = foldAxis == .horizontal ? g.size.height : g.size.width
            let stretch = max(1, 1.1 * along * (foldAxis == .horizontal ? center.y : center.x) / 150)
            RadialGradient(colors: [DoorArt.glow(dark: dark), .clear], center: center, startRadius: 0, endRadius: 150)
                .scaleEffect(x: foldAxis == .horizontal ? 1 : stretch, y: foldAxis == .horizontal ? stretch : 1, anchor: center)
        }
            .blendMode(dark ? .plusLighter : .screen)
            .mask {
                GeometryReader { g in
                    let len = max(foldAxis == .horizontal ? g.size.width : g.size.height, 1)
                    // Night: the same profile as the interior wall at the fold (full within 6pt, 12% at
                    // 14pt), then easing to nothing ~110pt out, so the house-pane wall rises toward the
                    // fold (DU16) and meets the work pane's wall with no step (DU9).
                    LinearGradient(stops: dark
                                   ? [.init(color: .clear, location: 0), .init(color: .clear, location: max(0, 1 - 110 / len)),
                                      .init(color: .black.opacity(0.12), location: 1 - 14 / len),
                                      .init(color: .black, location: 1 - 6 / len), .init(color: .black, location: 1)]
                                   : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                   startPoint: foldAxis == .horizontal ? .leading : .top,
                                   endPoint: foldAxis == .horizontal ? .trailing : .bottom)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The work pane lights from the fold outward as the door opens: a dark veil whose edge travels
/// away from the fold. Fully clear at t = 1 (at rest), so it draws nothing outside an unfold.
struct InsideLight: View {
    @ObservedObject var clock: DoorClock

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let r = DoorMotion.ease(clock.t, 0.12, 0.76)
        let dark = colorScheme == .dark
        if r < 1 {
            (dark ? DoorArt.veilNight : DoorArt.veilDusk)
                .opacity(dark ? 0.78 : 0.70)
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .clear, location: max(0, r * 1.3 - 0.3)),
                                           .init(color: .black, location: min(1, r * 1.3))],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
