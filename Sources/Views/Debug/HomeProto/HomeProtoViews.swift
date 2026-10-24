import SwiftUI
import LucideIcons

#if DEBUG
// MARK: - Root

struct HomeProtoRoot: View {
    let config: HomeProtoLaunch
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            switch config.screen {
            case .e, .seeall:
                HomeProtoTabShell {
                    NavigationStack {
                        HomeProtoToday { HomeProtoOptionE(config: config) }
                            .navigationTitle(Text("Today", tableName: "HomeProto"))
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
            case .goalcheck: HomeProtoGoalCheckRoot(config: config)
            case .stages: HomeProtoStageSheet()
            }
        }
    }
}

/// The real five-tab bar (the shipped custom tab icons), so a screen is judged with its chrome.
struct HomeProtoTabShell<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        TabView {
            content.background(colors.background.ignoresSafeArea()).tabItem { Label { Text("Today", tableName: "HomeProto") } icon: { LHIcon.home.tabItemImage } }
            Color.clear.tabItem { Label { Text("Properties", tableName: "HomeProto") } icon: { LHIcon.properties.tabItemImage } }
            Color.clear.tabItem { Label { Text("Track", tableName: "HomeProto") } icon: { LHIcon.track.tabItemImage } }
            Color.clear.tabItem { Label { Text("Reports", tableName: "HomeProto") } icon: { LHIcon.reports.tabItemImage } }
            Color.clear.tabItem { Label { Text("Settings", tableName: "HomeProto") } icon: { LHIcon.settings.tabItemImage } }
        }
        .tint(colors.action)
    }
}

/// A stand-in for the Today tab: the title, the option under test, and the Inbox row under it.
struct HomeProtoToday<Content: View>: View {
    var scrollTarget: String? = ProcessInfo.processInfo.arguments.firstIndex(of: "-LHHomeScroll")
        .flatMap { ProcessInfo.processInfo.arguments.indices.contains($0 + 1) ? ProcessInfo.processInfo.arguments[$0 + 1] : nil }
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today", tableName: "HomeProto")
                    .font(LHFont.fraunces(.largeTitle))
                    .foregroundStyle(colors.textPrimary)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                content
                HStack(spacing: 12) {
                    LucideIcon(image: Lucide.bell, size: 20).foregroundStyle(colors.action)
                    Text("2 to review in your Inbox", tableName: "HomeProto")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(colors.background.ignoresSafeArea())
        .onAppear {
            guard scrollTarget == "rentals" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("rentals", anchor: .top) }
        }
        }
    }
}

private func mono() -> Font { .system(.caption2, design: .monospaced).weight(.medium) }

// MARK: - The hero (own layout so the words scale with Dynamic Type)

/// The blueprint hero as the shipped card draws it, with one change: the eyebrow, the number and
/// the pace line follow Dynamic Type instead of stopping at Large, and the card grows with them.
/// The house itself is the shipped `HouseHeroView`; the stake and flag are the shipped ones.
struct HomeProtoHeroCard: View {
    let vm: HomeProtoSeed.HeroVM
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 56

    private var eyebrow: String {
        vm.name.map { String(localized: "\(vm.year) · \($0) · \(vm.tag)", table: "HomeProto") }
            ?? String(localized: "\(vm.year) · \(vm.tag)", table: "HomeProto")
    }

    private var statusColor: Color {
        switch vm.tone {
        case .positive: return HouseTokens.positiveOnHero
        case .caution: return HouseTokens.cautionOnHero
        case .neutral: return HouseTokens.onHeroSecondary
        }
    }

