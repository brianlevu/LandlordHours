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
            case .e: HomeProtoToday { HomeProtoOptionE(seed: config.seed, startIndex: config.focusIndex) }
            case .a: HomeProtoToday { HomeProtoOptionA(seed: config.seed, startIndex: config.focusIndex) }
            case .b: HomeProtoToday { HomeProtoOptionB(seed: config.seed, startIndex: config.focusIndex) }
            case .goalcheck: HomeProtoGoalCheckRoot(step: config.step)
            }
        }
    }
}

/// A stand-in for the Today tab: the title, the option under test, and the Inbox row under it
/// so the cost in first-screen height is visible.
struct HomeProtoToday<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today", tableName: "HomeProto")
                    .font(LHFont.fraunces(.largeTitle))
                    .foregroundStyle(colors.textPrimary)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                content
                HStack(spacing: 12) {
                    LucideIcon(image: Lucide.bell, size: 20)
                        .foregroundStyle(colors.action)
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
    }
}

// MARK: - The hero for one focus

struct HomeProtoHero: View {
    let seed: HomeProtoSeed
    let focus: HomeProtoFocus

    var body: some View {
        let m = seed.hero(focus)
        HouseHeroCard(
            progress: m.progress,
            year: 2026,
            status: m.copy.status,
            statusTone: m.copy.tone,
            heroCopy: m.copy,
            stakeName: m.flag,
            animatesChanges: false)
    }
}

private func mono(_ size: CGFloat) -> Font { .system(.caption2, design: .monospaced).weight(.medium) }

// MARK: - Option E: hero + a row of mini-houses

struct HomeProtoOptionE: View {
    let seed: HomeProtoSeed
    @State private var focus: HomeProtoFocus
    @Namespace private var ring
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAll = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(seed: HomeProtoSeed, startIndex: Int) {
        self.seed = seed
        let order = seed.focusOrder
        _focus = State(initialValue: order.indices.contains(startIndex) ? order[startIndex] : order[0])
    }

