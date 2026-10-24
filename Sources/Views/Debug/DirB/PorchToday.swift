import SwiftUI
import UIKit

#if DEBUG
// MARK: - Root: tab shell (§2.6 tab bar) + the floating Log time glass "+"

struct PorchRoot: View {
    let launch: PorchLaunch
    @State private var tab: Int
    @State private var showLog = false
    @Environment(\.colorScheme) private var scheme

    init(launch: PorchLaunch) {
        self.launch = launch
        _tab = State(initialValue: launch.screen == .inbox ? 1 : 0)
        _showLog = State(initialValue: launch.screen == .logtime)
    }

    private var seed: PorchSeed { PorchSeed(std: StdSeed.make(launch.seedID)) }

    var body: some View {
        content
            .tint(PorchColors(scheme).action)
            .sheet(isPresented: $showLog) {
                PorchLogTimeSheet(seed: seed, demo: launch.demo == "scrub")
                    .presentationDetents([.large])
                    .presentationBackground(PorchColors(scheme).surface)
            }
            .modifier(PorchTypeSize(size: launch.typeSize))
    }

    @ViewBuilder private var content: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $tab) {
                Tab(P("Today"), systemImage: PorchSky.now().symbol, value: 0) {
                    NavigationStack { PorchTodayScreen(seed: seed, launch: launch) }.modifier(PorchCompose { showLog = true })
                }
                Tab(P("Inbox"), systemImage: "tray", value: 1) {
                    NavigationStack { PorchInboxScreen(seed: seed, empty: launch.state == "empty") }.modifier(PorchCompose { showLog = true })
                }
                .badge(launch.state == "empty" && launch.screen == .inbox ? 0 : seed.std.suggestions.count)
                Tab(P("Records"), systemImage: "book.pages", value: 2) { PorchColors(scheme).ground.ignoresSafeArea() }
                Tab(P("Properties"), systemImage: "house.fill", value: 3) { PorchColors(scheme).ground.ignoresSafeArea() }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            TabView(selection: $tab) {
                NavigationStack { PorchTodayScreen(seed: seed, launch: launch) }.tabItem { Label(P("Today"), systemImage: PorchSky.now().symbol) }.tag(0)
                NavigationStack { PorchInboxScreen(seed: seed, empty: launch.state == "empty") }.tabItem { Label(P("Inbox"), systemImage: "tray") }.tag(1)
                PorchColors(scheme).ground.tabItem { Label(P("Records"), systemImage: "book.pages") }.tag(2)
                PorchColors(scheme).ground.tabItem { Label(P("Properties"), systemImage: "house.fill") }.tag(3)
            }
        }
    }
}

struct PorchTypeSize: ViewModifier {
    let size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size { content.dynamicTypeSize(size) } else { content }
    }
}

/// The detached "+" (glassProminent tinted action), bottom-trailing in its own safe-area band.
struct PorchCompose: ViewModifier {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: action) {
                        Image(systemName: "plus").font(.title2.weight(.semibold))
                            .foregroundStyle(PorchColors(scheme).onAction)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(PorchColors(scheme).action)
                    .accessibilityLabel(P("Log time"))
                    .accessibilityIdentifier("compose.logTime")
                }
                .padding(.trailing, 20).padding(.bottom, 6)
            }
        } else {
            content
        }
    }
}

/// The status bar sits on deep sky in every state: light content (via a hidden, dark-scheme bar).
struct PorchSkyStatusBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
    }
}

// MARK: - Today (§2.12)

struct PorchTodayScreen: View {
    let seed: PorchSeed
    let launch: PorchLaunch

