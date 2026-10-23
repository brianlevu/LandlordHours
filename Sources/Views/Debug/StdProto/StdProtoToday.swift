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

    @State private var logRequest = 0

    private var seed: StdSeed { StdSeed.make(launch.seedID) }

    @ViewBuilder private var today: some View {
        if launch.screen == .seeall {
            NavigationStack { StdSeeAllScreen(seed: seed) }
        } else {
            StdTodayScreen(seed: seed, launch: launch, openInbox: { tab = 1 }, logRequest: logRequest)
        }
    }

    private var records: some View { colors.background.ignoresSafeArea() }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) { nativeTabs } else { legacyTabs }
        }
        .tint(colors.action)
    }

    /// iOS 26+: the system Liquid Glass tab bar. Log time is the detached trailing glass button
    /// (the `.search`-role slot, the place Music and Photos give their one special action): a tap
    /// opens the Log time sheet over Today. The bar shrinks while scrolling down.
    @available(iOS 26.0, *)
    private var nativeTabs: some View {
        TabView(selection: $tab) {
            Tab(L("Today"), systemImage: "sun.max", value: 0) { today }
            Tab(L("Inbox"), systemImage: "tray", value: 1) { StdInboxScreen(seed: seed, launch: launch) }
                .badge(seed.suggestions.count)
            Tab(L("Records"), systemImage: "list.bullet.rectangle", value: 2) { records }
            Tab(L("Properties"), systemImage: "house", value: 3) { records }
            Tab(value: 4, role: .search) { Color.clear } label: { Label(L("Log time"), systemImage: "plus") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: tab) { _, new in
            guard new == 4 else { return }
            tab = 0
            logRequest += 1
        }
    }

    /// iOS 17–25 fallback: the classic tab bar; Log time stays in Today's title row.
    private var legacyTabs: some View {
        TabView(selection: $tab) {
            today.tabItem { Label(L("Today"), systemImage: "sun.max") }.tag(0)
            StdInboxScreen(seed: seed, launch: launch)
                .tabItem { Label(L("Inbox"), systemImage: "tray") }.tag(1)
                .badge(seed.suggestions.count)
            records.tabItem { Label(L("Records"), systemImage: "list.bullet.rectangle") }.tag(2)
            records.tabItem { Label(L("Properties"), systemImage: "house") }.tag(3)
        }
    }
}

// MARK: - Today as an inset-grouped List (§1.3a)

struct StdTodayScreen: View {
    let seed: StdSeed
    let launch: StdProtoLaunch
    var openInbox: () -> Void = {}
    /// Increments when the tab bar's Log time button is tapped.
    var logRequest = 0
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

