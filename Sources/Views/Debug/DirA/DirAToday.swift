import SwiftUI

#if DEBUG
// MARK: - Model: one focus (a rental, or All) as the drawing board shows it

struct DAFocus: Identifiable, Equatable {
    let id: String
    let name: String
    /// Goal word for the eyebrow: "REPS", "100H TEST", "RECORD ONLY".
    let goalWord: String
    var logged: Double
    let goal: Double?
    /// "of 750 hours" / "hours logged" / "hours here".
    let unit: String
    /// Plain reason for rentals without a target.
    let note: String?
    /// The house's hours on the 0–750 build scale (HouseProgress).
    let stageScale: Double
    /// Month the 100h mark was passed, for the permanent stamp.
    let reachedMonth: String?

    static let dayOfYear = 296.0   // Fri Oct 23, 2026
    static let daysLeft = 69.0

    var expected: Double? { goal.map { $0 * Self.dayOfYear / 365 } }
    var pace: DAPace { DAPace(logged: logged, goal: goal, expected: (goal == nil || done) ? nil : expected) }
    var stageHours: Double { min(logged * stageScale, 750) }
    var keyframe: HouseKeyframe { HouseProgress.keyframe(for: stageHours) }
    var done: Bool { goal.map { logged >= $0 } ?? false }

    /// The one sentence under the line (§1.5, voice §1.9).
    var sentence: String {
        guard let goal, let expected else { return note ?? DL("Hours kept, no target.") }
        if done { return goal <= 100 ? DL("100 hours. Frame's up. Your CPA takes it from here.") : DL("\(Int(goal)) hours. Done for 2026.") }
        if logged + 0.001 < expected {
            let weekly = Int(((goal - logged) / (Self.daysLeft / 7)).rounded(.up))
            return DL("\(weekly)h a week to reach \(Int(goal)) by Dec 31.")
        }
        return DL("Ahead of pace by \(Int((logged - expected).rounded()))h. Keep the pace.")
    }
}

struct DASeed {
    let id: String
    var focuses: [DAFocus]
    let suggestions: [StdSuggestion]
    let week: [StdEntry]

    static func make(_ id: String) -> DASeed {
        // Demo seeds: one rental just short of a mark.
        if id == "stage" || id == "goal" {
            let base = StdSeed.make("one")
            let f = id == "stage"
                ? DAFocus(id: "santa", name: "Santa Ray Ave", goalWord: DL("500H TEST"), logged: 98.5, goal: 500, unit: DL("of 500 hours"),
                          note: nil, stageScale: 1, reachedMonth: nil)
                : DAFocus(id: "santa", name: "Santa Ray Ave", goalWord: DL("100H TEST"), logged: 98, goal: 100, unit: DL("of 100 hours"),
                          note: nil, stageScale: 5, reachedMonth: nil)
            return DASeed(id: id, focuses: [f], suggestions: base.suggestions, week: base.week)
        }
        if id == "behind" {
            // The spec's own example: REPS, 206 of 750 across two rentals, well behind the plumb line.
            let base = StdSeed.make("brian")
            let all = DAFocus(id: "all", name: DL("All"), goalWord: DL("REPS"), logged: 206, goal: 750, unit: DL("of 750 hours"),
                              note: nil, stageScale: 1, reachedMonth: nil)
            let santa = DAFocus(id: "santa", name: "Santa Ray Ave", goalWord: DL("COUNTS TO 750"), logged: 120, goal: nil, unit: DL("hours here"),
                                note: DL("Counts toward your 750."), stageScale: 0, reachedMonth: nil)
            let delaney = DAFocus(id: "delaney", name: "Delaney Ct", goalWord: DL("COUNTS TO 750"), logged: 86, goal: nil, unit: DL("hours here"),
                                  note: DL("Counts toward your 750."), stageScale: 0, reachedMonth: nil)
            return DASeed(id: id, focuses: [all, santa, delaney], suggestions: base.suggestions, week: base.week)
        }
        let std = StdSeed.make(id)
        var list: [DAFocus] = []
        if let shared = std.rentals.sharedTarget {
            list.append(DAFocus(id: "all", name: DL("All"), goalWord: DL("REPS"), logged: std.rentals.totalHours, goal: Double(shared),
                                unit: DL("of \(shared) hours"), note: nil, stageScale: 1, reachedMonth: nil))
        }
        for r in std.rentals.rentals {
            switch r.target {
            case .own(let t):
                list.append(DAFocus(id: r.id, name: r.name, goalWord: DL("\(t)H TEST"), logged: r.hours, goal: Double(t),
                                    unit: DL("of \(t) hours"), note: nil, stageScale: 500 / Double(t), reachedMonth: r.reached))
            case .record(let reason):
                list.append(DAFocus(id: r.id, name: r.name, goalWord: DL("RECORD ONLY"), logged: r.hours, goal: nil,
                                    unit: DL("hours logged"), note: DL("\(reason)."), stageScale: 0, reachedMonth: nil))
            case .counts:
                list.append(DAFocus(id: r.id, name: r.name, goalWord: DL("COUNTS TO \(std.rentals.sharedTarget ?? 750)"), logged: r.hours, goal: nil,
                                    unit: DL("hours here"), note: DL("Counts toward your \(std.rentals.sharedTarget ?? 750)."), stageScale: 0, reachedMonth: nil))
            }
        }
        return DASeed(id: id, focuses: list, suggestions: std.suggestions, week: std.week)
    }
}

