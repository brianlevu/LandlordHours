import SwiftUI

#if DEBUG
// MARK: - Direction C model: one book page per rental

struct DirCBook: Identifiable, Equatable {
    let id: String
    let name: String
    let target: Int?
    let reason: String?
    let reached: String?
}

struct DirCEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let rental: String
    let kind: String
    let day: String
    let hours: Double
    var fresh = false
}

@Observable
final class DirCStore {
    let seed: StdSeed
    let books: [DirCBook]
    var logged: [String: Double]
    var focus: String
    var checked: Set<String> = []
    var slid: Set<String> = []
    var gone: Set<String> = []
    var entries: [DirCEntry]
    var toast: String?
    var confirmTick = 0
    var commitTick = 0
    var goalTick = 0
    var stageTick = 0
    var goalOrigin: CGPoint = .zero
    var sealShown: Set<String>
    var showLog = false
    var holdFreeze: Double? = nil
    var drum: Double? = 1.5
    var drumTarget: Double? = nil
    var demoPressing = false
    var finger: CGPoint? = nil
    var fingerDown = false
    var frames: [String: CGRect] = [:]

    /// Friday Oct 23, 2026 is "today" for every seed: day 296 of 365.
    static let dayOfYear = 296.0

    init(launch: DirCLaunch) {
        let seed = StdSeed.make(launch.seedID)
        self.seed = seed
        let shared = seed.rentals.sharedTarget
        let rentals = seed.rentals.rentals
        books = rentals.map { r in
            switch r.target {
            case .own(let t): return DirCBook(id: r.id, name: r.name, target: t, reason: nil, reached: r.reached)
            case .record(let reason): return DirCBook(id: r.id, name: r.name, target: nil, reason: reason, reached: nil)
            case .counts: return DirCBook(id: r.id, name: r.name, target: shared, reason: nil, reached: nil)
            }
        }
        var hours = Dictionary(uniqueKeysWithValues: rentals.map { ($0.id, $0.hours) })
        let f = launch.focus.flatMap { id in rentals.first { $0.id == id }?.id } ?? rentals.first?.id ?? ""
        if let start = launch.start { hours[f] = start }
        logged = hours
        focus = f
        entries = seed.week.map { DirCEntry(id: $0.id, title: $0.title, rental: $0.rental, kind: $0.category.stdLabel, day: $0.day, hours: $0.hours) }
        let allBooks = books
        sealShown = Set(allBooks.filter { b in b.target.map { (hours[b.id] ?? 0) >= Double($0) } ?? false }.map(\.id))
        if launch.state == "holding" { holdFreeze = 0.55 }
    }

    var book: DirCBook { books.first { $0.id == focus } ?? books[0] }
    var focusLogged: Double { logged[focus] ?? 0 }

    /// Today's items, in order: the ones dated today first.
    var todayItems: [StdSuggestion] { seed.suggestions.filter { $0.group == L("Today") && !gone.contains($0.id) } }
    var openCount: Int { seed.suggestions.count - gone.count }

    func rentalID(for item: StdSuggestion) -> String? {
        if let r = item.rental, logged[r] != nil { return r }
        return books.first { item.title.contains($0.name) }?.id
    }

    // MARK: Actions

