import SwiftUI

#if DEBUG
// MARK: - Check my goal, visual: people rows, the ruler, "no record" for what we don't know

struct StdGoalCheckStart: Identifiable {
    enum Step { case question, result, summary }
    enum Answer: CaseIterable { case me, spouse, cleaner, notSure }
    let id = UUID()
    var step: Step
    var answer: Answer = .cleaner
}

struct StdGoalCheckSheet: View {
    let seed: StdSeed
    let start: StdGoalCheckStart
    var demo = false
    let onClose: () -> Void

    @State private var step: StdGoalCheckStart.Step
    @State private var answer: StdGoalCheckStart.Answer?
    @State private var marker: Double = 100
    @State private var switched = false
    @State private var shownRows = 0
    @State private var showWhy = false
    /// `-LHWhyCase 500|100|750`: which recommendation the result shows (750 = a real estate pro household).
    private static let whyCase: StdWhyCase = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-LHWhyCase"), a.indices.contains(i + 1) else { return .t500 }
        return StdWhyCase(rawValue: a[i + 1]) ?? .t500
    }()
    private static let openWhy = ProcessInfo.processInfo.arguments.contains("-LHWhyOpen")
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(seed: StdSeed, start: StdGoalCheckStart, demo: Bool = false, onClose: @escaping () -> Void) {
        self.seed = seed
        self.start = start
        self.demo = demo
        self.onClose = onClose
        _step = State(initialValue: start.step)
        let why = Self.whyCase
        let answer: StdGoalCheckStart.Answer = why == .t500 ? start.answer : .me
        _answer = State(initialValue: start.step == .question ? nil : answer)
        _marker = State(initialValue: start.step == .question ? 100 : Double(why == .t500 && answer == .cleaner ? 500 : why.target))
        _showWhy = State(initialValue: Self.openWhy)
        _switched = State(initialValue: start.step == .summary)
        _shownRows = State(initialValue: start.step == .summary ? 99 : 0)
    }

    private var rental: HomeProtoRental { seed.rentals.rentals.first { $0.shortStay } ?? seed.rentals.rentals[0] }
    private var count: Int { seed.rentals.rentals.count }
    private var target: Int { if case .own(let t) = rental.target { return t }; return 500 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case .question, .result: rentalStep
                        case .summary: summary
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
                // The CTA is pinned under the content; the content scrolls above it (AX3).
                // Content scrolls under a material bar; no canvas-coloured block is painted over it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if step != .question {
                        footer.frame(maxWidth: .infinity).background(.bar)
                    }
                }
                .onAppear {
                    guard let target = StdProtoLaunch.current?.scroll else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if target == "chart" { proxy.scrollTo("chart", anchor: .top) } else { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
            }
        }
        .background(colors.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: answer)
        .task { await runDemo() }
        .sheet(isPresented: $showWhy) {
            StdWhyTargetSheet(rentalName: rental.name, recommended: Self.whyCase.target == 500 && answer != .cleaner ? 100 : Self.whyCase.target,
                              why: answer == .cleaner && Self.whyCase == .t500 ? .t500 : Self.whyCase,
                              onChange: { showWhy = false; withAnimation(StdMotion.flow) { step = .question; answer = nil; marker = 100 } },
                              onClose: { showWhy = false })
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Top bar: back, 3pt progress, close

    private var progress: Double {
        switch step {
        case .question: return 0.5 / Double(count)
        case .result: return 1 / Double(count)
        case .summary: return 1
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { withAnimation(StdMotion.flow) { step = .question; answer = nil; marker = 100 } } label: { Image(systemName: "chevron.left") }
                .buttonStyle(StdButtonStyle(.icon)).accessibilityLabel(L("Back"))
                .opacity(step == .question ? 0 : 1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.border)
                    Capsule().fill(colors.action).frame(width: g.size.width * progress)
                }
            }
            .frame(height: 3)
            .animation(StdMotion.flow, value: progress)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(StdButtonStyle(.icon)).accessibilityLabel(L("Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: One rental: question, then the picture

    @ScaledMetric(relativeTo: .body) private var iconBox: CGFloat = 36

    private var rentalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if step == .question && !typeSize.isAccessibilitySize {
                rentalBand
            } else {
                Text(typeSize.isAccessibilitySize ? L("Rental 1 of \(count)") : L("Rental 1 of \(count) · \(target)-hour target"))
                    .font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                    .foregroundStyle(colors.draftingInk)
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                    if !typeSize.isAccessibilitySize { HomeProtoArt(size: 56, keyframe: HomeProtoStage.keyframe(for: rental)) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rental.name).font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                        Text(L("\(Int(rental.hours)) of \(target) hours")).font(.subheadline).monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }
            // Large text: once answered, the question gives its room to the answer and the picture.
            if step == .question || !typeSize.isAccessibilitySize {
                Text(L("Who does most of the hands-on work here?"))
                    .font(.headline).foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            peopleRows
            if step == .result {
                VStack(alignment: .leading, spacing: 8) {
                    comparison.id("chart")
                    if answer == .cleaner { StdCPAFootnote() }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)), removal: .opacity))
            }
        }
    }

    /// Question state (critique #9): this rental's house on a 120pt blueprint band.
    private var rentalBand: some View {
        ZStack(alignment: .topLeading) {
            HouseBlueprintPaper()
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Rental 1 of \(count)"))
                        .font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                        .foregroundStyle(HouseTokens.drafting)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(rental.name).font(.title2.weight(.semibold)).foregroundStyle(HouseTokens.onHeroPrimary)
                    Text(L("\(Int(rental.hours)) of \(target) hours")).font(.subheadline).monospacedDigit()
                        .foregroundStyle(HouseTokens.onHeroSecondary).lineLimit(1)
                    Text(L("\(target)-hour target")).font(.subheadline)
                        .foregroundStyle(HouseTokens.onHeroSecondary).lineLimit(1)
                }
                .padding(16)
                Spacer(minLength: 0)
                let keyframe = HomeProtoStage.keyframe(for: rental)
                ZStack {
                    Image(decorative: keyframe.builtImageName).resizable().interpolation(.high).scaledToFit()
                    HouseLineworkImage(name: keyframe.linesImageName).foregroundStyle(HouseTokens.drafting)
                }
                .frame(width: 112, height: 112)
                .padding(.trailing, 12).padding(.bottom, -4)
            }
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func words(_ a: StdGoalCheckStart.Answer) -> (String, String) {
        switch a {
        case .me: return (L("Me"), "person.fill")
        case .spouse: return (L("Me and my spouse"), "person.2.fill")
        case .cleaner: return (L("A cleaner or manager"), "wrench.and.screwdriver.fill")
        case .notSure: return (L("Not sure"), "questionmark")
        }
    }

    /// Apple Settings selection: SF glyph leading, trailing checkmark in action, row hairline turns action (tileFocus).
    private var peopleRows: some View {
        let shown: [StdGoalCheckStart.Answer] = step == .question ? StdGoalCheckStart.Answer.allCases : (answer.map { [$0] } ?? [])
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element) { i, a in
                if i > 0 { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 64) }
                let w = words(a)
                let selected = answer == a
                Button { pick(a) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        // A fixed scaled box: the glyph sits inside it, the label wraps after it.
                        Image(systemName: w.1).resizable().scaledToFit()
                            .frame(width: iconBox * 0.55, height: iconBox * 0.55)
                            .foregroundStyle(a == .spouse ? colors.rose : colors.action)
                            .frame(width: iconBox, height: iconBox)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(a == .spouse ? colors.roseWash : colors.actionSurface))
                            .padding(.top, 10)
                        Text(w.0).font(.body).foregroundStyle(colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: iconBox + 20, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(colors.action)
                            .frame(width: 44, height: 44)
                            .opacity(selected ? 1 : 0)
                    }
                    .padding(.leading, 16).padding(.trailing, 6)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StdPressStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
        .stdMeasure("card.people")
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(answer == nil ? colors.border : colors.action, lineWidth: answer == nil ? 0.5 : 1.5)
                .animation(StdMotion.quick, value: answer)
        }
    }

    private func pick(_ a: StdGoalCheckStart.Answer) {
        guard step == .question else {
            withAnimation(StdMotion.flow) { step = .question; answer = nil; marker = 100 }
            return
        }
        StdMotionLog.mark("tileFocus")
        withAnimation(StdMotion.quick) { answer = a }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            StdMotionLog.mark("sheetUnfold")
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.flow) { step = .result }
            guard a == .cleaner, !reduceMotion else { if a == .cleaner { marker = 500 }; return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            StdMotionLog.mark("ringProgress.marker")
            withAnimation(StdMotion.ringProgress) { marker = 500 }
        }
    }

    // MARK: The picture: who puts in the hours, and the ruler

    private var otherLabel: String {
        switch answer {
        case .spouse: return L("Your spouse")
        default: return L("Cleaner")
        }
    }

    /// One compact card: the target ruler with your hours on it, then who else works here.
    private var comparison: some View {
        VStack(alignment: .leading, spacing: typeSize >= .xxLarge ? 5 : 8) {
            // Verdict first (critique #5): the sentence is the card's headline, the track is the evidence.
            Text(resultLine)
                .font(.headline).foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ruler
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 16))) {
                hoursChip(L("You"), StdFormat.hours(rental.hours), ink: colors.positive)
                if answer == .cleaner || answer == .spouse {
                    hoursChip(otherLabel, L("No record"), ink: nil)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
        }
        // Large text: 12pt padding keeps the card inside D6 (≤ 20% of the screen).
        .padding(typeSize >= .xxLarge ? 10 : 16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
        .stdMeasure("card.comparison")
        .accessibilityElement(children: .combine)
    }

    /// Your hours come from records; anyone else's are "No record", never a guess.
    private func hoursChip(_ who: String, _ value: String, ink: Color?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(ink ?? Color.clear)
                .overlay(Circle().strokeBorder(ink == nil ? colors.textTertiary : Color.clear, lineWidth: 1.5))
                .frame(width: 10, height: 10)
            // One Text so it wraps between words, never inside one.
            (Text(who).fontWeight(.semibold).foregroundColor(colors.textPrimary)
             + Text(verbatim: " ")
             + Text(value).foregroundColor(ink == nil ? colors.textSecondary : colors.textPrimary))
                .font(.subheadline).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultLine: String {
        if Self.whyCase == .t750 { return L("Real estate is your main job, so the 750 fits.") }
        switch answer {
        case .cleaner: return L("A cleaner does more here, so the 500-hour test fits.")
        case .notSure: return L("No change for now.")
        default: return L("You do most of the work here, so 100 still fits.")
        }
    }

    /// 0 … 750 with ticks at 100 / 500 / 750; your hours fill from 0; the target marker rides 100 → 500.
    private var ruler: some View {
        VStack(alignment: .leading, spacing: 4) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())) {
                Text(L("Target")).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                    .foregroundStyle(colors.draftingInk)
                if !typeSize.isAccessibilitySize { Spacer() }
                // Progressive disclosure: the target's reasons live one tap away, not in more body text.
                Button(L("Why \(Int(marker.rounded()))?")) { StdMotionLog.mark("sheetUnfold.why"); showWhy = true }
                    .buttonStyle(StdButtonStyle(.tertiary))
                    .padding(.vertical, -12)
                    .contentTransition(.numericText(value: marker))
                    .accessibilityHint(L("Shows how the three targets compare for you"))
            }
            // Read-only: a printed ruler. The target is a drafting tick with a pointer, not a knob.
            GeometryReader { g in
                let w = g.size.width
                let x: (Double) -> CGFloat = { CGFloat($0 / 750) * (w - 16) + 8 }
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(colors.border).frame(width: w - 16, height: 2).offset(x: 8, y: 9)
                    Rectangle().fill(colors.positive).frame(width: max(3, x(rental.hours) - 8), height: 4).offset(x: 8, y: 8)
                    ForEach([100.0, 500, 750], id: \.self) { t in
                        Rectangle().fill(colors.textTertiary).frame(width: 1, height: 6).offset(x: x(t), y: 11)
                        if !typeSize.isAccessibilitySize {
                            Text(verbatim: "\(Int(t))").font(StdFont.drafting).foregroundStyle(colors.textSecondary)
                                .fixedSize()
                                .frame(width: 40).offset(x: x(t) - 20, y: 18)
                        }
                    }
                    StdPointer().fill(colors.action).frame(width: 12, height: 8).offset(x: x(marker) - 6, y: -1)
                    Rectangle().fill(colors.action).frame(width: 2, height: 12).offset(x: x(marker) - 1, y: 5)
                }
            }
            .frame(height: typeSize.isAccessibilitySize ? 20 : 32)
            .accessibilityHidden(true)
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("\(count) rentals checked")).font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(switched ? L("\(rental.name) now tracks 500.") : L("No targets changed."))
                    .font(.subheadline).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(seed.rentals.rentals.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 64) }
                    let row = summaryWords(r)
                    StdBrowseRow(title: r.name, meta: row.meta, value: row.value, valueInk: row.changed ? colors.action : colors.textSecondary,
                                 chevron: false, metaLines: 3, stackValue: typeSize >= .xxLarge) {
                        HomeProtoArt(size: 36, keyframe: HomeProtoStage.keyframe(for: r))
                    }
                    .padding(.horizontal, 16).padding(.vertical, typeSize >= .xxLarge ? 6 : 8)
                    .opacity(i < shownRows ? 1 : 0)
                    .offset(y: i < shownRows || reduceMotion ? 0 : 8)
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
            .stdMeasure("card.summary")
            StdCPAFootnote()
        }
        .onAppear {
            guard shownRows == 0 else { return }
            for i in 0..<seed.rentals.rentals.count {
                withAnimation(StdMotion.reveal.delay(Double(min(i, 3)) * 0.03)) { shownRows = i + 1 }
            }
        }
    }

    private func summaryWords(_ r: HomeProtoRental) -> (meta: String, value: String, changed: Bool) {
        if r.id == rental.id {
            return switched ? (L("A cleaner does more here"), L("\(target) → 500"), true)
                            : (L("You do most of the work"), L("\(target) hours"), false)
        }
        switch r.target {
        case .record(let reason): return (reason.hasPrefix("Long") ? L("Long-stay rental: hours kept, no target") : L("A manager does most"), L("Record only"), false)
        case .own(let t): return (L("No change"), L("\(t) hours"), false)
        case .counts: return (L("No change"), L("Counts toward \(seed.rentals.sharedTarget ?? 750)"), false)
        }
    }

    // MARK: Footer: one primary, at most one tertiary

    @ViewBuilder private var footer: some View {
        VStack(spacing: 4) {
            switch step {
            case .question:
                EmptyView()
            case .result:
                if answer == .cleaner {
                    Button(L("Switch to \(500)")) { finish(switching: true) }.buttonStyle(StdButtonStyle(.primary))
                    Button(L("Keep \(target)")) { finish(switching: false) }.buttonStyle(StdButtonStyle(.tertiary))
                } else {
                    Button(L("Next")) { finish(switching: false) }.buttonStyle(StdButtonStyle(.primary))
                }
            case .summary:
                Button(L("Done"), action: onClose).buttonStyle(StdButtonStyle(.primary))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, step == .question ? 0 : 12)
        .padding(.bottom, 16)
    }

    private func finish(switching: Bool) {
        switched = switching
        shownRows = 0
        withAnimation(StdMotion.flow) { step = .summary }
    }

    private func runDemo() async {
        if ProcessInfo.processInfo.arguments.contains("-LHWhyDemo") {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            StdMotionLog.mark("sheetUnfold.why")
            showWhy = true
            return
        }
        guard demo else { return }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        pick(.cleaner)
        try? await Task.sleep(nanoseconds: 3_200_000_000)
        finish(switching: true)
    }
}
#endif