// MARK: - Root: native glass tab bar, the detached "+" (§1.6 tab bar)

struct DirARoot: View {
    let launch: DirALaunch
    @State private var tab = 0
    @State private var showLog: Bool
    @State private var logged: (hours: Double, rental: String)? = nil
    @State private var logSerial = 0
    private var env = DAEnv()

    init(launch: DirALaunch) {
        self.launch = launch
        _showLog = State(initialValue: launch.screen == .logtime)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                TabView(selection: $tab) {
                    Tab(DL("Today"), systemImage: "sun.horizon", value: 0) {
                        DATodayScreen(launch: launch, logSerial: logSerial, logged: logged, onCompose: { showLog = true })
                    }
                    Tab(DL("Inbox"), systemImage: "tray", value: 1) { blank }.badge(7)
                    Tab(DL("Records"), systemImage: "book.closed", value: 2) { blank }
                    Tab(DL("Rentals"), systemImage: "house", value: 3) { blank }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                DATodayScreen(launch: launch, logSerial: logSerial, logged: logged, onCompose: { showLog = true })
            }
        }
        .tint(env.c.action)
        .sheet(isPresented: $showLog) {
            DALogTimeSheet(demo: launch.demo, scrollTo: launch.scroll, onLog: { hours, rental in
                logged = (hours, rental)
                logSerial += 1
                showLog = false
            }, onClose: { showLog = false })
            .presentationDetents([.large])
            .presentationBackground(env.c.sheet)
        }
    }

    private var blank: some View { DAPaper() }
}

// MARK: - Today (§1.12)

struct DATodayScreen: View {
    let launch: DirALaunch
    let logSerial: Int
    let logged: (hours: Double, rental: String)?
    let onCompose: () -> Void

    @State private var seed: DASeed
    @State private var focusID: String
    @State private var confirmed: Set<String> = []
    @State private var removed: Set<String> = []
    @State private var toast: String? = nil
    @State private var successTick = 0
    @State private var logKnock = 0
    @State private var stampLand = 0
    @State private var showStampNow = false
    @State private var stampDropped = false
    @State private var goalTick = 0
    @State private var stageTick = 0
    @State private var rippleOrigin: CGPoint = .zero
    @Namespace private var glassNS

    private var env = DAEnv()
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 96

    init(launch: DirALaunch, logSerial: Int, logged: (hours: Double, rental: String)?, onCompose: @escaping () -> Void) {
        self.launch = launch
        self.logSerial = logSerial
        self.logged = logged
        self.onCompose = onCompose
        let s = DASeed.make(launch.seedID)
        _seed = State(initialValue: s)
        _focusID = State(initialValue: s.focuses[min(launch.focusIndex, s.focuses.count - 1)].id)
    }

