import SwiftUI

// MARK: - Shared scaffold: question (SF Pro 28 semibold), scrolling body, pinned actions

struct OnbStepScaffold<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String? = nil
    /// A short note that belongs beside the ask (trust lines, the CPA note). Pinned above the
    /// actions; at accessibility text sizes it moves to the end of the scrolling content instead,
    /// so the pinned area never crowds out the question.
    var note: AnyView? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @Environment(\.onbBottomInset) private var bottomInset
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let pinNote = !typeSize.isAccessibilitySize
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(.title, weight: .semibold))
                    .foregroundStyle(PC.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(PC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                content.padding(.top, 20)
                if !pinNote, let note { note.padding(.top, 16) }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicatorsFlash(onAppear: true)
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "LHOnbScrollBottom") ? .bottom : .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if pinNote, let note { note.padding(.bottom, 6) }
                actions
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, bottomInset)
            .background(PC.card)
            // A short fade above the pinned area: content slides under it, never hard-cut.
            .background(alignment: .top) {
                LinearGradient(colors: [PC.card.opacity(0), PC.card], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .offset(y: -24)
                    .allowsHitTesting(false)
            }
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
                            .foregroundStyle(PC.action)
                            .frame(width: 36, height: 36)
                            .background(PC.actionSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                                .foregroundStyle(PC.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !typeSize.isAccessibilitySize, let badge { badgeView(badge) }
                        }
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(PC.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hint {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(PC.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? PC.action : PC.border)
                        .accessibilityHidden(true)
                }
                extra
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PC.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? PC.action : PC.border, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension OnbOptionCard {
    fileprivate func badgeView(_ badge: String) -> some View {
        Text(badge)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PC.action)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(PC.actionSurface, in: Capsule())
            .fixedSize()
    }
}

extension OnbOptionCard where Extra == EmptyView {
    init(symbol: String? = nil, title: String, detail: String, badge: String? = nil, hint: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, detail: detail, badge: badge, hint: hint, selected: selected, action: action, extra: { EmptyView() })
    }
}

// MARK: - 1 · Goal

struct OnbGoalStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var cta: String {
        switch flow.goal {
        case .reps750: "Build toward 750h"
        case .mp500: "Build toward 500h"
        case .mp100: "Build toward 100h"
        case .record: "Keep a record"
        case nil: "Build toward 750h"
        }
    }
    private var isMP: Bool { flow.goal == .mp500 || flow.goal == .mp100 }

    var body: some View {
        OnbStepScaffold(title: "What are you building toward?", note: AnyView(
            Text("Change this any time. Reaching a number is based on your records; your CPA decides what it means.")
                .font(.footnote)
                .foregroundStyle(PC.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading))) {
            VStack(alignment: .leading, spacing: 10) {
                OnbOptionCard(title: "750 hours",
                              detail: "Real estate professional. For owners who make rentals their main work.",
                              badge: "Most common",
                              hint: "And more than half your working hours go to real estate.",
                              selected: flow.goal == .reps750) { pick(.reps750) }
                    .accessibilityIdentifier("goal-750")
                OnbOptionCard(title: "500 or 100 hours",
                              detail: "Material participation. 500 hours, or 100 and more than anyone else.",
                              selected: isMP, action: { if !isMP { pick(.mp500) } }) {
                    if isMP {
                        HStack(spacing: 8) {
                            mpChip(.mp500, "500h")
                            mpChip(.mp100, "100h")
                        }
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .accessibilityIdentifier("goal-mp")
                OnbOptionCard(title: "Just keep a record",
                              detail: "No target. A clean log for your CPA.",
                              selected: flow.goal == .record) { pick(.record) }
                    .accessibilityIdentifier("goal-record")
            }
        } actions: {
            Button(cta) { flow.next(reduce: reduce) }
                .buttonStyle(ProdPrimaryPill())
                .disabled(flow.goal == nil)
                .contentTransition(.opacity)
                .accessibilityIdentifier("onb-primary")
        }
    }

    private func pick(_ g: OnbGoal) { withAnimation(OnbMotion.flow(reduce)) { flow.goal = g } }

    private func mpChip(_ g: OnbGoal, _ label: String) -> some View {
        let on = flow.goal == g
        return Button { pick(g) } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(on ? PC.onAction : PC.action)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(on ? PC.action : PC.actionSurface, in: Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - 2 · Calendar

struct OnbSampleRow: View {
    var hours: String
    var tool: String
    var when: String
    var title: String
    var category: String
    var categoryColor: Color
    var onConfirm: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var id: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mainRow
            if let onConfirm {
                HStack(spacing: 4) {
                    Button(action: onConfirm) {
                        Label("Confirm", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PC.onAction)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(PC.action, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(Pressable())
                    .accessibilityIdentifier("confirm-\(id)")
                    if let onSkip {
                        Button("Not work", action: onSkip)
                            .buttonStyle(ProdLink(color: PC.textSecondary))
                            .accessibilityIdentifier("skip-\(id)")
                    }
                }
                .padding(.leading, 82)
            }
        }
        .padding(.vertical, 8)
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            Text(hours)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PC.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 70, alignment: .leading)
            Image(tool)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Label(when, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(PC.textSecondary)
                    .labelStyle(TightLabel())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PC.textPrimary)
                Text(category)
                    .font(.subheadline)
                    .foregroundStyle(categoryColor)
            }
            Spacer(minLength: 4)
            if onConfirm == nil {
                // Hollow: a suggestion, not a record, until the owner confirms it.
                Circle()
                    .strokeBorder(PC.draftingInk, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Suggestion, not saved")
    }
}

struct OnbCalendarStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let rows: [(String, String, String, String, String, Category)] = [
        ("2h", "bp_tool_repairs_36", "Calendar · Wed 9–11", "Plumber", "Repairs", .repairs),
        ("1h", "bp_tool_showing_36", "Calendar · Sat 10–11", "Showing", "Leasing", .leasing),
        ("1h 30m", "bp_tool_inspection_36", "Calendar · Mon 2–3:30", "Inspection", "Inspections", .inspections),
    ]

    var body: some View {
        OnbStepScaffold(title: "Your calendar already knows.",
                        subtitle: "We look back 90 days for things like a plumber visit, a showing or an inspection, then ask you.",
                        note: AnyView(
                            // Trust at the ask: what we read, what we never do.
                            VStack(alignment: .leading, spacing: 6) {
                                trustLine("eye", PC.informational, "What we read:", "event titles and times.")
                                trustLine("hand.raised.fill", PC.informational, "What we never do:", "send them anywhere, or log anything without you.")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading))) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { i, r in
                        if i > 0 { Divider().overlay(PC.border).padding(.leading, 82) }
                        OnbSampleRow(hours: r.0, tool: r.1, when: r.2, title: r.3, category: r.4, categoryColor: onbCategoryColor(r.5))
                            .opacity(flow.calendarRows > i ? 1 : 0)
                            .offset(y: flow.calendarRows > i || reduce ? 0 : 6)
                    }
                }
                .padding(.horizontal, 14)
                .background(PC.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(PC.border, lineWidth: 1))
            }
        } actions: {
            Button("Look at my calendar") { askCalendar() }
                .buttonStyle(ProdPrimaryPill())
                .accessibilityIdentifier("onb-primary")
            Button("Not now") {
                flow.calendar = .denied
                flow.next(reduce: reduce)
            }
            .buttonStyle(ProdOutlinePill())
            .accessibilityIdentifier("onb-link")
        }
        .task {
            // Rows and hatched storeys appear one by one (each row is a storey).
            guard flow.calendarRows < 3 else { return }
            try? await Task.sleep(for: .milliseconds(reduce ? 0 : 300))
            for i in (flow.calendarRows + 1)...3 {
                withAnimation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.28)) { flow.calendarRows = i }
                try? await Task.sleep(for: .milliseconds(reduce ? 0 : 380))
            }
        }
    }

    private func trustLine(_ sym: String, _ tint: Color, _ lead: String, _ rest: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: sym)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            (Text(lead).fontWeight(.semibold).foregroundStyle(PC.textPrimary) + Text(" " + rest).foregroundStyle(PC.textSecondary))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func askCalendar() {
        withAnimation(.easeOut(duration: 0.2)) { flow.prompt = .calendar }
    }
}

