import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted after the suggestion inbox changes (a confirm, dismiss, mute or scan), so the tab
    /// badge and an open inbox reload. WP4's refresher can post it after a scan.
    static let captureSuggestionsDidChange = Notification.Name("LandlordHours.captureSuggestionsDidChange")
}

/// A row action that has ALREADY been saved and can still be undone for a few seconds.
/// Saving first means a crash, a watchdog kill or a force-quit inside the Undo window loses
/// nothing; Undo reverses the write through the normal delete path.
enum InboxUndoableAction: Equatable {
    /// A new entry was saved for this suggestion.
    case logged(Suggestion, entryId: UUID, hours: Double)
    case dismissed(Suggestion)
    /// The rule and every suggestion key it hid.
    case muted(Suggestion, CaptureMuteRule, hiddenKeys: Set<String>)

    var suggestion: Suggestion {
        switch self {
        case .logged(let s, _, _), .dismissed(let s), .muted(let s, _, _): return s
        }
    }
}

/// The toast under the inbox: a confirmation with Undo, or a plain message when an action could
/// not be completed.
struct InboxToast: Equatable, Identifiable {
    enum Kind: Equatable { case success, neutral, problem }
    var id = UUID()
    var message: String
    var kind: Kind
    var undo: InboxUndoableAction?

    var isLog: Bool { kind == .success }
}

enum InboxSwipeOutcome: Equatable {
    /// Saved (Undo available).
    case logged
    /// The item needs a decision: the confirm sheet opens.
    case needsSheet
    /// Nothing was saved; the toast says why and the item stays in the inbox.
    case failed
}