    private var focus: DAFocus { seed.focuses.first { $0.id == focusID } ?? seed.focuses[0] }
    private var c: DAColors { env.c }
    private var ax: Bool { typeSize.isAccessibilitySize }
    /// AX2+: the model hides, the line keeps its labels (§1.10).
    private var hidesModel: Bool { typeSize >= .accessibility2 }
    private var heroPt: CGFloat { min(heroSize, 120) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .id("top")
                Color.clear.frame(height: 1).id("bottom")
            }
            .scrollIndicators(.hidden)
            .background {
                // The ripple runs on the paper and the model only: layerEffect can't rasterize the
                // UIKit-backed scroll views in the content (they render blank).
                DAPaper().modifier(DARippleEffect(trigger: goalTick, origin: rippleOrigin, enabled: !reduceMotion))
            }
            .onAppear {
                if launch.scroll == "bottom" { DADemo.after(0.4) { proxy.scrollTo("bottom", anchor: .bottom) } }
                runDemo()
            }
        }
        .modifier(DAComposeBar(toast: toast, ns: glassNS, onCompose: onCompose))
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: logKnock)
        .sensoryFeedback(.impact(weight: .heavy), trigger: stampLand)
        .onChange(of: logSerial) { _, _ in
            guard let logged else { return }
            add(logged.hours, toast: DL("\(StdFormat.hours(logged.hours)) on the books. \(focus.name)."))
            logKnock += 1
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            numeral.padding(.top, 8)
            dimension.padding(.top, ax ? 16 : 8)
            if !hidesModel {
                model.padding(.top, 8)
            }
            switcher.padding(.top, hidesModel ? 20 : 8)
            DASectionHeader(DL("To confirm · \(rows.count + rest)"), trailing: DL("See all"))
                .padding(.top, 24)
            rowsSection.padding(.top, 8)
            DASectionHeader(DL("This week"), trailing: DL("Records")).padding(.top, 24)
            weekSection.padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 40)
    }

    private var eyebrow: some View {
        Text(DL("Today · Fri, Oct 23 · \(focus.goalWord)").uppercased())
            .font(DAFont.mono).tracking(DAFont.monoTracking)
            .foregroundStyle(c.draftingInk)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 16, alignment: .leading)
    }

    /// The number is the title: Fraunces opsz 144, wght 600, SOFT 50, tabular, tracking −3.
    private var numeral: some View {
        let number = Text(verbatim: "\(Int(focus.logged.rounded(.down)))")
            .font(DAFont.fraunces(size: heroPt, opsz: 144, wght: 600))
            .tracking(-3)
            .foregroundStyle(c.ink)
            .contentTransition(.numericText(value: focus.logged))
            .animation(reduceMotion ? nil : .spring(duration: 0.40, bounce: 0), value: focus.logged)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
        let unit = Text(focus.unit).font(.body).foregroundStyle(c.textSecondary)
        return Group {
            if ax {
                VStack(alignment: .leading, spacing: 0) { number; unit }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) { number; unit }
                    .frame(height: 100, alignment: .bottomLeading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dimension: some View {
        VStack(alignment: .leading, spacing: 6) {
            DADimensionLine(pace: focus.pace)
            Text(focus.sentence)
                .font(.subheadline)
                .foregroundStyle(c.textSecondary)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onTapGesture {}   // Pace check → Reports zoom (not mocked)
    }

    // MARK: The model on the desk (no card; contact shadow; stage drop-and-settle; stamp)

    private var model: some View {
        ZStack {
            Ellipse().fill(c.ink.opacity(0.18)).frame(width: 240, height: 24).blur(radius: 6)
                .offset(y: 72)
            house
                .keyframeAnimator(initialValue: DADrop(), trigger: stageTick) { v, k in
                    v.scaleEffect(k.scale, anchor: .bottom).offset(y: k.y)
                } keyframes: { _ in
                    KeyframeTrack(\.y) {
                        CubicKeyframe(reduceMotion ? 0 : -14, duration: 0.18)
                        SpringKeyframe(0, duration: 0.42, spring: .snappy)
                    }
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(reduceMotion ? 1 : 1.04, duration: 0.18)
                        SpringKeyframe(1, duration: 0.42, spring: .snappy)
                    }
                }
            if let lines = stampLines {
                DAStamp(lines: lines)
                    .rotationEffect(.degrees(-8))
                    .scaleEffect(stampDropped || !showStampNow ? 1 : 1.5)
                    .opacity(stampDropped || !showStampNow ? 1 : 0)
                    .offset(x: 108, y: 50)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .onGeometryChange(for: CGPoint.self) { g in
            let f = g.frame(in: .global); return CGPoint(x: f.midX, y: f.maxY - 24)
        } action: { rippleOrigin = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DL("House, \(focus.keyframe.rawValue)"))
    }

    private var house: some View {
        let k = focus.keyframe
        return ZStack {
            Image(decorative: k.builtImageName).resizable().interpolation(.high).scaledToFit()
            HouseLineworkImage(name: k.linesImageName).foregroundStyle(c.linework)
        }
        .frame(width: 300, height: 176)
        .modifier(DARippleEffect(trigger: goalTick, origin: CGPoint(x: 150, y: 152), enabled: !reduceMotion))
        .id(k)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.30), value: k)
    }

    /// The red inspection stamp: once at 100h (demo), and kept on rentals past 100 that are not behind
    /// (terracotta is one glyph per screen; when behind, the plumb marker has it).
    private var stampLines: [String]? {
        if showStampNow { return [DL("INSPECTED"), DL("100 H · OCT 23")] }
        guard focus.logged >= 100, focus.goal != nil, !focus.pace.behind else { return nil }
        return [DL("INSPECTED"), DL("100 H · \((focus.reachedMonth ?? "2026").uppercased())")]
    }

    // MARK: Rental switcher (§1.6): chips under the house, "All" first, selected = 1.5pt action ring

    @ViewBuilder private var switcher: some View {
        if seed.focuses.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(seed.focuses) { f in chip(f) }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .frame(minHeight: 46)
            .sensoryFeedback(.selection, trigger: focusID)
        }
    }

    private func chip(_ f: DAFocus) -> some View {
        let selected = f.id == focusID
        return Button {
            withAnimation(.spring(duration: 0.25, bounce: 0)) { focusID = f.id }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: f.id == "all" ? "square.grid.2x2" : "house")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(c.draftingInk)
                    .frame(width: 20, height: 20)
                Text(f.name).font(.footnote.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(c.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? c.action : c.border, lineWidth: selected ? 1.5 : 0.5))
            // Chip names cap at AX1 so two rentals stay in view; long-press shows the large content viewer.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .accessibilityShowsLargeContentViewer()
        .buttonStyle(DAPress())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Rows

    private var todayItems: [StdSuggestion] {
        seed.suggestions.filter { $0.group == L("Today") && !removed.contains($0.id) }
    }
    private var rows: [StdSuggestion] { Array(todayItems.prefix(2)) }
    private var rest: Int { seed.suggestions.filter { !removed.contains($0.id) }.count - rows.count }
    private var likely: Int { seed.suggestions.filter { $0.isLikely && !removed.contains($0.id) }.count }

    private var rowsSection: some View {
        DASection {
            HStack {
                Text(DL("Today")).font(.subheadline.weight(.semibold)).foregroundStyle(c.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16).frame(minHeight: 28).padding(.top, 6)
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                if i > 0 { DAHairline().padding(.leading, 50) }
                DAActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if likely >= 2 {
                DAHairline()
                Button(StdCanon.confirmLikely(likely)) {}
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(c.action)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(DAPress())
            }
        }
    }

    private var weekSection: some View {
        DASection {
            ForEach(Array(seed.week.enumerated()), id: \.element.id) { i, e in
                if i > 0 { DAHairline().padding(.leading, 16) }
                DAWeekRow(entry: e).padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }

    // MARK: Actions

    private func confirm(_ item: StdSuggestion) {
        guard !confirmed.contains(item.id) else { return }
        withAnimation(.easeOut(duration: 0.15)) { _ = confirmed.insert(item.id) }
        successTick += 1
        DADemo.after(0.45) {
            withAnimation(.spring(duration: 0.25, bounce: 0)) { _ = removed.insert(item.id) }
            let rental = seed.focuses.first { $0.id == item.rental }?.name ?? focus.name
            add(item.hours ?? 0, toast: DL("\(StdFormat.hours(item.hours)) on the books. \(item.title.replacingOccurrences(of: " at \(rental)", with: "")), \(rental)."))
        }
    }

    /// Logged hours land on the focused rental: the numeral rolls, the line's fill extends.
    private func add(_ hours: Double, toast text: String) {
        guard let i = seed.focuses.firstIndex(where: { $0.id == focusID }) else { return }
        let before = seed.focuses[i]
        withAnimation(.spring(duration: 0.60, bounce: 0)) { seed.focuses[i].logged += hours }
        let after = seed.focuses[i]
        if before.keyframe != after.keyframe { stageTick += 1 }
        withAnimation(.spring(duration: 0.3, bounce: 0)) { toast = text }
        DADemo.after(2.6) { withAnimation(.easeIn(duration: 0.2)) { toast = nil } }
        // Stage advance at 100: the stamp lands after the drop settles.
        if before.logged < 100, after.logged >= 100, after.goal != nil {
            showStampNow = true
            stampDropped = false
            DADemo.after(0.45) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.30, bounce: 0.30)) { stampDropped = true }
                DADemo.after(0.12) { stampLand += 1 }
            }
        }
        // Goal reached: the line completes, one ripple from the house, the custom haptic.
        if !before.done, after.done {
            DADemo.after(0.55) {
                goalTick += 1
                if reduceMotion { successTick += 1 } else { DAGoalHaptics.shared.play() }
            }
        }
    }

    private func runDemo() {
        switch launch.demo {
        case "confirm":
            DADemo.after(2.0) { if let first = rows.first(where: { $0.isLikely }) { confirm(first) } }
        case "stage":
            DADemo.after(2.0) { add(1.5, toast: DL("1h 30m on the books. Santa Ray Ave.")); logKnock += 1 }
        case "goal":
            DADemo.after(2.0) { add(2, toast: DL("2h on the books. Santa Ray Ave.")); logKnock += 1 }
        default: break
        }
    }
}

struct DADrop { var y: CGFloat = 0; var scale: CGFloat = 1 }

// MARK: - Goal ripple (one shader moment, §1.7)

struct DARippleEffect: ViewModifier {
    let trigger: Int
    let origin: CGPoint
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, t in
                view.visualEffect { v, _ in
                    v.layerEffect(ShaderLibrary.daRipple(.float2(origin), .float(t), .float(10), .float(14), .float(5), .float(900)),
                                  maxSampleOffset: CGSize(width: 10, height: 10), isEnabled: t > 0 && t < 0.8)
                }
            } keyframes: { _ in
                MoveKeyframe(0)
                LinearKeyframe(0.8, duration: 0.8)
                MoveKeyframe(0)
            }
        } else {
            content
        }
    }
}