    private var tap: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0) }

    private func select(_ f: HomeProtoFocus) { withAnimation(tap) { focus = f } }

    private func step(_ delta: Int) {
        let order = seed.focusOrder
        guard let i = order.firstIndex(of: focus) else { return }
        let n = i + delta
        if order.indices.contains(n) { select(order[n]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                HomeProtoHero(seed: seed, focus: focus)
                    .id(focus)
                    .transition(.opacity)
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
            .accessibilityElement(children: .contain)
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-LHHomeAutoplay") else { return }
            let order = seed.focusOrder
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for i in [1, 2, 0, 1, 2, 0] where order.indices.contains(i) {
                select(order[i])
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                headerTitle
                Spacer(minLength: 8)
                headerTotal
            }
            VStack(alignment: .leading, spacing: 2) { headerTitle; headerTotal }
        }
    }

    private var headerTitle: some View {
        Text("Your rentals", tableName: "HomeProto")
            .font(mono(11)).textCase(.uppercase).tracking(1.3)
            .foregroundStyle(colors.draftingInk)
            .accessibilityAddTraits(.isHeader)
    }

    private var headerTotal: some View {
        Text("\(Int(seed.totalHours.rounded(.down)))h logged this year", tableName: "HomeProto")
            .font(.footnote.weight(.medium)).monospacedDigit()
            .foregroundStyle(colors.textSecondary)
    }

    // MARK: Tiles

    private var tileWidth: CGFloat { seed.id == "brian" ? 112 : 104 }

    private var tiles: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if seed.sharedTarget != nil { allTile }
                    ForEach(seed.rentals) { r in rentalTile(r) }
                    addTile
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(focus, anchor: .center) }
            .onChange(of: focus) { _, f in withAnimation(tap) { proxy.scrollTo(f, anchor: .center) } }
        }
    }

    private func tileFrame<Art: View>(_ f: HomeProtoFocus, label: String, name: String, line1: String, line2: String, @ViewBuilder art: () -> Art) -> some View {
        let selected = focus == f
        return Button { select(f) } label: {
            VStack(alignment: .leading, spacing: 4) {
                art()
                Text(name).font(.footnote.weight(.semibold)).foregroundStyle(colors.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text(line1).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(colors.textPrimary).lineLimit(1)
                Text(line2).font(.caption2).foregroundStyle(colors.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: tileWidth - 20, alignment: .leading)
            .padding(10)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(colors.action, lineWidth: 2)
                        .matchedGeometryEffect(id: "ring", in: ring)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id(f)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func rentalTile(_ r: HomeProtoRental) -> some View {
        tileFrame(.rental(r.id), label: seed.spoken(r), name: r.name, line1: seed.hoursLine(r), line2: seed.targetLine(r)) {
            PropertyHouseTile(hours: r.houseHours, size: tileWidth - 20)
                .opacity(r.isRecord ? 0.78 : 1)
        }
    }

    private var allTile: some View {
        tileFrame(.all, label: String(localized: "All rentals, \(Int(seed.totalHours)) of \(seed.sharedTarget ?? 750) hours", table: "HomeProto"),
                  name: seed.name(.all), line1: String(localized: "\(Int(seed.totalHours)) of \(seed.sharedTarget ?? 750)", table: "HomeProto"),
                  line2: String(localized: "One shared total", table: "HomeProto")) {
            PropertyHouseTile(hours: min(seed.totalHours / Double(seed.sharedTarget ?? 750) * 500, 500), size: tileWidth - 20)
        }
    }

    private var addTile: some View {
        Button {} label: {
            VStack(spacing: 8) {
                LucideIcon(image: Lucide.circlePlus, size: 24).foregroundStyle(colors.action)
                Text("Add", tableName: "HomeProto")
                    .font(.footnote.weight(.semibold)).foregroundStyle(colors.action)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 64, height: tileWidth + 36)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.lhPressable)
    }

    // MARK: Large text: a list instead of a row

    private var list: some View {
        let order = seed.focusOrder
        let shown = showAll ? order : Array(order.prefix(3))
        return VStack(spacing: 8) {
            ForEach(shown, id: \.self) { f in listRow(f) }
            if order.count > 3 && !showAll {
                Button { withAnimation(tap) { showAll = true } } label: {
                    Text("See all \(order.count) rentals", tableName: "HomeProto")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.lhPressable)
            }
        }
    }

    private func listRow(_ f: HomeProtoFocus) -> some View {
        let r: HomeProtoRental? = { if case .rental(let id) = f { return seed.rental(id) } else { return nil } }()
        let selected = focus == f
        return Button { select(f) } label: {
            HStack(spacing: 12) {
                PropertyHouseTile(hours: r?.houseHours ?? min(seed.totalHours / 750 * 500, 500), size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r?.name ?? seed.name(.all)).font(.headline).foregroundStyle(colors.textPrimary)
                    Text(r.map { String(localized: "\(seed.hoursLine($0)) · \(seed.targetLine($0))", table: "HomeProto") } ?? String(localized: "\(Int(seed.totalHours)) of \(seed.sharedTarget ?? 750)", table: "HomeProto"))
                        .font(.subheadline).foregroundStyle(colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2) }
            }
        }
        .buttonStyle(.lhPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Option A: a pager

struct HomeProtoOptionA: View {
    let seed: HomeProtoSeed
    @State private var index: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 320
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    /// Shared total: one page. Otherwise one page per rental.
    private var pages: [HomeProtoFocus] { seed.sharedTarget != nil ? [.all] : seed.rentals.map { .rental($0.id) } }
    private var pageHeight: CGFloat { min(max(scaledHeight, 320), 460) + 36 }

    init(seed: HomeProtoSeed, startIndex: Int) {
        self.seed = seed
        _index = State(initialValue: max(0, min(startIndex, (seed.sharedTarget != nil ? 1 : seed.rentals.count) - 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, f in
                    HomeProtoHero(seed: seed, focus: f)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .tag(i)
                        .accessibilityElement(children: .contain)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: pageHeight)
            .padding(.horizontal, -20)

            if pages.count > 1 { pageIndicator }
            if case .rental(let id) = pages[min(index, pages.count - 1)], let r = seed.rental(id), case .record(let reason) = r.target {
                (Text("Record only: ", tableName: "HomeProto").fontWeight(.semibold) + Text("\(r.name) · \(reason)"))
                    .font(.footnote).foregroundStyle(colors.textSecondary)
            }
            Text(summary)
                .font(.footnote.weight(.medium)).monospacedDigit()
                .foregroundStyle(colors.textSecondary)
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-LHHomeAutoplay") else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for i in [1, 2, 1, 0, 1, 2, 0] where pages.indices.contains(i) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { index = i }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }

    private var summary: String {
        let hours = Int(seed.totalHours.rounded(.down))
        let n = seed.rentals.count
        return seed.sharedTarget != nil
            ? String(localized: "\(n) rentals count toward this · \(hours)h logged this year", table: "HomeProto")
            : String(localized: "\(n) rentals · \(hours)h logged this year", table: "HomeProto")
    }

    @ViewBuilder private var pageIndicator: some View {
        if pages.count > 5 {
            Text("\(index + 1) of \(pages.count)", tableName: "HomeProto")
                .font(mono(11)).tracking(1.3).foregroundStyle(colors.draftingInk)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        } else {
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? colors.action : colors.textTertiary.opacity(0.5))
                        .frame(width: i == index ? 20 : 7, height: 7)
                        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: index)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Option B: one street (a still composite, for a gut check only)

struct HomeProtoOptionB: View {
    let seed: HomeProtoSeed
    @State private var focus: Int
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 320
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var cardHeight: CGFloat { min(max(scaledHeight, 320), 460) }

    init(seed: HomeProtoSeed, startIndex: Int) {
        self.seed = seed
        _focus = State(initialValue: max(0, min(startIndex, seed.rentals.count - 1)))
    }

    private var focused: HomeProtoRental { seed.rentals[focus] }

    var body: some View {
        let h = seed.hero(.rental(focused.id))
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                HouseBlueprintPaper()
                street
                VStack(alignment: .leading, spacing: 2) {
                    Text("2026 · \(seed.rentals.count) rentals · \(Int(seed.totalHours))h logged", tableName: "HomeProto")
                        .font(mono(11)).textCase(.uppercase).tracking(1.3)
                        .foregroundStyle(HouseTokens.drafting)
                        .lineLimit(2)
                    Text("\(Int(focused.hours.rounded(.down)))")
                        .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .padding(.top, 2)
                    Text(h.copy.caption)
                        .font(.title3.weight(.medium)).foregroundStyle(HouseTokens.onHeroSecondary)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                }
                .padding(20)
            }
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: HouseTokens.blueprint.opacity(0.25), radius: 16, y: 8)
            .accessibilityElement(children: .contain)
            Text("This is a still, put together from the shipped house art. It is only for a gut check.", tableName: "HomeProto")
                .font(.footnote).foregroundStyle(colors.textSecondary)
        }
    }

    /// Focused house in the middle at ~55% of the card, neighbours at ~35%, one ground line.
    private var street: some View {
        GeometryReader { g in
            let n = seed.rentals.count
            let others = (0..<n).filter { $0 != focus }.prefix(2)
            let ids: [Int] = others.count == 2 ? [others[others.startIndex], focus, others[others.startIndex + 1]] : (others.first.map { [$0, focus] } ?? [focus])
            let big = g.size.width * 0.5, small = g.size.width * 0.32
            ZStack(alignment: .bottom) {
                Rectangle().fill(HouseTokens.drafting.opacity(0.55)).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 44)
                HStack(alignment: .bottom, spacing: -g.size.width * 0.08) {
                    ForEach(ids, id: \.self) { i in
                        let r = seed.rentals[i]
                        let isFocus = i == focus
                        let size = isFocus ? big : small
                        Button { withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) { focus = i } } label: {
                            VStack(spacing: 2) {
                                HouseArtView(keyframe: PropertyHouseStage.keyframe(for: r.houseHours), canvas: .blueprintHero)
                                    .frame(width: size, height: size)
                                    .opacity(isFocus ? 1 : 0.85)
                                Text(r.name)
                                    .font(mono(isFocus ? 11 : 10)).textCase(.uppercase).tracking(1)
                                    .foregroundStyle(isFocus ? HouseTokens.onHeroPrimary : HouseTokens.onHeroSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    .frame(width: size)
                            }
                            .overlay(alignment: .topTrailing) {
                                if isFocus { OnbFlag(name: r.name, maxTextWidth: 90).frame(height: 18).offset(x: 24, y: size * 0.30) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(seed.spoken(r))
                        .accessibilityAddTraits(isFocus ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
        }
    }
}
#endif