    func confirm(_ item: StdSuggestion, reduceMotion: Bool) {
        guard !checked.contains(item.id), let h = item.hours else { return }
        checked.insert(item.id)
        confirmTick += 1
        DirCHaptic.log(".success", "row confirmed: \(item.title)")
        let rid = rentalID(for: item)
        let crossed = add(h, to: rid)
        let name = rid.flatMap { id in books.first { $0.id == id }?.name } ?? ""
        show(toast: C("Entered. \(DirCFormat.hours(h)), \(name), 23 Oct."))
        if crossed, let rid { Task { @MainActor in await pressSeal(rid) } }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : DirCMotion.slideOut) { slid.insert(item.id) }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(DirCMotion.collapse) { gone.insert(item.id) }
        }
    }

    /// After the sheet has gone: the numeral rolls and the new line's rule draws.
    func applyEntry(hours h: Double) {
        let crossed = add(h, to: focus)
        withAnimation(DirCMotion.collapse) {
            entries.insert(DirCEntry(id: "new\(commitTick)", title: C("Fixed the garbage disposal"), rental: book.name,
                                     kind: ActivityCategory.repairs.stdLabel, day: C("Today"), hours: h, fresh: true), at: 0)
        }
        show(toast: C("Entered. \(DirCFormat.hours(h)), \(book.name), 23 Oct."))
        if crossed { let f = focus; Task { @MainActor in await pressSeal(f) } }
    }

    /// Adds hours with the odometer roll; true when this crosses the rental's target.
    @discardableResult private func add(_ h: Double, to rid: String?) -> Bool {
        guard let rid, let before = logged[rid] else { return false }
        let target = books.first { $0.id == rid }?.target
        let oldStage = DirCEngraving.stage(logged: before, target: target)
        withAnimation(DirCMotion.odometer) { logged[rid] = before + h }
        let newStage = DirCEngraving.stage(logged: before + h, target: target)
        let crossed = target.map { before < Double($0) && before + h >= Double($0) } ?? false
        if rid == focus, newStage > oldStage, !crossed {
            stageTick += 1
            DirCHaptic.log(".impact(.heavy)", "stage advance, engraving gains stage \(newStage) lines")
        }
        return crossed
    }

    @MainActor private func pressSeal(_ rid: String) async {
        try? await Task.sleep(for: .milliseconds(600))   // the dot arrives at the mark first (0.60 spring)
        withAnimation(DirCMotion.seal) { _ = sealShown.insert(rid) }
        goalTick += 1
        DirCPressHaptic.shared.play()
        show(toast: C("\(books.first { $0.id == rid }?.target ?? 100) hours, entered and dated. Ready for your CPA."), seconds: 4)
    }

    func show(toast text: String, seconds: Double = 2.4) {
        withAnimation(.easeOut(duration: 0.22)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if toast == text { withAnimation(.easeIn(duration: 0.18)) { toast = nil } }
        }
    }
}

private extension View {
    /// Records a control's on-screen frame for the scripted demos (the finger dot goes there).
    func dircFrame(_ key: String, _ store: DirCStore) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames[key] = $0 }
    }
}

// MARK: - Root: tabs, the Log time sheet, the toast, the demo finger

struct DirCRoot: View {
    let launch: DirCLaunch
    @State private var store: DirCStore
    @State private var tab = 0
    @ScaledMetric(relativeTo: .body) private var pitch: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let c = DirCColors()

    init(launch: DirCLaunch) {
        self.launch = launch
        _ = DirCHaptic.t0   // haptic log times count from launch
        _store = State(initialValue: DirCStore(launch: launch))
    }

    var body: some View {
        let p = c.p
        Group {
            if #available(iOS 26.0, *) {
                TabView(selection: $tab) {
                    Tab(C("Today"), systemImage: "text.book.closed", value: 0) { DirCTodayScreen(store: store, openLog: openLog) }
                    Tab(C("Inbox"), systemImage: "tray", value: 1) { blank }.badge(store.openCount)
                    Tab(C("Records"), systemImage: "list.bullet.rectangle", value: 2) { blank }
                    Tab(C("Properties"), systemImage: "house", value: 3) { blank }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                TabView(selection: $tab) {
                    DirCTodayScreen(store: store, openLog: openLog).tabItem { Label(C("Today"), systemImage: "text.book.closed") }.tag(0)
                    blank.tabItem { Label(C("Inbox"), systemImage: "tray") }.tag(1).badge(store.openCount)
                    blank.tabItem { Label(C("Records"), systemImage: "list.bullet.rectangle") }.tag(2)
                    blank.tabItem { Label(C("Properties"), systemImage: "house") }.tag(3)
                }
            }
        }
        .tint(p.action)
        .environment(\.dircPitch, pitch)
        .environment(\.dircMargin, typeSize.isAccessibilitySize ? 72 : 56)
        .sheet(isPresented: $store.showLog) {
            DirCLogTimeSheet(store: store)
                .environment(\.dircPitch, pitch)
                .environment(\.dircMargin, typeSize.isAccessibilitySize ? 72 : 56)
                .presentationDetents([.large])
                .presentationBackground(p.canvas)
                .presentationDragIndicator(.hidden)
        }
        .overlay(alignment: .bottom) { toast }
        .overlay { DirCFinger(store: store) }
        .sensoryFeedback(.success, trigger: store.confirmTick)
        .task {
            if launch.screen == .logtime { store.showLog = true }
            if let demo = launch.demo { await DirCDemo(store: store, reduceMotion: reduceMotion).run(demo) }
        }
    }

    private func openLog() { store.showLog = true }