// MARK: - Rows (§1.3 anatomy; drafting circle control)

struct DAActionRow: View {
    let item: StdSuggestion
    let confirmed: Bool
    let onConfirm: () -> Void
    private var env = DAEnv()
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var titleLine: CGFloat = 22

    init(item: StdSuggestion, confirmed: Bool, onConfirm: @escaping () -> Void) {
        self.item = item; self.confirmed = confirmed; self.onConfirm = onConfirm
    }

    private var c: DAColors { env.c }
    private var tag: (String, Color, Color)? {
        switch item.status {
        case .notSure: return (L("Not sure"), c.caution, c.cautionSurface)
        case .needsHours: return (L("Needs hours"), c.caution, c.cautionSurface)
        case .mightBeLogged: return (L("Might be logged"), c.informational, c.informationalSurface)
        case .none:
            guard let cat = item.category else { return nil }
            return (cat.stdLabel, c.tagInk(cat), c.tagWash(cat))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            control
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    meta
                    // Hours and tag share a line when both fit; otherwise the tag drops to its own line.
                    // Either way it renders in full (wraps to 2 lines at most), with no width cap.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { hours; tagView }
                        VStack(alignment: .leading, spacing: 4) {
                            hours
                            if let tag { DATag(text: tag.0, ink: tag.1, wash: tag.2) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    // Fit order: the word "Calendar" yields first, then the tag. Nothing truncates.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { meta(word: true).fixedSize(); tagView }
                        HStack(spacing: 6) { meta(word: false).fixedSize(); tagView }
                        meta(word: false).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                hours.padding(.top, 2)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// Drafting circle: 1.5pt, textTertiary; confirm fills positive and draws the check on.
    private var control: some View {
        Button(action: onConfirm) {
            ZStack {
                Circle().strokeBorder(confirmed ? c.positive : c.textTertiary, lineWidth: 1.5)
                Circle().fill(c.positive).opacity(confirmed ? 1 : 0)
                if confirmed {
                    Image(systemName: "checkmark")
                        .font(.system(size: circle * 0.5, weight: .bold))
                        .foregroundStyle(c.dark ? c.onAction : Color.white)
                        .daDrawOnTransition()
                }
            }
            .frame(width: circle, height: circle)
            .frame(height: max(circle, titleLine))
            .padding(11).contentShape(Rectangle()).padding(-11)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("Confirm \(StdFormat.hours(item.hours))"))
        .accessibilityIdentifier("da.confirm.\(item.id)")
    }

    private var title: some View {
        Text(item.title).font(.body.weight(.semibold)).foregroundStyle(c.ink)
            .lineLimit(typeSize >= .xxLarge ? nil : 2)   // no ellipsis at XXL in narrow panes (Duo, 322pt)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var tagView: some View {
        if let tag { DATag(text: tag.0, ink: tag.1, wash: tag.2).fixedSize() }
    }

    private var meta: some View { meta(word: true) }

    private func meta(word showWord: Bool) -> some View {
        let glyph = Text(Image(systemName: item.source == .calendar ? "calendar" : "checklist")).foregroundStyle(c.draftingInk)
        let word = item.source == .calendar ? L("Calendar") : L("Reminder")
        let range = (item.timeRange ?? "").replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
        let words = showWord ? (range.isEmpty ? word : word + " · " + range) : (range.isEmpty ? word : range)
        return (glyph + Text(verbatim: " ") + Text(words).foregroundStyle(c.textSecondary))
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }

    private var hours: some View {
        Text(StdFormat.hours(item.hours))
            .font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
            .foregroundStyle(c.ink).fixedSize()
    }
}

struct DAWeekRow: View {
    let entry: StdEntry
    private var env = DAEnv()
    @Environment(\.dynamicTypeSize) private var typeSize
    init(entry: StdEntry) { self.entry = entry }

    var body: some View {
        let c = env.c
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(.semibold)).foregroundStyle(c.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(DL("\(entry.day) · \(entry.rental)")).font(.subheadline).foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize {
                        DATag(text: entry.category.stdLabel, ink: c.tagInk(entry.category), wash: c.tagWash(entry.category)).fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(StdFormat.hours(entry.hours)).font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(c.ink)
                if typeSize.isAccessibilitySize {
                    DATag(text: entry.category.stdLabel, ink: c.tagInk(entry.category), wash: c.tagWash(entry.category))
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The "+" (glassProminent, tinted action) and the toast, one glass container (morph)

struct DAComposeBar: ViewModifier {
    let toast: String?
    let ns: Namespace.ID
    let onCompose: () -> Void
    private var env = DAEnv()

    init(toast: String?, ns: Namespace.ID, onCompose: @escaping () -> Void) {
        self.toast = toast; self.ns = ns; self.onCompose = onCompose
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 24) {
                    HStack(spacing: 10) {
                        if let toast {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(env.c.positive)
                                Text(toast).font(.subheadline.weight(.semibold)).foregroundStyle(env.c.ink)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .capsule)
                            .glassEffectID("toast", in: ns)
                        } else {
                            Spacer()
                        }
                        Button(action: onCompose) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundStyle(env.c.onAction)
                                .frame(width: 56, height: 56)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(env.c.action).interactive(), in: .circle)
                        .glassEffectID("plus", in: ns)
                        .accessibilityLabel(DL("Log time"))
                        .accessibilityIdentifier("da.compose")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        } else {
            content
        }
    }
}
#endif
