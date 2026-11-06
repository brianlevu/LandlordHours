import SwiftUI

// MARK: - RentalSkyline: the "All rentals" hero (standard §H.1 H10, §1.27 AD18)
//
// No single house, no stage and no goal. Each rental's own house-only render (`LHThumb`) at its
// own stage and its own lit state, in one row on one shared ground line, under one spill pool and
// one contact shadow. Ignores `stageScale` and `stageLift`. Cap 5 houses when the frame side is
// 290 or more, 4 under that; over the cap the most-behind rentals show first and nothing in the art
// counts the rest. Houses are never under 44pt. No `timberDrop`; a house whose stage changes takes
// `stageFade` and its windows take `windowsOn` (inside `LHThumb`).

struct RentalSkylineItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// The rental's own stage (`CraftStage.stage(hours:goal:)` on its own totals).
    let stage: CraftStage
    /// The rental's own `loggedToday`.
    let lit: Bool
    /// Hours behind its own pace (zero when on pace); orders the houses when over the cap.
    let behindBy: Double

    init(id: String, name: String, stage: CraftStage, lit: Bool, behindBy: Double = 0) {
        self.id = id
        self.name = name
        self.stage = stage
        self.lit = lit
        self.behindBy = behindBy.isFinite ? max(0, behindBy) : 0
    }
}

enum RentalSkylineLayout {
    /// Gap between houses as a fraction of the frame side.
    static let gapFraction: CGFloat = 0.04
    /// The ground line as a fraction of the frame, measured from the top (the asset's 92%).
    static let groundFraction: CGFloat = 0.92

    /// 5 houses when the frame side is 290 or more, else 4.
    static func cap(frame: CGFloat) -> Int { frame >= 290 ? 5 : 4 }

    /// `min(0.42 S, (0.92 S − 0.04 S (n − 1)) / n)`, never under 44.
    static func houseSide(frame: CGFloat, count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        let fit = (groundFraction * frame - gapFraction * frame * (n - 1)) / n
        return max(CraftHeroSize.thumbnailRow, min(0.42 * frame, fit))
    }

    /// The houses to draw, in the shelf's order. Over the cap, the most-behind rentals first
    /// (largest gap to their own pace, ties by shelf order) up to the cap.
    static func visible(_ items: [RentalSkylineItem], frame: CGFloat) -> [RentalSkylineItem] {
        let cap = cap(frame: frame)
        guard items.count > cap else { return items }
        let keep = items.enumerated()
            .sorted { a, b in a.element.behindBy != b.element.behindBy ? a.element.behindBy > b.element.behindBy : a.offset < b.offset }
            .prefix(cap)
            .map(\.offset)
        let set = Set(keep)
        return items.enumerated().filter { set.contains($0.offset) }.map(\.element)
    }
}

struct RentalSkyline: View {
    let items: [RentalSkylineItem]
    /// The hero frame side (390 on a 402 window, 220 at AX, 287 on the closed Duo).
    let side: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var shown: [RentalSkylineItem] { RentalSkylineLayout.visible(items, frame: side) }
    private var anyLit: Bool { shown.contains { $0.lit } }

    var body: some View {
        let houses = shown
        let houseSide = RentalSkylineLayout.houseSide(frame: side, count: houses.count)
        ZStack {
            spillPool
            contactShadow
            VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: RentalSkylineLayout.gapFraction * side) {
                ForEach(houses) { item in
                    LHThumb(stage: item.stage, lit: item.lit, size: houseSide)
                        .animation(reduceMotion ? nil : AppAnimation.stageFade, value: item.stage)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(item.name). \(CraftHouseView.accessibilityLabel(stage: item.stage, lit: item.lit))"))
                        .accessibilityAddTraits(.isImage)
                }
            }
            // Every house stands on the shared ground line, 92% of the way down the frame.
            .padding(.bottom, side * (1 - RentalSkylineLayout.groundFraction))
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("craft.skyline")
    }

    private var windowsAnimation: Animation { reduceMotion ? AppAnimation.windowsReduced : AppAnimation.windows }

    /// The page's warm pool under the row; × 0.2 when no window is lit.
    private var spillPool: some View {
        let spill = colors.spillPool
        return Circle()
            .fill(RadialGradient(colors: [spill, spill.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.48))
            .frame(width: side * 0.96, height: side * 0.96)
            .scaleEffect(y: 0.34)
            .offset(y: side * (RentalSkylineLayout.groundFraction - 0.54))   // centred just above the ground line
            .opacity(anyLit ? 1 : 0.2)
            .animation(windowsAnimation, value: anyLit)
            .accessibilityHidden(true)
    }

    /// One contact shadow under the whole row.
    private var contactShadow: some View {
        Ellipse()
            .fill(colors.contactShadow)
            .frame(width: side * 0.92, height: side * 0.07)
            .blur(radius: side * 0.035)
            .offset(y: side * (RentalSkylineLayout.groundFraction - 0.5))
            .accessibilityHidden(true)
    }
}