// MARK: - 3 · Who does the work

struct OnbWhoStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var note: String {
        switch flow.goal {
        case .mp500, .mp100: "Your hours count together for material participation."
        case .record: "You'll each have your own count."
        default: "You'll each have your own count. For the 750-hour test, one of you has to get there alone."
        }
    }

    var body: some View {
        OnbStepScaffold(title: "Who does the work?") {
            VStack(alignment: .leading, spacing: 12) {
                OnbOptionCard(symbol: "person.fill", title: "Just me", detail: "I manage the rentals.",
                              selected: flow.who == .me) { pick(.me) }
                    .accessibilityIdentifier("who-me")
                OnbOptionCard(symbol: "person.2.fill", title: "My spouse and me", detail: "We both put in hours.",
                              selected: flow.who == .both) { pick(.both) }
                    .accessibilityIdentifier("who-both")
                if flow.who == .both {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "person.2")
                            .foregroundStyle(PC.rose)
                            .accessibilityHidden(true)
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(PC.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PC.roseSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -8)))
                }
            }
        } actions: {
            Button("Continue") { flow.next(reduce: reduce) }
                .buttonStyle(ProdPrimaryPill())
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
    @State private var address = ""

    var body: some View {
        OnbStepScaffold(title: "Name your first rental.") {
            VStack(alignment: .leading, spacing: 12) {
                if flow.calendar == .allowed && flow.suggestions > 0 {
                    Label(flow.scanDone ? "\(flow.suggestions) suggestions waiting" : "\(flow.suggestions) suggestions so far · still looking",
                          systemImage: "tray.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PC.draftingInk)
                        .contentTransition(.numericText(value: Double(flow.suggestions)))
                        .transition(.opacity)
                }
                Text("Property name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PC.textPrimary)
                    .accessibilityHidden(true)
                TextField("", text: $flow.name, prompt: Text("Oak Street duplex").foregroundStyle(PC.textTertiary))
                    .font(.body)
                    .foregroundStyle(PC.textPrimary)
                    .focused($focused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(PC.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(focused ? PC.action : PC.border, lineWidth: focused ? 2 : 1))
                    .accessibilityLabel("Rental name")
                    .accessibilityIdentifier("property-name")
                if flow.addressOpen {
                    TextField("", text: $address, prompt: Text("Street address (optional)").foregroundStyle(PC.textTertiary))
                        .font(.body)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(PC.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(PC.border, lineWidth: 1))
                        .transition(.opacity)
                } else {
                    Button {
                        withAnimation(OnbMotion.flow(reduce)) { flow.addressOpen = true }
                    } label: {
                        Label("Add address", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PC.action)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(Pressable())
                }
                Text("A nickname is fine. Addresses, units and more places come later.")
                    .font(.footnote)
                    .foregroundStyle(PC.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            // One tap: the stake drops, the flag shows the name, and the flow moves on by itself.
            Button {
                stake()
            } label: {
                if flow.stakeDropped { Label("Saved", systemImage: "checkmark") } else { Text("Save it") }
            }
                .buttonStyle(ProdPrimaryPill())
                .disabled(flow.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .allowsHitTesting(!flow.stakeDropped)
                .accessibilityIdentifier("onb-primary")
            Button("I'll add it later") {
                focused = false
                flow.skippedProperty = true
                flow.next(reduce: reduce)
            }
            .buttonStyle(ProdLink(color: PC.textSecondary))
            .accessibilityIdentifier("onb-link")
        }
        .onChange(of: UserDefaults.standard.bool(forKey: "LHOnbFocus"), initial: true) { _, f in focused = f }
        .onReceive(NotificationCenter.default.publisher(for: .onbStake)) { _ in stake() }
        .onReceive(NotificationCenter.default.publisher(for: .onbFocus)) { _ in focused = true }
    }

    private func stake() {
        focused = false
        Task { @MainActor in
            // The stake drops (220 ms), the flag unfurls with the name, hold 500 ms, then the morph.
            if reduce {
                withAnimation(.easeInOut(duration: 0.2)) { flow.stakeDropped = true; flow.flagOpen = true }
            } else {
                withAnimation(.easeIn(duration: 0.22)) { flow.stakeDropped = true }
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { flow.flagOpen = true }
            }
            try? await Task.sleep(for: .milliseconds(reduce ? 500 : 720))
            if UserDefaults.standard.bool(forKey: "LHOnbStaked") { return }
            flow.next(reduce: reduce)
        }
    }
}

extension Notification.Name {
    static let onbStake = Notification.Name("onb.stake")
    static let onbFocus = Notification.Name("onb.focus")
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
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example notification. \(title). \(bodyText)")
    }
}

/// "MOCK OF SYSTEM UI" tag for the approval frames.
struct MockTag: View {
    var onDark = false
    var body: some View {
        Text("Mock of system UI")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.white.opacity(0.5)))
            .accessibilityHidden(true)
    }
}

struct OnbNotifyStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var place: String { flow.name.isEmpty ? "Oak Street" : flow.name }

    var body: some View {
        OnbStepScaffold(title: "Want a note when a visit ends?") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    if flow.mockLabels { MockTag() }
                    OnbNotificationPreview(title: "Plumber visit just ended", bodyText: "Log 2h at \(place)?")
                }
                Text("One short note after a calendar event, so you can log it with a tap. At most two a day, never at night.")
                    .font(.body)
                    .foregroundStyle(PC.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("Yes, after visits") { withAnimation(.easeOut(duration: 0.2)) { flow.prompt = .notify } }
                .buttonStyle(ProdPrimaryPill())
                .accessibilityIdentifier("onb-primary")
            Button("Not now") {
                flow.notify = false
                flow.next(reduce: reduce)
            }
            .buttonStyle(ProdOutlinePill())
            .accessibilityIdentifier("onb-secondary")
        }
    }
}

/// Category ink. Leasing has its own harbour blue, so it never reads as the spouse rose
/// (#B04266) or the concept's violet.
func onbCategoryColor(_ c: Category) -> Color {
    switch c {
    case .leasing: Color(light: 0x1B6C8C, dark: 0x7CC6E4)
    case .repairs: PC.timberInk
    default: PC.informational
    }
}
