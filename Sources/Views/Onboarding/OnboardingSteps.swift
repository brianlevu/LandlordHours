import SwiftUI

// MARK: - Shared scaffold (standard §1.24): step title, scrolling body, one pinned primary
//
// The plain canvas, gutter 20. Title SF `.title1.semibold` (`.title.weight(.semibold)`), an
// optional `.body` subtitle, the content, an optional note at the end of the scroll. The actions
// are pinned in a `safeAreaInset`: one `LHButton.primary`, at most one `.tertiary` (the step's
// skip). Words scrolling under the actions fade into the canvas. No Dynamic Type clamps.

struct OnbStepScaffold<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String? = nil
    var titleIdentifier: String? = nil
    /// A short note under the content (the CPA line, trust lines, the spouse rule).
    var note: AnyView? = nil
    /// Scrolls this id into view whenever it changes (the property step keeps its field above
    /// the keyboard).
    var scrollTarget: String? = nil
    /// False for the question steps (a tap answers): nothing is pinned.
    var showsActions = true
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .modifier(OptionalIdentifier(identifier: titleIdentifier))
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                            .padding(.top, 8)
                    }
                    content.padding(.top, LHMetrics.sectionGap)
                    if let note { note.padding(.top, 16) }
                }
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, LHMetrics.sectionGap)
                .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(OnbDebugLaunch.scrollToBottom ? .bottom : .top)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(AppAnimation.standard) { proxy.scrollTo(target, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsActions {
                    VStack(spacing: 4) { actions }
                        .padding(.horizontal, LHMetrics.gutter)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: LHMetrics.readingColumn)
                        .frame(maxWidth: .infinity)
                        .background(alignment: .top) {
                            LinearGradient(stops: [.init(color: colors.background.opacity(0), location: 0),
                                                   .init(color: colors.background, location: typeSize.isAccessibilitySize ? 0.2 : 0.3)],
                                           startPoint: .top, endPoint: .bottom)
                                .padding(.top, -24)
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                        }
                }
            }
        }
    }
}

/// A `.footnote` note in `textSecondary`, optionally with a leading SF glyph.
struct OnbNote: View {
    var text: String
    var symbol: String? = nil
    var identifier: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(colors.informational)
                    .accessibilityHidden(true)
            }
            Text(text)
                .foregroundStyle(colors.textSecondary)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

// MARK: - 1 · Goal: two plain questions, then a suggested target

