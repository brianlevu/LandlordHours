import SwiftUI

// MARK: - Today, below the house: the views (redesign-specs.md §2, sandbox-screens S2Today)
//
// Order under the hero: timer/draft slot → To confirm → This week → pace cards (2-up) →
// Your record (free only). The rules live in TodayLogic.swift; the confirm/not-work writes go
// through the Inbox's own model (`InboxViewModel`), so Today, the Inbox and the tab badge read
// and write one list.

// MARK: Section header

/// The one section header: 13 semibold caps, +0.3 tracking, `textSecondary`, then a trailing
/// slot. To confirm passes two things there (the count, and later a batch action) plus "See all".
struct TodaySectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            trailing()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 32)
    }
}

extension TodaySectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title, trailing: { EmptyView() }) }
}

/// The count capsule (`action` on `actionSurface`).
struct TodayCountCapsule: View {
    let count: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Text("\(count)")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(colors.action)
            .padding(.horizontal, 8)
            .frame(minWidth: 24, minHeight: 22)
            .background(Capsule().fill(colors.actionSurface))
            .contentTransition(.numericText(value: Double(count)))
            .accessibilityLabel("\(count) to confirm")
            .accessibilityIdentifier("today.confirm.count")
    }
}

// MARK: - To confirm

/// The To confirm block. Reads the Inbox model; every action is the Inbox's own action.
struct TodayConfirmSection: View {
    @ObservedObject var inbox: InboxViewModel
    let state: TodayConfirm.State
    let isScanning: Bool
    var onSeeAll: () -> Void
    var onTurnOn: () -> Void
    /// Called after a row was logged (the hero plays its build from the live hours).
    var onLogged: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logTick = 0
    @State private var dismissTick = 0

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var count: Int { inbox.badgeCount }
    private var rows: [Suggestion] { TodayConfirm.rows(visible: inbox.visible) }

    var body: some View {
        if state != .hidden {
            VStack(alignment: .leading, spacing: 10) {
                TodaySectionHeader("To confirm") {
                    if state == .rows {
                        TodayCountCapsule(count: count)
                    }
                    Spacer(minLength: 8)
                    // Second trailing slot: the smart layer's batch action ("Log 5 likely") goes
                    // here (design-implications §1). Empty for now.
                    batchActionSlot
                    if state == .rows {
                        Button("See all", action: onSeeAll)
                            .font(.subheadline)
                            .foregroundStyle(colors.action)
                            .frame(minHeight: 44)
                            .accessibilityHint("Opens your Inbox")
                            .accessibilityIdentifier("today.confirm.seeAll")
                    }
                }
                if isScanning, state == .rows || state == .loading {
                    scanningLine
                }
                switch state {
                case .rows: card
                case .loading: ghostRows
                case .caughtUp(let captureOn): caughtUp(captureOn: captureOn)
                case .hidden: EmptyView()
                }
            }
            .sensoryFeedback(.success, trigger: logTick)
            .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.confirm")
        }
    }

    @ViewBuilder private var batchActionSlot: some View { EmptyView() }

    private static var debugSwipeOffset: CGFloat? {
        #if DEBUG
        return TodayDebugSeed.swipePreviewOffset
        #else
        return nil
        #endif
    }

    // MARK: Rows