// MARK: - Inbox view model
//
// Owns no data: it reads the profile's SuggestionStore and writes through
// `AppViewModel.confirm` (the only path from a suggestion to a tax record).
@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var suggestions: [Suggestion] = []
    /// The toast on screen, if any.
    @Published private(set) var toast: InboxToast?
    /// The suggestion the confirm sheet shows.
    @Published var sheetSuggestion: Suggestion?
    /// WP-P: the paywall to open from the list (a swipe that hit the free plan's limit).
    @Published var paywallRequest: ProPaywallRequest?

    private weak var app: AppViewModel?
    private let storeProvider: () -> SuggestionStore?
    private let now: () -> Date
    private let calendar: Calendar
    private let spouseTracking: () -> Bool
    private let isPro: () -> Bool
    let waitList: ProWaitList
    /// Seconds the toast (and its Undo) stays.
    var undoWindow: TimeInterval
    private var toastTask: Task<Void, Never>?

    init(
        app: AppViewModel?,
        storeProvider: @escaping () -> SuggestionStore?,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        spouseTracking: @escaping () -> Bool = { TaxProfileManager.shared.spouseTracking },
        isPro: @escaping () -> Bool = { SubscriptionManager.shared.isPro },
        waitList: ProWaitList = .shared,
        undoWindow: TimeInterval = 5
    ) {
        self.app = app
        self.storeProvider = storeProvider
        self.now = now
        self.calendar = calendar
        self.spouseTracking = spouseTracking
        self.isPro = isPro
        self.waitList = waitList
        self.undoWindow = undoWindow
    }

    /// The app's inbox: the single model's store.
    static func live(app: AppViewModel) -> InboxViewModel {
        InboxViewModel(app: app, storeProvider: { AppModelHost.shared.suggestionStore }, now: { InboxClock.now() })
    }

    var store: SuggestionStore? { storeProvider() }

    // MARK: Reads

    var visible: [Suggestion] { InboxLogic.visible(suggestions, now: now()) }

    var sections: [InboxSection] { InboxLogic.sections(suggestions, now: now(), calendar: calendar) }

    /// Tab badge: what still needs the user.
    var badgeCount: Int { visible.count }

    /// Pending backfill items (the blueprint banner).
    var backfillCount: Int { visible.filter(\.isBackfill).count }

    var properties: [RentalProperty] { app?.properties ?? [] }

    var showsSpousePicker: Bool { spouseTracking() }

    func propertyName(for suggestion: Suggestion) -> String? {
        guard let id = suggestion.proposedPropertyId else { return nil }
        return properties.first { $0.id == id }?.name
    }

    func badges(for suggestion: Suggestion) -> SuggestionBadges { InboxLogic.badges(for: suggestion) }

    // MARK: Free plan at its limit (WP-P)

    /// The free plan is full (one rental) and this item is at a rental the user doesn't have.
    func needsNewRental(_ suggestion: Suggestion) -> Bool {
        InboxProLimit.needsNewRental(suggestion, propertyIds: Set(properties.map(\.id)), isPro: isPro())
    }

    /// The user kept this item for later with "Keep it in my inbox".
    func isWaitingOnPro(_ suggestion: Suggestion) -> Bool {
        needsNewRental(suggestion) && waitList.contains(suggestion.sourceKey)
    }

    var limitCounts: InboxProLimit.Counts {
        InboxProLimit.counts(suggestions, propertyIds: Set(properties.map(\.id)), isPro: isPro(), waitingKeys: waitList.keys)
    }

    /// "Keep it in my inbox": the item stays, marked "Waiting on Pro". It never expires silently
    /// and is never logged to the wrong place.
    func keepForPro(_ suggestion: Suggestion) {
        if sheetSuggestion?.sourceKey == suggestion.sourceKey { sheetSuggestion = nil }
        waitList.add(suggestion.sourceKey)
        changed()
        present(InboxToast(message: "Kept in your inbox", kind: .neutral, undo: nil))
    }

    /// The paywall about adding a rental, opened from the Inbox.
    func paywallForNewRental(onUnlocked: (() -> Void)? = nil) -> ProPaywallRequest {
        ProPaywallRequest(context: .secondProperty, entry: .inboxLimit, onUnlocked: onUnlocked)
    }

    func canQuickLog(_ suggestion: Suggestion) -> Bool {
        InboxLogic.canQuickLog(suggestion, propertyIds: Set(properties.map(\.id)))
    }

    // MARK: Lifecycle

    /// Re-reads the store. Re-checks pending items against current entries first, so a manual
    /// log or an iCloud pull updates "might already be logged" and hides recorded items.
    func reload(animated: Bool) {
        guard animated else { return reload() }
        animateChange { reload() }
    }

    func reload() {
        guard let store else {
            suggestions = []
            return
        }
        if let entries = app?.timeEntries {
            store.reconcile(with: entries, calendar: calendar)
        }
        suggestions = store.suggestions
    }

    // MARK: Row actions (all save immediately)

    /// Swipe right. Logs only when `canQuickLog`; otherwise opens the sheet. Re-checks
    /// "might already be logged" at tap time against current entries.
    @discardableResult
    func swipeLog(_ suggestion: Suggestion) -> InboxSwipeOutcome {
        var current = latest(suggestion)
        if let entries = app?.timeEntries {
            current.mightAlreadyBeLogged = CaptureReconciler.mightAlreadyBeLogged(current, in: entries, calendar: calendar)
        }
        guard canQuickLog(current) else {
            sheetSuggestion = current
            return .needsSheet
        }
        return save(current, edits: SuggestionEdits()).entryId != nil ? .logged : .failed
    }

    /// The confirm sheet's "Log Xh". Returns what happened: `.created` / `.alreadyRecorded` mean
    /// saved; `.needsInput` means nothing was saved (missing values, no profile, or the plan's
    /// limit) and the sheet must stay open. (WP-P fix: this used to return nil on failure too, so
    /// the sheet closed as if the entry was logged.)
    @discardableResult
    func log(_ suggestion: Suggestion, edits: SuggestionEdits) -> CaptureConfirmResult {
        let missing = missingFields(suggestion, edits: edits)
        guard missing.isEmpty else { return .needsInput(missing: missing) }
        let result = save(latest(suggestion), edits: edits)
        if result.entryId != nil, sheetSuggestion?.sourceKey == suggestion.sourceKey { sheetSuggestion = nil }
        return result
    }

    /// Swipe left / "Not rental work".
    func dismiss(_ suggestion: Suggestion) {
        let current = latest(suggestion)
        if sheetSuggestion?.sourceKey == current.sourceKey { sheetSuggestion = nil }
        guard let store else { return showProblem(Self.noProfileMessage) }
        store.dismiss(key: current.sourceKey, reason: .notLandlordWork)
        waitList.remove(current.sourceKey)
        finish(InboxToast(message: "Marked not rental work", kind: .neutral, undo: .dismissed(current)))
    }

    /// "Don't suggest events like this": hides every matching pending item.
    func mute(_ suggestion: Suggestion, rule: CaptureMuteRule) {
        let current = latest(suggestion)
        if sheetSuggestion?.sourceKey == current.sourceKey { sheetSuggestion = nil }
        guard let store else { return showProblem(Self.noProfileMessage) }
        var hidden = Set(store.pending.filter { rule.mutes($0) }.map(\.sourceKey))
        hidden.insert(current.sourceKey)
        store.addMuteRule(rule)
        store.dismiss(key: current.sourceKey, reason: .muted)
        finish(InboxToast(message: "We won’t suggest events like this", kind: .neutral,
                          undo: .muted(current, rule, hiddenKeys: hidden)))
    }

    /// Reverses the toast's action: deletes the saved entry through the normal delete path
    /// (iCloud tombstone), removes a mute rule, and puts the items back in the inbox.
    func undo() {
        guard let action = toast?.undo else { return }
        dismissToast()
        guard let store else { return }
        switch action {
        case .logged(let suggestion, let entryId, _):
            if let app, let entry = app.timeEntries.first(where: { $0.id == entryId }) {
                app.deleteTimeEntry(entry)
            }
            store.restorePending(keys: [suggestion.sourceKey])
        case .dismissed(let suggestion):
            store.restorePending(keys: [suggestion.sourceKey])
        case .muted(_, let rule, let hiddenKeys):
            store.removeMuteRule(id: rule.id)
            store.restorePending(keys: hiddenKeys)
        }
        changed()
    }

    /// Hides the toast. Nothing is pending: every action was saved when it happened.
    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        animateChange { toast = nil }
    }

    func missingFields(_ suggestion: Suggestion, edits: SuggestionEdits) -> Set<CaptureConfirmField> {
        var missing = Set<CaptureConfirmField>()
        let property = edits.propertyId ?? suggestion.proposedPropertyId
        if property == nil || !properties.contains(where: { $0.id == property }) { missing.insert(.property) }
        if (edits.category ?? suggestion.proposedCategory) == nil { missing.insert(.category) }
        if (edits.hours ?? suggestion.proposedHours ?? 0) <= 0 { missing.insert(.hours) }
        return missing
    }

    static let noProfileMessage = "Couldn’t save. Sign in to a profile and try again."

    // MARK: Private

    /// Saves through `confirm()` and checks the result. Anything but created/already recorded
    /// leaves the item in the inbox and says why.
    @discardableResult
    private func save(_ suggestion: Suggestion, edits: SuggestionEdits) -> CaptureConfirmResult {
        guard let store, let app else {
            showProblem(Self.noProfileMessage)
            return .needsInput(missing: [.profile])
        }
        let result = app.confirm(suggestion, edits: edits, store: store)
        switch result {
        case .created(let entryId):
            waitList.remove(suggestion.sourceKey)
            let hours = edits.hours ?? suggestion.proposedHours ?? 0
            finish(InboxToast(message: "Logged \(InboxFormat.hours(hours))", kind: .success,
                              undo: .logged(suggestion, entryId: entryId, hours: hours)))
        case .alreadyRecorded:
            waitList.remove(suggestion.sourceKey)
            finish(InboxToast(message: "Already in your records", kind: .neutral, undo: nil))
        case .needsInput(let missing):
            reload()
            showProblem(Self.message(for: missing))
            if missing.contains(.plan) {
                // The plan's limit: route to the paywall instead of a dead end.
                if sheetSuggestion == nil { paywallRequest = paywallForNewRental() }
            } else {
                sheetSuggestion = latest(suggestion)
            }
        }
        return result
    }

    static func message(for missing: Set<CaptureConfirmField>) -> String {
        if missing.contains(.profile) { return noProfileMessage }
        if missing.contains(.plan) { return "Not saved. This one needs Pro." }
        if missing.contains(.property) { return "Not saved. Pick a property for this one." }
        if missing.contains(.hours) { return "Not saved. Add the hours for this one." }
        return "Not saved. Add a category for this one."
    }

    private func latest(_ suggestion: Suggestion) -> Suggestion {
        suggestions.first { $0.sourceKey == suggestion.sourceKey } ?? suggestion
    }

    private func showProblem(_ message: String) {
        present(InboxToast(message: message, kind: .problem, undo: nil))
    }

    private func finish(_ toast: InboxToast) {
        changed()
        present(toast)
    }

    private func changed() {
        reload()
        NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
    }

    private func present(_ newToast: InboxToast) {
        toastTask?.cancel()
        animateChange { toast = newToast }
        guard undoWindow.isFinite, undoWindow > 0 else { return }
        let window = undoWindow
        let id = newToast.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            self.dismissToast()
        }
    }

    private func animateChange(_ body: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeInOut(duration: 0.2), body)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86), body)
        }
    }
}