#if DEBUG
/// A small downward pointer for the read-only ruler.
struct StdPointer: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
#endif

#if DEBUG
// MARK: - Why this target? (Brian: "I don't know why 500 was recommended")

enum StdWhyCase: String {
    case t500 = "500", t100 = "100", t750 = "750"
    var target: Int { Int(rawValue) ?? 500 }
}

/// A medium sheet: the three targets as rows, each with its plain meaning and a ✓ / ✕ for this
/// owner with the reason from their answers; the recommended row is highlighted. Then the one
/// fact that decided it, with a way to change that answer, and the CPA line.
struct StdWhyTargetSheet: View {
    let rentalName: String
    let recommended: Int
    let why: StdWhyCase
    let onChange: () -> Void
    let onClose: () -> Void
    @State private var shown = 0
    @State private var emphasis = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    private struct Row { let target: Int; let meaning: String; let fits: Bool; let reason: String }

    private var rows: [Row] {
        let cleaner = why == .t500
        let pro = why == .t750
        return [
            Row(target: 100, meaning: typeSize.isAccessibilitySize ? L("100 hours, more than anyone here")
                                                                  : L("100 hours, and more than anyone else here"),
                fits: !cleaner, reason: cleaner ? L("A cleaner does more hours here") : L("You do most of the work here")),
            Row(target: 500, meaning: L("500 hours, no comparison"),
                fits: true, reason: L("Doesn't depend on who else works here")),
            Row(target: 750, meaning: typeSize.isAccessibilitySize ? L("750 hours, and more than half your working time")
                                                                  : L("750 hours, and more than half your working time, as a real estate pro"),
                fits: pro, reason: pro ? L("You said real estate is your main job") : L("Needs real estate as your main job")),
        ]
    }

