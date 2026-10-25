import SwiftUI
import UIKit

// MARK: - LHThumb: the house-only thumbnail (standard §H.3, §H.5)
//
// `craft_thumb_<stage>`: the house only (camera framed at 90% of the house's bounding box, no lot,
// contact shadow only), Any = dusk, Dark = night, lit only. Sizes: 44 in rental rows and Reports
// rows, 56 in picker grids and sheet headers, 120 on the onboarding step, and
// the widgets. Never under 44: the diorama with its lot is never shown under 220.
//
// Lit state by `loggedToday`: the asset is lit only, so an unlit thumbnail is the lit render
// multiplied to the unlit still's mean luma (the same 0.76 dusk / 0.66 night the build clip uses
// while the windows are held dark).
//
// Fallback until the art lane renders the thumbnails: the lit still, cropped to the house (the top
// 92% of the still, centred, so the ground line sits at the bottom edge). The lot's front edge
// shows; `asset_check.py` reports the missing `craft_thumb_*` sets.

struct LHThumb: View {
    let stage: CraftStage
    var lit = true
    var size: CGFloat = CraftHeroSize.thumbnailRow

    @Environment(\.colorScheme) private var colorScheme

    init(stage: CraftStage, lit: Bool = true, size: CGFloat = CraftHeroSize.thumbnailRow) {
        self.stage = stage
        self.lit = lit
        self.size = max(size, CraftHeroSize.thumbnailRow)
    }

    /// 44 in rows.
    static func row(_ stage: CraftStage, lit: Bool) -> LHThumb { LHThumb(stage: stage, lit: lit, size: CraftHeroSize.thumbnailRow) }
    /// 56 in sheet headers and picker grids.
    static func header(_ stage: CraftStage, lit: Bool) -> LHThumb { LHThumb(stage: stage, lit: lit, size: CraftHeroSize.thumbnailHeader) }
    /// 120 on the onboarding step, and the widgets.
    static func large(_ stage: CraftStage, lit: Bool) -> LHThumb { LHThumb(stage: stage, lit: lit, size: CraftHeroSize.thumbnailLarge) }

    static func hasThumbnail(_ stage: CraftStage) -> Bool { UIImage(named: stage.thumbnailName) != nil }

    private var dim: Double { CraftMotion.clipDim(windowsLit: lit, dark: colorScheme == .dark) }

    var body: some View {
        Group {
            if Self.hasThumbnail(stage) {
                Image(stage.thumbnailName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                // Interim crop of the still: the house fills the square, the ground line at the bottom.
                Image(stage.assetName(lit: true))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(1.5, anchor: UnitPoint(x: 0.5, y: CraftStage.groundLine))
                    .offset(y: size * (1 - CraftStage.groundLine))
            }
        }
        .colorMultiply(Color(white: dim))
        .animation(AppAnimation.windows, value: lit)
        .frame(width: size, height: size)
        .clipped()
        .accessibilityLabel(CraftHouseView.accessibilityLabel(stage: stage, lit: lit))
    }
}
