import SwiftUI

// MARK: - Today's timer card (spec §2 order: hero → timer card → To confirm …, §3d)
//
// Shown only while a timer runs or a draft waits. One generic `DraftCard` serves the running
// timer, a stopped timer and a recovered one; later it serves receipt and contact drafts too
// (smart-layer design-implications §1). v2: one grouped container on the page (`LHRowGroup(onPage:)`,
// §1.3a), an SF glyph in a wash tile, a `.secondary` for the action and a `.tertiary` for Discard.

/// One draft: a glyph, a title, one line of meta, one `.secondary` action and a "Discard" link.
struct DraftCard: View {
    var symbol: String = "timer"
    let title: String
    let meta: String
    var moreCount = 0
    let primaryTitle: String
    var primaryIdentifier = "draft.primary"
    var onPrimary: () -> Void
    var discardTitle: String? = nil
    var onDiscard: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHRowGroup(onPage: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    LHRowGlyph(systemImage: symbol)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                            .monospacedDigit()
                            .accessibilityIdentifier("draft.title")
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                        if moreCount > 0 {
                            LHTag(lt("+\(moreCount) more"), tone: .action)
                                .accessibilityIdentifier("draft.more")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen?() }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
                    .accessibilityIdentifier("draft.summary")
                }
                let actions = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(spacing: 8))
                actions {
                    Button(primaryTitle, action: onPrimary)
                        .buttonStyle(LHButton.secondary)
                        .accessibilityIdentifier(primaryIdentifier)
                    if let discardTitle, let onDiscard {
                        Button(discardTitle, action: onDiscard)
                            .buttonStyle(LHButton.destructiveTertiary)
                            .accessibilityIdentifier("draft.discard")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LHRow.insets)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("draft.card")
    }
}