    private var blank: some View { DirCPaper() }

    @ViewBuilder private var toast: some View {
        if let text = store.toast {
            let p = c.p
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(p.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .modifier(DirCGlassCapsule(fallback: p.canvas))
                .padding(.horizontal, 24)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Glass is chrome only: the toast. Neutral (untinted) so the paper shows through.
struct DirCGlassCapsule: ViewModifier {
    let fallback: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - Today: the ledger page

struct DirCTodayScreen: View {
    let store: DirCStore
    let openLog: () -> Void
    @Environment(\.dircPitch) private var pitch
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let c = DirCColors()

    var body: some View {
        let p = c.p
        ScrollView {
            DirCRuledStack(pitch: pitch) {
                DirCHero(store: store)
                spine
                toConfirmHeader
                if store.todayItems.isEmpty {
                    DirCRuleLine { DirCLedgerLine { Text(C("No entries today.")).font(.body).foregroundStyle(p.textSecondary) } }
                } else {
                    DirCRuleLine { DirCLedgerLine { Text(C("Today")).font(.subheadline.weight(.semibold)).foregroundStyle(p.textSecondary) } }
                    ForEach(store.todayItems.prefix(2)) { item in
                        DirCActionRow(store: store, item: item)
                            .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    }
                    batchFoot
                }
                weekHeader
                ForEach(store.entries) { e in DirCEntryRow(entry: e) }
                Color.clear.frame(height: pitch * 2)
            }
            .background(alignment: .top) { DirCRules(overscan: 1200) }
        }
        .scrollIndicators(.hidden)
        .background { DirCPaper() }
        .modifier(DirCScrollEdges())
        .modifier(DirCComposeButton(store: store, action: openLog))
    }

    // Spine tabs: "Santa Ray Ave · Delaney Ct · Yeandle Ave", selected underlined 1.5pt oxblood.
    private var spine: some View {
        DirCSpineTabs(store: store)
    }

    private var toConfirmHeader: some View {
        let p = c.p
        return DirCRuleLine {
            DirCLedgerLine {
                Text(verbatim: "\(store.openCount)").font(DirCFont.stamp).foregroundStyle(p.action).monospacedDigit()
                    .contentTransition(.numericText(value: Double(store.openCount)))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            } main: {
                HStack(alignment: .lastTextBaseline) {
                    Text(C("To confirm")).font(DirCFont.smallCaps).foregroundStyle(p.ink).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    DirCLink(title: C("See all")) {}
                }
            }
        }
    }

    @ViewBuilder private var batchFoot: some View {
        let likely = store.todayItems.filter { $0.isLikely }
        let open = likely.filter { !store.checked.contains($0.id) }
        if !likely.isEmpty {
            DirCRuleLine {
                DirCLedgerLine {
                    DirCLink(title: StdCanon.confirmLikely(likely.count)) {
                        for item in open { store.confirm(item, reduceMotion: reduceMotion) }
                    }
                    .padding(.leading, 34)
                }
            }
        }
    }

    private var weekHeader: some View {
        let p = c.p
        return DirCRuleLine(pitches: 2) {
            DirCLedgerLine {
                HStack(alignment: .lastTextBaseline) {
                    Text(C("This week")).font(DirCFont.smallCaps).foregroundStyle(p.ink).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    DirCLink(title: C("Records")) {}
                }
            }
        }
    }
}

/// Top: the soft system edge so the clock never sits on rules. Bottom: soft under the tab bar.
struct DirCScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top).scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content
        }
    }
}

/// The detached glass "+": `.glassProminent`-style, tinted oxblood.
struct DirCComposeButton: ViewModifier {
    let store: DirCStore
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let p = DirCPalette.make(scheme)
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: action) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(p.onAction)
                            .frame(width: 56, height: 56)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(p.action).interactive(), in: .circle)
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel(C("New entry"))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames["plus"] = $0 }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 6)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .primaryAction) { Button(C("New entry"), systemImage: "plus", action: action) }
            }
        }
    }
}

/// `.tertiary`: oxblood text with a 0.5pt underline, a ledger link.
struct DirCLink: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = DirCPalette.make(scheme)
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(p.action)
                .underline(true, pattern: .solid, color: p.action.opacity(0.8))
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(DirCPress())
    }
}

/// Every pressable thing: scale 0.98 on press, 0.12s ease-out.
struct DirCPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - The hero: stamp, engraving, the 120pt numeral, the year line, the balance