struct OnbGoalStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            switch flow.goalPhase {
            case .rental: rentalQuestion
            case .pro: proQuestion
            case .target: targetRows
            }
        }
        .transition(OnbMotion.stepTransition(forward: flow.forward, reduce: reduce))
        .id(flow.goalPhase)
    }

    // MARK: Q1 · What do you rent out?

    private var rentalQuestion: some View {
        OnbStepScaffold(title: String(localized: "What do you rent out?", table: "ConversionPath"), showsActions: false) {
            OnbOptionGroup(hasSelection: flow.rental != nil) {
                OnbOptionRow(symbol: "calendar", title: String(localized: "Short stays", table: "ConversionPath"),
                             meta: String(localized: "A week or less, on average", table: "ConversionPath"),
                             selected: flow.rental == .shortStays) { flow.answerRental(.shortStays, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("rental-short")
                LHDivider(leadingInset: LHRow.browseDividerInset)
                OnbOptionRow(symbol: "key", title: String(localized: "Long-term", table: "ConversionPath"),
                             meta: String(localized: "Leases of a month or more", table: "ConversionPath"),
                             selected: flow.rental == .longTerm) { flow.answerRental(.longTerm, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("rental-long")
                LHDivider(leadingInset: LHRow.browseDividerInset)
                OnbOptionRow(symbol: "square.stack", title: String(localized: "Both", table: "ConversionPath"),
                             meta: String(localized: "Some of each", table: "ConversionPath"),
                             selected: flow.rental == .both) { flow.answerRental(.both, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("rental-both")
            }
        } actions: {
            EmptyView()
        }
    }

    // MARK: Q2 · Do you or your spouse do real estate as a main job?

    private var proQuestion: some View {
        OnbStepScaffold(title: String(localized: "Is real estate your main job, or your spouse’s?", table: "ConversionPath"),
                        subtitle: String(localized: "Main job means most of your working hours, all year.", table: "ConversionPath"),
                        showsActions: false) {
            OnbOptionGroup(hasSelection: flow.pro != nil) {
                OnbOptionRow(symbol: "person", title: String(localized: "Me", table: "ConversionPath"),
                             meta: String(localized: "It’s my main job", table: "ConversionPath"),
                             selected: flow.pro == .me) { flow.answerPro(.me, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("pro-me")
                LHDivider(leadingInset: LHRow.browseDividerInset)
                OnbOptionRow(symbol: "person.2", title: String(localized: "My spouse", table: "ConversionPath"),
                             meta: String(localized: "It’s my spouse’s main job", table: "ConversionPath"),
                             selected: flow.pro == .spouse) { flow.answerPro(.spouse, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("pro-spouse")
                LHDivider(leadingInset: LHRow.browseDividerInset)
                OnbOptionRow(symbol: "minus.circle", title: String(localized: "No", table: "ConversionPath"),
                             meta: String(localized: "Neither of us", table: "ConversionPath"),
                             selected: flow.pro == .nobody) { flow.answerPro(.nobody, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("pro-none")
            }
        } actions: {
            EmptyView()
        }
    }

    // MARK: The suggested target (first, already selected), the others, then the record

    private var targetRows: some View {
        OnbStepScaffold(title: String(localized: "Based on your answers, start here", table: "ConversionPath"), note: AnyView(note)) {
            OnbOptionGroup(hasSelection: flow.goal != nil) {
                if let suggestion = flow.suggestion {
                    ForEach(Array(suggestion.ordered.enumerated()), id: \.element) { index, goal in
                        if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                        OnbOptionRow(symbol: OnbGoalCopy.symbol(goal),
                                     title: OnbGoalCopy.rowTitle(goal),
                                     meta: index == 0 ? String(localized: "Suggested for you", table: "ConversionPath")
                                                      : OnbGoalCopy.rowMeta(goal, pro: flow.pro),
                                     selected: flow.goal == goal) {
                            withAnimation(OnbMotion.flow(reduce)) { flow.goal = goal }
                        }
                        .accessibilityIdentifier(Self.identifier(goal))
                    }
                }
            }
        } actions: {
            Button((flow.goal ?? .reps750).callToAction) { flow.confirmGoal(OnbMotion.morph(reduce)) }
                .buttonStyle(LHButton.primary)
                .disabled(flow.goal == nil)
                .contentTransition(.opacity)
                .accessibilityIdentifier("onb-primary")
        }
    }

    /// What the selected goal counts, then "You can change this later." and the CPA line.
    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let goal = flow.goal {
                OnbNote(text: OnbGoalCopy.detail(goal, pro: flow.pro, isSuggested: goal == flow.suggestion?.suggested, rental: flow.rental),
                        identifier: "goal-detail")
                    .contentTransition(.opacity)
                    .animation(AppAnimation.quick, value: goal)
            }
            OnbNote(text: String(localized: "You can change this later.", table: "ConversionPath"))
            LHFootnote.cpa
        }
    }

    static func identifier(_ goal: OnbGoal) -> String {
        switch goal {
        case .reps750: return "goal-750"
        case .mp500: return "goal-500"
        case .mp100: return "goal-100"
        case .record: return "goal-record"
        }
    }
}

// MARK: - 2 · A source (today: the calendar). One reusable step; its rows and trust lines are data.

/// One capture source the onboarding asks about. A later version adds email or receipts as more
/// values; the step's layout does not change.
struct OnbSource {
    struct SampleRow {
        var hours: Double
        var category: ActivityCategory
        var when: String
        var title: String
    }

    struct TrustLine {
        var symbol: String
        var text: String
    }

    var id: String
    var title: String
    var subtitle: String
    var rows: [SampleRow]
    var trust: [TrustLine]
    var primary: String
    var secondary: String

    /// The calendar. Row categories are what the shipped classifier proposes for those titles
    /// (`ClassifierKeywords`: plumber → Repairs, showing → Leasing, inspect → Management).
    static let calendar = OnbSource(
        id: "calendar",
        title: String(localized: "Your calendar already has some of your hours.", table: "ConversionPath"),
        subtitle: String(localized: "We look back 90 days for things like a plumber visit or a showing. Then we ask you.", table: "ConversionPath"),
        rows: [
            SampleRow(hours: 2, category: .repairs, when: String(localized: "Calendar · Wed 9–11", table: "ConversionPath"), title: String(localized: "Plumber", table: "ConversionPath")),
            SampleRow(hours: 1, category: .leasing, when: String(localized: "Calendar · Sat 10–11", table: "ConversionPath"), title: String(localized: "Showing", table: "ConversionPath")),
            SampleRow(hours: 3, category: .management, when: String(localized: "Calendar · Sun 11–2", table: "ConversionPath"), title: String(localized: "Turnover clean", table: "ConversionPath")),
        ],
        trust: [
            TrustLine(symbol: "eye", text: String(localized: "We read event titles and times.", table: "ConversionPath")),
            TrustLine(symbol: "hand.raised", text: String(localized: "We never send them anywhere or log anything without you.", table: "ConversionPath")),
        ],
        primary: String(localized: "Look at my calendar", table: "ConversionPath"),
        secondary: String(localized: "Not now", table: "ConversionPath")
    )
}

struct OnbSourceStep: View {
    @Bindable var flow: OnbFlow
    var source: OnbSource = .calendar
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        OnbStepScaffold(title: source.title, subtitle: source.subtitle, note: AnyView(trust)) {
            LHRowGroup {
                ForEach(Array(source.rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    LHRow.Browse(title: row.title, meta: row.when, value: LHFormat.hours(row.hours), showsChevron: false) {
                        CategoryToolTile(category: row.category, size: 36)
                    }
                    .opacity(flow.calendarRows > i ? 1 : 0)
                    .offset(y: flow.calendarRows > i || reduce ? 0 : 6)
                    .accessibilityLabel(String(localized: "Example: \(row.title), \(LHFormat.spokenHours(row.hours)), \(row.category.inboxLabel)", table: "ConversionPath"))
                    .accessibilityHint(String(localized: "Suggestion, not saved", table: "ConversionPath"))
                }
            }
        } actions: {
            Button(source.primary) { Task { await flow.askCalendar(OnbMotion.morph(reduce)) } }
                .buttonStyle(LHButton.primary)
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-primary")
            Button(source.secondary) { flow.calendarNotNow(OnbMotion.morph(reduce)) }
                .buttonStyle(LHButton.tertiary)
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-link")
        }
        .task {
            // The sample rows appear one by one (each bound to `calendarRows`).
            let total = source.rows.count
            guard flow.calendarRows < total else { return }
            if !reduce { try? await Task.sleep(for: .milliseconds(300)) }
            for i in (flow.calendarRows + 1)...total {
                withAnimation(reduce ? AppAnimation.quick : AppAnimation.reveal) { flow.calendarRows = i }
                if !reduce { try? await Task.sleep(for: .milliseconds(320)) }
            }
        }
    }

    /// Trust at the ask: what we read, what we never do, and that nothing counts unconfirmed.
    private var trust: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(source.trust.enumerated()), id: \.offset) { _, line in
                OnbNote(text: line.text, symbol: line.symbol)
            }
            OnbNote(text: String(localized: "common.nothingCountsUntilConfirm", defaultValue: "Nothing counts until you confirm it."),
                    symbol: "checkmark.circle")
        }
    }
}

// MARK: - 3 · Who does the work

struct OnbWhoStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        OnbStepScaffold(title: String(localized: "Who puts in the hours?", table: "ConversionPath"),
                        note: flow.who == .both ? AnyView(OnbNote(text: OnbGoal.spouseNote(for: flow.goal), symbol: "person.2", identifier: "who-note")
                            .transition(.opacity)) : nil) {
            OnbOptionGroup(hasSelection: true) {
                OnbOptionRow(symbol: "person", title: String(localized: "Just me", table: "ConversionPath"),
                             meta: String(localized: "I handle the rentals", table: "ConversionPath"),
                             selected: flow.who == .me) { pick(.me) }
                    .accessibilityIdentifier("who-me")
                LHDivider(leadingInset: LHRow.browseDividerInset)
                OnbOptionRow(symbol: "person.2", title: String(localized: "My spouse and me", table: "ConversionPath"),
                             meta: String(localized: "We both do", table: "ConversionPath"),
                             selected: flow.who == .both) { pick(.both) }
                    .accessibilityIdentifier("who-both")
            }
        } actions: {
            Button(String(localized: "Continue", table: "ConversionPath")) { flow.confirmWho(OnbMotion.morph(reduce)) }
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("onb-primary")
        }
    }

    private func pick(_ w: OnbWho) { withAnimation(OnbMotion.flow(reduce)) { flow.who = w } }
}

// MARK: - 4 · First rental (the one typed field) with the 120pt house thumbnail (§H.5)

struct OnbPropertyStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var savedTick = 0

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        OnbStepScaffold(title: String(localized: "Add your first rental.", table: "ConversionPath"),
                        subtitle: String(localized: "Every hour you log starts with a place.", table: "ConversionPath"),
                        note: AnyView(OnbNote(text: String(localized: "A nickname is fine. The rest comes later.", table: "ConversionPath"))),
                        scrollTarget: flow.addressOpen ? "property-address-row" : nil) {
            VStack(alignment: .leading, spacing: 16) {
                if let hint = flow.propertyHint {
                    Label(hint, systemImage: "tray.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                        .contentTransition(.numericText(value: Double(flow.found.count)))
                        .transition(.opacity)
                        .accessibilityIdentifier("property-hint")
                }
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    // The house the year starts from; it lights when the rental is saved.
                    LHThumb.large(.started, lit: flow.stakeDropped)
                        .accessibilityIdentifier("property-thumb")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Rental name", table: "ConversionPath"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                            .accessibilityHidden(true)
                        LHField(flow.firstPropertyType == .str ? String(localized: "Tahoe cabin", table: "ConversionPath")
                                                               : String(localized: "Oak Street duplex", table: "ConversionPath"),
                                text: $flow.name,
                                accessibilityLabel: String(localized: "Rental name", table: "ConversionPath"),
                                identifier: "property-name")
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    }
                }
                if flow.addressOpen {
                    LHField(String(localized: "Street address (optional)", table: "ConversionPath"), text: $flow.address,
                            accessibilityLabel: String(localized: "Street address, optional", table: "ConversionPath"),
                            identifier: "property-address")
                        .textContentType(.fullStreetAddress)
                        .transition(.opacity)
                        .id("property-address-row")
                } else {
                    Button {
                        withAnimation(OnbMotion.flow(reduce)) { flow.addressOpen = true }
                    } label: {
                        Label(String(localized: "Add address", table: "ConversionPath"), systemImage: "plus")
                    }
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("property-add-address")
                }
                if flow.rental == .both { kindPicker(colors) }
            }
        } actions: {
            Button {
                save()
            } label: {
                if flow.stakeDropped {
                    Label(String(localized: "Saved", table: "ConversionPath"), systemImage: "checkmark")
                } else {
                    Text(String(localized: "Save it", table: "ConversionPath"))
                }
            }
            .buttonStyle(LHButton.primary)
            .disabled(flow.trimmedName.isEmpty)
            .allowsHitTesting(!flow.stakeDropped)
            .contentTransition(.opacity)
            .accessibilityIdentifier("onb-primary")
            Button(String(localized: "I’ll add it later", table: "ConversionPath")) {
                dismissKeyboard()
                flow.skipProperty(OnbMotion.morph(reduce))
            }
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("onb-link")
        }
        .onSubmit { if !flow.trimmedName.isEmpty { save() } }
        .sensoryFeedback(.success, trigger: savedTick)
    }

    /// Owners with both kinds say which kind this first rental is (the 100 and 500 hour tests count
    /// each rental on its own).
    private func kindPicker(_ colors: AdaptiveColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Which kind is this one?", table: "ConversionPath"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
            LHSegmented([.init(true, String(localized: "Short stays", table: "ConversionPath")),
                         .init(false, String(localized: "Long-term", table: "ConversionPath"))],
                        selection: $flow.firstPropertyIsShortStay,
                        accessibilityLabel: String(localized: "Which kind is this one?", table: "ConversionPath"))
                .accessibilityIdentifier("property-kind")
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// One tap: the rental is saved, its house lights (`windows`), the button says Saved, and the
    /// flow moves on by itself.
    private func save() {
        dismissKeyboard()
        guard flow.saveProperty() else { return }
        savedTick += 1
        withAnimation(reduce ? AppAnimation.windowsReduced : AppAnimation.windows) {
            flow.stakeDropped = true
            flow.flagOpen = true
        }
        UIAccessibility.post(notification: .announcement,
                             argument: String(localized: "\(flow.displayName) saved.", table: "ConversionPath"))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduce ? 500 : 700))
            if OnbDebugLaunch.holdAfterStake { return }
            flow.next(OnbMotion.morph(reduce))
        }
    }
}