    private var statusSymbol: String? {
        switch vm.tone {
        case .positive: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .neutral: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(mono()).textCase(.uppercase).tracking(1.3)
                .foregroundStyle(HouseTokens.drafting)
                .fixedSize(horizontal: false, vertical: true)
            if let q = vm.qualifier {
                Text(q)
                    .font(mono()).textCase(.uppercase).tracking(1.3)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(vm.number)")
                .font(.system(size: min(numberSize, 90), weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(HouseTokens.onHeroPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 2)
            Text(vm.caption)
                .font(.title3.weight(.medium)).foregroundStyle(HouseTokens.onHeroSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status = vm.status {
                let glyph = statusSymbol.map { Text(Image(systemName: $0)) + Text(" ") } ?? Text("")
                (glyph + Text(status))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            houseBlock
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(HouseBlueprintPaper())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HouseTokens.blueprint.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.flag), \(vm.number) hours. \(vm.spoken)")
        .accessibilityIdentifier("house-hero-card")
    }

    private var stageWords: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vm.stageTitle).font(.subheadline.weight(.semibold)).foregroundStyle(HouseTokens.onHeroPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = vm.stageSub {
                Text(sub).font(.footnote).foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var houseBlock: some View {
        if typeSize.isAccessibilitySize {
            // Large text: the words come first and the house sits under them, so nothing collides.
            stageWords.padding(.top, 10)
            house(width: 380, flagWidth: 32 + 0.32 * 202)
                .padding(.trailing, 28).frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Color.clear.frame(height: 176)
                .overlay { GeometryReader { g in
                    let s = g.size.width * 0.62 * 0.86
                    let cx = g.size.width - 4 - s * 0.44 - 40
                    let cy = g.size.height - 6 - s * 0.417
                    house(width: g.size.width, flagWidth: 32 + 0.32 * s)
                        .frame(width: s, height: s)
                        .position(x: cx, y: cy)
                    stageWords.frame(width: max(96, cx - s * 0.46), alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                } }
        }
    }

    /// The shipped house at this stage, with the stake and flag.
    private func house(width: CGFloat, flagWidth: CGFloat) -> some View {
        let s = width * 0.62 * 0.86
        return GeometryReader { g in
            HouseHeroView(progress: HouseProgress(hours: vm.stageHours, goal: vm.goal), canvas: .blueprintHero, animatesConfirms: false)
                .overlay {
                    OnbMiniStake(name: vm.flag, maxFlagWidth: flagWidth)
                }
        }
        .frame(width: typeSize.isAccessibilitySize ? s : nil, height: typeSize.isAccessibilitySize ? s : nil)
    }
}

// MARK: - Option E: hero + one swipeable row of houses

struct HomeProtoOptionE: View {
    let seed: HomeProtoSeed
    private let autoplayOn: Bool
    @State private var focus: HomeProtoFocus
    @State private var summing: Bool
    @State private var summed: [String]
    @State private var showSeeAll: Bool
    @State private var scrollTo: String?
    @Namespace private var ring
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private let tileWidth: CGFloat = 120
    private let tileHeight: CGFloat = 176

    init(config: HomeProtoLaunch) {
        seed = config.seed
        autoplayOn = config.autoplay
        let order = config.seed.focusOrder
        _focus = State(initialValue: order.indices.contains(config.focusIndex) ? order[config.focusIndex] : order[0])
        _summing = State(initialValue: !config.sum.isEmpty)
        _summed = State(initialValue: config.sum)
        _showSeeAll = State(initialValue: config.grid)
    }

    private var tap: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0) }
    private func animate(_ body: () -> Void) { withAnimation(tap, body) }

    private var heroVM: HomeProtoSeed.HeroVM {
        summing && summed.count >= 2 ? seed.combined(summed) : seed.hero(focus)
    }

    private func select(_ f: HomeProtoFocus) {
        switch f {
        case .all:
            animate { summing = false; summed = []; focus = .all }
        case .rental(let id):
            if summing {
                animate { if let i = summed.firstIndex(of: id) { summed.remove(at: i) } else { summed.append(id) } }
            } else {
                animate { focus = f }
            }
        }
    }

    private func toggleSum() {
        animate {
            if summing { summing = false; summed = [] }
            else {
                summing = true
                if case .rental(let id) = focus { summed = [id] } else { summed = [] }
            }
        }
    }

    private func step(_ delta: Int) {
        guard !summing else { return }
        let order = seed.focusOrder
        guard let i = order.firstIndex(of: focus), order.indices.contains(i + delta) else { return }
        select(order[i + delta])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                HomeProtoHeroCard(vm: heroVM).id(heroVM.key).transition(.opacity)
            }
            .background(HouseBlueprintPaper().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { v in
                    guard abs(v.translation.width) > 48, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    step(v.translation.width < 0 ? 1 : -1)
                })

            VStack(alignment: .leading, spacing: 10) {
                header
                if typeSize.isAccessibilitySize { list } else { tiles }
            }
            .id("rentals")
            .accessibilityElement(children: .contain)
        }
        .navigationDestination(isPresented: $showSeeAll) {
            HomeProtoSeeAll(seed: seed) { f in showSeeAll = false; select(f) }
        }
        .task { await autoplay() }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) { headerText; Spacer(minLength: 8); addUpButton }
            VStack(alignment: .leading, spacing: 6) { headerText; addUpButton }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Your rentals", tableName: "HomeProto")
                .font(mono()).textCase(.uppercase).tracking(1.3).foregroundStyle(colors.draftingInk)
                .accessibilityAddTraits(.isHeader)
            if summing {
                Text("Tap rentals to add them up", tableName: "HomeProto")
                    .font(.footnote.weight(.medium)).foregroundStyle(colors.textSecondary)
            } else {
                Text("\(Int(seed.totalHours.rounded(.down)))h logged this year", tableName: "HomeProto")
                    .font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(colors.textSecondary)
            }
        }
    }

    private var addUpButton: some View {
        Button { toggleSum() } label: {
            Text(summing ? String(localized: "Done", table: "HomeProto") : String(localized: "Add up rentals", table: "HomeProto"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summing ? colors.onAction : colors.action)
                .padding(.horizontal, 14).frame(minHeight: 34)
                .background(Capsule().fill(summing ? colors.action : colors.actionSurface))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier("e.addup")
    }

    // MARK: Row of tiles

    private func isFocused(_ f: HomeProtoFocus) -> Bool { !summing && focus == f }
    private func isSelected(_ f: HomeProtoFocus) -> Bool {
        if summing, case .rental(let id) = f { return summed.contains(id) }
        return !summing && focus == f
    }

    private var tiles: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if seed.sharedTarget != nil { allTile }
                    ForEach(seed.rentals) { r in rentalTile(r) }
                    if seed.rentals.count >= 6 { seeAllTile }
                    addTile
                }
                .scrollTargetLayout()
                .padding(.vertical, 4).padding(.horizontal, 2)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(focus, anchor: .center) }
            .onChange(of: focus) { _, f in withAnimation(tap) { proxy.scrollTo(f, anchor: .center) } }
            .onChange(of: scrollTo) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(id, anchor: .trailing) }
            }
        }
    }

    /// 120 x 176: art box, optional 3pt bar, name, hours, plan. A tile never changes size when focused.
    private func tileFrame<Art: View>(_ f: HomeProtoFocus, label: String, name: String, hours: String, plan: String,
                                      bar: (fraction: Double, color: Color)?, reached: Bool,
                                      @ViewBuilder art: () -> Art) -> some View {
        let selected = isSelected(f)
        return Button { select(f) } label: {
            VStack(alignment: .leading, spacing: 0) {
                art().frame(maxWidth: .infinity)
                Group {
                    if let bar {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(colors.border)
                                Capsule().fill(bar.color).frame(width: max(3, g.size.width * min(1, bar.fraction)))
                            }
                        }
                    } else { Color.clear }
                }
                .frame(height: 3).padding(.horizontal, 4).padding(.top, 8)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85).padding(.top, 8)
                Text(hours).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(colors.textPrimary).lineLimit(1).padding(.top, 2)
                Text(plan).font(.system(size: 11)).foregroundStyle(colors.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85).padding(.top, 2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
            .frame(width: tileWidth, height: tileHeight, alignment: .topLeading)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if reached {
                    ZStack {
                        Circle().fill(colors.action)
                        LucideIcon(image: Lucide.check, size: 12).foregroundStyle(colors.onAction)
                    }
                    .frame(width: 22, height: 22).offset(x: -4, y: 4)
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.action, lineWidth: 2)
                        .matchedGeometryEffect(id: summing ? "sum-\(name)" : "ring", in: ring)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id(f)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func rentalTile(_ r: HomeProtoRental) -> some View {
        let f = HomeProtoFocus.rental(r.id)
        let under: Bool = { if case .own(let t) = r.target { return r.hours < Double(t) }; return false }()
        let bar: (Double, Color)? = under ? (ownFraction(r) ?? 0, HomeProtoPaceStyle.color(r, colors)) : nil
        return tileFrame(f, label: seed.spoken(r), name: r.name, hours: seed.tileHours(r), plan: seed.tilePlan(r),
                         bar: bar, reached: r.pace == .done) {
            HomeProtoArt(size: 88, keyframe: HomeProtoStage.keyframe(for: r), style: isFocused(f) ? .plain : .quiet)
                .overlay(alignment: .topTrailing) {
                    if summing && summed.contains(r.id) {
                        ZStack { Circle().fill(colors.action); LucideIcon(image: Lucide.check, size: 12).foregroundStyle(colors.onAction) }
                            .frame(width: 22, height: 22).offset(x: 6, y: -6)
                    }
                }
        }
    }

    private func ownFraction(_ r: HomeProtoRental) -> Double? {
        if case .own(let t) = r.target { return r.hours / Double(t) }
        return nil
    }

    private var allTile: some View {
        let total = seed.totalHours, target = Double(seed.sharedTarget ?? 750)
        return tileFrame(.all, label: String(localized: "All rentals, \(Int(total)) of \(Int(target)) hours", table: "HomeProto"),
                         name: seed.name(.all), hours: String(localized: "\(Int(total)) of \(Int(target))", table: "HomeProto"),
                         plan: String(localized: "One shared total", table: "HomeProto"),
                         bar: (total / target, colors.action), reached: false) {
            HomeProtoArt(size: 88, keyframe: HomeProtoStage.keyframe(hours: total), style: .plain)
        }
    }

    private var seeAllTile: some View {
        Button { showSeeAll = true } label: {
            VStack(spacing: 14) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        HomeProtoArt(size: 40, keyframe: .k00_lot, style: .plain)
                            .offset(x: CGFloat(i - 1) * 6, y: CGFloat(i - 1) * 6)
                            .zIndex(Double(i))
                    }
                }
                .frame(width: 56, height: 56)
                VStack(spacing: 2) {
                    Text("See all", tableName: "HomeProto").font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.action)
                    Text("\(seed.rentals.count) rentals", tableName: "HomeProto").font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.action)
                }
            }
            .frame(width: tileWidth, height: tileHeight)
            .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id("seeall")
        .accessibilityLabel(String(localized: "See all \(seed.rentals.count) rentals", table: "HomeProto"))
    }

    private var addTile: some View {
        Button {} label: {
            VStack(spacing: 8) {
                LucideIcon(image: Lucide.plus, size: 22).foregroundStyle(colors.action)
                Text("Add", tableName: "HomeProto").font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.action)
            }
            .frame(width: 80, height: tileHeight)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(colors.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
        }
        .buttonStyle(.lhPressable)
        .id("add")
    }

    // MARK: Large text: the See-all row grammar, three shown

    private var list: some View {
        let order = seed.focusOrder
        return VStack(spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(order.prefix(3).enumerated()), id: \.element) { i, f in
                    if i > 0 { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 84) }
                    listRow(f)
                }
            }
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if order.count > 3 {
                Button { showSeeAll = true } label: {
                    Text("See all \(order.count) rentals", tableName: "HomeProto")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.lhPressable)
            }
        }
    }

    @ViewBuilder private func listRow(_ f: HomeProtoFocus) -> some View {
        let selected = isSelected(f)
        Button { select(f) } label: {
            Group {
                switch f {
                case .rental(let id):
                    if let r = seed.rental(id) { HomeProtoRentalRow(seed: seed, r: r) }
                case .all:
                    let total = seed.totalHours, target = seed.sharedTarget ?? 750
                    HomeProtoListRow(keyframe: HomeProtoStage.keyframe(hours: total), name: seed.name(.all),
                                     plan: String(localized: "One shared total", table: "HomeProto")) {
                        HomeProtoNumber(main: "\(Int(total))", rest: String(localized: "of \(target)", table: "HomeProto"))
                    } tag: { EmptyView() }
                }
            }
            .overlay { if selected { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2) } }
        }
        .buttonStyle(.lhPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Scripted tour for the video (-LHHomeAutoplay)

    private func autoplay() async {
        guard autoplayOn else { return }
        let order = seed.focusOrder
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await pause(1.5)
        for i in [1, 2, 3] where order.indices.contains(i) { select(order[i]); await pause(1.4) }
        select(order[0]); await pause(1.2)
        toggleSum(); await pause(1.2)
        for i in [1, 2] where order.indices.contains(i) { select(order[i]); await pause(1.3) }
        await pause(0.8)
        toggleSum(); await pause(1.3)
        scrollTo = "seeall"; await pause(1.4)
        if seed.rentals.count >= 6 { showSeeAll = true; await pause(3.2); showSeeAll = false; await pause(1.0) }
    }
}
#endif