struct DirCHero: View {
    let store: DirCStore
    @Environment(\.dircPitch) private var pitch
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let c = DirCColors()

    var body: some View {
        let p = c.p
        let book = store.book
        let logged = store.focusLogged
        let stage = DirCEngraving.stage(logged: logged, target: book.target)
        DirCRuledStack(pitch: pitch) {
            // y 59-91: the margin stamp.
            DirCRuleLine(fixed: true) {
                DirCLedgerLine {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: "23")
                        Text(C("OCT"))
                    }
                    .font(DirCFont.stamp).foregroundStyle(p.action)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityElement(children: .ignore).accessibilityLabel(C("October 23"))
                } main: { Text(verbatim: " ").font(DirCFont.stamp) }
            }
            // y 91-187: the numeral, baseline on the rule.
            DirCRuleLine(pitches: typeSize.isAccessibilitySize ? 2 : 3, fixed: true) {
                DirCLedgerLine {
                    Text(verbatim: "\(Int(logged.rounded(.down)))")
                        .font(DirCFont.hero(typeSize.isAccessibilitySize))
                        .tracking(-4)
                        .foregroundStyle(p.ink)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: logged))
                        .fixedSize()
                        .accessibilityLabel(book.target.map { C("\(DirCFormat.figure(logged)) of \($0) hours, \(book.name)") }
                                            ?? C("\(DirCFormat.figure(logged)) hours entered, \(book.name)"))
                }
            }
            // y 187-219: "of 100 hours".
            DirCRuleLine {
                DirCLedgerLine {
                    Text(book.target.map { C("of \($0) hours") } ?? C("hours entered, record only"))
                        .font(DirCFont.heroLabel).foregroundStyle(p.textSecondary).dircRuled(.title3)
                        // The 132pt numeral above it does not grow either; this caption follows it.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            // y 219-251: the year line.
            DirCLedgerLine {
                if let t = book.target {
                    DirCYearLine(logged: logged, target: t)
                } else {
                    Color.clear.frame(height: pitch)
                }
            }
            // y 251-347: the balance, three ledger lines and a double rule.
            DirCBalance(book: book, logged: logged)
        }
        .padding(.bottom, 0)
        .overlay(alignment: .topTrailing) {
            // Once sealed, the house lives inside the seal.
            DirCEngraving(stage: stage, ink: p.ink)
                .opacity(store.sealShown.contains(book.id) ? 0 : 1)
                .frame(width: 48, height: 40)
                .padding(.top, pitch * 0.75).padding(.trailing, 20)
                .sensoryFeedback(.impact(weight: .heavy), trigger: store.stageTick)
        }
        .overlay(alignment: .topTrailing) {
            if store.sealShown.contains(book.id), let t = book.target {
                DirCSeal(threshold: min(t, 750))
                    .padding(.top, pitch * 0.55).padding(.trailing, 16)
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.08).combined(with: .opacity))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .local) } action: { _ in }
            }
        }
        .background { DirCRules().background(p.canvas).overlay { DirCMarginRule() } }
        .modifier(DirCRipple(trigger: store.goalTick, origin: CGPoint(x: 330, y: pitch * 3.9), enabled: !reduceMotion))
    }
}