    init(seed: PorchSeed, launch: PorchLaunch) {
        self.seed = seed
        self.launch = launch
        _focusID = State(initialValue: launch.focus ?? seed.focuses.first?.id ?? "")
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numeralBase: CGFloat = 96

    @State private var focusID: String = ""
    @State private var extra: [String: Double] = [:]
    @State private var confirmed: Set<String> = []
    @State private var removed: Set<String> = []
    @State private var confirmCount = 0
    @State private var windowBump = 0
    @State private var porchLit = false
    @State private var goalMet = false
    @State private var skyOverride: PorchSky?
    @State private var rippleTrigger = 0
    @State private var toast: String?
    @State private var clockSky = PorchSky.now()
    @State private var scrolled = false

    private var c: PorchColors { PorchColors(scheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var sky: PorchSky { skyOverride ?? clockSky }
    private var numeralSize: CGFloat { min(numeralBase, 110) }
    /// The curve's rise (goal = full rise) and the band: room for the house standing on the curve's
    /// end, so the house never climbs into the numeral (the §2.12 160pt band could not hold both).
    private var curveRise: CGFloat { ax ? 40 : 64 }
    private var houseSize: CGFloat { ax ? 64 : 170 }
    private var bandHeight: CGFloat { curveRise + houseSize * 0.80 + 4 }

    private var focuses: [PorchFocus] {
        seed.focuses.map { f in
            var h = f.hours + (extra[f.id] ?? 0)
            if let preset = launch.preset, f.id == initialFocusID { h = preset + (extra[f.id] ?? 0) }
            return PorchFocus(id: f.id, name: f.name, hours: h, target: f.target, rentalIDs: f.rentalIDs)
        }
    }
    private var initialFocusID: String { launch.focus ?? seed.focuses.first?.id ?? "" }
    private var focus: PorchFocus { focuses.first { $0.id == focusID } ?? focuses.first! }
    private var lit: Int { goalMet ? PorchWindows.panes.count : focus.litPanes(PorchWindows.panes.count) }

    private var rows: [StdSuggestion] {
        let open = seed.std.suggestions.filter { !removed.contains($0.id) }
        let today = open.filter { $0.group == P("Today") }
        return Array((today.isEmpty ? open : today).prefix(2))
    }
    private var openCount: Int { seed.std.suggestions.filter { !removed.contains($0.id) }.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    ground
                    Color.clear.frame(height: 1).id("porch.end")
                }
            }
            .modifier(PorchScrolledFlag(scrolled: $scrolled, threshold: 24))
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-LHDirBScrollEnd") else { return }
                try? await Task.sleep(nanoseconds: 600_000_000)
                proxy.scrollTo("porch.end", anchor: .bottom)
            }
        }
        .scrollIndicators(.hidden)
        .background(c.ground)
        .ignoresSafeArea(edges: .top)
        .modifier(PorchHideTopEdge())
        .overlay(alignment: .top) { PorchZenithBand(sky: sky, dark: scheme == .dark, height: safeTop, visible: scrolled) }
        .modifier(PorchSkyStatusBar())
        .sensoryFeedback(.success, trigger: confirmCount)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: windowBump)
        .onAppear {
            if focusID.isEmpty { focusID = initialFocusID }
            if ["confirm", "stage", "goal"].contains(launch.demo ?? "") { Task { await demo() } }
        }
    }

    // MARK: Hero: sky, chips, numeral, horizon band

    private var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.top ?? 59
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: safeTop + 8)
            chips.padding(.horizontal, 20)
            numeral.padding(.top, ax ? 8 : 16)
            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)
            horizonBand.padding(.top, 10)
        }
        .background(alignment: .top) {
            GeometryReader { g in
                PorchSkyView(sky: sky, dark: scheme == .dark, height: g.size.height, deepUntil: g.size.height - bandHeight)
                    .modifier(PorchRipple(trigger: rippleTrigger, origin: CGPoint(x: g.size.width * 0.75, y: g.size.height - bandHeight * 0.5)))
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in clockSky = PorchSky.now() }
    }

    private var label: String {
        if let t = focus.target { return P("of \(t) hours") }
        return P("hours logged")
    }

    private var numeral: some View {
        Text(verbatim: "\(Int(focus.hours.rounded(.down)))")
            .font(.system(size: numeralSize, weight: .bold, design: .rounded))
            .tracking(-2)
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .contentTransition(.numericText(value: focus.hours))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: numeralSize * 1.04)
            .accessibilityElement()
            .accessibilityLabel(focus.target.map { P("\(Int(focus.hours)) of \($0) hours, \(focus.name)") } ?? P("\(Int(focus.hours)) hours logged, \(focus.name)"))
            .accessibilityIdentifier("porch.numeral")
    }

    private var chips: some View {
        let date = Text(P("Fri, Oct 23"))
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .modifier(PorchSkyGlass())
        let goal = Button {} label: {
            HStack(spacing: 4) {
                Text(focus.target.map { P("\($0) goal") } ?? P("Record only"))
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .modifier(PorchSkyGlass())
        }
        .buttonStyle(PorchPress())
        .accessibilityHint(P("Opens Reports"))
        return ViewThatFits(in: .horizontal) {
            HStack { date; Spacer(minLength: 8); goal }
            VStack(alignment: .leading, spacing: 8) { date; goal }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: The horizon (§2.5): the ground silhouette is the cumulative-hours curve

    private var horizonBand: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let x0: CGFloat = 20, x1 = w - 20
            let top: CGFloat = h - curveRise
            let todayX = x0 + CGFloat(PorchYear.fraction) * (x1 - x0)
            let ratio = CGFloat(focus.target.map { focus.hours / Double($0) } ?? min(focus.hours / 100, 1))
            let scaleY = (h - top)
            let pts = focus.curve.map { CGPoint(x: x0 + CGFloat($0.t) * (x1 - x0), y: h - CGFloat($0.v) * min(ratio, 1) * scaleY) }
            let endY = pts.last?.y ?? h
            let houseX = min(max(todayX, ax ? 52 : 100), w - (ax ? 52 : 100))
            let behind: Bool = { if case .behind = focus.pace { return true }; return false }()

            ZStack(alignment: .topLeading) {
                // Behind pace: the shortfall between the target line and the curve, in ember.
                if behind, focus.target != nil {
                    Path { p in
                        p.move(to: CGPoint(x: x0, y: h))
                        p.addLine(to: CGPoint(x: todayX, y: h - CGFloat(PorchYear.fraction) * scaleY))
                        p.addLine(to: CGPoint(x: todayX, y: endY))
                        for pt in pts.reversed() { p.addLine(to: pt) }
                        p.closeSubpath()
                    }
                    .fill(c.behind.opacity(0.18))
                    .overlay {
                        // Hatched shortfall: ember diagonals clipped to the gap (reads as "missing", not as a tint).
                        Path { p in
                            var x: CGFloat = -h
                            while x < w { p.move(to: CGPoint(x: x, y: h)); p.addLine(to: CGPoint(x: x + h, y: 0)); x += 7 }
                        }
                        .stroke(c.behind, lineWidth: 1.5)
                        .clipShape(Path { p in
                            p.move(to: CGPoint(x: x0, y: h))
                            p.addLine(to: CGPoint(x: todayX, y: h - CGFloat(PorchYear.fraction) * scaleY))
                            p.addLine(to: CGPoint(x: todayX, y: endY))
                            for pt in pts.reversed() { p.addLine(to: pt) }
                            p.closeSubpath()
                        })
                    }
                }
                // Ground silhouette (area fill in the ground colour), flat after today.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: x0, y: h))
                    for pt in pts { p.addLine(to: pt) }
                    p.addCurve(to: CGPoint(x: min(todayX + 18, w), y: h), control1: CGPoint(x: todayX + 8, y: endY), control2: CGPoint(x: todayX + 10, y: h))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h + 1)); p.addLine(to: CGPoint(x: 0, y: h + 1))
                    p.closeSubpath()
                }
                .fill(c.ground)
                .animation(.spring(duration: 0.60, bounce: 0), value: focus.hours)
                // Target: 1.5pt dotted, white 60%, straight to the goal at Dec 31.
                if focus.target != nil {
                    Path { p in p.move(to: CGPoint(x: x0, y: h)); p.addLine(to: CGPoint(x: x1, y: top)) }
                        .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))
                }
                // Horizon line.
                Rectangle().fill(.white.opacity(0.4)).frame(width: w, height: 1).offset(y: h - 0.5)

                // The house stands at today's x, its base on the curve.
                PorchHouse(lit: lit, intensity: focus.progress, sky: sky, porchLight: porchLit, size: houseSize)
                    .offset(x: houseX - houseSize / 2, y: min(endY, h) - houseSize * 0.80)

                if !ax {
                    paceChip.frame(maxWidth: houseX - houseSize * 0.40 - 20 - 4, alignment: .leading)
                        .offset(x: 20, y: h * 0.18)
                }
            }
        }
        .frame(height: bandHeight)
        .overlay(alignment: .bottom) { if ax { EmptyView() } }
    }

    // MARK: Pace (behind pace made unmistakable: word + glyph + solid ember chip + ember shortfall)

    @ViewBuilder private var paceChip: some View {
        switch focus.pace {
        case .behind(let gap, let weekly):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").font(.footnote.weight(.bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(P("Behind by \(gap)h")).font(.footnote.weight(.bold))
                    Text(P("\(weekly)h a week to reach \(focus.target ?? 0)")).font(.footnote.weight(.medium))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(scheme == .dark ? c.ground : .white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.behind))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("porch.pace")
        case .ahead(let by):
            softChip(icon: "checkmark.circle.fill", title: P("On pace"), line: by > 0 ? P("Ahead by \(by)h") : nil)
        case .reached:
            softChip(icon: "checkmark.seal.fill", title: P("Reached \(focus.target ?? 0)"), line: P("Every light is on"))
        case .record:
            softChip(icon: "tray.full", title: P("Record only"), line: P("No target here"), tint: c.textSecondary)
        }
    }

    private func softChip(icon: String, title: String, line: String?, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(tint ?? c.glowInk)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(c.ink)
                if let line { Text(line).font(.footnote.weight(.medium)).foregroundStyle(c.textSecondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.surface.opacity(0.94)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("porch.pace")
    }

    // MARK: Below the horizon

    private var ground: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ax { paceChip.padding(.top, 16) }
            if focuses.count > 1 { switcher.padding(.top, 16) }
            toastView.padding(.top, toast == nil ? 0 : 12)
            PorchSectionHeader(title: P("To confirm · \(openCount)"), trailing: P("See all"))
                .padding(.top, 20)
            confirmCard.padding(.top, 8)
            PorchSectionHeader(title: P("This week"), trailing: P("Records")).padding(.top, 24)
            weekCard.padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .background(c.ground)
    }

    private var switcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(focuses, id: \.id) { f in
                    let selected = f.id == focusID
                    Button {
                        withAnimation(.spring(duration: 0.30, bounce: 0)) { focusID = f.id }
                    } label: {
                        HStack(spacing: 6) {
                            PorchHouse(lit: (selected || goalMet) ? f.litPanes(PorchWindows.panes.count) : 0, sky: .day, size: 34)
                                .opacity(selected || goalMet ? 1 : 0.55)
                                .saturation(selected || goalMet ? 1 : 0.3)
                            Text(f.name).font(.footnote.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
                        }
                        .padding(.leading, 6).padding(.trailing, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(selected ? c.surface : c.surfaceInner))
                        .overlay(Capsule().strokeBorder(selected ? c.ink.opacity(0.8) : c.border, lineWidth: selected ? 1.5 : 0.5))
                    }
                    .buttonStyle(PorchPress())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
        .sensoryFeedback(.selection, trigger: focusID)
    }

    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(P("Today")).font(.subheadline.weight(.semibold)).foregroundStyle(c.textSecondary)
                .frame(minHeight: 28, alignment: .bottomLeading)
                .padding(.horizontal, 16).padding(.top, 4)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(c.border).frame(height: 0.5).padding(.leading, 50) }
                PorchActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .transition(.opacity)
            }
            if rows.filter(\.isLikely).count >= 2 {
                Rectangle().fill(c.border).frame(height: 0.5)
                Button { confirmLikely() } label: {
                    Text(P("Confirm \(rows.filter(\.isLikely).count) likely"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(c.action)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PorchPress())
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(seed.std.week.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Rectangle().fill(c.border).frame(height: 0.5).padding(.leading, 16) }
                let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.body.weight(.semibold)).foregroundStyle(c.ink).fixedSize(horizontal: false, vertical: true)
                        Text(P("\(e.day) · \(e.rental) · \(e.category.stdLabel)")).font(.subheadline).foregroundStyle(c.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !ax { Spacer(minLength: 8) }
                    Text(porchHours(e.hours)).font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit().foregroundStyle(c.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            // The confirmation line (§2.9 voice), inline under the switcher so it never covers a row.
            Label(toast, systemImage: "lightbulb.max.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
                .labelStyle(PorchToastLabel(tint: c.glowInk))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
                .transition(.opacity.combined(with: .offset(y: -6)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Behaviour

    private func confirm(_ item: StdSuggestion) {
        guard !confirmed.contains(item.id) else { return }
        withAnimation(.easeOut(duration: 0.12)) { _ = confirmed.insert(item.id) }
        confirmCount += 1
        PorchHapticLog.mark("confirm: .success")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0)) { _ = removed.insert(item.id) }
            if let h = item.hours { credit(rental: item.rental, hours: h, title: item.title) }
        }
    }

    private func confirmLikely() {
        for item in rows where item.isLikely { confirm(item) }
    }

    /// The hours land: the numeral rolls, the curve end rises, earned windows light one by one.
    private func credit(rental: String?, hours: Double, title: String) {
        guard let rental else { show(P("\(porchHours(hours)) in. Saved.")); return }
        let before = focus
        let litBefore = lit
        withAnimation(.spring(duration: 0.60, bounce: 0)) {
            for f in focuses where f.rentalIDs.contains(rental) { extra[f.id, default: 0] += hours }
        }
        let after = focus
        if lit > litBefore { windowBump += 1; PorchHapticLog.mark("window lit: .impact(light, 0.6)") }
        if let t = after.target, before.hours < Double(t), after.hours >= Double(t) {
            reachGoal(t)
        } else if let m = [100.0, 500, 750].first(where: { before.hours < $0 && after.hours >= $0 }) {
            advanceStage(Int(m))
        } else {
            show(lit > litBefore ? P("\(porchHours(hours)) in. Another window lit.") : P("\(porchHours(hours)) in."))
        }
    }

    private func advanceStage(_ milestone: Int) {
        porchLit = true
        PorchHaptics.shared.stage()
        show(P("\(milestone) hours. The porch light's on."))
        guard !reduceMotion else { return }
        skyOverride = .golden
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_900_000_000)
            if !goalMet { skyOverride = nil }
        }
    }

    private func reachGoal(_ target: Int) {
        porchLit = true
        goalMet = true
        PorchHaptics.shared.goal()
        if !reduceMotion { skyOverride = .golden; rippleTrigger += 1 }
        show(P("\(target) hours. Every light is on."))
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.22)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeIn(duration: 0.18)) { if toast == text { toast = nil } }
        }
    }

    private func demo() async {
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await pause(2.5)
        guard let first = rows.first else { return }
        confirm(first)
    }
}