// MARK: - 5 · Visit-end note (opt-in, only after a calendar grant)

struct OnbNotificationPreview: View {
    var title: String
    var bodyText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(alignment: .top, spacing: 10) {
            Image("onb-appicon")
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    Spacer()
                    Text(String(localized: "now", table: "ConversionPath")).font(.footnote).foregroundStyle(colors.textSecondary)
                }
                Text(bodyText).font(.subheadline).foregroundStyle(colors.textPrimary)
            }
        }
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous).strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Example notification. \(title). \(bodyText)", table: "ConversionPath"))
    }
}

struct OnbNotifyStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var colorScheme
    private var place: String {
        if !flow.trimmedName.isEmpty { return flow.trimmedName }
        return flow.firstPropertyType == .str ? String(localized: "Tahoe cabin", table: "ConversionPath") : String(localized: "Oak Street", table: "ConversionPath")
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        OnbStepScaffold(title: String(localized: "Want a nudge to log it while it’s fresh?", table: "ConversionPath")) {
            VStack(alignment: .leading, spacing: 16) {
                OnbNotificationPreview(title: String(localized: "Plumber visit just ended", table: "ConversionPath"),
                                       bodyText: String(localized: "Log 2 hours at \(place)?", table: "ConversionPath"))
                Text(String(localized: "A short note after a calendar event, so you log it the same day. At most 2 a day, never at night.", table: "ConversionPath"))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
            }
        } actions: {
            Button(String(localized: "Yes, after visits", table: "ConversionPath")) { Task { await flow.askNotify(OnbMotion.morph(reduce)) } }
                .buttonStyle(LHButton.primary)
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-primary")
            Button(String(localized: "Not now", table: "ConversionPath")) { flow.notifyNotNow(OnbMotion.morph(reduce)) }
                .buttonStyle(LHButton.tertiary)
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-secondary")
        }
    }
}

