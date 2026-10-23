import SwiftUI
import LucideIcons

#if DEBUG
// MARK: - "Check my goal", visual first (prototype)
//
// One rental per screen: the blueprint house, one question as four tiles, then the answer as a
// picture (your bar, the other person's bar drawn as drafting linework, a ruler with a marker that
// slides from the old target to the new). Spec: AgentScratch/landlordhours/2026-10-23/goalcheck-redesign/spec.md

enum HomeProtoAnswer: String, CaseIterable, Hashable {
    case me, spouse, other, notSure

    init?(arg: String) {
        switch arg {
        case "me": self = .me
        case "spouse": self = .spouse
        case "other", "cleaner": self = .other
        case "notsure": self = .notSure
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .me: return String(localized: "Me", table: "HomeProto")
        case .spouse: return String(localized: "Me + spouse", table: "HomeProto")
        case .other: return String(localized: "Cleaner or manager", table: "HomeProto")
        case .notSure: return String(localized: "Not sure", table: "HomeProto")
        }
    }

    var symbol: String {
        switch self {
        case .me: return "person.fill"
        case .spouse: return "person.2.fill"
        case .other: return "wrench.and.screwdriver.fill"
        case .notSure: return "questionmark"
        }
    }

    var youDoMore: Bool { self == .me || self == .spouse }
}

/// What the app would do with an answer. Nothing changes without a tap.
struct HomeProtoOutcome {
    enum Kind { case propose(to: Int), same, unsure }
    let kind: Kind
    let line: String
    let primary: String
    let secondary: String?
    let summary: String
    /// The target the marker and the house preview move to (same as now when nothing changes).
    let shownTarget: Int?

    static func make(_ r: HomeProtoRental, _ a: HomeProtoAnswer) -> HomeProtoOutcome {
        let next = String(localized: "Next", table: "HomeProto")
        switch r.target {
        case .counts:
            return .init(kind: .same, line: String(localized: "Every rental counts toward one 750.", table: "HomeProto"),
                         primary: next, secondary: nil, summary: String(localized: "Counts toward 750", table: "HomeProto"), shownTarget: 750)
        case .record(let reason):
            let long = reason.hasPrefix("Long")
            let line = long ? String(localized: "Long stays stay record only under your goal.", table: "HomeProto")
                            : String(localized: "Someone else does more here, so this one stays record only.", table: "HomeProto")
            return .init(kind: a == .notSure ? .unsure : .same, line: a == .notSure ? String(localized: "No change for now.", table: "HomeProto") : line,
                         primary: next, secondary: a == .notSure ? String(localized: "Ask me later", table: "HomeProto") : nil,
                         summary: long ? String(localized: "Long stays", table: "HomeProto") : String(localized: "Someone else does more", table: "HomeProto"),
                         shownTarget: nil)
        case .own(let t):
            if a == .notSure {
                return .init(kind: .unsure, line: String(localized: "No change for now.", table: "HomeProto"), primary: next,
                             secondary: String(localized: "Ask me later", table: "HomeProto"),
                             summary: String(localized: "No change for now", table: "HomeProto"), shownTarget: t)
            }
            if a == .other && t == 100 {
                return .init(kind: .propose(to: 500),
                             line: String(localized: "Someone else does more here, so the app would track 500.", table: "HomeProto"),
                             primary: String(localized: "Switch to \(500)", table: "HomeProto"),
                             secondary: String(localized: "Keep \(t)", table: "HomeProto"),
                             summary: String(localized: "Cleaner does more", table: "HomeProto"), shownTarget: 500)
            }
            if a.youDoMore && t == 500 {
                return .init(kind: .propose(to: 100),
                             line: String(localized: "You do most of the work here, so the app could track 100.", table: "HomeProto"),
                             primary: String(localized: "Switch to \(100)", table: "HomeProto"),
                             secondary: String(localized: "Keep \(t)", table: "HomeProto"),
                             summary: String(localized: "You do more", table: "HomeProto"), shownTarget: 100)
            }
            return .init(kind: .same, line: String(localized: "No change: the app keeps tracking \(t).", table: "HomeProto"),
                         primary: next, secondary: nil, summary: String(localized: "No change", table: "HomeProto"), shownTarget: t)
        }
    }
}

// MARK: Root

struct HomeProtoGoalCheckRoot: View {
    let config: HomeProtoLaunch
    var body: some View {
        if config.step == .inbox { HomeProtoInboxPage(seed: config.seed) } else { HomeProtoGoalFlow(config: config) }
    }
}

