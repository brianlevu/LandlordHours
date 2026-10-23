import SwiftUI

#if DEBUG
// MARK: - Root: the tab shell with SF Symbols (LHIcon retired, standard §D)

struct StdProtoRoot: View {
    let launch: StdProtoLaunch
    @State private var tab: Int
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(launch: StdProtoLaunch) {
        self.launch = launch
        _tab = State(initialValue: [.inbox, .goalcheck].contains(launch.screen) ? 1 : 0)
    }

    var body: some View {
        let seed = StdSeed.make(launch.seedID)
        TabView(selection: $tab) {
            Group {
                if launch.screen == .seeall {
                    NavigationStack { StdSeeAllScreen(seed: seed) }
                } else {
                    StdTodayScreen(seed: seed, launch: launch, openInbox: { tab = 1 })
                }
            }
            .tabItem { Label(L("Today"), systemImage: "sun.max") }.tag(0)
            StdInboxScreen(seed: seed, launch: launch)
                .tabItem { Label(L("Inbox"), systemImage: "tray") }.tag(1)
                .badge(seed.suggestions.count)
            colors.background.ignoresSafeArea()
                .tabItem { Label(L("Records"), systemImage: "list.bullet.rectangle") }.tag(2)
            colors.background.ignoresSafeArea()
                .tabItem { Label(L("Properties"), systemImage: "house") }.tag(3)
        }
        .tint(colors.action)
    }
}

// MARK: - Today as an inset-grouped List (§1.3a)

struct StdTodayScreen: View {
    let seed: StdSeed
    let launch: StdProtoLaunch
    var openInbox: () -> Void = {}
    @State private var focus: HomeProtoFocus
    @State private var items: [StdSuggestion]
    @State private var confirmed: Set<String> = []
    /// rowConfirm phase 2/3: faded, then collapsed to zero height (our spring), then removed without animation.
    @State private var fading: Set<String> = []
    @State private var collapsing: Set<String> = []
    @State private var extra: [String: Double] = [:]
    @State private var toast: LHToastSpec?
    @State private var successTick = 0
    @State private var dismissTick = 0
    @State private var showLog: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(seed: StdSeed, launch: StdProtoLaunch, openInbox: @escaping () -> Void = {}) {
        self.seed = seed
        self.launch = launch
        self.openInbox = openInbox
        _focus = State(initialValue: seed.rentals.focusOrder.first ?? .all)
        let byDay = seed.suggestions.enumerated().sorted { ($0.element.groupRank, $0.offset) < ($1.element.groupRank, $1.offset) }.map(\.element)
        _items = State(initialValue: Array(byDay.prefix(3)))
        _showLog = State(initialValue: launch.screen == .logtime || launch.demo == "postlog")
    }

    /// The rentals with confirmed hours added, so the hero moves on confirm.
    private var live: StdSeed {
        guard !extra.isEmpty else { return seed }
        let rentals = seed.rentals.rentals.map { r -> HomeProtoRental in
            guard let add = extra[r.id] else { return r }
            var weekly = r.weeklyNeed
            if case .own(let t) = r.target, r.pace == .behind {
                weekly = Int(((Double(t) - r.hours - add) / (Double(StdSeed.daysLeft) / 7)).rounded(.up))
            }
            return HomeProtoRental(id: r.id, name: r.name, shortStay: r.shortStay, hours: r.hours + add, target: r.target,
                                   pace: r.pace, weeklyNeed: weekly, reached: r.reached)
        }
        return StdSeed(id: seed.id, rentals: HomeProtoSeed(id: seed.rentals.id, rentals: rentals, sharedTarget: seed.rentals.sharedTarget),
                       suggestions: seed.suggestions, week: seed.week)
    }

