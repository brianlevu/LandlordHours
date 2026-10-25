import SwiftUI

// MARK: - The house pane's figures and the timber shelf (§1.27 two-pane, DU6, DU7, DU15; H10)
//
// `HouseShelf` turns the real rentals into what the house pane shows: one item per rental (its own
// hours, its own goal, its own stage and lit state, its own pace) plus "All rentals" first. "All
// rentals" never has a goal or a stage [grep]: its hero is the skyline of each rental's own house,
// its number block says "N hours across M rentals · K of M behind" (`AllRentalsSummary`, A2).
//
// `RentalShelf` is the timber shelf under the hero: "All rentals" first, then one model per rental
// with its name and "46 of 100h". It snaps to whole items, so no glyph is cut at either edge at any
// type size (DU15), and a count line above the plank says how many of the rentals are in view.

struct HouseShelfItem: Identifiable, Equatable {
    let id: String
    let rentalID: UUID?
    let name: String
    let hours: Double
    /// The rental's own goal (nil for "All rentals": it has none).
    let goal: Double?
    let stage: CraftStage?
    let lit: Bool
    let pace: TodayPaceSentence?
    /// Hours behind its own pace (0 on pace).
    let behindBy: Double

    var isAll: Bool { rentalID == nil }
    var isBehind: Bool { pace?.tone == .behind }
}

struct HouseShelf: Equatable {
    static let allID = "all"

    let rentals: [HouseShelfItem]

    /// "All rentals" leads when there are two or more rentals (H10), as on the phone.
    var items: [HouseShelfItem] {
        guard rentals.count > 1 else { return rentals }
        let all = HouseShelfItem(id: Self.allID, rentalID: nil, name: summaryName, hours: summary.hours, goal: nil,
                                 stage: nil, lit: rentals.contains { $0.lit }, pace: nil, behindBy: 0)
        return [all] + rentals
    }

    var summaryName: String {
        String(localized: "allRentals.name", defaultValue: "All rentals", table: "Shared")
    }

    /// Hours across the rentals and how many are behind their own pace. No goal.
    var summary: AllRentalsSummary {
        AllRentalsSummary(hours: rentals.map(\.hours).reduce(0, +), rentalCount: rentals.count,
                          behindCount: rentals.filter(\.isBehind).count)
    }

    /// The skyline houses: each rental's own stage and lit state.
    var skyline: [RentalSkylineItem] {
        rentals.compactMap { r in
            r.stage.map { RentalSkylineItem(id: r.id, name: r.name, stage: $0, lit: r.lit, behindBy: r.behindBy) }
        }
    }

    func item(_ id: String) -> HouseShelfItem? { items.first { $0.id == id } }

    /// The shown item: the selection if it exists, else the first item.
    func resolved(_ id: String) -> HouseShelfItem? { item(id) ?? items.first }

    /// The item `step` away (swipe on the house, VoiceOver adjust), wrapping.
    func step(from id: String, by step: Int) -> String? {
        let all = items
        guard !all.isEmpty else { return nil }
        let i = all.firstIndex { $0.id == id } ?? 0
        let n = all.count
        return all[((i + step) % n + n) % n].id
    }

    /// "46 of 100h" per rental; "All rentals" says how many are behind (never a summed goal).
    func status(_ item: HouseShelfItem) -> String {
        if item.isAll { return summary.behindLabel }
        let goal = Int((item.goal ?? 0).rounded())
        return String(localized: "twoPane.shelf.progress", defaultValue: "\(Int(item.hours.rounded(.down))) of \(goal)h",
                      table: "Adaptive")
    }
}

extension HouseShelf {
    /// The live figures, the same ones compact Today draws (`DashboardView`): countable hours this
    /// tax year against the house goal, the pace sentence per rental, lit when logged today.
    @MainActor
    static func live(app: AppViewModel, goal houseGoal: HouseGoal, isRecord: Bool, now: Date = InboxClock.now()) -> HouseShelf {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let target = houseGoal.targetHours
        let firstEntry = app.timeEntries.filter { calendar.component(.year, from: $0.date) == year }.map(\.date).min()
        let daysOfData = firstEntry.map {
            max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0)
        } ?? 0
        let day = Double(calendar.ordinality(of: .day, in: .year, for: now) ?? 1)
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: now)?.count ?? 365)
        let items: [HouseShelfItem] = app.properties.map { p in
            let hours = app.propertyCountableHours(p.id, goal: houseGoal, year: year)
            let pace = TodayPaceSentence.make(.init(
                hours: hours, goal: target, year: year, now: now, isRecord: isRecord,
                paceReady: TodayHeroCopy.paceIsReady(hours: hours, daysOfData: daysOfData)))
            let expected = target * day / daysInYear
            let lit = TodayWindowState.loggedToday(entries: app.timeEntries, rentalIDs: [p.id], now: now)
            return HouseShelfItem(id: p.id.uuidString, rentalID: p.id, name: p.name, hours: hours, goal: target,
                                  stage: CraftStage.stage(hours: hours, goal: target), lit: lit, pace: pace,
                                  behindBy: max(0, expected - hours))
        }
        return HouseShelf(rentals: items)
    }
}

// MARK: - The shelf

