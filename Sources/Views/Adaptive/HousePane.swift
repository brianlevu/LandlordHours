import SwiftUI

// MARK: - HousePane: the left (two-pane) or top (stacked) pane (§1.27 "What sits where"; DU6)
//
// The selected rental's lit diorama (or the skyline on "All rentals", H10), the shared number block
// (`HouseNumberBlock`, A2), the pace sentence, then the timber shelf. Nothing else here is operable
// except the account menu (Reports, Settings) at the top trailing, which opens in the right pane.
// The house pane is the same view in every tab: switching tabs never moves or re-lays the house.
//
// iPad sizing (plan J, 2026-10-25): the hero, the numeral and the shelf scale with the pane, and
// the column spreads its free height into three equal bands (above the house, between the number
// and the shelf, below the shelf), so no band of empty wall exceeds 20% of the pane (DU4, DU6).

struct HousePane: View {
    let split: LayoutSplit
    /// Plays the door on the hero (the Duo only; never on iPad).
    var showsDoor = false
    /// The window's top inset when the pane runs to the window's top edge (stacked ignores the
    /// safe area so the halves meet at the fold); 0 when the pane already sits inside it.
    var topInset: CGFloat = 0
    @ObservedObject var clock: DoorClock

    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var goalManager: GoalManager
    @EnvironmentObject private var selection: AdaptiveSelection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("today.focus") private var rememberedFocus = ""
    @State private var slideEdge: Edge = .trailing
    /// The scrolling column's hero and number block height (the shelf starts below the fold).
    @State private var leadHeight: CGFloat = 0

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var pane: CGRect { split.first }
    private var stacked: Bool { split.mode == .stacked }
    private var isRecord: Bool { goalManager.goalChoice == .record }

    /// The share of the skyline's frame kept in a pane (the houses, their pool and shadow).
    static let skylineShare: CGFloat = 0.6

    private var shelf: HouseShelf { HouseShelf.live(app: viewModel, goal: goalManager.houseGoal, isRecord: isRecord) }

    private var heroSide: CGFloat {
        stacked ? PaneMetrics.stackedHeroSide(accessibility: ax)
                : PaneMetrics.heroSide(paneWidth: pane.width, paneHeight: pane.height, accessibility: ax)
    }

    private var numeral: CGFloat {
        PaneMetrics.numeral(mode: split.mode, paneWidth: pane.width, paneHeight: pane.height, accessibility: ax)
    }

