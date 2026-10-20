import SwiftUI

// MARK: - Today's timer card (spec §2 order: hero → timer card → To confirm …, §3d)
//
// Shown only while a timer runs or a draft waits. One generic `DraftCard` serves the running
// timer, a stopped timer and a recovered one; later it serves receipt and contact drafts too
// (smart-layer design-implications §1). This replaces the 1.x floating timer banner and the
// Track tab's "Finish your saved timer" card.

/// One draft: a glyph, a title, one line of meta, a tinted primary and a "Discard" link.
struct DraftCard: View {
    var symbol: String = "timer"
    let title: String
    let meta: String
    var moreCount = 0
    let primaryTitle: String
    var primaryIdentifier = "draft.primary"
    var onPrimary: () -> Void
    var discardTitle: String? = "Discard"
    var onDiscard: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

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
                        .accessibilityIdentifier("draft.title")
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
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 16))
            actions {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(PropertyTintedButtonStyle())
                    .accessibilityIdentifier(primaryIdentifier)
                if let discardTitle, let onDiscard {
                    Button(discardTitle, action: onDiscard)
                        .font(.body)
                        .foregroundStyle(colors.destructive)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("draft.discard")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 12, y: 4)
        )
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
                    DraftCard(
                        title: "Timer running\(LogTimeFormat.dot)\(LogTimeFormat.clock(min(context.date.timeIntervalSince(start), TimerReviewMath.cap)))",
                        meta: "\(viewModel.timerCategory.inboxLabel) at \(propertyName(viewModel.timerPropertyId))\(LogTimeFormat.dot)started \(InboxFormat.clockTime(start))",
                        primaryTitle: "Stop",
                        primaryIdentifier: "today.timer.stop",
                        onPrimary: stop,
                        discardTitle: nil,
                        onOpen: { open(.timer) }
                    )
                }
                .accessibilityIdentifier("today.timer")
            } else if let stopped, viewModel.properties.contains(where: { $0.id == stopped.propertyId }) {
                DraftCard(
                    title: "Timer ran \(InboxFormat.hours(Double(Int(min(stopped.elapsed, TimerReviewMath.cap) / 60)) / 60)) at \(propertyName(stopped.propertyId))",
                    meta: "Started \(InboxFormat.clockTime(stopped.startDate)). Add a note, or log it as it is.",
                    moreCount: viewModel.staleTimerRecoveries.count,
                    primaryTitle: stopped.reviewHours > 0 ? "Log \(InboxFormat.hours(stopped.reviewHours))" : "Review",
                    onPrimary: { logStopped(stopped) },
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
        let place = needsProperty ? "" : " at \(propertyName(recovery.propertyId))"
        return DraftCard(
            title: "Timer \(recovery.ranLabel.lowercased())\(place)",
            meta: recoveryMeta(recovery, needsProperty: needsProperty),
            moreCount: viewModel.staleTimerRecoveries.count - 1,
            primaryTitle: quick ? "Log \(InboxFormat.hours(recovery.suggestedHours))" : "Review",
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
            onDiscard: {
                viewModel.discardRecoveredStaleTimer(id: recovery.id)
                AppToastCenter.shared.show("Timer discarded", kind: .neutral)
            },
            onOpen: { open(.recovery(recovery.id)) }
        )
        .accessibilityIdentifier("today.timerRecovery")
    }

    private func recoveryMeta(_ recovery: StaleTimerRecovery, needsProperty: Bool) -> String {
        let start = "Started \(InboxFormat.longDay(recovery.startTime)), \(InboxFormat.clockTime(recovery.startTime))."
        if needsProperty { return "\(start) Its rental was deleted, so pick where it goes." }
        if recovery.wasCapped { return "\(start) We stopped counting at 24h, so check the hours." }
        switch recovery.reason {
        case .pausedAtSwitch:
            return "\(start) It stopped when you switched profiles at \(InboxFormat.clockTime(recovery.pausedAt ?? recovery.startTime))."
        case .forgotten:
            return "\(start) It was left running, so check the hours."
        }
    }

    private func propertyName(_ id: UUID?) -> String {
        viewModel.properties.first { $0.id == id }?.name ?? "your rental"
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
        AppToastCenter.shared.show("Timer discarded", kind: .neutral) { StoppedTimerDraftStore.save(draft) }
    }
}