// MARK: - What's new for upgraders · 1: their hours and their house

struct OnbWhatsNewHouseStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var colorScheme

    private var stageLine: String { Self.stageLine(hours: flow.upgradeHours, goal: flow.upgradeGoal) }

    /// "312h · frame going up · roof at 500h": the upgrader's real total, as the house stage.
    static func stageLine(hours: Double, goal: HouseGoal) -> String {
        let progress = HouseProgress(hours: hours, goal: goal)
        var parts = ["\(Int(progress.hours.rounded(.down)))h", progress.stage.spokenName.lowercased()]
        if progress.nextStep != nil { parts.append(progress.nextMilestoneLabel.lowercased()) }
        return parts.joined(separator: " · ")
    }

    /// The upgrader's house: the craft stage of their countable hours against their goal.
    static func stage(hours: Double, goal: HouseGoal) -> CraftStage {
        CraftStage.stage(hours: max(0, hours), goal: goal.targetHours)
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        OnbStepScaffold(title: OnbCopy.upgradeHeadline(hours: flow.upgradeHours, goal: flow.upgradeGoal, isRecord: flow.upgradeIsRecord)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    LHThumb.large(Self.stage(hours: flow.upgradeHours, goal: flow.upgradeGoal), lit: true)
                    Text(stageLine)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                }
                Text(OnbCopy.upgradeBody(isRecord: flow.upgradeIsRecord))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                if flow.upgradeGoal == .reps750, !flow.upgradeIsRecord {
                    Text(OnbCopy.upgradeRepsNote)
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("whatsnew-reps-note")
                }
            }
        } actions: {
            Button(String(localized: "Continue", table: "ConversionPath")) { flow.next(OnbMotion.morph(reduce)) }
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("onb-primary")
        }
    }
}