    var body: some View {
        let shelf = self.shelf
        let shown = shelf.resolved(selection.selectedID)
        // DU6/DU15: the hero, the number, the pace sentence and the shelf ("All rentals" first) all
        // sit in the pane at rest. When the column does not fit (a short pane, XXL, AX), the house
        // art steps down toward its floor (the diorama's 220, §H.5; the skyline's 44pt houses)
        // before anything scrolls, so the key figure and its sentence are never cut or faded at
        // rest (gate J r2). Only when even the floor does not fit does the whole column scroll,
        // from the top, with no fade: the shelf then waits below the fold.
        ViewThatFits(in: .vertical) {
            ForEach(heroSides(shelf, shown), id: \.self) { side in
                resting(shelf, shown, side: side)
            }
            scrolling(shelf, shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { accountMenu.padding(.trailing, PaneMetrics.gutter(paneWidth: pane.width, onDuo: split.isDivision) - 8) }
        .padding(.top, topInset)
        .onAppear(perform: restoreFocus)
        .onChange(of: selection.selectedID) { old, new in
            rememberedFocus = new
            let items = shelf.items
            let from = items.firstIndex { $0.id == old } ?? 0
            let to = items.firstIndex { $0.id == new } ?? 0
            slideEdge = to >= from ? .trailing : .leading
        }
        .sensoryFeedback(.selection, trigger: selection.selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.house")
    }

    /// The hero sides to try, largest first: the pane's own size, then steps of 10% down to the
    /// floor. The diorama never goes under 220 (§H.5, H6); the skyline's houses never under 44.
    private func heroSides(_ shelf: HouseShelf, _ shown: HouseShelfItem?) -> [CGFloat] {
        let full = heroSide
        let isAll = shown?.isAll ?? false
        var sides: [CGFloat] = [full]
        for step in stride(from: 0.9, through: 0.4, by: -0.1) {
            var side = (full * step).rounded()
            if isAll {
                let houses = RentalSkylineLayout.visible(shelf.skyline, frame: side).count
                guard side >= 150, RentalSkylineLayout.houseSide(frame: side, count: max(houses, 1)) >= 44 else { break }
            } else {
                side = max(side, min(full, CraftHeroSize.minimumDioramaSide))
            }
            if side < (sides.last ?? full) { sides.append(side) }
        }
        return sides
    }

    // MARK: Layouts

    /// Everything fits: the free height becomes bands of air (above the house, around the number,
    /// below the shelf), so no bare band of a tall pane passes 20% (DU4, DU6).
    @ViewBuilder private func resting(_ shelf: HouseShelf, _ shown: HouseShelfItem?, side: CGFloat) -> some View {
        VStack(spacing: 0) {
            if stacked {
                Spacer(minLength: 4)
                heroRow(shelf, shown, side: side)
                Spacer(minLength: 8)
                shelfView(shelf)
                Spacer(minLength: 8)
            } else {
                Spacer(minLength: 0)
                hero(shelf, shown, side: side)
                // The skyline's rows of sky already sit above the houses; a fourth band of air
                // between it and the number keeps every bare band of a tall pane under 20%.
                if shown?.isAll ?? false { Spacer(minLength: 8) }
                numberBlock(shelf, shown)
                    .padding(.top, numberLift(shown, side: side))
                Spacer(minLength: ax ? 12 : 16)
                shelfView(shelf)
                Spacer(minLength: 12)
            }
        }
        .frame(maxWidth: PaneMetrics.contentCap)
        .frame(maxWidth: .infinity)
    }

    /// Not even the floor fits (AX on a short pane, the propped Duo at AX): the whole column
    /// scrolls, starting at the top. The hero, the number and the pace sentence are read first and
    /// whole; nothing is faded or blurred at either edge. The shelf starts below the fold, never
    /// half in view, so no label is cut at rest; the scroll indicator flashes once to say there is
    /// more (gate J r2, Brian's open question 3).
    @ViewBuilder private func scrolling(_ shelf: HouseShelf, _ shown: HouseShelfItem?) -> some View {
        let side = heroSides(shelf, shown).last ?? heroSide
        GeometryReader { g in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if stacked {
                            heroRow(shelf, shown, side: side)
                        } else {
                            hero(shelf, shown, side: side)
                            numberBlock(shelf, shown)
                                .padding(.top, numberLift(shown, side: side))
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { leadHeight = $0 }
                    // The lead sits centred in the pane at rest (the slack split above and below,
                    // so no band of bare wall passes 20%); the shelf starts just below the fold.
                    .padding(.top, slack(g.size.height) / 2)
                    shelfView(shelf)
                        .padding(.top, max(ax ? 12 : 16, slack(g.size.height) / 2 + 8))
                }
                .padding(.bottom, 12)
                .frame(maxWidth: PaneMetrics.contentCap)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .scrollIndicatorsFlash(onAppear: true)
            .scrollBounceBehavior(.basedOnSize)
            .modifier(NoScrollEdgeEffect())
        }
    }

    /// The scrolling column's spare height at rest, above and below its lead.
    private func slack(_ visible: CGFloat) -> CGFloat {
        leadHeight > 0 ? max(0, visible - leadHeight) : visible
    }

    /// Stacked: the hero beside the number block.
    private func heroRow(_ shelf: HouseShelf, _ shown: HouseShelfItem?, side: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            hero(shelf, shown, side: side)
            numberBlock(shelf, shown)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PaneMetrics.gutter(paneWidth: pane.width, onDuo: split.isDivision))
    }

    @ViewBuilder private func shelfView(_ shelf: HouseShelf) -> some View {
        if !shelf.items.isEmpty {
            RentalShelf(shelf: shelf, selectedID: $selection.selectedID,
                        model: stacked ? 104 : PaneMetrics.shelfModel(paneWidth: pane.width),
                        widthHint: PaneMetrics.contentWidth(paneWidth: pane.width))
        }
    }

    /// The number sits in the diorama's shadow (H4); at AX and under the skyline it sits below.
    private func numberLift(_ shown: HouseShelfItem?, side: CGFloat) -> CGFloat {
        ax || (shown?.isAll ?? false) ? 4 : -side * 0.10
    }

    // MARK: Hero

    @ViewBuilder private func hero(_ shelf: HouseShelf, _ shown: HouseShelfItem?, side: CGFloat) -> some View {
        ZStack {
            if let shown, shown.isAll {
                // The skyline's houses stand on the ground line at the frame's foot and leave its
                // top as sky; in a pane the frame is trimmed to the houses so the sky does not
                // become a band of bare wall (plan J iPad sizing, DU6).
                RentalSkyline(items: shelf.skyline, side: side)
                    .frame(height: side * Self.skylineShare, alignment: .bottom)
                    .clipped()
            } else if let shown, let stage = shown.stage {
                CraftHouseView(stage: stage, windowsLit: shown.lit, side: side, fillsStage: !ax,
                               onSwipe: shelf.items.count > 1 ? { step($0) } : nil)
                    .overlay {
                        if showsDoor { FrontDoor(stage: stage, side: side, clock: clock) }
                    }
            } else {
                // No rental yet: the empty lot, unlit.
                CraftHouseView(stage: .started, windowsLit: false, side: side, fillsStage: !ax)
            }
        }
        .id(shown?.id ?? "none")
        .transition(CraftHouseView.rentalSlide(edge: slideEdge, reduceMotion: reduceMotion))
        .frame(width: side, height: (shown?.isAll ?? false) ? side * Self.skylineShare : side)
        .frame(maxWidth: stacked ? nil : .infinity)
        .clipped()
        .accessibilityIdentifier("pane.hero")
    }

    private func step(_ delta: Int) {
        guard let next = shelf.step(from: selection.selectedID, by: delta) else { return }
        withAnimation(CraftHouseView.rentalSlideAnimation(reduceMotion: reduceMotion)) { selection.select(next) }
    }

    // MARK: Number block

    @ViewBuilder private func numberBlock(_ shelf: HouseShelf, _ shown: HouseShelfItem?) -> some View {
        Group {
            if let shown, shown.isAll {
                HouseNumberBlock(content: .allRentals(shelf.summary), numeralSize: numeral,
                                 isPending: viewModel.isAwaitingInitialPull)
            } else if let shown, let pace = shown.pace {
                HouseNumberBlock(content: .rental(hours: shown.hours, goal: shown.goal ?? goalManager.houseGoal.targetHours,
                                                  name: shown.name, pace: pace),
                                 numeralSize: numeral, isPending: viewModel.isAwaitingInitialPull)
            } else {
                HouseNumberBlock(content: .rental(hours: 0, goal: goalManager.houseGoal.targetHours, name: "",
                                                  pace: TodayPaceSentence(lead: nil,
                                                                          rest: TodayHeroCopy.emptyLotLine(target: isRecord ? nil : Int(goalManager.houseGoal.targetHours)),
                                                                          tone: .neutral)),
                                 numeralSize: numeral)
            }
        }
    }

    // MARK: Account menu (Reports, Settings): opens in the right pane

    private var accountMenu: some View {
        Menu {
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.reportsIndex)
            } label: {
                Label(String(localized: "today.account.reports", defaultValue: "Reports", table: "Today"), systemImage: "chart.bar")
            }
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.settingsIndex)
            } label: {
                Label(String(localized: "today.account.settings", defaultValue: "Settings", table: "Today"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 36, height: 36)
                .background(colors.heroChipFill, in: Circle())
                .overlay(Circle().strokeBorder(colors.heroChipHairline, lineWidth: 0.5))
                .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                .contentShape(Circle())
        }
        .help(Text(String(localized: "today.account.label", defaultValue: "Reports and settings", table: "Today")))
        .hoverEffect(.highlight)
        .accessibilityLabel(String(localized: "today.account.label", defaultValue: "Reports and settings", table: "Today"))
        .accessibilityIdentifier("pane.account")
    }

    private func restoreFocus() {
        let items = shelf.items
        if items.contains(where: { $0.id == selection.selectedID }) { return }
        if !rememberedFocus.isEmpty, items.contains(where: { $0.id == rememberedFocus }) {
            selection.selectedID = rememberedFocus
        } else if let first = items.first {
            selection.selectedID = first.id
        }
    }
}

/// iOS 26+: no soft scroll edge on the house column. Its first line at rest is the numeral (the
/// propped Duo at AX), which the system's top edge effect blurred (gate J r2).
private struct NoScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}