    /// Rows shown on Today: at most 3 across day groups (2 at XXL+), and a row that would open a
    /// new day group past the second row is left for Inbox, so "This week" stays above the tab bar.
    private var shown: [StdSuggestion] {
        var out = Array(items.prefix(rowLimit))
        // Each extra day header costs a row's height: with two days on Today, show two rows.
        if out.count > 2, Set(out.map(\.group)).count > 1 { out = Array(out.prefix(2)) }
        return out
    }
    private var likely: [StdSuggestion] { shown.filter { $0.isLikely && !confirmed.contains($0.id) } }
    /// Everything still waiting, across Today and Inbox.
    private var waiting: Int { seed.suggestions.count - (3 - items.count) }
    /// D3b: at XXL and up Today shows two items so "This week" stays above the tab bar.
    private var rowLimit: Int { typeSize >= .xxLarge ? 2 : 3 }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                confirmSection
                weekSection
                paceSection
            }
            .listStyle(.insetGrouped)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom } action: { y in
                StdGeom.log(String(format: "STDGEOM fold %.1f 0 0 0", y))
            }
            .listSectionSpacing(24)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(colors.background.ignoresSafeArea())
            .environment(\.defaultMinListRowHeight, 1)
            .onAppear {
                if launch.scroll == "bottom" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
        .sheet(isPresented: $showLog) {
            StdLogTimeSheet(seed: seed, launch: launch, onClose: { showLog = false }, onLog: logged)
                .presentationDragIndicator(.visible)
        }
        .task { await demo() }
    }

    // MARK: To confirm

    /// To confirm, grouped by day (§1.15a): the first day header sits under "TO CONFIRM"; the
    /// batch foot closes the last group.
    @ViewBuilder private var confirmSection: some View {
        let groups = stdDayGroups(shown)
        if groups.isEmpty {
            Section {
                Label { Text(L("Nothing to confirm.")) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.positive) }
                    .font(.subheadline).foregroundStyle(colors.textSecondary)
                    .listRowBackground(colors.backgroundSecondary)
            } header: { topHeader(day: nil) }
        }
        if !groups.isEmpty {
            Section {
                ForEach(Array(groups.enumerated()), id: \.element.name) { gi, g in
                    // Day header as a row inside the one card (§1.15a): the card never breaks per day.
                    StdDayHeader(title: g.name).stdDayRow(first: gi == 0, colors: colors)
                    ForEach(Array(g.items.enumerated()), id: \.element.id) { ii, item in
                        actionRow(item)
                            .listRowSeparator(ii == g.items.count - 1 && gi < groups.count - 1 ? .hidden : .automatic, edges: .bottom)
                    }
                }
                // One foot row: "Confirm N likely" and, when more wait, "Review all N" (opens Inbox).
                if likely.count >= 2 || waiting > shown.count {
                    HStack(spacing: 8) {
                        if likely.count >= 2 {
                            Button(StdCanon.confirmLikely(likely.count)) { confirmLikely() }
                                .buttonStyle(StdButtonStyle(.tertiary))
                                .accessibilityIdentifier("today.confirmLikely")
                        }
                        Spacer(minLength: 8)
                        if waiting > shown.count {
                            Button(L("Review all \(waiting)")) { openInbox() }
                                .buttonStyle(StdButtonStyle(.tertiary))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(colors.backgroundSecondary)
                    .stdMeasure("foot")
                }
                if typeSize.isAccessibilitySize {
                    Button(L("See all")) {}
                        .buttonStyle(StdButtonStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(colors.backgroundSecondary)
                }
            } header: {
                topHeader(day: nil)
            }
        }
    }

    private func actionRow(_ item: StdSuggestion) -> some View {
        StdActionRow(item: item, confirmed: confirmed.contains(item.id), onConfirm: { confirm(item) }, showDay: false)
            .stdMeasure("row.\(item.id)")
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(colors.backgroundSecondary)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 34 }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 16 }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { confirm(item, swipe: true) } label: { Label(StdCanon.confirm, systemImage: "checkmark") }
                    .tint(colors.positive)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { decline(item) } label: { Label(StdCanon.notRentalWork, systemImage: "xmark") }
                    .tint(colors.textSecondary)
            }
    }

    /// Title, hero and the To confirm header live in the first section's header: List masks a
    /// row's corners with its own radius, which clips anything drawn to the row edge.
    private func topHeader(day: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                StdScreenTitle(title: L("Today"), subtitle: typeSize.isAccessibilitySize ? nil : L("Fri, Oct 23"))
                Button { showLog = true } label: { Image(systemName: "plus") }
                    .buttonStyle(StdButtonStyle(.icon))
                    .accessibilityLabel(L("Log time"))
            }
            .padding(.bottom, 8)
            StdHeroCard(seed: live, focus: $focus).stdMeasure("hero").padding(.top, 16)
            StdSectionHeader(title: L("To confirm"), count: seed.suggestions.count - (seed.suggestions.prefix(3).count - items.count),
                             trailing: nil)
                .padding(.top, 24)
            if let day { StdDayHeader(title: day).padding(.top, 4) }
        }
        .stdHeaderInsets()
    }

    private func confirm(_ item: StdSuggestion, swipe: Bool = false) {
        guard item.canQuickLog, !confirmed.contains(item.id) else { return }
        StdMotionLog.mark(swipe ? "swipeConfirm" : "rowConfirm")
        successTick += 1
        collapseRows([item.id], fill: true) {
            if let r = item.rental, let h = item.hours {
                withAnimation(StdMotion.count) { extra[r, default: 0] += h }
            }
            let place = item.rental.flatMap { seed.rentals.rental($0)?.name }
            show(LHToastSpec(kind: .success,
                             message: place.map { L("Logged \(StdFormat.hours(item.hours)) at \($0).") } ?? L("Logged \(StdFormat.hours(item.hours))."),
                             actionTitle: L("Undo")))
        }
    }

    private func decline(_ item: StdSuggestion) {
        StdMotionLog.mark("rowDismiss")
        dismissTick += 1
        collapseRows([item.id], fill: false) {
            show(LHToastSpec(kind: .neutral, message: L("Marked not rental work."), actionTitle: L("Undo")))
        }
    }

    private func confirmLikely() {
        let batch = likely
        StdMotionLog.mark("rowConfirm.batch")
        successTick += 1
        collapseRows(batch.map(\.id), fill: true) {
            withAnimation(StdMotion.count) {
                for item in batch { if let r = item.rental, let h = item.hours { extra[r, default: 0] += h } }
            }
            show(LHToastSpec(kind: .success, message: L("Logged \(batch.count)."), actionTitle: L("Undo")))
        }
    }

    /// fill → fade → collapse → remove (StdRowConfirm); `then` runs at the fill, so the hero and toast move with it.
    private func collapseRows(_ ids: [String], fill: Bool, then: @escaping () -> Void) {
        let set = Set(ids)
        StdRowConfirm.run(id: ids.first ?? "", reduceMotion: reduceMotion,
                          fill: { if fill { confirmed.formUnion(set) } },
                          fade: { fading.formUnion(set) },
                          collapse: { collapsing.formUnion(set) },
                          remove: { items.removeAll { set.contains($0.id) }; fading.subtract(set); collapsing.subtract(set) })
        then()
    }

    // MARK: Toast (§1.19, toastIn / toastOut)

    private func show(_ spec: LHToastSpec) {
        StdMotionLog.mark("toastIn")
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.reveal) { toast = spec }
        let id = spec.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard toast?.id == id else { return }
            StdMotionLog.mark("toastOut")
            withAnimation(StdMotion.quick) { toast = nil }
        }
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            LHToast(spec: toast)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .id(toast.id)
                .transition(.asymmetric(insertion: .offset(y: reduceMotion ? 0 : 24).combined(with: .opacity),
                                        removal: .offset(y: reduceMotion ? 0 : 12).combined(with: .opacity)))
        }
    }

    // MARK: This week

    private var weekSection: some View {
        Section {
            ForEach(seed.week) { e in
                StdBrowseRow(title: e.title, meta: L("\(e.rental) · \(e.category.stdLabel)"),
                             value: StdFormat.hours(e.hours)) {
                    CategoryToolTile(category: e.category, size: 36)
                }
                .stdMeasure("week.\(e.id)")
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(colors.backgroundSecondary)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
                .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 16 }
            }
        } header: {
            StdSectionHeader(title: L("This week"), trailing: L("Records")).stdMeasure("header.week").stdHeaderInsets()
        }
    }

    // MARK: Pace

    private var paceSection: some View {
        Section {
            Color.clear.frame(height: 1).id("end").stdClearRow()
        } header: {
            VStack(alignment: .leading, spacing: 8) {
                StdSectionHeader(title: L("Pace"))
                let tiles = live.paceTiles(focus)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                        StdStatTile(value: t.0, label: t.1, ink: i == 0 ? (t.2 == "checkmark.circle.fill" ? colors.positive : colors.caution) : nil, glyph: t.2)
                            .stdMeasure("stat.\(i)")
                    }
                }
                StdCPAFootnote().padding(.top, 8)
            }
            .stdHeaderInsets()
        }
    }

    // MARK: Scripted runs for the videos

    /// The post-log beat: the sheet drops, then the hero counts up, the house rises with the
    /// drafting pass, and the toast says what was logged.
    private func logged(_ hours: Double) {
        StdMotionLog.mark("postLog")
        showLog = false
        successTick += 1
        guard let r = seed.rentals.rentals.first else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(StdMotion.count) { extra[r.id, default: 0] += hours }
            show(LHToastSpec(kind: .success, message: L("Logged \(StdFormat.hours(hours)) at \(r.name)."), actionTitle: L("Undo")))
        }
    }

    private func demo() async {
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        switch launch.demo {
        case "postlog":
            await pause(2.2)
            logged(1.5)
        case "confirm":
            await pause(2.0)
            if let first = items.first { confirm(first) }
        case "tiles":
            let order = seed.rentals.focusOrder
            await pause(1.6)
            for i in [1, 2, 0] where order.indices.contains(i) {
                StdMotionLog.mark("tileFocus")
                withAnimation(StdMotion.quick) { focus = order[i] }
                await pause(1.8)
            }
        default: break
        }
    }
}