    private var card: some View {
        let shown = rows
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.sourceKey) { index, suggestion in
                TodaySwipeRow(
                    suggestion: suggestion,
                    propertyName: inbox.propertyName(for: suggestion),
                    badges: inbox.badges(for: suggestion),
                    canQuickLog: inbox.canQuickLog(suggestion),
                    peek: index == 0 && TodaySwipeHint.shouldPeek,
                    previewOffset: index == 0 ? Self.debugSwipeOffset : nil,
                    onOpen: { inbox.sheetSuggestion = suggestion },
                    onConfirm: { confirm(suggestion) },
                    onNotWork: { notWork(suggestion) }
                )
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                ))
                if index < shown.count - 1 {
                    PropertyInsetDivider(leading: 16 + 108)
                }
            }
            if TodayConfirm.showsReviewAll(count: count) {
                Button("Review all \(count)", action: onSeeAll)
                    .buttonStyle(TodayTintedButtonStyle(fullWidth: true))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier("today.confirm.reviewAll")
            }
        }
        // Rows and their swipe circles stay inside the card's rounded corners.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .propertyCard()
        .background(alignment: .bottom) {
            // More than the card holds: a deck card 6pt behind it.
            if TodayConfirm.showsReviewAll(count: count) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colors.backgroundSecondary)
                    .scaleEffect(x: 0.96, y: 1, anchor: .bottom)
                    .opacity(0.6)
                    .offset(y: 6)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.86),
                   value: shown.map(\.sourceKey))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.confirm.card")
    }

    private func confirm(_ suggestion: Suggestion) {
        TodaySwipeHint.markUsed()
        switch inbox.swipeLog(suggestion) {
        case .logged:
            logTick += 1
            onLogged()
            UIAccessibility.post(notification: .announcement, argument: "Logged. Undo is available.")
        case .needsSheet, .failed:
            break
        }
    }

    private func notWork(_ suggestion: Suggestion) {
        TodaySwipeHint.markUsed()
        inbox.dismiss(suggestion)
        dismissTick += 1
        UIAccessibility.post(notification: .announcement, argument: "Marked not rental work. Undo is available.")
    }

    // MARK: States

    private var scanningLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Looking through your calendar")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TodayDraftingLine()
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Looking through your calendar. Work we find shows up here and in your Inbox.")
        .accessibilityIdentifier("today.lookingBack")
    }

    private var ghostRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { index in
                HStack(spacing: 10) {
                    PlaceholderBar(width: 36, height: 22).frame(width: 52)
                    PlaceholderBar(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceholderBar(width: 120, height: 10)
                        PlaceholderBar(width: index == 0 ? 170 : 140, height: 14)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 76)
                if index == 0 { PropertyInsetDivider(leading: 16 + 108) }
            }
        }
        .propertyCard()
        .accessibilityHidden(true)
    }

    private func caughtUp(captureOn: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(colors.positive)
                .accessibilityHidden(true)
            Text("All caught up")
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
            Text(captureOn
                 ? "We’ll put new work here when your calendar looks like rental work."
                 : "Turn on suggestions and we’ll spot the work for you.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !captureOn {
                Button("Turn on", action: onTurnOn)
                    .buttonStyle(TodayTintedButtonStyle())
                    .padding(.top, 6)
                    .accessibilityIdentifier("today.confirm.turnOn")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(captureOn ? "today.caughtUp" : "today.caughtUp.off")
    }
}

/// One suggestion row on Today: tap opens the confirm sheet; the visible Confirm / Not work
/// buttons and the two swipes do the same as the Inbox's.
struct TodaySwipeRow: View {
    let suggestion: Suggestion
    let propertyName: String?
    let badges: SuggestionBadges
    let canQuickLog: Bool
    var peek = false
    /// DEBUG captures: draw the row already slid by this much.
    var previewOffset: CGFloat? = nil
    var onOpen: () -> Void
    var onConfirm: () -> Void
    var onNotWork: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var dx: CGFloat = 0
    @State private var isHorizontal: Bool?
    @State private var checkPop = false
    @State private var didPeek = false
    /// The row moves with the finger, so a swipe would also end as a tap on it: a swipe in progress
    /// (and the moment after) never opens the sheet.
    @State private var suppressTap = false

