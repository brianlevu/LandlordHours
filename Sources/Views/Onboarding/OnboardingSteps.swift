import SwiftUI

// MARK: - Shared scaffold: question (SF Pro title semibold), scrolling body, pinned actions

struct OnbStepScaffold<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String? = nil
    /// A short note that belongs beside the ask (trust lines, the CPA note). Pinned above the
    /// actions; at accessibility text sizes it moves to the end of the scrolling content, so the
    /// pinned area never crowds out the question.
    var note: AnyView? = nil
    /// Scrolls this id into view whenever it changes (the property step keeps "Add address"
    /// above the keyboard).
    var scrollTarget: String? = nil
    /// False for the question steps (a tap answers): no pinned bar, so nothing fades over the last card.
    var showsActions = true
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.onbBottomInset) private var bottomInset
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.onbDisplayTitles) private var displayTitles

    var body: some View {
        let pinNote = !typeSize.isAccessibilitySize
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleText
                    .foregroundStyle(OnbColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(OnbColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                content.padding(.top, 20)
                if !pinNote, let note { note.padding(.top, 16) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            // Room for the last line to scroll clear of the fade above the pinned actions.
            .padding(.bottom, typeSize.isAccessibilitySize ? 80 : 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: scrollTarget) { _, target in
            guard let target else { return }
            // After the keyboard has moved the sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(AppAnimation.standard) { proxy.scrollTo(target, anchor: .bottom) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Scrolled-up words fade at the sheet's top edge instead of being cut mid-line.
        .overlay(alignment: .top) {
            LinearGradient(colors: [OnbColor.card, OnbColor.card.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .allowsHitTesting(false)
        }
        .scrollIndicatorsFlash(onAppear: true)
        .defaultScrollAnchor(OnbDebugLaunch.scrollToBottom ? .bottom : .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showsActions {
                Color.clear.frame(height: bottomInset)
            } else {
            VStack(spacing: 6) {
                if pinNote, let note { note.padding(.bottom, 6) }
                actions
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, bottomInset)
            .background(OnbColor.card)
            // A short fade above the pinned area: content slides under it, never hard-cut.
            .background(alignment: .top) {
                // Clear for the first part, so a control resting just above the pinned area keeps
                // full contrast; only words actually sliding under it fade.
                // At accessibility sizes one line is ~40pt, so a 28pt fade would still hard-cut it:
                // the fade grows and starts at once, so the next line visibly runs on under it.
                let fade: CGFloat = typeSize.isAccessibilitySize ? 72 : 28
                LinearGradient(stops: [.init(color: OnbColor.card.opacity(0), location: 0),
                                       .init(color: OnbColor.card.opacity(0), location: typeSize.isAccessibilitySize ? 0.1 : 0.45),
                                       .init(color: OnbColor.card, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
                    .offset(y: -fade)
                    .allowsHitTesting(false)
            }
            }
        }
        }
    }
}

extension OnbStepScaffold {
    /// What's new (upgraders) titles are Fraunces display, like the app's own titles;
    /// onboarding questions stay SF Pro (approved design).
    @ViewBuilder fileprivate var titleText: some View {
        if displayTitles {
            Text(title).lhDisplayFont(.title)
        } else {
            Text(title).font(.system(.title, weight: .semibold))
        }
    }
}

/// The one card style: hairline border, 16pt radius, blueprint ring when selected.
struct OnbOptionCard<Extra: View>: View {
    var symbol: String? = nil
    var title: String
    var detail: String
    var badge: String? = nil
    var hint: String? = nil
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var extra: Extra
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(OnbColor.action)
                            .frame(width: 36, height: 36)
                            .background(OnbColor.actionSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // At accessibility sizes the badge sits on its own line so the title keeps its width.
                        let stack = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                        stack {
                            if typeSize.isAccessibilitySize, let badge { badgeView(badge) }
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(OnbColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !typeSize.isAccessibilitySize, let badge { badgeView(badge) }
                        }
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(OnbColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hint {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(OnbColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? OnbColor.action : OnbColor.textTertiary)   // 3:1 or better; the hairline border is decorative
                        .accessibilityHidden(true)
                }
                extra
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnbColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? OnbColor.action : OnbColor.border, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(OnbPressable())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badgeView(_ badge: String) -> some View {
        Text(badge)
            .font(.caption.weight(.semibold))
            .foregroundStyle(OnbColor.action)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(OnbColor.actionSurface, in: Capsule())
            .fixedSize()
    }
}

extension OnbOptionCard where Extra == EmptyView {
    init(symbol: String? = nil, title: String, detail: String, badge: String? = nil, hint: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, detail: detail, badge: badge, hint: hint, selected: selected, action: action, extra: { EmptyView() })
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
            case .target: targetCards
            }
        }
        .transition(reduce ? .opacity : .asymmetric(
            insertion: .offset(x: flow.forward ? 36 : -36).combined(with: .opacity),
            removal: .offset(x: flow.forward ? -36 : 36).combined(with: .opacity)))
        .id(flow.goalPhase)
    }

    // MARK: Q1 · What do you rent out?

    private var rentalQuestion: some View {
        OnbStepScaffold(title: String(localized: "What do you rent out?"), showsActions: false) {
            VStack(alignment: .leading, spacing: 12) {
                OnbOptionCard(symbol: "calendar", title: String(localized: "Short stays"),
                              detail: String(localized: "Guests stay 7 days or less, on average."),
                              selected: flow.rental == .shortStays) { flow.answerRental(.shortStays, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("rental-short")
                OnbOptionCard(symbol: "key.fill", title: String(localized: "Long-term"),
                              detail: String(localized: "Leases of a month or more."),
                              selected: flow.rental == .longTerm) { flow.answerRental(.longTerm, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("rental-long")
                OnbOptionCard(symbol: "square.stack.fill", title: String(localized: "Both"),
                              detail: String(localized: "Some of each."),
                              selected: flow.rental == .both) { flow.answerRental(.both, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("rental-both")
            }
        } actions: {
            EmptyView()
        }
    }

    // MARK: Q2 · Do you or your spouse do real estate as a main job?

    private var proQuestion: some View {
        OnbStepScaffold(title: String(localized: "Do you or your spouse do real estate as a main job?"),
                        subtitle: String(localized: "Main job means most of your working hours, all year, running your own business or as a contractor."),
                        showsActions: false) {
            VStack(alignment: .leading, spacing: 12) {
                OnbOptionCard(symbol: "person.fill", title: String(localized: "Me"), detail: String(localized: "Real estate is my main job."),
                              selected: flow.pro == .me) { flow.answerPro(.me, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("pro-me")
                OnbOptionCard(symbol: "person.2.fill", title: String(localized: "My spouse"), detail: String(localized: "Real estate is my spouse’s main job."),
                              selected: flow.pro == .spouse) { flow.answerPro(.spouse, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("pro-spouse")
                OnbOptionCard(symbol: "minus.circle", title: String(localized: "No"), detail: String(localized: "Neither of us."),
                              selected: flow.pro == .nobody) { flow.answerPro(.nobody, OnbMotion.morph(reduce)) }
                    .accessibilityIdentifier("pro-none")
            }
        } actions: {
            EmptyView()
        }
    }

    // MARK: The suggested target (first, already selected), the others, then the record

    private var targetCards: some View {
        OnbStepScaffold(title: String(localized: "Based on your answers, start here"), note: AnyView(
            Text("Change this any time. Reaching a number is based on your records; your CPA decides what it means.")
                .font(.footnote)
                .foregroundStyle(OnbColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading))) {
            VStack(alignment: .leading, spacing: 10) {
                if let suggestion = flow.suggestion {
                    ForEach(Array(suggestion.ordered.enumerated()), id: \.element) { index, goal in
                        card(goal, isSuggested: index == 0)
                            .padding(.top, index == 1 ? 6 : 0)
                    }
                }
            }
        } actions: {
            Button((flow.goal ?? .reps750).callToAction) { flow.confirmGoal(OnbMotion.morph(reduce)) }
                .buttonStyle(OnbPrimaryPill())
                .disabled(flow.goal == nil)
                .contentTransition(.opacity)
                .accessibilityIdentifier("onb-primary")
        }
    }

    private func card(_ goal: OnbGoal, isSuggested: Bool) -> some View {
        OnbOptionCard(title: OnbGoalCopy.title(goal, pro: flow.pro),
                      detail: OnbGoalCopy.detail(goal, pro: flow.pro, isSuggested: isSuggested, rental: flow.rental),
                      selected: flow.goal == goal) {
            withAnimation(OnbMotion.flow(reduce)) { flow.goal = goal }
        }
        .accessibilityIdentifier(Self.identifier(goal))
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
        var hours: String
        var category: ActivityCategory
        var when: String
        var title: String
        /// SF Symbol for where the row came from (calendar, envelope, receipt).
        var sourceGlyph: String
    }

    struct TrustLine {
        var symbol: String
        var lead: String
        var rest: String
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
        title: String(localized: "Your calendar already has some of your hours."),
        subtitle: String(localized: "We look back 90 days for things like a plumber visit, a showing or a turnover, then ask you. Every one you confirm is a dated entry."),
        rows: [
            SampleRow(hours: "2h", category: .repairs, when: "Calendar · Wed 9–11", title: "Plumber", sourceGlyph: "calendar"),
            SampleRow(hours: "1h", category: .leasing, when: "Calendar · Sat 10–11", title: "Showing", sourceGlyph: "calendar"),
            SampleRow(hours: "3h", category: .management, when: "Calendar · Sun 11–2", title: "Turnover clean", sourceGlyph: "calendar"),
        ],
        trust: [
            TrustLine(symbol: "eye", lead: String(localized: "What we read:"), rest: String(localized: "event titles and times.")),
            TrustLine(symbol: "hand.raised.fill", lead: String(localized: "What we never do:"), rest: String(localized: "send them anywhere, or log anything without you.")),
        ],
        primary: String(localized: "Look at my calendar"),
        secondary: String(localized: "Not now")
    )
}

struct OnbSampleRow: View {
    let row: OnbSource.SampleRow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Large text: hours and tool on a line of their own above the words; nothing truncates.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) { hours; tool; Spacer(minLength: 4); hollow }
                    words
                }
            } else {
                HStack(spacing: 12) {
                    hours.frame(width: 70, alignment: .leading)
                    tool
                    words
                    Spacer(minLength: 4)
                    hollow
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: \(row.title), \(row.hours), \(row.category.inboxLabel)")
        .accessibilityHint("Suggestion, not saved")
    }

    private var hours: some View {
        Text(row.hours)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(OnbColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var tool: some View {
        Image("bp_tool_\(row.category.blueprintToolName)_36")
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(row.when, systemImage: row.sourceGlyph)
                .font(.footnote)
                .foregroundStyle(OnbColor.textSecondary)
                .labelStyle(OnbTightLabel())
                .lineLimit(typeSize >= .xxLarge ? 3 : 1)
                .minimumScaleFactor(typeSize >= .xxLarge ? 1 : 0.8)
                .fixedSize(horizontal: false, vertical: typeSize >= .xxLarge)
            Text(row.title)
                .font(.headline)
                .foregroundStyle(OnbColor.textPrimary)
            Text(row.category.inboxLabel)
                .font(.subheadline)
                .foregroundStyle(row.category.inboxInk(AdaptiveColors(colorScheme: colorScheme)))
        }
    }

    /// Hollow: a suggestion, not a record, until the owner confirms it.
    private var hollow: some View {
        Circle()
            .strokeBorder(OnbColor.draftingInk, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

struct OnbSourceStep: View {
    @Bindable var flow: OnbFlow
    var source: OnbSource = .calendar
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        OnbStepScaffold(title: source.title, subtitle: source.subtitle, note: AnyView(
            // Trust at the ask: what we read, what we never do.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(source.trust.enumerated()), id: \.offset) { _, line in trustLine(line) }
            }
            .frame(maxWidth: .infinity, alignment: .leading))) {
            VStack(spacing: 0) {
                ForEach(Array(source.rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().overlay(OnbColor.border).padding(.leading, 82) }
                    OnbSampleRow(row: row)
                        .opacity(flow.calendarRows > i ? 1 : 0)
                        .offset(y: flow.calendarRows > i || reduce ? 0 : 6)
                }
            }
            .padding(.horizontal, 14)
            .background(OnbColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OnbColor.border, lineWidth: 1))
        } actions: {
            Button(source.primary) { Task { await flow.askCalendar(OnbMotion.morph(reduce)) } }
                .buttonStyle(OnbPrimaryPill())
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-primary")
            Button(source.secondary) { flow.calendarNotNow(OnbMotion.morph(reduce)) }
                .buttonStyle(OnbOutlinePill())
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-link")
        }
        .task {
            // Rows (and hatched storeys) appear one by one.
            let total = source.rows.count
            guard flow.calendarRows < total else { return }
            if !reduce { try? await Task.sleep(nanoseconds: 300_000_000) }
            for i in (flow.calendarRows + 1)...total {
                withAnimation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.28)) { flow.calendarRows = i }
                if !reduce { try? await Task.sleep(nanoseconds: 380_000_000) }
            }
        }
    }

    private func trustLine(_ line: OnbSource.TrustLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: line.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OnbColor.informational)
                .frame(width: 18)
                .accessibilityHidden(true)
            (Text(line.lead).fontWeight(.semibold).foregroundColor(OnbColor.textPrimary)
             + Text(" \(line.rest)").foregroundColor(OnbColor.textSecondary))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3 · Who does the work

struct OnbWhoStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        OnbStepScaffold(title: String(localized: "Who puts in the hours?")) {
            VStack(alignment: .leading, spacing: 12) {
                OnbOptionCard(symbol: "person.fill", title: String(localized: "Just me"), detail: String(localized: "I handle the rentals."),
                              selected: flow.who == .me) { pick(.me) }
                    .accessibilityIdentifier("who-me")
                OnbOptionCard(symbol: "person.2.fill", title: String(localized: "My spouse and me"), detail: String(localized: "We both do."),
                              selected: flow.who == .both) { pick(.both) }
                    .accessibilityIdentifier("who-both")
                if flow.who == .both {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "person.2")
                            .foregroundStyle(OnbColor.rose)
                            .accessibilityHidden(true)
                        Text(OnbGoal.spouseNote(for: flow.goal))
                            .font(.subheadline)
                            .foregroundStyle(OnbColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OnbColor.roseSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -8)))
                    .accessibilityIdentifier("who-note")
                }
            }
        } actions: {
            Button(String(localized: "Continue")) { flow.confirmWho(OnbMotion.morph(reduce)) }
                .buttonStyle(OnbPrimaryPill())
                .accessibilityIdentifier("onb-primary")
        }
    }

    private func pick(_ w: OnbWho) { withAnimation(OnbMotion.flow(reduce)) { flow.who = w } }
}

// MARK: - 4 · First property (the one typed field)

struct OnbPropertyStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @FocusState private var focused: Bool

    var body: some View {
        OnbStepScaffold(title: String(localized: "Which rental first?"), scrollTarget: focused ? "property-add-address-row" : nil) {
            VStack(alignment: .leading, spacing: 12) {
                if let hint = flow.propertyHint {
                    Label(hint, systemImage: "tray.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OnbColor.draftingInk)
                        .contentTransition(.numericText(value: Double(flow.found.count)))
                        .transition(.opacity)
                        .accessibilityIdentifier("property-hint")
                }
                Text("Rental name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnbColor.textPrimary)
                    .accessibilityHidden(true)
                TextField("", text: $flow.name, prompt: Text(flow.firstPropertyType == .str ? String(localized: "Tahoe cabin") : String(localized: "Oak Street duplex")).foregroundColor(OnbColor.textTertiary))
                    .font(.body)
                    .foregroundStyle(OnbColor.textPrimary)
                    .focused($focused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(OnbColor.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(focused ? OnbColor.action : OnbColor.border, lineWidth: focused ? 2 : 1))
                    .accessibilityLabel("Rental name")
                    .accessibilityIdentifier("property-name")
                if flow.addressOpen {
                    TextField("", text: $flow.address, prompt: Text("Street address (optional)").foregroundColor(OnbColor.textTertiary))
                        .font(.body)
                        .foregroundStyle(OnbColor.textPrimary)
                        .textContentType(.fullStreetAddress)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(OnbColor.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(OnbColor.border, lineWidth: 1))
                        .accessibilityLabel("Street address, optional")
                        .accessibilityIdentifier("property-address")
                        .transition(.opacity)
                } else {
                    Button {
                        withAnimation(OnbMotion.flow(reduce)) { flow.addressOpen = true }
                    } label: {
                        Label("Add address", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OnbColor.action)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(OnbPressable())
                    .accessibilityIdentifier("property-add-address")
                    .id("property-add-address-row")
                }
                if flow.rental == .both { kindPicker }
                Text("A nickname is fine. Address, units and more rentals come later.")
                    .font(.footnote)
                    .foregroundStyle(OnbColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            // One tap: the stake drops, the flag shows the name, and the flow moves on by itself.
            Button {
                stake()
            } label: {
                if flow.stakeDropped { Label("Saved", systemImage: "checkmark") } else { Text("Save it") }
            }
            .buttonStyle(OnbPrimaryPill())
            .disabled(flow.trimmedName.isEmpty)
            .allowsHitTesting(!flow.stakeDropped)
            .accessibilityIdentifier("onb-primary")
            Button("I'll add it later") {
                focused = false
                flow.skipProperty(OnbMotion.morph(reduce))
            }
            .buttonStyle(OnbLink(color: OnbColor.textSecondary))
            .accessibilityIdentifier("onb-link")
        }
        .onSubmit { if !flow.trimmedName.isEmpty { stake() } }
        .onAppear { if OnbDebugLaunch.focusName { focused = true } }
    }

    /// Owners with both kinds say which kind this first rental is (the 100 and 500 hour tests count each rental on its own).
    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which kind is this one?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnbColor.textPrimary)
            HStack(spacing: 8) {
                kindChip(String(localized: "Short stays"), short: true, id: "property-kind-short")
                kindChip(String(localized: "Long-term"), short: false, id: "property-kind-long")
            }
        }
    }

    private func kindChip(_ label: String, short: Bool, id: String) -> some View {
        let on = flow.firstPropertyIsShortStay == short
        return Button { withAnimation(OnbMotion.flow(reduce)) { flow.firstPropertyIsShortStay = short } } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? OnbColor.onAction : OnbColor.action)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(on ? OnbColor.action : OnbColor.actionSurface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(OnbPressable())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func stake() {
        focused = false
        guard flow.saveProperty() else { return }
        Task { @MainActor in
            // The stake drops (220 ms), the flag unfurls with the name, hold, then the morph.
            if reduce {
                withAnimation(.easeInOut(duration: 0.2)) { flow.stakeDropped = true; flow.flagOpen = true }
            } else {
                withAnimation(.easeIn(duration: 0.22)) { flow.stakeDropped = true }
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { flow.flagOpen = true }
            }
            UIAccessibility.post(notification: .announcement, argument: "\(flow.displayName) saved.")
            try? await Task.sleep(nanoseconds: reduce ? 500_000_000 : 720_000_000)
            if OnbDebugLaunch.holdAfterStake { return }
            flow.next(OnbMotion.morph(reduce))
        }
    }
}

// MARK: - 5 · Visit-end note (opt-in, only after a calendar grant)

struct OnbNotificationPreview: View {
    var title: String
    var bodyText: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("onb-appicon")
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("now").font(.footnote).foregroundStyle(.secondary)
                }
                Text(bodyText).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example notification. \(title). \(bodyText)")
    }
}

struct OnbNotifyStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var place: String {
        if !flow.trimmedName.isEmpty { return flow.trimmedName }
        return flow.firstPropertyType == .str ? String(localized: "Tahoe cabin") : String(localized: "Oak Street")
    }

    var body: some View {
        OnbStepScaffold(title: String(localized: "Want a nudge to log it while it’s fresh?")) {
            VStack(alignment: .leading, spacing: 14) {
                OnbNotificationPreview(title: String(localized: "Plumber visit just ended"), bodyText: String(localized: "Log 2h at \(place)?"))
                Text("One short note after a calendar event, so your entry is dated the day it happened. At most two a day, never at night.")
                    .font(.body)
                    .foregroundStyle(OnbColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("Yes, after visits") { Task { await flow.askNotify(OnbMotion.morph(reduce)) } }
                .buttonStyle(OnbPrimaryPill())
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-primary")
            Button("Not now") { flow.notifyNotNow(OnbMotion.morph(reduce)) }
                .buttonStyle(OnbOutlinePill())
                .disabled(flow.isAsking)
                .accessibilityIdentifier("onb-secondary")
        }
    }
}

// MARK: - What's new for upgraders · 1 "Your hours now build a house."

struct OnbWhatsNewHouseStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var stageLine: String { Self.stageLine(hours: flow.upgradeHours, goal: flow.upgradeGoal) }

    /// "312h · frame going up · roof at 500h": the upgrader's real total, as the house stage.
    static func stageLine(hours: Double, goal: HouseGoal) -> String {
        let progress = HouseProgress(hours: hours, goal: goal)
        var parts = ["\(Int(progress.hours.rounded(.down)))h", progress.stage.spokenName.lowercased()]
        if progress.nextStep != nil { parts.append(progress.nextMilestoneLabel.lowercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        OnbStepScaffold(title: OnbCopy.upgradeHeadline(hours: flow.upgradeHours, goal: flow.upgradeGoal, isRecord: flow.upgradeIsRecord)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(stageLine)
                    .onbDrafting(OnbColor.draftingInk)
                Text(OnbCopy.upgradeBody(isRecord: flow.upgradeIsRecord))
                    .font(.body)
                    .foregroundStyle(OnbColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if flow.upgradeGoal == .reps750, !flow.upgradeIsRecord {
                    Text(OnbCopy.upgradeRepsNote)
                        .font(.body)
                        .foregroundStyle(OnbColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("whatsnew-reps-note")
                }
            }
        } actions: {
            Button("Continue") { flow.next(OnbMotion.morph(reduce)) }
                .buttonStyle(OnbPrimaryPill())
                .accessibilityIdentifier("onb-primary")
        }
    }
}