/// iOS 26: no scroll-edge tint over the sky.
struct PorchHideTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .top) } else { content }
    }
}

struct PorchToastLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(tint)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The goal ripple (one shader moment)

struct PorchRipple: ViewModifier {
    let trigger: Int
    let origin: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = reduceMotion, origin = origin, fired = trigger > 0
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, t in
            view.layerEffect(ShaderLibrary.porchRipple(.float2(origin), .float(t), .float(10), .float(14), .float(5), .float(900)),
                             maxSampleOffset: CGSize(width: 12, height: 12), isEnabled: fired && t > 0 && t < 1.6 && !still)
        } keyframes: { _ in
            MoveKeyframe(0.0)
            LinearKeyframe(1.6, duration: 1.6)
        }
    }
}

// MARK: - LHRow.Action, Porch Light (§2.6): soft circle fills lamplight, check draws on

struct PorchActionRow: View {
    let item: StdSuggestion
    let confirmed: Bool
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 22

    var body: some View {
        let c = PorchColors(scheme)
        HStack(alignment: .top, spacing: 12) {
            Button(action: onConfirm) {
                ZStack {
                    Circle().fill(c.surfaceInner)
                    Circle().strokeBorder(confirmed ? c.glowInk : c.textTertiary, lineWidth: 1.5)
                    Circle().fill(c.glowInk).scaleEffect(confirmed ? 1 : 0.6).opacity(confirmed ? 1 : 0)
                    check(c)
                }
                .frame(width: circle, height: circle)
                .padding(11).contentShape(Rectangle()).padding(-11)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(P("Confirm \(porchHours(item.hours))"))
            .accessibilityIdentifier("row.confirm.\(item.id)")

            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(c.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // The tag yields before the time is ever cut (no "10–11:…").
                    if typeSize.isAccessibilitySize {
                        meta(c, tag: false)
                    } else {
                        ViewThatFits(in: .horizontal) { meta(c, tag: true); meta(c, tag: false) }
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Text(porchHours(item.hours)).font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(c.ink).padding(.top, typeSize.isAccessibilitySize ? 0 : 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func meta(_ c: PorchColors, tag: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: item.source == .calendar ? "calendar" : "checklist").foregroundStyle(c.action)
            Text(item.when.replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")).foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            if tag, let cat = item.category {
                Text(cat.stdLabel).font(.caption.weight(.medium)).foregroundStyle(c.tagInk)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(c.tagWash))
                    .fixedSize()
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder private func check(_ c: PorchColors) -> some View {
        let img = Image(systemName: "checkmark").font(.system(size: circle * 0.48, weight: .bold)).foregroundStyle(scheme == .dark ? c.ground : .white)
        if #available(iOS 26.0, *) {
            img.symbolEffect(.drawOn.byLayer, options: .speed(1.4), isActive: !confirmed)
        } else {
            img.opacity(confirmed ? 1 : 0)
        }
    }
}
#endif

#if DEBUG
/// Once the sky scrolls away, a strip of zenith stays behind the status bar so its white text
/// never lands on cream (the sky's own top colour, so at rest nothing changes).
struct PorchZenithBand: View {
    let sky: PorchSky
    let dark: Bool
    let height: CGFloat
    let visible: Bool
    var body: some View {
        let p = sky.palette(dark: dark)
        PorchColors.hex(p[0])
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: visible)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct PorchScrolledFlag: ViewModifier {
    @Binding var scrolled: Bool
    let threshold: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in g.contentOffset.y + g.contentInsets.top > threshold } action: { _, new in scrolled = new }
        } else {
            content
        }
    }
}
#endif