    /// Past this the release commits (log or not work).
    static let threshold: CGFloat = 96

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ZStack {
            // What a swipe will do, revealed under the row as it moves.
            HStack {
                actionCircle("checkmark", label: canQuickLog ? "Log" : "Review",
                             fill: colors.positive, ink: colorScheme == .dark ? colors.background : .white,
                             armed: dx > Self.threshold)
                    .scaleEffect(checkPop && !reduceMotion ? 1.15 : 1)
                    .opacity(dx > 8 ? 1 : 0)
                Spacer()
                actionCircle("xmark", label: "Not work", fill: colors.textSecondary,
                             ink: colorScheme == .dark ? colors.background : .white,
                             armed: -dx > Self.threshold)
                    .opacity(dx < -8 ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    guard !suppressTap else { return }
                    onOpen()
                } label: {
                    SuggestionRowView(suggestion: suggestion, propertyName: propertyName, badges: badges)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SuggestionRowView.accessibilityLabel(for: suggestion, propertyName: propertyName,
                                                                         badges: badges, now: InboxClock.now()))
                .accessibilityHint("Opens the details to confirm")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: canQuickLog ? "Log \(InboxFormat.hours(suggestion.proposedHours ?? 0))" : "Review and log") {
                    onConfirm()
                }
                .accessibilityAction(named: "Not rental work") { onNotWork() }
                .accessibilityIdentifier("today.row.\(suggestion.sourceKey)")
                InboxRowActions(key: suggestion.sourceKey, onConfirm: onConfirm, onNotWork: onNotWork)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 16)
            .background(colors.backgroundSecondary)
            .offset(x: dx)
        }
        .clipped()
        .contentShape(Rectangle())
        // Simultaneous, so a vertical drag that starts on a row still scrolls Today.
        .simultaneousGesture(swipe)
        .onAppear {
            if let previewOffset { dx = previewOffset } else { peekIfNeeded() }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                if isHorizontal == nil {
                    isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
                }
                guard isHorizontal == true else { return }
                suppressTap = true
                dx = value.translation.width
            }
            .onEnded { value in
                defer {
                    isHorizontal = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { suppressTap = false }
                }
                guard isHorizontal == true else { return }
                let projected = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.3
                if projected > Self.threshold {
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { checkPop = true }
                    }
                    settle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.18)) { onConfirm() }
                } else if projected < -Self.threshold {
                    settle()
                    onNotWork()
                } else {
                    settle()
                }
            }
    }

    private func settle() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.86)) {
            dx = 0
        }
    }

    /// The swipe affordance: the first row slides a little to show the Log circle under it, once
    /// per profile, until a row has been swiped or confirmed. Never under Reduce Motion.
    private func peekIfNeeded() {
        guard peek, !didPeek, !reduceMotion, !dynamicTypeSize.isAccessibilitySize else { return }
        didPeek = true
        TodaySwipeHint.markPeeked()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.28)) { dx = 56 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { dx = 0 }
            }
        }
    }

    private func actionCircle(_ symbol: String, label: String, fill: Color, ink: Color, armed: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(fill.opacity(armed ? 1 : 0.7)))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
        }
    }
}

/// Remembers, per profile, that the swipe was shown (peek) or used, so the hint stops.
enum TodaySwipeHint {
    static let baseKey = "LandlordHours.today.swipeHintSeen"

    static var shouldPeek: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHNoSwipePeek") { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: UserScope.key(baseKey))
    }

    static func markPeeked() { UserDefaults.standard.set(true, forKey: UserScope.key(baseKey)) }
    static func markUsed() { markPeeked() }
}