private func mono() -> Font { .system(.caption2, design: .monospaced).weight(.medium) }
private let curve = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)

// MARK: Inbox card (entry)

struct HomeProtoInboxPage: View {
    let seed: HomeProtoSeed
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var rental: HomeProtoRental { seed.rentals.first(where: { $0.hasOwnTarget }) ?? seed.rentals[0] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inbox", tableName: "HomeProto")
                    .font(LHFont.fraunces(.largeTitle)).foregroundStyle(colors.textPrimary)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                card
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.calendar, size: 16).foregroundStyle(colors.informational)
                Text("From your calendar", tableName: "HomeProto")
                    .font(mono()).textCase(.uppercase).tracking(1.3).foregroundStyle(colors.informational)
            }
            HStack(alignment: .center, spacing: 12) {
                HomeProtoArt(size: 56, keyframe: HomeProtoStage.keyframe(for: rental))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rental.name).font(.headline).foregroundStyle(colors.textPrimary)
                    Text("“Turnover clean” · \(seed.hoursLine(rental))", tableName: "HomeProto")
                        .font(.footnote).foregroundStyle(colors.textSecondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            Text("Does the cleaner do more hours here than you?", tableName: "HomeProto")
                .font(.headline).foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                tile(symbol: "wrench.and.screwdriver.fill", title: String(localized: "They do", table: "HomeProto"))
                tile(symbol: "person.fill", title: String(localized: "I do", table: "HomeProto"))
            }
            Button {} label: {
                Text("Not sure", tableName: "HomeProto").font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.lhPressable)
        }
        .padding(16)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func tile(symbol: String, title: String) -> some View {
        Button {} label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(colors.actionSurface)
                    Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.action)
                }
                .frame(width: 40, height: 40)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.border, lineWidth: 1))
        }
        .buttonStyle(.lhPressable)
    }
}

// MARK: Flow

struct HomeProtoGoalFlow: View {
    enum Phase { case question, result, summary }

    let config: HomeProtoLaunch
    private var seed: HomeProtoSeed { config.seed }
    @State private var index: Int
    @State private var phase: Phase
    @State private var answers: [String: HomeProtoAnswer] = [:]
    @State private var picked: HomeProtoAnswer?
    @State private var decisions: [String: Int] = [:]    // rental id -> new target, when switched
    // Result choreography
    @State private var bars = false
    @State private var markerMoved = false
    @State private var lineShown = false
    @State private var buttonsShown = false
    @State private var forward = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var slow: Double { config.slow }

    init(config: HomeProtoLaunch) {
        self.config = config
        let rentals = config.seed.rentals
        var preset: [String: HomeProtoAnswer] = [:]
        for (i, r) in rentals.enumerated() {
            let given = config.answers.indices.contains(i) ? HomeProtoAnswer(arg: config.answers[i]) : nil
            if let given { preset[r.id] = given }
            else if case .record(let reason) = r.target, reason.hasPrefix("Long") { preset[r.id] = .me }
            else { preset[r.id] = .other }
        }
        _answers = State(initialValue: preset)
        var start = 0, ph = Phase.question
        switch config.step {
        case .inbox: break
        case .question(let n): start = min(max(0, n), rentals.count - 1)
        case .result(let n): start = min(max(0, n), rentals.count - 1); ph = .result
        case .summary: start = rentals.count - 1; ph = .summary
        }
        _index = State(initialValue: start)
        _phase = State(initialValue: ph)
        // Earlier rentals are already decided when a frame starts mid-flow: the app's proposal was accepted.
        var decided: [String: Int] = [:]
        let upTo = ph == .summary ? rentals.count : start
        for r in rentals.prefix(upTo) {
            if case .propose(let to) = HomeProtoOutcome.make(r, preset[r.id] ?? .other).kind { decided[r.id] = to }
        }
        _decisions = State(initialValue: decided)
        if ph == .result { _picked = State(initialValue: preset[rentals[start].id]) }
    }

    private var rental: HomeProtoRental { seed.rentals[index] }
    private var count: Int { seed.rentals.count }