    private var fact: String {
        switch why {
        case .t500: return L("You said a cleaner does most of the hands-on work at \(rentalName).")
        case .t100: return L("You said you do most of the hands-on work at \(rentalName).")
        case .t750: return L("You said real estate is your main job.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StdSheetHeader(eyebrow: rentalName, title: L("Why \(recommended)?"), onClose: onClose)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 16) }
                        row(r)
                            .opacity(i < shown ? 1 : 0)
                            .offset(y: i < shown || reduceMotion ? 0 : 6)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
                VStack(alignment: .leading, spacing: 4) {
                    StdSectionHeader(title: L("How we decided"))
                    Text(fact).font(.subheadline).foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Change this answer"), action: onChange)
                        .buttonStyle(StdButtonStyle(.tertiary))
                        .padding(.leading, -4)
                }
                StdCPAFootnote()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            // Clear of the sheet's bottom corner curve when scrolled to the end.
            .padding(.bottom, 44)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(colors.background.ignoresSafeArea())
        .task {
            // sheetUnfold: rows fade up 30ms apart, then the recommended row's highlight arrives.
            for i in 0..<3 {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.reveal.delay(Double(i) * 0.03)) { shown = i + 1 }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.flow) { emphasis = true }
        }
        .sensoryFeedback(.selection, trigger: emphasis)
    }

    private func row(_ r: Row) -> some View {
        let isPick = r.target == recommended
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            // Large text: the meaning line already starts with the number, so the big numeral goes.
            if !typeSize.isAccessibilitySize {
                Text(verbatim: "\(r.target)")
                    .font(.title3.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(isPick ? colors.action : colors.textPrimary)
                    .frame(minWidth: 48, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.meaning).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // The mark sits inline so the reason wraps at full width (large text stays compact).
                (Text(Image(systemName: r.fits ? "checkmark.circle.fill" : "xmark.circle.fill"))
                    .foregroundColor(r.fits ? colors.positive : colors.textSecondary)
                 + Text(verbatim: " ") + Text(r.reason))
                    .font(.subheadline).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(r.fits ? L("Fits: \(r.reason)") : L("Doesn't fit: \(r.reason)"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, typeSize.isAccessibilitySize ? 4 : 6)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.actionSurface)
                .opacity(isPick && emphasis ? 1 : 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.action, lineWidth: 1.5)
                .opacity(isPick && emphasis ? 1 : 0)
        }
        .scaleEffect(isPick && !emphasis && !reduceMotion ? 0.985 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPick ? .isSelected : [])
    }
}
#endif
