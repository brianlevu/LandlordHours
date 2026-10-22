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
            case .e: HomeProtoToday { HomeProtoOptionE(config: config) }
            case .goalcheck: HomeProtoGoalCheckRoot(step: config.step)
            }
        }
    }
}

/// A stand-in for the Today tab: the title, the option under test, and the Inbox row under it.
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

// MARK: - Tile art

/// A flat house, one colour. The quiet stand-in for a rental that isn't focused.
struct HomeProtoSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        p.move(to: pt(0.5, 0.06)); p.addLine(to: pt(0.96, 0.46)); p.addLine(to: pt(0.04, 0.46)); p.closeSubpath()
        p.addRect(CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.44, width: r.width * 0.68, height: r.height * 0.5))
        p.addRect(CGRect(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.66, width: r.width * 0.14, height: r.height * 0.28))
        return p
    }
}

struct HomeProtoTileArt: View {
    let size: CGFloat
    let full: Bool
    let keyframe: HouseKeyframe
    /// Progress to the rental's own target; nil when it has none (no bar is drawn).
    let fraction: Double?
    var checked = false
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            if full {
                InboxBlueprintPaper(cornerRadius: size * 0.28)
                Image(decorative: keyframe.builtImageName)
                    .resizable().interpolation(.high).scaledToFit()
                    .scaleEffect(1.18).offset(y: -size * 0.02)
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(colors.backgroundTertiary)
                HomeProtoSilhouette()
                    .fill(colors.draftingInk, style: FillStyle(eoFill: true))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .offset(y: -size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(alignment: .bottom) {
            if let fraction, !full {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.border)
                        Capsule().fill(colors.action).frame(width: max(3, g.size.width * min(1, fraction)))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, size * 0.18).padding(.bottom, size * 0.1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if checked {
                ZStack {
                    Circle().fill(colors.action)
                    LucideIcon(image: Lucide.check, size: 12).foregroundStyle(colors.onAction)
                }
                .frame(width: 22, height: 22).offset(x: 6, y: -6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Option E: hero + one swipeable row of houses

struct HomeProtoOptionE: View {
    let seed: HomeProtoSeed
    @State private var focus: HomeProtoFocus
    @State private var summing: Bool
    @State private var summed: [String]
    @State private var showGrid: Bool
    @State private var scrollTo: String?
    @Namespace private var ring
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private let tileWidth: CGFloat = 108

    init(config: HomeProtoLaunch) {
        seed = config.seed
        let order = config.seed.focusOrder
        _focus = State(initialValue: order.indices.contains(config.focusIndex) ? order[config.focusIndex] : order[0])
        _summing = State(initialValue: !config.sum.isEmpty)
        _summed = State(initialValue: config.sum)
        _showGrid = State(initialValue: config.grid)
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
            .accessibilityElement(children: .contain)
        }
        .sheet(isPresented: $showGrid) {
            HomeProtoGridSheet(seed: seed, focus: focus) { f in showGrid = false; select(f) }
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

    // MARK: Row

    private func isFull(_ f: HomeProtoFocus) -> Bool { !summing && focus == f }
    private func isSelected(_ f: HomeProtoFocus) -> Bool {
        if summing, case .rental(let id) = f { return summed.contains(id) }
        return !summing && focus == f
    }

    private var tiles: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if seed.sharedTarget != nil { allTile }
                    ForEach(seed.rentals) { r in rentalTile(r) }
                    if seed.rentals.count >= 6 { seeAllTile }
                    addTile
                }
                .padding(.vertical, 4).padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(focus, anchor: .center) }
            .onChange(of: focus) { _, f in withAnimation(tap) { proxy.scrollTo(f, anchor: .center) } }
            .onChange(of: scrollTo) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(id, anchor: .trailing) }
            }
        }
    }

    private func tileFrame<Art: View>(_ f: HomeProtoFocus, label: String, name: String, line1: String, line2: String,
                                      @ViewBuilder art: () -> Art) -> some View {
        let selected = isSelected(f)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2)
                        .matchedGeometryEffect(id: summing ? "sum-\(name)" : "ring", in: ring)
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
        let f = HomeProtoFocus.rental(r.id)
        return tileFrame(f, label: seed.spoken(r), name: r.name, line1: seed.hoursLine(r), line2: seed.targetLine(r)) {
            HomeProtoTileArt(size: tileWidth - 20, full: isFull(f), keyframe: HomeProtoStage.keyframe(for: r),
                             fraction: ownFraction(r), checked: summing && summed.contains(r.id))
        }
    }

    private func ownFraction(_ r: HomeProtoRental) -> Double? {
        if case .own(let t) = r.target { return r.hours / Double(t) }
        return nil
    }

