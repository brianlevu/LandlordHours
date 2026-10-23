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
                    StdTodayScreen(seed: seed, launch: launch)
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
    @State private var focus: HomeProtoFocus
    @State private var items: [StdSuggestion]
    @State private var confirmed: Set<String> = []
    @State private var extra: [String: Double] = [:]
    @State private var toast: LHToastSpec?
    @State private var successTick = 0
    @State private var dismissTick = 0
    @State private var showLog: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(seed: StdSeed, launch: StdProtoLaunch) {
        self.seed = seed
        self.launch = launch
        _focus = State(initialValue: seed.rentals.focusOrder.first ?? .all)
        _items = State(initialValue: Array(seed.suggestions.prefix(3)))
        _showLog = State(initialValue: launch.screen == .logtime)
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

    private var likely: [StdSuggestion] { items.filter { $0.isLikely && !confirmed.contains($0.id) } }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                confirmSection
                if typeSize.isAccessibilitySize {
                    // Large text: the rentals row moves under the confirm list so a row stays above the fold (D3c).
                    Section {} header: {
                        VStack(alignment: .leading, spacing: 8) {
                            StdSectionHeader(title: L("Your rentals"))
                            StdRentalTiles(seed: live, focus: $focus).stdMeasure("tiles")
                        }
                        .stdHeaderInsets()
                    }
                }
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
            StdLogTimeSheet(seed: seed, launch: launch) { showLog = false }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await demo() }
    }

    // MARK: To confirm

    @ViewBuilder private var confirmSection: some View {
        Section {
            if items.isEmpty {
                Label { Text(L("Nothing to confirm.")) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.positive) }
                    .font(.subheadline).foregroundStyle(colors.textSecondary)
                    .listRowBackground(colors.backgroundSecondary)
            }
            ForEach(items) { item in
                StdActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
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
                    .transition(.opacity)
            }
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
            // Title, hero and tiles live in the header: List masks a row's corners with its own
            // radius, which clips anything drawn to the row edge (measured: the tile's ring).
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    StdScreenTitle(title: L("Today"), subtitle: typeSize.isAccessibilitySize ? nil : L("Fri, Oct 23"))
                    Button { showLog = true } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(StdButtonStyle(.icon))
                        .accessibilityLabel(L("Log time"))
                }
                .padding(.bottom, 8)
                StdHeroCard(hero: live.hero(focus)).stdMeasure("hero").padding(.top, 16)
                if !typeSize.isAccessibilitySize {
                    StdRentalTiles(seed: live, focus: $focus).stdMeasure("tiles").padding(.top, 12)
                }
                StdSectionHeader(title: L("To confirm"), count: seed.suggestions.count - (seed.suggestions.prefix(3).count - items.count),
                                 trailing: L("See all"))
                    .padding(.top, 24)
            }
            .stdHeaderInsets()
        }
    }

    private func confirm(_ item: StdSuggestion, swipe: Bool = false) {
        guard item.canQuickLog, !confirmed.contains(item.id) else { return }
        StdMotionLog.mark(swipe ? "swipeConfirm" : "rowConfirm")
        withAnimation(reduceMotion ? StdMotion.quick : StdMotion.feedback) { _ = confirmed.insert(item.id) }
        successTick += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: swipe ? 0 : 120_000_000)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : StdMotion.collapse) {
                items.removeAll { $0.id == item.id }
            }
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
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : StdMotion.collapse) { items.removeAll { $0.id == item.id } }
        show(LHToastSpec(kind: .neutral, message: L("Marked not rental work."), actionTitle: L("Undo")))
    }

    private func confirmLikely() {
        let batch = likely
        StdMotionLog.mark("rowConfirm.batch")
        withAnimation(StdMotion.feedback) { batch.forEach { confirmed.insert($0.id) } }
        successTick += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(StdMotion.collapse) { items.removeAll { item in batch.contains { $0.id == item.id } } }
            withAnimation(StdMotion.count) {
                for item in batch { if let r = item.rental, let h = item.hours { extra[r, default: 0] += h } }
            }
            show(LHToastSpec(kind: .success, message: L("Logged \(batch.count)."), actionTitle: L("Undo")))
        }
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

    private func demo() async {
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        switch launch.demo {
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

// MARK: - Blueprint hero, compact (≈ 240pt, house beside the number)

struct StdHeroCard: View {
    let hero: StdSeed.Hero
    @State private var rise: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 56

    private var statusColor: Color {
        switch hero.tone {
        case .positive: return HouseTokens.positiveOnHero
        case .caution: return HouseTokens.cautionOnHero
        case .neutral: return HouseTokens.onHeroSecondary
        }
    }

    private var statusWords: String { hero.status ?? "" }

    private var statusGlyph: String? {
        switch hero.tone {
        case .positive: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .neutral: return nil
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { compact } else { full }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HouseBlueprintPaper())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(hero.flag), \(Int(hero.number)) \(hero.label). \(statusWords)"))
        .accessibilityIdentifier("std.hero")
        .onChange(of: hero.key) { _, _ in raise(from: 0.45) }
        .onChange(of: hero.number) { old, new in if new > old { raise(from: 0.82) } }
    }

    /// heroCountUp: the built house rises behind its linework (ringProgress 0.60) while the digits count (count 0.60).
    private func raise(from start: CGFloat) {
        StdMotionLog.mark("heroCountUp")
        guard !reduceMotion else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { rise = start }
        withAnimation(StdMotion.ringProgress) { rise = 1 }
    }

    private var eyebrow: some View {
        Text(hero.eyebrow).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
            .foregroundStyle(HouseTokens.drafting)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }

    private var number: some View {
        StdCountingText(value: hero.number)
            .font(.system(size: min(numberSize, typeSize.isAccessibilitySize ? 64 : 80), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(HouseTokens.onHeroPrimary)
            .animation(reduceMotion ? nil : StdMotion.count, value: hero.number)
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

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    number
                    label
                    status.padding(.top, 8)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                house.frame(width: 164, height: 164)
                    .padding(.top, -12).padding(.trailing, -10).padding(.bottom, -6)
            }
        }
        .padding(16)
    }

    /// D3c: number + one label, art and eyebrow hidden (the rental's name rides in the label).
    private var compact: some View {
        VStack(alignment: .leading, spacing: 2) {
            number
            Text(hero.label).font(.title3.weight(.medium)).foregroundStyle(HouseTokens.onHeroSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var house: some View {
        let keyframe = HouseProgress.keyframe(for: hero.stageHours)
        return ZStack {
            Image(decorative: keyframe.builtImageName).resizable().interpolation(.high).scaledToFit()
                .mask(alignment: .bottom) {
                    GeometryReader { g in
                        Rectangle().frame(height: g.size.height * rise).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            HouseLineworkImage(name: keyframe.linesImageName).foregroundStyle(HouseTokens.drafting)
        }
        .id(keyframe)
        .transition(.opacity)
        .animation(StdMotion.reveal, value: keyframe)
        .accessibilityHidden(true)
    }
}

// MARK: - The rental tile row (tileFocus: ring crossfades border → action, 0.15, no scale)

struct StdRentalTiles: View {
    let seed: StdSeed
    @Binding var focus: HomeProtoFocus
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seed.rentals.focusOrder, id: \.self) { f in tile(f).id(f) }
                    addTile
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .onChange(of: focus) { _, f in withAnimation(StdMotion.flow) { proxy.scrollTo(f, anchor: .center) } }
        }
        .sensoryFeedback(.selection, trigger: focus)
    }

    private func words(_ f: HomeProtoFocus) -> (String, String, HouseKeyframe) {
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

    private func tile(_ f: HomeProtoFocus) -> some View {
        let w = words(f)
        let selected = focus == f
        return Button {
            StdMotionLog.mark("tileFocus")
            withAnimation(StdMotion.quick) { focus = f }
        } label: {
            HStack(spacing: 10) {
                if !typeSize.isAccessibilitySize { HomeProtoArt(size: 44, keyframe: w.2) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.0).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary).lineLimit(1)
                    Text(w.1).font(.caption).fontDesign(.rounded).monospacedDigit().foregroundStyle(colors.textSecondary).lineLimit(1)
                }
            }
            .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.border, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2)
                        .opacity(selected ? 1 : 0)
                }
                .animation(StdMotion.quick, value: selected)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(StdPressStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var addTile: some View {
        Button {} label: {
            Label(L("Add"), systemImage: "plus")
                .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(StdPressStyle())
        .accessibilityLabel(L("Add a rental"))
    }
}
#endif