struct DirCBalance: View {
    let book: DirCBook
    let logged: Double
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dircPitch) private var pitch
    private let c = DirCColors()

    private struct Line: Identifiable { let id: String; let label: String; let value: String; let number: Double; let tone: Color }

    private var lines: [Line] {
        let p = c.p
        var out = [Line(id: "logged", label: C("Logged"), value: DirCFormat.figure(logged), number: logged, tone: p.ink)]
        guard let t = book.target else {
            out.append(Line(id: "target", label: C("Target"), value: C("None"), number: 0, tone: p.ink))
            out.append(Line(id: "why", label: book.reason ?? "", value: "", number: 0, tone: p.textSecondary))
            return out
        }
        if logged >= Double(t) {
            out.append(Line(id: "target", label: C("Target"), value: "\(t)", number: Double(t), tone: p.ink))
            out.append(Line(id: "state", label: C("Reached"), value: book.reached.map { C("\($0)") } ?? C("Today"), number: 0, tone: p.positive))
        } else {
            let needed = (Double(t) * DirCStore.dayOfYear / 365).rounded()
            out.append(Line(id: "needed", label: C("Needed by today"), value: DirCFormat.figure(needed), number: needed, tone: p.ink))
            if logged < needed {
                out.append(Line(id: "state", label: C("Short"), value: DirCFormat.figure(needed - logged), number: needed - logged, tone: p.brassInk))
            } else {
                out.append(Line(id: "state", label: C("Ahead"), value: DirCFormat.figure(logged - needed), number: logged - needed, tone: p.positive))
            }
        }
        return out
    }

    var body: some View {
        let p = c.p
        let all = lines
        DirCRuledStack(pitch: pitch) {
            ForEach(all) { line in
                let last = line.id == all.last?.id
                DirCRuleLine {
                    DirCLedgerLine {
                        ViewThatFits(in: .horizontal) {
                            row(line, last: last, p: p)
                            stacked(line, last: last, p: p)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ line: Line, p: DirCPalette) -> some View {
        Text(line.value)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(line.tone)
            .contentTransition(.numericText(value: line.number))
            .frame(minWidth: line.value.isEmpty ? 0 : 44, alignment: .trailing)
    }

    private func row(_ line: Line, last: Bool, p: DirCPalette) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(line.label).font(.subheadline).foregroundStyle(line.id == "state" ? line.tone : p.textSecondary)
                .lineLimit(1)
            figure(line, p: p)
        }
        .fixedSize(horizontal: true, vertical: false)
        .overlay(alignment: Alignment(horizontal: .center, vertical: .lastTextBaseline)) {
            if last && !line.value.isEmpty { doubleRule(p) }
        }
    }

    private func stacked(_ line: Line, last: Bool, p: DirCPalette) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(line.label).font(.subheadline).foregroundStyle(line.id == "state" ? line.tone : p.textSecondary)
                .multilineTextAlignment(.trailing)
            figure(line, p: p)
        }
        .dircRuled(.subheadline)
        .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
            if last && !line.value.isEmpty { doubleRule(p).frame(width: 120) }
        }
    }

    /// The accountant's double rule: the page rule under the total turns ink, and a second one 2pt below.
    private func doubleRule(_ p: DirCPalette) -> some View {
        VStack(spacing: 2) {
            Rectangle().fill(p.ink).frame(height: 0.5)
            Rectangle().fill(p.ink).frame(height: 0.5)
        }
        .alignmentGuide(.lastTextBaseline) { _ in -(pitch / 8) + 0.25 }
        .accessibilityHidden(true)
    }
}

// MARK: - Spine tabs

struct DirCSpineTabs: View {
    let store: DirCStore
    @Namespace private var ns
    @Environment(\.dircPitch) private var pitch
    private let c = DirCColors()

    var body: some View {
        let p = c.p
        DirCLedgerLine {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 22) {
                        ForEach(store.books) { b in
                            let on = b.id == store.focus
                            Button {
                                withAnimation(DirCMotion.segment) { store.focus = b.id }
                            } label: {
                                VStack(spacing: 0) {
                                    Text(b.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(on ? p.ink : p.textSecondary)
                                        .lineLimit(1)
                                        .padding(.bottom, pitch / 8 + 3)
                                    ZStack {
                                        if on {
                                            Rectangle().fill(p.action).frame(height: 1.5)
                                                .matchedGeometryEffect(id: "spine", in: ns)
                                        } else {
                                            Color.clear.frame(height: 1.5)
                                        }
                                    }
                                }
                                .frame(minHeight: pitch, alignment: .bottom)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(DirCPress())
                            .id(b.id)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames["tab.\(b.id)"] = $0 }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear { proxy.scrollTo(store.focus, anchor: .center) }
            }
        }
        .offset(y: 0.75)   // the selected underline lands on the page rule
        .sensoryFeedback(.selection, trigger: store.focus)
        .onChange(of: store.focus) { _, f in DirCHaptic.log(".selection", "spine tab → \(f)") }
    }
}

// MARK: - Rows on the rules

struct DirCActionRow: View {
    let store: DirCStore
    let item: StdSuggestion
    @Environment(\.dircPitch) private var pitch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 22
    private let c = DirCColors()

    private var meta: (String, Bool) {
        let source = item.source == .calendar ? C("Calendar") : C("Reminder")
        switch item.status {
        case .mightBeLogged: return (C("\(source) · Might already be entered"), true)
        case .notSure: return (C("\(source) · Not sure it is rental work"), true)
        case .needsHours: return (C("\(source) · Needs hours"), true)
        case .none: return (C("\(source) · \(item.category?.stdLabel ?? "")"), false)
        }
    }