    private var allTile: some View {
        let total = seed.totalHours, target = Double(seed.sharedTarget ?? 750)
        return tileFrame(.all, label: String(localized: "All rentals, \(Int(total)) of \(Int(target)) hours", table: "HomeProto"),
                         name: seed.name(.all), line1: String(localized: "\(Int(total)) of \(Int(target))", table: "HomeProto"),
                         line2: String(localized: "One shared total", table: "HomeProto")) {
            HomeProtoTileArt(size: tileWidth - 20, full: isFull(.all), keyframe: HomeProtoStage.keyframe(hours: total), fraction: total / target)
        }
    }

    private var seeAllTile: some View {
        Button { showGrid = true } label: {
            VStack(spacing: 8) {
                LucideIcon(image: Lucide.layoutGrid, size: 24).foregroundStyle(colors.action)
                Text("See all", tableName: "HomeProto").font(.footnote.weight(.semibold)).foregroundStyle(colors.action)
                Text("\(seed.rentals.count) rentals", tableName: "HomeProto").font(.caption2).foregroundStyle(colors.textSecondary)
            }
            .frame(width: 84, height: tileWidth + 36)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id("seeall")
        .accessibilityLabel(String(localized: "See all \(seed.rentals.count) rentals", table: "HomeProto"))
    }

    private var addTile: some View {
        Button {} label: {
            VStack(spacing: 8) {
                LucideIcon(image: Lucide.circlePlus, size: 24).foregroundStyle(colors.action)
                Text("Add", tableName: "HomeProto").font(.footnote.weight(.semibold)).foregroundStyle(colors.action)
            }
            .frame(width: 64, height: tileWidth + 36)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.lhPressable)
        .id("add")
    }

    // MARK: Large text: a list instead of a row

    private var list: some View {
        let order = seed.focusOrder
        return VStack(spacing: 8) {
            ForEach(Array(order.prefix(3)), id: \.self) { f in listRow(f) }
            if order.count > 3 {
                Button { showGrid = true } label: {
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
        let selected = isSelected(f)
        let total = seed.totalHours, target = Double(seed.sharedTarget ?? 750)
        return Button { select(f) } label: {
            HStack(spacing: 12) {
                HomeProtoTileArt(size: 56, full: isFull(f),
                                 keyframe: r.map { HomeProtoStage.keyframe(for: $0) } ?? HomeProtoStage.keyframe(hours: total),
                                 fraction: r.map { ownFraction($0) } ?? total / target,
                                 checked: summing && (r.map { summed.contains($0.id) } ?? false))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r?.name ?? seed.name(.all)).font(.headline).foregroundStyle(colors.textPrimary)
                    Text(r.map { String(localized: "\(seed.hoursLine($0)) · \(seed.targetLine($0))", table: "HomeProto") }
                         ?? String(localized: "\(Int(total)) of \(Int(target))", table: "HomeProto"))
                        .font(.subheadline).foregroundStyle(colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { if selected { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2) } }
        }
        .buttonStyle(.lhPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Scripted tour for the video (-LHHomeAutoplay)

    private func autoplay() async {
        guard ProcessInfo.processInfo.arguments.contains("-LHHomeAutoplay") else { return }
        let order = seed.focusOrder
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await pause(1.5)
        for i in [1, 2] where order.indices.contains(i) { select(order[i]); await pause(1.4) }
        select(order[0]); await pause(1.2)
        toggleSum(); await pause(1.2)
        for i in [1, 2] where order.indices.contains(i) { select(order[i]); await pause(1.3) }
        await pause(0.8)
        toggleSum(); await pause(1.3)
        scrollTo = "seeall"; await pause(1.4)
        if seed.rentals.count >= 6 { showGrid = true; await pause(2.8); showGrid = false; await pause(1.0) }
    }
}

// MARK: - See all: a grid of every house

struct HomeProtoGridSheet: View {
    let seed: HomeProtoSeed
    let focus: HomeProtoFocus
    let onPick: (HomeProtoFocus) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("All rentals", tableName: "HomeProto").font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(Int(seed.totalHours.rounded(.down)))h logged this year", tableName: "HomeProto")
                            .font(.footnote.weight(.medium)).foregroundStyle(colors.textSecondary)
                    }
                    .padding(.top, 24)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 12)], spacing: 12) {
                        ForEach(seed.rentals) { r in cell(r) }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
    }

    private func cell(_ r: HomeProtoRental) -> some View {
        let f = HomeProtoFocus.rental(r.id)
        return Button { onPick(f) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HomeProtoTileArt(size: 88, full: true, keyframe: HomeProtoStage.keyframe(for: r), fraction: nil)
                Text(r.name).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                Text(seed.hoursLine(r)).font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(colors.textPrimary)
                Text(seed.targetLine(r)).font(.caption).foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { if focus == f { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2) } }
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(seed.spoken(r))
    }
}
#endif