extension View {
    /// A List row that draws nothing of its own: hero, tiles, titles.
    func stdClearRow(top: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    func stdHeaderInsets() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
    }
}

// MARK: - Blueprint hero with the rentals folded into its foot (Brian, round 2)
//
// One card: the number and the house on top, a slim row of small houses at the bottom (name +
// hours each). Tap a small house, or swipe the card, to switch. No separate strip, no eyebrow.

struct StdHeroCard: View {
    let seed: StdSeed
    @Binding var focus: HomeProtoFocus
    @State private var rise: CGFloat = 1
    @State private var skyPhase: StdSkyPhase = StdSkyPhase.at(Date())
    /// draftingPass (critique #10): one cyan line sweeps the newly built band as the mask rises.
    @State private var sweep: CGFloat = 0
    @State private var sweepOpacity: Double = 0
    @State private var passTick = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hero: StdSeed.Hero { seed.hero(focus) }

    private var statusColor: Color {
        switch hero.tone {
        case .positive: return HouseTokens.positiveOnHero
        case .caution: return HouseTokens.cautionOnHero
        case .neutral: return HouseTokens.onHeroSecondary
        }
    }

    private var statusGlyph: String? {
        switch hero.tone {
        case .positive: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .neutral: return nil
        }
    }

    private var statusWords: String { hero.status ?? "" }
    /// One rental: no switcher; the card names it and gives the house and the sky the room.
    private var single: Bool { seed.rentals.rentals.count == 1 && seed.rentals.sharedTarget == nil }

