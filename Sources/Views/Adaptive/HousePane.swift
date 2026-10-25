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
    @ObservedObject var clock: DoorClock

    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var goalManager: GoalManager
    @EnvironmentObject private var selection: AdaptiveSelection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("today.focus") private var rememberedFocus = ""
    @State private var slideEdge: Edge = .trailing

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
        GeometryReader { g in
            ScrollView {
                VStack(spacing: 0) {
                    if stacked {
                        HStack(alignment: .center, spacing: 0) {
                            hero(shelf, shown)
                            numberBlock(shelf, shown)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, PaneMetrics.gutter(paneWidth: pane.width, onDuo: split.isDivision))
                        RentalShelf(shelf: shelf, selectedID: $selection.selectedID, model: 104,
                                    widthHint: PaneMetrics.contentWidth(paneWidth: pane.width))
                            .padding(.top, 8)
                    } else {
                        Spacer(minLength: 0)
                        hero(shelf, shown)
                        // The skyline's rows of sky already sit above the houses; a fourth band of air
                        // between it and the number keeps every bare band of a tall pane under 20%.
                        if shown?.isAll ?? false { Spacer(minLength: 8) }
                        numberBlock(shelf, shown)
                            .padding(.top, ax || (shown?.isAll ?? false) ? 4 : -heroSide * 0.10)   // the number sits in the diorama's shadow (H4)
                        Spacer(minLength: ax ? 12 : 16)
                        if !shelf.items.isEmpty {
                            RentalShelf(shelf: shelf, selectedID: $selection.selectedID,
                                        model: PaneMetrics.shelfModel(paneWidth: pane.width),
                                        widthHint: PaneMetrics.contentWidth(paneWidth: pane.width))
                        }
                        Spacer(minLength: 12)
                    }
                }
                .frame(maxWidth: PaneMetrics.contentCap)
                .frame(maxWidth: .infinity)
                .frame(minHeight: g.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .overlay(alignment: .topTrailing) { accountMenu.padding(.trailing, PaneMetrics.gutter(paneWidth: pane.width, onDuo: split.isDivision) - 8) }
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

    // MARK: Hero

    @ViewBuilder private func hero(_ shelf: HouseShelf, _ shown: HouseShelfItem?) -> some View {
        let side = heroSide
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