/// Today's slot: running timer, else a stopped timer, else recovered drafts. Nothing otherwise.
struct TodayTimerSection: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var stopped: StoppedTimerDraft?

    var body: some View {
        Group {
            if viewModel.isTimerRunning, let start = viewModel.timerStartTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let clock = LogTimeFormat.clock(min(context.date.timeIntervalSince(start), TimerReviewMath.cap))
                    DraftCard(
                        title: lt("Timer running \u{00B7}\u{00A0}\(clock)"),
                        meta: lt("\(viewModel.timerCategory.inboxLabel) at \(propertyName(viewModel.timerPropertyId)) \u{00B7}\u{00A0}started \(LogTimeFormat.clockTime(start))"),
                        primaryTitle: lt("Stop"),
                        primaryIdentifier: "today.timer.stop",
                        onPrimary: stop,
                        onOpen: { open(.timer) }
                    )
                }
                .accessibilityIdentifier("today.timer")
            } else if let stopped, viewModel.properties.contains(where: { $0.id == stopped.propertyId }) {
                let ran = LHFormat.hours(Double(Int(min(stopped.elapsed, TimerReviewMath.cap) / 60)) / 60)
                DraftCard(
                    title: lt("Timer ran \(ran) at \(propertyName(stopped.propertyId))"),
                    meta: lt("Started \(LogTimeFormat.clockTime(stopped.startDate)). Add a note, or log it as it is."),
                    moreCount: viewModel.staleTimerRecoveries.count,
                    primaryTitle: stopped.reviewHours > 0 ? lt("Log \(LHFormat.hours(stopped.reviewHours))") : lt("Review"),
                    onPrimary: { logStopped(stopped) },
                    discardTitle: lt("Discard"),
                    onDiscard: { discardStopped(stopped) },
                    onOpen: { open(.timerReview) }
                )
                .accessibilityIdentifier("today.timerDraft")
            } else if let recovery = viewModel.staleTimerRecoveries.first {
                recoveryCard(recovery)
            }
        }
        .onAppear { stopped = StoppedTimerDraftStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: .stoppedTimerDraftDidChange)) { _ in
            stopped = StoppedTimerDraftStore.load()
        }
    }

    private func recoveryCard(_ recovery: StaleTimerRecovery) -> some View {
        let needsProperty = viewModel.staleTimerRecoveryNeedsProperty(recovery)
        let quick = !recovery.requiresReview && !needsProperty
        let ran = recovery.ranLabel.lowercased()
        return DraftCard(
            title: needsProperty ? lt("Timer \(ran)") : lt("Timer \(ran) at \(propertyName(recovery.propertyId))"),
            meta: recoveryMeta(recovery, needsProperty: needsProperty),
            moreCount: viewModel.staleTimerRecoveries.count - 1,
            primaryTitle: quick ? lt("Log \(LHFormat.hours(recovery.suggestedHours))") : lt("Review"),
            onPrimary: {
                if quick {
                    let hours = recovery.suggestedHours
                    let name = propertyName(recovery.propertyId)
                    if viewModel.saveRecoveredStaleTimer(id: recovery.id) {
                        AppToastCenter.shared.show(LogTimeFormat.loggedToast(hours: hours, propertyName: name))
                    } else {
                        AppToastCenter.shared.show(viewModel.persistenceError ?? LogSaveResult.writeFailedMessage, kind: .problem)
                    }
                } else {
                    open(.recovery(recovery.id))
                }
            },
            discardTitle: lt("Discard"),
            onDiscard: {
                viewModel.discardRecoveredStaleTimer(id: recovery.id)
                AppToastCenter.shared.show(lt("Timer discarded"), kind: .neutral)
            },
            onOpen: { open(.recovery(recovery.id)) }
        )
        .accessibilityIdentifier("today.timerRecovery")
    }

    private func recoveryMeta(_ recovery: StaleTimerRecovery, needsProperty: Bool) -> String {
        let start = lt("Started \(LogTimeFormat.longDay(recovery.startTime)), \(LogTimeFormat.clockTime(recovery.startTime)).")
        if needsProperty { return lt("\(start) Its rental was deleted, so pick where it goes.") }
        if recovery.wasCapped { return lt("\(start) We stopped counting at 24h, so check the hours.") }
        switch recovery.reason {
        case .pausedAtSwitch:
            return lt("\(start) It stopped when you switched profiles at \(LogTimeFormat.clockTime(recovery.pausedAt ?? recovery.startTime)).")
        case .forgotten:
            return lt("\(start) It was left running, so check the hours.")
        }
    }

    private func propertyName(_ id: UUID?) -> String {
        viewModel.properties.first { $0.id == id }?.name ?? lt("your rental")
    }

    private func open(_ route: LogSheetRoute) {
        NotificationCenter.default.post(name: .openLogSheet, object: route)
    }

    private func stop() {
        guard viewModel.stopTimerIntoDraft() != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        open(.timerReview)
    }

    private func logStopped(_ draft: StoppedTimerDraft) {
        guard draft.reviewHours > 0 else { return open(.timerReview) }
        let name = propertyName(draft.propertyId)
        let result = viewModel.logTimeEntry(propertyId: draft.propertyId,
                                            participant: LogParticipantRule.resolve(draft.participant, spouseTracking: viewModel.tracksSpouseJointly),
                                            category: draft.category, hours: draft.reviewHours, date: draft.startDate,
                                            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines), source: .timer)
        switch result {
        case .failed(let message):
            AppToastCenter.shared.show(message, kind: .problem)
        case .saved(let id):
            StoppedTimerDraftStore.clear()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AppToastCenter.shared.show(LogTimeFormat.loggedToast(hours: draft.reviewHours, propertyName: name)) { [weak viewModel = viewModel] in
                if let entry = viewModel?.timeEntries.first(where: { $0.id == id }) { viewModel?.deleteTimeEntry(entry) }
                StoppedTimerDraftStore.save(draft)
            }
        }
    }

    private func discardStopped(_ draft: StoppedTimerDraft) {
        StoppedTimerDraftStore.clear()
        AppToastCenter.shared.show(lt("Timer discarded"), kind: .neutral) { StoppedTimerDraftStore.save(draft) }
    }
}