    var body: some View {
        // The sky is a state (B.4): read on appear, then on each hour boundary by one sleeping task.
        card(phase: skyPhase)
            .task {
                skyPhase = StdSkyPhase.at(Date())
                while !Task.isCancelled {
                    let now = Date()
                    let next = Calendar.current.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
                    try? await Task.sleep(nanoseconds: UInt64(max(1, next.timeIntervalSince(now)) * 1_000_000_000))
                    skyPhase = StdSkyPhase.at(Date())
                }
            }
    }

    private func card(phase: StdSkyPhase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize { compactTop } else { fullTop(phase == .night) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded(swipe))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(hero.flag), \(Int(hero.number)) \(hero.label). \(statusWords)"))
            .accessibilityAdjustableAction { dir in step(dir == .increment ? 1 : -1) }
            .accessibilityIdentifier("std.hero")
            if !typeSize.isAccessibilitySize && !single {
                Rectangle().fill(HouseTokens.drafting.opacity(0.25)).frame(height: 0.5)
                rentalRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StdHeroSky(phase: phase))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: hero.key) { _, _ in raise(from: 0.45) }
        .onChange(of: hero.number) { old, new in if new > old { raise(from: 0.82); draftingPass() } }
        .sensoryFeedback(.selection, trigger: focus)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: passTick)
    }

    // MARK: Switching

    private func select(_ f: HomeProtoFocus) {
        StdMotionLog.mark("tileFocus")
        withAnimation(StdMotion.quick) { focus = f }
    }

    private func step(_ delta: Int) {
        let order = seed.rentals.focusOrder
        guard let i = order.firstIndex(of: focus), order.indices.contains(i + delta) else { return }
        select(order[i + delta])
    }

    private func swipe(_ v: DragGesture.Value) {
        guard abs(v.translation.width) > 48, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
        step(v.translation.width < 0 ? 1 : -1)
    }

    /// heroCountUp: the built house rises behind its linework (ringProgress 0.60) while the digits count (count 0.60).
    /// draftingPass: a 1pt drafting-cyan line draws left → right along the rising mask edge
    /// (sweep easeOut 0.45) and fades by 0.55s, then stillness. Reduce Motion: no line.
    /// `-LHStdSlow 4` plays the hero motions at quarter speed for review clips.
    private static let slow: Double = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-LHStdSlow"), a.indices.contains(i + 1) else { return 1 }
        return Double(a[i + 1]) ?? 1
    }()

    private func draftingPass() {
        guard !reduceMotion else { return }
        StdMotionLog.mark("draftingPass")
        passTick += 1
        let k = Self.slow
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { sweep = 0; sweepOpacity = 0.9 }
        withAnimation(.easeOut(duration: 0.45 * k)) { sweep = 1 }
        withAnimation(.easeIn(duration: 0.2 * k).delay(0.35 * k)) { sweepOpacity = 0 }
    }

    private func raise(from start: CGFloat) {
        StdMotionLog.mark("heroCountUp")
        guard !reduceMotion else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { rise = start }
        withAnimation(.spring(duration: 0.60 * Self.slow, bounce: 0)) { rise = 1 }
    }

    // MARK: Top: number and house

    private var number: some View {
        StdCountingText(value: hero.number)
            .font(AppTypography.heroNumber)
            .foregroundStyle(HouseTokens.onHeroPrimary)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.60 * Self.slow), value: hero.number)
    }

    private var label: some View {
        Text(hero.label).font(.title3.weight(.medium)).foregroundStyle(HouseTokens.onHeroSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var status: some View {
        if let s = hero.status {
            let glyph = statusGlyph.map { Text(Image(systemName: $0)) + Text(verbatim: " ") } ?? Text(verbatim: "")
            (glyph + Text(s)).font(.subheadline.weight(.semibold)).foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fullTop(_ night: Bool) -> some View {
        let houseSize: CGFloat = single ? 172 : 150
        return VStack(alignment: .leading, spacing: 0) {
            if single {
                Text(L("2026 · \(hero.flag)")).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                    .foregroundStyle(HouseTokens.drafting)
                    .lineLimit(1)
                    .padding(.bottom, 4)
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    number
                    label
                    if !single { status.padding(.top, 8) }
                }
                .layoutPriority(1)
                .padding(.bottom, 4)
                Spacer(minLength: 0)
                house(night).frame(width: houseSize, height: houseSize)
                    .padding(.trailing, -8).padding(.bottom, -10)
            }
            // One rental: the pace line runs the card's full width under the number and house, on one line.
            if single { status.padding(.top, 6) }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, single ? 16 : 12)
        // The ambient sky: a fixed box in the top-right corner, behind the house, clear of the number.
        .background(alignment: .topTrailing) {
            StdHeroAmbient().frame(width: 190, height: 64)
        }
    }

    /// D3c: number + one label; art hidden. The rental switcher is one 44pt control in the card.
    private var compactTop: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                number
                Spacer(minLength: 8)
                if !single { rentalMenu }
            }
            label
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    /// Capture hook: `-LHHeroFinished` shows the finished house so the night windows can be judged.
    private static let forceFinished = ProcessInfo.processInfo.arguments.contains("-LHHeroFinished")

    private func house(_ night: Bool) -> some View {
        let keyframe = Self.forceFinished ? HouseKeyframe.k18_finished : HouseProgress.keyframe(for: hero.stageHours)
        return ZStack {
            StdNightHouse(builtImageName: keyframe.builtImageName, night: night)
                .mask(alignment: .bottom) {
                    GeometryReader { g in
                        Rectangle().frame(height: g.size.height * rise).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            HouseLineworkImage(name: keyframe.linesImageName).foregroundStyle(HouseTokens.drafting)
            GeometryReader { g in
                // The pen: a line drawn left → right along the top edge of what is built (the newest
                // band), with a bright nib at its head. Bounds come from the built pass's own pixels.
                let b = StdBuiltBounds.unit(for: keyframe.builtImageName)
                let x0 = g.size.width * b.minX, w = g.size.width * b.width
                let y = g.size.height * b.minY
                ZStack(alignment: .leading) {
                    Rectangle().fill(HouseTokens.drafting)
                        .frame(width: w * sweep, height: 1.5)
                    Circle().fill(HouseTokens.drafting)
                        .frame(width: 5, height: 5)
                        .shadow(color: HouseTokens.drafting.opacity(0.8), radius: 3)
                        .offset(x: w * sweep - 2.5)
                }
                .offset(x: x0, y: y - 2.5)
                .opacity(sweepOpacity)
            }
            .allowsHitTesting(false)
        }
        .id(keyframe)
        .transition(.opacity)
        .animation(StdMotion.reveal, value: keyframe)
        .accessibilityHidden(true)
    }

    // MARK: Foot: the slim row of small houses (tileFocus: ring crossfade 0.15, no scale)

    private func words(_ f: HomeProtoFocus) -> (name: String, hours: String, keyframe: HouseKeyframe) {
        switch f {
        case .all:
            let t = seed.rentals.sharedTarget ?? 750
            return (L("All rentals"), L("\(Int(seed.rentals.totalHours)) of \(t)"),
                    HouseProgress.keyframe(for: min(seed.rentals.totalHours / Double(t) * 500, 500)))
        case .rental(let id):
            guard let r = seed.rentals.rental(id) else { return ("", "", .k00_lot) }
            let hours: String
            switch r.target {
            case .own(let t): hours = L("\(Int(r.hours)) of \(t)")
            case .record: hours = L("\(Int(r.hours))h · record")
            case .counts: hours = L("\(Int(r.hours))h")
            }
            return (r.name, hours, HomeProtoStage.keyframe(for: r))
        }
    }

    private var rentalRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(seed.rentals.focusOrder, id: \.self) { f in item(f).id(f) }
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
            }
            .onChange(of: focus) { _, f in withAnimation(StdMotion.flow) { proxy.scrollTo(f, anchor: .center) } }
        }
        .stdMeasure("hero.rentals")
    }

    private func item(_ f: HomeProtoFocus) -> some View {
        let w = words(f)
        let selected = focus == f
        return Button { select(f) } label: {
            HStack(spacing: 8) {
                // The real blueprint mini-house: built pass plus its drafted linework, so an early
                // stage still reads as a house (not a bare lot) at 36pt.
                ZStack {
                    Image(decorative: w.keyframe.builtImageName).resizable().interpolation(.high).antialiased(true).scaledToFit()
                    HouseLineworkImage(name: w.keyframe.linesImageName).foregroundStyle(HouseTokens.drafting)
                }
                .scaleEffect(1.25)
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.name).font(.footnote.weight(.semibold)).foregroundStyle(HouseTokens.onHeroPrimary).lineLimit(1)
                    Text(w.hours).font(.caption).monospacedDigit().foregroundStyle(HouseTokens.onHeroSecondary).lineLimit(1)
                }
            }
            .padding(.leading, 6).padding(.trailing, 12)
            .frame(minHeight: 48)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HouseTokens.onHeroPrimary, lineWidth: 1.5)
                }
                .opacity(selected ? 1 : 0)
                .animation(StdMotion.quick, value: selected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StdPressStyle())
        .accessibilityLabel(L("\(w.name), \(w.hours)"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Large text: a 44pt control in the card that opens the list of rentals.
    private var rentalMenu: some View {
        Menu {
            ForEach(seed.rentals.focusOrder, id: \.self) { f in
                Button { select(f) } label: {
                    let w = words(f)
                    Label(L("\(w.name), \(w.hours)"), systemImage: focus == f ? "checkmark" : "house")
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
        }
        .buttonStyle(StdButtonStyle(.iconOnBlueprint))
        .accessibilityLabel(L("Rental: \(words(focus).name)"))
    }
}
#endif


#if DEBUG
/// The unit bounding box of a built pass's opaque pixels (cached per keyframe). Its top edge is the
/// newest built band, where the drafting pass draws.
enum StdBuiltBounds {
    private static var cache: [String: CGRect] = [:]
    static func unit(for name: String) -> CGRect {
        if let hit = cache[name] { return hit }
        var r = CGRect(x: 0.2, y: 0.55, width: 0.6, height: 0.3)
        if let cg = UIImage(named: name)?.cgImage {
            let w = cg.width, h = cg.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            if let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                var minX = w, minY = h, maxX = 0, maxY = 0
                for y in stride(from: 0, to: h, by: 2) {
                    for x in stride(from: 0, to: w, by: 2) where px[(y * w + x) * 4 + 3] > 128 {
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
                if maxX > minX, maxY > minY {
                    // Skip the tree on the left: the band is the top of the middle 76% of the footprint.
                    let fw = Double(maxX - minX)
                    let c0 = minX + Int(fw * 0.30), c1 = minX + Int(fw * 0.88)
                    var top = maxY
                    for y in stride(from: 0, to: h, by: 2) {
                        if (stride(from: c0, to: c1, by: 2).contains { px[(y * w + $0) * 4 + 3] > 128 }) { top = y; break }
                    }
                    r = CGRect(x: (Double(minX) + fw * 0.12) / Double(w), y: Double(top) / Double(h),
                               width: fw * 0.76 / Double(w), height: Double(maxY - top) / Double(h))
                }
            }
        }
        cache[name] = r
        return r
    }
}
#endif