    var body: some View {
        let p = c.p
        let checked = store.checked.contains(item.id)
        DirCRuledStack(pitch: pitch) {
            DirCRuleLine {
                DirCLedgerLine {
                    Text(item.timeRange ?? "").font(DirCFont.stamp).foregroundStyle(p.action).monospacedDigit()
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                } main: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        control(checked: checked, p: p)
                        Text(item.title).font(.body.weight(.semibold)).foregroundStyle(p.ink).dircRuled(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(DirCFormat.hours(item.hours ?? 0)).font(.body).monospacedDigit().foregroundStyle(p.ink)
                            .opacity(item.hours == nil ? 0 : 1)
                    }
                }
            }
            DirCRuleLine {
                DirCLedgerLine {
                    Text(meta.0).font(.subheadline).foregroundStyle(meta.1 ? p.brassInk : p.textSecondary)
                        .dircRuled(.subheadline)
                        .padding(.leading, circle + 12)
                }
            }
        }
        .contentShape(Rectangle())
        .offset(x: store.slid.contains(item.id) ? -440 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(StdCanon.confirm)) { store.confirm(item, reduceMotion: reduceMotion) }
    }

    /// 22pt hairline circle at x 68; confirm draws an oxblood check, no fill.
    private func control(checked: Bool, p: DirCPalette) -> some View {
        Button {
            store.confirm(item, reduceMotion: reduceMotion)
        } label: {
            ZStack {
                Circle().strokeBorder(checked ? p.action : p.textSecondary, lineWidth: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: circle * 0.5, weight: .semibold))
                    .foregroundStyle(p.action)
                    .modifier(DirCDrawOn(hidden: !checked))
            }
            .frame(width: circle, height: circle)
            .padding(11).contentShape(Rectangle()).padding(-11)
        }
        .buttonStyle(DirCPress())
        .disabled(item.hours == nil)
        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + circle * 0.27 }
        .accessibilityLabel(StdCanon.confirm)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames["row.\(item.id)"] = $0 }
    }
}

/// iOS 26+: the check draws on along its stroke. Earlier: a short fade.
struct DirCDrawOn: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.symbolEffect(.drawOn.byLayer, options: .speed(1.4), isActive: hidden)
        } else {
            content.opacity(hidden ? 0 : 1).animation(.easeOut(duration: 0.2), value: hidden)
        }
    }
}

struct DirCEntryRow: View {
    let entry: DirCEntry
    @Environment(\.dircPitch) private var pitch
    @State private var drawn = false
    private let c = DirCColors()

    var body: some View {
        let p = c.p
        DirCRuledStack(pitch: pitch) {
            DirCRuleLine {
                DirCLedgerLine {
                    Text(entry.day.uppercased()).font(DirCFont.stamp).foregroundStyle(p.action)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                } main: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.title).font(.body.weight(.semibold)).foregroundStyle(p.ink).dircRuled(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(DirCFormat.hours(entry.hours)).font(.body).monospacedDigit().foregroundStyle(p.ink)
                    }
                }
            }
            DirCRuleLine {
                DirCLedgerLine {
                    Text(C("\(entry.rental) · \(entry.kind)")).font(.subheadline).foregroundStyle(p.textSecondary)
                        .dircRuled(.subheadline)
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            // A new entry: its rule draws under it in ink, like a pen stroke.
            if entry.fresh {
                Rectangle().fill(p.ink).frame(height: 0.75)
                    .scaleEffect(x: drawn ? 1 : 0, anchor: .leading)
                    .offset(y: -0.25)
                    .onAppear { withAnimation(.linear(duration: 0.30).delay(0.15)) { drawn = true } }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Goal reached: one ripple across the pressed page (the only shader in the app)

struct DirCRipple: ViewModifier {
    let trigger: Int
    let origin: CGPoint
    let enabled: Bool
    private let duration: TimeInterval = 0.8

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, elapsed in
            view.visualEffect { v, _ in
                v.layerEffect(ShaderLibrary.dircRipple(.float2(origin), .float(elapsed), .float(9), .float(14), .float(5.5), .float(900)),
                              maxSampleOffset: CGSize(width: 9, height: 9),
                              isEnabled: enabled && trigger > 0 && elapsed > 0 && elapsed < duration)
            }
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(duration, duration: duration)
        }
    }
}
#endif