/// The 1pt drafting line that draws itself while the look-back runs (static under Reduce Motion).
struct TodayDraftingLine: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = AdaptiveColors(colorScheme: colorScheme).draftingInk
        GeometryReader { proxy in
            if reduceMotion {
                Rectangle().fill(ink).frame(width: proxy.size.width * 0.6)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                    let head = min(1, t / 0.7)
                    let tail = max(0, (t - 0.55) / 0.45)
                    Rectangle()
                        .fill(ink)
                        .frame(width: proxy.size.width * max(0, head - tail))
                        .offset(x: proxy.size.width * tail)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Tinted (44pt, `action` on `actionSurface`, 15 semibold); optionally full width.
struct TodayTintedButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(Capsule().fill(colors.actionSurface))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - This week

struct TodayWeekSection: View {
    let days: [TodayWeekDay]
    var onOpenDay: (TodayWeekDay) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let total = TodayWeek.total(days)
        VStack(alignment: .leading, spacing: 10) {
            TodaySectionHeader("This week") {
                Spacer(minLength: 8)
                Text(InboxFormat.hours(total))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText(value: total))
                    .accessibilityLabel("\(InboxFormat.spokenHours(total)) this week")
                    .accessibilityIdentifier("today.week.total")
            }
            if dynamicTypeSize >= .xxLarge { list(colors) } else { strip(colors) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.week")
    }

    private func strip(_ colors: AdaptiveColors) -> some View {
        let peak = days.compactMap(\.hours).max() ?? 0
        let labelled = TodayWeek.labelledIndex(days)
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Button { onOpenDay(day) } label: {
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        if index == labelled, let hours = day.hours {
                            Text(InboxFormat.hours(hours))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        bar(day, peak: peak, colors: colors)
                        Text(day.letter)
                            .font(.caption.weight(day.isToday ? .semibold : .regular))
                            .foregroundStyle(day.isToday ? colors.action : colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TodayWeek.spoken(day))
                .accessibilityHint("Opens Records")
                .accessibilityIdentifier("today.week.day.\(index)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(height: 112)
        .propertyCard()
    }

    @ViewBuilder private func bar(_ day: TodayWeekDay, peak: Double, colors: AdaptiveColors) -> some View {
        if let hours = day.hours {
            if hours > 0 {
                Capsule()
                    .fill(colors.action)
                    .frame(width: 10, height: TodayWeek.barHeight(hours: hours, peak: peak))
            } else {
                Circle()
                    .fill(colors.border)
                    .frame(width: 4, height: 4)
                    .padding(.top, 6)
            }
        } else {
            // Not yet: drawn as unbuilt, like the house's linework.
            Capsule()
                .strokeBorder(colors.draftingInk.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                .frame(width: 10, height: 11)
        }
    }

    private func list(_ colors: AdaptiveColors) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Button { onOpenDay(day) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(day.shortName)
                            .fontWeight(day.isToday ? .semibold : .regular)
                            .foregroundStyle(day.isToday ? colors.action : colors.textPrimary)
                        Spacer(minLength: 8)
                        Text(day.hours.map { $0 > 0 ? InboxFormat.hours($0) : "None" } ?? "Not yet")
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TodayWeek.spoken(day))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("today.week.day.\(index)")
                if index < days.count - 1 { PropertyInsetDivider() }
            }
        }
        .propertyCard()
    }
}

// MARK: - Pace cards

struct TodayPaceCard: View {
    let model: TodayPaceCardModel
    var isPending = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(model.label)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isPending ? 0 : 1)
                .overlay(alignment: .leading) {
                    if isPending { PlaceholderBar(width: 96, height: 20).transition(.opacity) }
                }
            if let status = model.status {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if model.tone == .caution {
                        Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
                    }
                    Text(status).fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote.weight(model.tone == .caution ? .semibold : .regular))
                .foregroundStyle(tint(colors))
                .opacity(isPending ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .propertyCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPending ? "\(model.label). Loading" : [model.label, model.value, model.status].compactMap { $0 }.joined(separator: ". "))
    }

    private func tint(_ colors: AdaptiveColors) -> Color {
        switch model.tone {
        case .caution: return colors.caution
        case .positive: return colors.positiveText
        case .neutral: return colors.textSecondary
        }
    }
}

// MARK: - Draft card (generic)

/// One draft on Today: a glyph, a title, one line of meta, a tinted primary and a "Discard"
/// link, with "+N more". Timer drafts today; receipt and contact drafts later (smart-layer
/// design-implications §1, "one component").
/// INTEGRATION (wp-log): wp-log ships the same card as `DraftCard` inside `TodayTimerSection`
/// (running timer, stopped timer, recovered drafts). When it merges, `TodayTimerSlot` becomes
/// `TodayTimerSection()` and this type is deleted.
struct TodayDraftCard: View {
    var symbol: String = "timer"
    let title: String
    let meta: String
    var moreCount = 0
    let primaryTitle: String
    var primaryIdentifier = "today.draft.primary"
    var onPrimary: () -> Void
    var onDiscard: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var glyphSize: CGFloat = 44

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .frame(width: glyphSize, height: glyphSize)
                    .background(Circle().fill(colors.actionSurface))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if moreCount > 0 {
                        Text("+\(moreCount) more")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(colors.action)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(colors.actionSurface))
                            .accessibilityIdentifier("today.draft.more")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.draft.summary")
            }
            let actions = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 16))
            actions {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(TodayTintedButtonStyle())
                    .accessibilityIdentifier(primaryIdentifier)
                if let onDiscard {
                    Button("Discard", action: onDiscard)
                        .font(.body)
                        .foregroundStyle(colors.destructive)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("today.draft.discard")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .propertyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.draft")
    }
}