struct RentalShelf: View {
    let shelf: HouseShelf
    @Binding var selectedID: String
    /// The house model's side (104 on the Duo, larger in wide iPad panes; `PaneMetrics.shelfModel`).
    var model: CGFloat = 104
    /// The pane's content width, so the first layout already has whole slots (no tall first pass).
    var widthHint: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var minSlot: CGFloat = 108
    @State private var viewport: CGFloat = 0
    @State private var firstID: String?

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var items: [HouseShelfItem] { shelf.items }
    /// The scroll viewport's side inset (8pt of air each side).
    static let inset: CGFloat = 8

    /// Whole items only: how many slots fit, and the width that makes them fill the viewport.
    private var visible: Int {
        let slot = max(minSlot, model + 4)
        return max(1, min(items.count, Int(width / (slot + 8))))
    }
    private var width: CGFloat { viewport > 0 ? viewport : max(widthHint - 2 * Self.inset, 1) }
    private var slotWidth: CGFloat { width / CGFloat(visible) }
    /// The rentals in view at rest: "All rentals" holds the first slot (DU15), so it is not counted.
    private var visibleRentals: Int {
        let allSlot = items.first?.isAll == true ? 1 : 0
        return max(0, min(shelf.rentals.count, visible - allSlot))
    }

    /// "2 of 8 rentals" when some are out of view; "3 rentals" when every rental is in view (or only
    /// the "All rentals" slot fits, at the largest type sizes).
    static func countLine(visibleRentals: Int, total: Int) -> String {
        if visibleRentals > 0, visibleRentals < total {
            return String(localized: "twoPane.shelf.count", defaultValue: "\(visibleRentals) of \(total) rentals", table: "Adaptive")
        }
        return String(localized: "twoPane.shelf.total", defaultValue: "\(total) rentals", table: "Adaptive")
    }

    var body: some View {
        VStack(spacing: 6) {
            // DU15: the honest count, always above the plank (plain SF footnote, no dots or "+5"
            // tile): the rentals in view at rest out of all of them.
            Text(Self.countLine(visibleRentals: visibleRentals, total: shelf.rentals.count))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Self.inset + 8)
                .accessibilityIdentifier("shelf.count")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(items) { item in slot(item).id(item.id) }
                }
                .scrollTargetLayout()
                .background(alignment: .top) {
                    Image("duo_shelf")
                        .resizable(resizingMode: .tile)
                        .frame(height: 12)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 3, y: 2)
                        .offset(y: model * 0.86)
                        .accessibilityHidden(true)
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $firstID, anchor: .leading)
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewport = $0 }
            .padding(.horizontal, Self.inset)
        }
        .onAppear { firstID = items.isEmpty ? nil : items[leadIndex(for: selectedID)].id }
        .onChange(of: selectedID) { _, id in
            guard let f = firstID.flatMap({ k in items.firstIndex { $0.id == k } }),
                  let i = items.firstIndex(where: { $0.id == id }) else { return }
            if i < f || i >= f + visible {
                withAnimation(reduceMotion ? AppAnimation.quick : AppAnimation.rentalSlide) { firstID = items[leadIndex(for: id)].id }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house.shelf")
    }

    /// "All rentals" is the first slot and is visible at rest (DU15): the lead index keeps 0 in
    /// view until the selection is past the first page.
    private func leadIndex(for id: String) -> Int {
        let i = items.firstIndex { $0.id == id } ?? 0
        if i < visible { return 0 }
        return max(0, min(items.count - visible, i - visible / 2))
    }

    private func slot(_ item: HouseShelfItem) -> some View {
        let on = item.id == selectedID
        return Button {
            withAnimation(reduceMotion ? AppAnimation.quick : AppAnimation.rentalSlide) { selectedID = item.id }
        } label: {
            VStack(spacing: 6) {
                houseModel(item)
                    .frame(width: model, height: model)
                    .padding(.bottom, -model * 0.06)
                VStack(spacing: 1) {
                    Text(item.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(shelf.status(item))
                        .font(.caption)
                        .foregroundStyle(colors.textSecondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: slotWidth - 8)
                .background(on ? colors.heroChipFill : .clear, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                    .strokeBorder(on ? DoorArt.shelfPillEdge(dark: colorScheme == .dark) : .clear, lineWidth: 1))
            }
            .frame(width: slotWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(LHButton.press)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text(verbatim: "\(item.name), \(shelf.status(item))"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("shelf.\(item.isAll ? "all" : item.name)")
    }

    @ViewBuilder private func houseModel(_ item: HouseShelfItem) -> some View {
        if item.isAll {
            // All rentals: up to three of the rentals' own models grouped on one lot edge.
            ZStack {
                ForEach(Array(shelf.rentals.prefix(3).enumerated()), id: \.element.id) { i, r in
                    if let stage = r.stage {
                        still(stage, lit: r.lit)
                            .frame(width: model * 0.62, height: model * 0.62)
                            .offset(x: CGFloat(i - 1) * model * 0.27, y: CGFloat(abs(i - 1)) * -model * 0.04 + model * 0.16)
                            .zIndex(i == 1 ? 1 : 0)
                    }
                }
            }
        } else if let stage = item.stage {
            still(stage, lit: item.lit)
        }
    }

    /// The shelf model is the rental's own diorama still (the locked v7 shelf: the house on its lot,
    /// standing on the plank), lit or unlit by its own `loggedToday`.
    private func still(_ stage: CraftStage, lit: Bool) -> some View {
        let name = (lit || !CraftHouseView.hasUnlitTwin(stage)) ? stage.assetName(lit: true) : stage.assetName(lit: false)
        return Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .brightness(colorScheme == .dark ? CraftHouseView.nightLift(stage) : 0)
            .accessibilityHidden(true)
    }
}
