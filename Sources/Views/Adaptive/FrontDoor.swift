import SwiftUI

// MARK: - FrontDoor: `duoUnfold`'s leaf, hall and step light (§B.3; DU14)
//
// Drawn over the hero in the house pane. The leaf is the still's own door pixels, masked to
// `DoorArt.doorRect(stage:)` and turned about its left edge in perspective; the hall behind it and
// the step pool rise with it. Every layer is a pure function of the clock's t, so the motion and a
// still at any t are the same thing. At rest t = 1 (open and lit); only a Duo hinge event moves it.
// Stages with no door rect draw nothing (the pane light still plays).

struct FrontDoor: View {
    let stage: CraftStage
    let side: CGFloat
    @ObservedObject var clock: DoorClock

    @Environment(\.colorScheme) private var colorScheme

    private var door: CGRect? {
        guard let px = DoorArt.doorRect(stage: stage) else { return nil }
        let k = side / DoorArt.stillSide
        return CGRect(x: px.minX * k, y: px.minY * k, width: px.width * k, height: px.height * k)
    }

    var body: some View {
        if let door {
            let t = clock.t
            let open = DoorMotion.ease(t, 0.0, 0.42)
            let glow = DoorMotion.ease(t, 0.05, 0.5)
            let dark = colorScheme == .dark
            let warm = DoorArt.warm(dark: dark)
            ZStack(alignment: .topLeading) {
                // The hall behind the door.
                Rectangle()
                    .fill(dark
                          ? AnyShapeStyle(LinearGradient(colors: [warm, warm.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LinearGradient(colors: [DoorArt.hallDuskTop, DoorArt.hallDuskBottom], startPoint: .top, endPoint: .bottom)))
                    .overlay {
                        if !dark {
                            RadialGradient(colors: [warm.opacity(0.75), .clear], center: UnitPoint(x: 0.65, y: 0.45),
                                           startRadius: 0, endRadius: door.height * 0.55)
                        }
                    }
                    .frame(width: door.width, height: door.height)
                    .offset(x: door.minX, y: door.minY)
                    .opacity(glow)
                // The step pool: a radial with 5 stops (no hard edge), sheared and turned with the leaf.
                let spill = door.width * 3.4
                RadialGradient(stops: [.init(color: warm.opacity(dark ? 0.62 : 0.42), location: 0),
                                       .init(color: warm.opacity(dark ? 0.40 : 0.27), location: 0.22),
                                       .init(color: warm.opacity(dark ? 0.19 : 0.13), location: 0.48),
                                       .init(color: warm.opacity(dark ? 0.06 : 0.03), location: 0.76),
                                       .init(color: warm.opacity(0), location: 1)],
                               center: .center, startRadius: 0, endRadius: spill / 2)
                    .frame(width: spill, height: spill * 0.62)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: 0.45 * open, d: 1, tx: 0, ty: 0))
                    .rotationEffect(.degrees(16 * open))
                    .offset(x: door.midX - spill / 2 + door.width * (0.5 + 0.9 * open),
                            y: door.maxY - spill * 0.62 / 2 + door.width * 0.5)
                    .blendMode(dark ? .plusLighter : .screen)
                    .opacity(glow)
                // The leaf: the still's own door pixels, swung on its left hinge.
                Image(stage.assetName(lit: true))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .brightness(dark ? CraftHouseView.nightLift(stage) : 0)
                    .mask(alignment: .topLeading) {
                        Rectangle().frame(width: door.width, height: door.height).offset(x: door.minX, y: door.minY)
                    }
                    .brightness(-0.12 * open)
                    .rotation3DEffect(.degrees(-78 * open), axis: (x: 0, y: 1, z: 0),
                                      anchor: UnitPoint(x: door.minX / side, y: door.midY / side), perspective: 2.2)
                    .shadow(color: .black.opacity(0.35 * open), radius: 1.5, x: 1, y: 0)
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