/// Today's timer slot: a recovered timer draft (paused at a profile switch, or left running),
/// as the generic draft card. The running timer keeps the shell's existing floating banner
/// (wp-log owns the running-timer visuals).
/// INTEGRATION (wp-log): replace this body with `TodayTimerSection()`.
struct TodayTimerSlot: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        if let recovery = viewModel.staleTimerRecoveries.first {
            card(recovery)
        }
    }

    private func card(_ recovery: StaleTimerRecovery) -> some View {
        let needsProperty = viewModel.staleTimerRecoveryNeedsProperty(recovery)
        let quick = !recovery.requiresReview && !needsProperty && !viewModel.properties.isEmpty
        let name = viewModel.properties.first { $0.id == recovery.propertyId }?.name
        let place = needsProperty ? "" : name.map { " at \($0)" } ?? ""
        return TodayDraftCard(
            title: "Timer ran \(Self.ran(recovery))\(place)",
            meta: Self.meta(recovery, needsProperty: needsProperty),
            moreCount: viewModel.staleTimerRecoveries.count - 1,
            primaryTitle: quick ? "Log \(InboxFormat.hours(recovery.suggestedHours))" : "Review",
            onPrimary: {
                if quick {
                    if viewModel.saveRecoveredStaleTimer(id: recovery.id) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } else {
                    // The Track tab's review card asks for the hours or the property.
                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.logTimeIndex)
                }
            },
            onDiscard: { viewModel.discardRecoveredStaleTimer(id: recovery.id) }
        )
    }

    /// "1h 12m", "45m", "under 1m": the real run time, in the same words as the Log button.
    static func ran(_ recovery: StaleTimerRecovery) -> String {
        let hours = max(recovery.elapsedHours, 0)
        return hours * 60 < 1 ? "under 1m" : InboxFormat.hours(hours)
    }

    static func meta(_ recovery: StaleTimerRecovery, needsProperty: Bool) -> String {
        let start = "Started \(InboxFormat.clockTime(recovery.startTime))."
        if needsProperty { return "\(start) Its rental was deleted, so pick where it goes." }
        if recovery.wasCapped { return "\(start) We stopped counting at 24h, so check the hours." }
        switch recovery.reason {
        case .pausedAtSwitch:
            return "\(start) It stopped when you switched profiles at \(InboxFormat.clockTime(recovery.pausedAt ?? recovery.startTime))."
        case .forgotten:
            return "\(start) It was left running, so check the hours."
        }
    }
}

// MARK: - Your record (free)

/// Today's Pro surface: "Your record" for a free user with 10 confirmed hours or more.
/// INTEGRATION (wp-paywall): replace this body with wp-paywall's `TodayRecordLockCard`
/// (`LockedPreview(.card)`, entry `.todayRecord`, paywall context `.todayUnlock`); keep the
/// caller's `isShown` rule (it is `ProGate.showsTodayRecordLock`) and the unlock action.
struct TodayRecordSlot: View {
    let year: Int
    let confirmedHours: Double
    var onUnlock: () -> Void

    /// ProGate.todayRecordMinimumHours on wp-paywall.
    static let minimumHours: Double = 10

    static func isShown(isPro: Bool, confirmedHours: Double) -> Bool {
        !isPro && confirmedHours.isFinite && confirmedHours >= minimumHours
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            TodaySectionHeader("Your record")
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.title3)
                        .foregroundStyle(colors.action)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(colors.actionSurface))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your \(String(year)) record")
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        Text("Your \(Int(max(0, confirmedHours).rounded(.down))) hours, ready to export.")
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your record keeps growing. Export unlocks with Pro.")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                Button("Unlock Pro", action: onUnlock)
                    .buttonStyle(TodayTintedButtonStyle())
                    .accessibilityHint("Opens Pro for exports")
                    .accessibilityIdentifier("dashboard.unlockPro")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .propertyCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.yourRecord")
    }
}