    init(seed: StdSeed, launch: StdProtoLaunch, openInbox: @escaping () -> Void = {}, logRequest: Int = 0) {
        self.seed = seed
        self.launch = launch
        self.openInbox = openInbox
        self.logRequest = logRequest
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
        .onChange(of: logRequest) { _, _ in showLog = true }
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
                    }
                }
                // §1.3 foot: "Confirm N likely", centred, only when N ≥ 2. "Review all N" lives in the header.
                if likely.count >= 2 {
                    Button(StdCanon.confirmLikely(likely.count)) { confirmLikely() }
                        .buttonStyle(StdButtonStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(colors.backgroundSecondary)
                        .accessibilityIdentifier("today.confirmLikely")
                        .stdMeasure("foot")
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
                // iOS 26+: Log time is the tab bar's trailing glass button; earlier versions keep it here.
                if #unavailable(iOS 26.0) {
                    Button { showLog = true } label: { Image(systemName: "plus") }
                        .buttonStyle(StdButtonStyle(.icon))
                        .accessibilityLabel(L("Log time"))
                }
            }
            .padding(.bottom, 8)
            StdHeroCard(seed: live, focus: $focus).stdMeasure("hero").padding(.top, 16)
            StdSectionHeader(title: L("To confirm"), count: waiting,
                             trailing: waiting > shown.count ? L("Review all") : nil, onTrailing: openInbox)
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
    /// buildStep: the app's own confirm language (HouseHeroView's timber beam + course glow),
    /// re-timed to ≤ 0.6s for every logged or confirmed hour.
    @State private var beamLabel: String?
    @State private var beamAt: CGPoint = .zero
    @State private var beamScale: CGFloat = 1
    @State private var beamOpacity: Double = 0
    @State private var glow: Double = 0
    @State private var buildTick = 0
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
        .onChange(of: hero.number) { old, new in if new > old { buildStep(new - old) } }
        .sensoryFeedback(.selection, trigger: focus)
        .sensoryFeedback(.impact(weight: .light), trigger: buildTick)
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
    /// `-LHStdSlow 4` plays the hero motions at quarter speed for review clips.
    private static let slow: Double = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-LHStdSlow"), a.indices.contains(i + 1) else { return 1 }
        return Double(a[i + 1]) ?? 1
    }()

    /// buildStep (replaces the drafting pass, Brian 2026-10-23): one timber plank, labelled with the
    /// hours ("+1h", HouseBeam), flies from the number onto the house's newest course
    /// (HouseKeyframe.courseAnchor) on the HouseMotion beam spring, lands with the course glow and
    /// the light haptic, and is absorbed. A crossed stage crossfades to the next bp_house_k* keyframe.
    /// Total 0.48s scripted: flight 0.18, absorb 0.12, glow out 0.18. Reduce Motion: number and house change in place.
    private func buildStep(_ delta: Double) {
        StdMotionLog.mark("buildStep")
        guard !reduceMotion else { buildTick += 1; return }
        let k = Self.slow
        beamLabel = HouseHeroView.deltaLabel(delta)
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { beamAt = CGPoint(x: -0.55, y: 0.25); beamScale = 1; beamOpacity = 1; glow = 0 }
        withAnimation(.spring(response: HouseMotion.beamSpringResponse * k, dampingFraction: HouseMotion.beamSpringDamping)) {
            beamAt = CGPoint(x: 0.5, y: 0.6)   // replaced by the course anchor in house(_:)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.beamFlight * k * 1_000_000_000))
            buildTick += 1
            withAnimation(.easeOut(duration: HouseMotion.glowIn * k)) { glow = 1 }
            withAnimation(.easeIn(duration: 0.12 * k)) { beamScale = 0.3; beamOpacity = 0 }
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.glowIn * k * 1_000_000_000))
            withAnimation(.easeOut(duration: 0.18 * k)) { glow = 0 }
        }
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
        let houseSize: CGFloat = single ? (typeSize >= .xxLarge ? 132 : 172) : 150
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
        }
        .id(keyframe)
        .transition(.opacity)
        .animation(.easeInOut(duration: HouseMotion.keyframeCrossfade), value: keyframe)
        .overlay { buildLayer(keyframe) }
        .accessibilityHidden(true)
    }

    /// The beam and the course glow, drawn over the house (HouseHeroView's look, shared tokens).
    private func buildLayer(_ keyframe: HouseKeyframe) -> some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let anchor = keyframe.courseAnchor
            Capsule()
                .fill(RadialGradient(colors: [HouseTokens.window, HouseTokens.window.opacity(0)], center: .center, startRadius: 0, endRadius: s * 0.26))
                .frame(width: s * 0.56, height: s * 0.13)
                .blur(radius: 5)
                .blendMode(.plusLighter)
                .position(x: anchor.x * s, y: anchor.y * s)
                .opacity(glow)
            if let label = beamLabel {
                // Flight target is the course anchor; the start is left of the house, by the number.
                let landed = beamAt.x > 0
                HouseBeam(label: label)
                    .scaleEffect(beamScale * 0.8)
                    .rotationEffect(.degrees(-6))
                    .position(x: (landed ? anchor.x : beamAt.x) * s, y: (landed ? anchor.y : beamAt.y) * s)
                    .opacity(beamOpacity)
            }
        }
        .allowsHitTesting(false)
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