    private var progress: Double {
        switch phase {
        case .question: return (Double(index) + 0.5) / Double(count)
        case .result: return Double(index + 1) / Double(count)
        case .summary: return 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                switch phase {
                case .summary: summary.transition(slide)
                default: card.id(index).transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colors.background)
        .task { await autoplay() }
        .task(id: phase) { if phase == .result { await runResult() } }
    }

    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity),
                           removal: .offset(x: forward ? -24 : 24).combined(with: .opacity))
    }

    private func go(_ body: @escaping () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.24 * slow), body)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { back() } label: {
                LucideIcon(image: Lucide.chevronLeft, size: 22).foregroundStyle(colors.action)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.lhPressable)
            .accessibilityLabel(String(localized: "Back", table: "HomeProto"))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.actionSurface)
                    Capsule().fill(colors.action).frame(width: g.size.width * progress)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.24 * slow), value: progress)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(.leading, 8).padding(.trailing, 20).padding(.top, 4)
    }

    private func back() {
        forward = false
        switch phase {
        case .result: go { phase = .question; resetReveal() }
        case .question: if index > 0 { go { index -= 1; phase = .result } }
        case .summary: go { phase = .result }
        }
    }

    // MARK: Card

    private var stageTarget: Int? {
        guard case .own(let t) = rental.target else { return nil }
        if phase == .result, markerMoved, case .propose(let to) = outcome.kind { return to }
        return t
    }

    private var keyframe: HouseKeyframe {
        guard let t = stageTarget else { return .k00_lot }
        return HomeProtoStage.keyframe(hours: HomeProtoStage.hours(for: rental, target: t))
    }

    private var outcome: HomeProtoOutcome { HomeProtoOutcome.make(rental, picked ?? answers[rental.id] ?? .other) }

    private var planEyebrow: String {
        let plan: String
        switch rental.target {
        case .own(let t): plan = String(localized: "\(t)-hour target", table: "HomeProto")
        case .record: plan = String(localized: "Record only", table: "HomeProto")
        case .counts: plan = String(localized: "Counts toward \(seed.sharedTarget ?? 750)", table: "HomeProto")
        }
        return count > 1 ? String(localized: "Rental \(index + 1) of \(count) · \(plan)", table: "HomeProto") : plan
    }

    private var card: some View {
        ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                Text(planEyebrow).font(mono()).textCase(.uppercase).tracking(1.3).foregroundStyle(colors.draftingInk)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                HomeProtoArt(size: ax ? 96 : 128, keyframe: keyframe, lines: true)
                VStack(spacing: 4) {
                    Text(rental.name).font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.subheadline).foregroundStyle(colors.textSecondary).monospacedDigit()
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                if phase == .question { question.transition(.opacity.combined(with: .scale(scale: 0.97))) }
                else { result.transition(.opacity) }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
            Color.clear.frame(height: 1).id("end")
        }
        .onAppear {
            guard config.scroll == "end" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { proxy.scrollTo("end", anchor: .bottom) }
        }
        }
    }

    private var subtitle: String {
        let whole = Int(rental.hours.rounded(.down))
        if case .own(let t) = rental.target { return String(localized: "\(whole) of \(t) hours", table: "HomeProto") }
        return String(localized: "\(whole) hours", table: "HomeProto")
    }

    // MARK: Step 1

    private var question: some View {
        VStack(spacing: 16) {
            Text("Who does most of the hands-on work here?", tableName: "HomeProto")
                .font(.headline).foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            let cols = ax ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(HomeProtoAnswer.allCases, id: \.self) { a in answerTile(a) }
            }
        }
    }

    private func answerTile(_ a: HomeProtoAnswer) -> some View {
        let selected = picked == a
        let spouse = a == .spouse
        return Button { choose(a) } label: {
            let content = VStack(spacing: 8) {
                ZStack {
                    Circle().fill(selected ? colors.onAction.opacity(0.18) : (spouse ? colors.roseWash : colors.actionSurface))
                    Image(systemName: a.symbol).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? colors.onAction : (spouse ? colors.rose : colors.action))
                }
                .frame(width: 44, height: 44)
                Text(a.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? colors.onAction : colors.textPrimary)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            content
                .frame(maxWidth: .infinity, minHeight: ax ? 88 : 112)
                .padding(.horizontal, 8)
                .background(selected ? colors.action : colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.clear : colors.border, lineWidth: 1))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(String(localized: "\(a.title), who does most of the work here", table: "HomeProto"))
    }

    private func choose(_ a: HomeProtoAnswer) {
        withAnimation(.easeOut(duration: 0.16 * slow)) { picked = a }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(0.22 * slow * 1e9))
            forward = true
            resetReveal()
            go { answers[rental.id] = a; phase = .result }
        }
    }

    // MARK: Step 2

    private var result: some View {
        let o = outcome
        let a = picked ?? .other
        return VStack(spacing: 20) {
            if a != .notSure { comparison(a).opacity(bars ? 1 : 0) }
            if o.shownTarget != nil, hasRuler { ruler(o).opacity(bars ? 1 : 0) }
            Text(o.line).font(.subheadline).foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .opacity(lineShown ? 1 : 0).offset(y: lineShown || reduceMotion ? 0 : 8)
            buttons(o).opacity(buttonsShown ? 1 : 0)
        }
    }

    private var hasRuler: Bool { rental.hasOwnTarget }

    private func comparison(_ a: HomeProtoAnswer) -> some View {
        let more = !a.youDoMore
        let hours = Int(rental.hours.rounded(.down))
        return VStack(alignment: .leading, spacing: ax ? 24 : 14) {
            barRow(label: String(localized: "You", table: "HomeProto")) { w in
                let bar = max(6, w * 0.4 * min(1, rental.hours / max(rental.hours, 50)))
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.action).frame(width: bars ? bar : 0, height: 8)
                    Text("\(hours)h", tableName: "HomeProto")
                        .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(colors.textPrimary)
                        .offset(x: bar + 8).opacity(bars ? 1 : 0)
                }
            }
            barRow(label: String(localized: "Cleaner", table: "HomeProto")) { w in
                let mine = max(6, w * 0.4)
                let full = more ? max(w - 64, mine + 20) : max(mine * 0.55, 18)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(colors.draftingInk, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: bars ? full : 0, height: 8)
                    HStack(spacing: 4) {
                        Text(more ? String(localized: "more", table: "HomeProto") : String(localized: "less", table: "HomeProto"))
                            .font(.footnote).foregroundStyle(colors.textSecondary)
                        if more { LucideIcon(image: Lucide.arrowRight, size: 12).foregroundStyle(colors.draftingInk) }
                    }
                    .offset(x: full + 8).opacity(bars ? 1 : 0).animation(curve.delay(0.06 * slow), value: bars)
                }
                .animation(curve.speed(1 / slow).delay(0.06 * slow), value: bars)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : curve.speed(1 / slow), value: bars)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(more ? String(localized: "You \(hours) hours, cleaner more", table: "HomeProto")
                                 : String(localized: "You \(hours) hours, cleaner less", table: "HomeProto"))
    }

    private func barRow<Bar: View>(label: String, @ViewBuilder bar: @escaping (CGFloat) -> Bar) -> some View {
        let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(colors.textPrimary)
                .frame(width: ax ? nil : 64, alignment: .leading)
            GeometryReader { g in bar(g.size.width).frame(maxHeight: .infinity, alignment: .center) }.frame(height: 20)
        }
    }

    // Ruler: 100 · 500 · 750 with a marker that slides from the old target to the new one.
    private func ruler(_ o: HomeProtoOutcome) -> some View {
        let from = { () -> Int in if case .own(let t) = rental.target { return t }; return 500 }()
        let to = o.shownTarget ?? from
        func x(_ h: Int, _ w: CGFloat) -> CGFloat { w * (0.04 + CGFloat(h - 100) / 650 * 0.92) }
        return GeometryReader { g in
            let w = g.size.width
            let at = markerMoved ? to : from
            ZStack(alignment: .topLeading) {
                Capsule().fill(colors.border).frame(height: 3).offset(y: 9)
                Capsule().fill(colors.action)
                    .frame(width: max(3, abs(x(at, w) - x(from, w))), height: 3)
                    .offset(x: min(x(at, w), x(from, w)), y: 9)
                ForEach([100, 500, 750], id: \.self) { h in
                    VStack(spacing: 4) {
                        Rectangle().fill(colors.textTertiary).frame(width: 1, height: 6)
                        Text("\(h)").font(mono()).foregroundStyle(colors.textTertiary)
                    }
                    .fixedSize()
                    .position(x: x(h, w), y: 38)
                    .offset(y: 0)
                }
                Circle().fill(colors.action).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(colors.backgroundSecondary, lineWidth: 2))
                    .position(x: x(at, w), y: 10.5)
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : curve.speed(1 / slow), value: markerMoved)
        }
        .frame(height: 58)
        .accessibilityHidden(true)
    }

    private func buttons(_ o: HomeProtoOutcome) -> some View {
        let layout = ax ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if let secondary = o.secondary {
                Button { advance(accept: false) } label: {
                    Text(secondary).font(.body.weight(.semibold)).foregroundStyle(colors.action)
                        .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
                        .background(Capsule().fill(colors.actionSurface))
                }
                .buttonStyle(.lhPressable)
            }
            Button { advance(accept: true) } label: {
                Text(o.primary).font(.body.weight(.semibold)).foregroundStyle(colors.onAction)
                    .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
                    .background(Capsule().fill(colors.action))
            }
            .buttonStyle(.lhPressable)
        }
    }

    private func advance(accept: Bool) {
        forward = true
        if accept, case .propose(let to) = outcome.kind { decisions[rental.id] = to }
        let last = index == count - 1
        go {
            if last { phase = .summary } else { index += 1; phase = .question; picked = nil }
            resetReveal()
        }
    }

    private func resetReveal() { bars = false; markerMoved = false; lineShown = false; buttonsShown = false }

    /// 0 tiles out · 80 bars · 160 marker + house · 260 line · 300 buttons (all x `slow`).
    private func runResult() async {
        func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * slow * 1e9)) }
        resetReveal()
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { bars = true; markerMoved = true; lineShown = true; buttonsShown = true }
            return
        }
        await wait(0.08)
        withAnimation(curve.speed(1 / slow)) { bars = true }
        await wait(0.08)
        withAnimation(curve.speed(1 / slow)) { markerMoved = true }
        await wait(0.10)
        withAnimation(.easeOut(duration: 0.18 * slow)) { lineShown = true }
        await wait(0.04)
        withAnimation(.easeOut(duration: 0.12 * slow)) { buttonsShown = true }
    }

    // MARK: Step 3

    private var summary: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Checked", tableName: "HomeProto")
                    .font(LHFont.fraunces(.largeTitle)).foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(seed.rentals.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 84) }
                        summaryRow(r).modifier(Rise(delay: Double(i) * 0.04 * slow, reduce: reduceMotion))
                    }
                }
                .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Your CPA decides what these numbers mean.", tableName: "HomeProto")
                    .font(.footnote).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {} label: {
                    Text("Done", tableName: "HomeProto").font(.body.weight(.semibold)).foregroundStyle(colors.onAction)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(colors.action))
                }
                .buttonStyle(.lhPressable)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }
    }

    private func summaryRow(_ r: HomeProtoRental) -> some View {
        let o = HomeProtoOutcome.make(r, answers[r.id] ?? .other)
        let newTarget = decisions[r.id]
        let kf: HouseKeyframe = {
            guard case .own(let t) = r.target else { return .k00_lot }
            return HomeProtoStage.keyframe(hours: HomeProtoStage.hours(for: r, target: newTarget ?? t))
        }()
        var oldT = 0
        if case .own(let t) = r.target { oldT = t }
        return HomeProtoListRow(keyframe: kf, name: r.name, plan: newTarget != nil ? o.summary : seed.planLine(r).components(separatedBy: " · ").first.map { _ in o.summary } ?? o.summary) {
            if let newTarget {
                HStack(spacing: 6) {
                    Text("\(oldT)").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(colors.textSecondary)
                    LucideIcon(image: Lucide.arrowRight, size: 13).foregroundStyle(colors.action)
                    Text("\(newTarget)").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(colors.action)
                }
                .monospacedDigit()
            } else if r.isRecord {
                Text("Record only", tableName: "HomeProto").font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.textPrimary)
            } else {
                Text("Keeps \(oldT)", tableName: "HomeProto").font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.textPrimary)
            }
        } tag: {
            if newTarget != nil { Circle().fill(colors.action).frame(width: 6, height: 6) }
        }
    }

    // MARK: Scripted tour (-LHHomeAutoplay)

    private func autoplay() async {
        guard config.autoplay else { return }
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
        await pause(1.6)
        for i in 0..<count {
            if phase == .question { choose(picked == nil ? (answers[seed.rentals[index].id] ?? .other) : picked!) }
            await pause(i == 0 ? 3.6 : 2.2)
            advance(accept: true)
            await pause(1.4)
        }
        await pause(2.5)
    }
}

/// The summary rows rise 8pt as they arrive (staggered 40ms, ease-out).
private struct Rise: ViewModifier {
    let delay: Double
    let reduce: Bool
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 8)
            .onAppear { withAnimation(.easeOut(duration: 0.24).delay(delay)) { shown = true } }
    }
}
#endif
