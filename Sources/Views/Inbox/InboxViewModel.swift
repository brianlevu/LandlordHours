import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted after the suggestion inbox changes (a confirm, dismiss, mute or scan), so the tab
    /// badge and an open inbox reload. WP4's refresher can post it after a scan.
    static let captureSuggestionsDidChange = Notification.Name("LandlordHours.captureSuggestionsDidChange")
}

/// What a row action is waiting to do. Actions are held for a few seconds so Undo is a true undo:
/// nothing is written (no entry, no dismissed key, no mute rule) until the window closes.
enum InboxPendingAction: Equatable {
    case log(Suggestion, SuggestionEdits)
    case dismiss(Suggestion)
    case mute(Suggestion, CaptureMuteRule)

    var suggestion: Suggestion {
        switch self {
        case .log(let s, _), .dismiss(let s), .mute(let s, _): return s
        }
    }

    /// Toast text: "Logged 2h", "Marked not landlord work", "We won't suggest these".
    func message(defaultHours: Double?) -> String {
        switch self {
        case .log(let s, let edits):
            let hours = edits.hours ?? s.proposedHours ?? defaultHours ?? 0
            return "Logged \(InboxFormat.hours(hours))"
        case .dismiss:
            return "Marked not landlord work"
        case .mute:
            return "We won't suggest events like this"
        }
    }
}

enum InboxSwipeOutcome: Equatable {
    /// Logged (held for Undo).
    case logged
    /// The item needs a decision: the confirm sheet opens.
    case needsSheet
}

// MARK: - Inbox view model
//
// Owns no data: it reads the profile's SuggestionStore and writes through
// `AppViewModel.confirm` (the only path from a suggestion to a tax record).
@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var suggestions: [Suggestion] = []
    /// The action waiting behind the Undo toast, if any.
    @Published private(set) var pendingAction: InboxPendingAction?
    /// The suggestion the confirm sheet shows.
    @Published var sheetSuggestion: Suggestion?

    private weak var app: AppViewModel?
    private let storeProvider: () -> SuggestionStore?
    private let now: () -> Date
    private let calendar: Calendar
    private let spouseTracking: () -> Bool
    /// Seconds the Undo toast stays before the action is written.
    var undoWindow: TimeInterval
    private var commitTask: Task<Void, Never>?

    init(
        app: AppViewModel?,
        storeProvider: @escaping () -> SuggestionStore?,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        spouseTracking: @escaping () -> Bool = { TaxProfileManager.shared.spouseTracking },
        undoWindow: TimeInterval = 4
    ) {
        self.app = app
        self.storeProvider = storeProvider
        self.now = now
        self.calendar = calendar
        self.spouseTracking = spouseTracking
        self.undoWindow = undoWindow
    }

    /// The app's inbox: the single model's store.
    static func live(app: AppViewModel) -> InboxViewModel {
        InboxViewModel(app: app, storeProvider: { AppModelHost.shared.suggestionStore })
    }

    var store: SuggestionStore? { storeProvider() }

    // MARK: Reads

    /// Pending, visible items minus the one held behind Undo.
    var visible: [Suggestion] {
        let hiddenKeys = hiddenByPendingAction
        return InboxLogic.visible(suggestions, now: now()).filter { !hiddenKeys.contains($0.sourceKey) }
    }

    var sections: [InboxSection] {
        let hiddenKeys = hiddenByPendingAction
        return InboxLogic.sections(suggestions.filter { !hiddenKeys.contains($0.sourceKey) }, now: now(), calendar: calendar)
    }

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

    func canQuickLog(_ suggestion: Suggestion) -> Bool {
        InboxLogic.canQuickLog(suggestion, propertyIds: Set(properties.map(\.id)))
    }

    private var hiddenByPendingAction: Set<String> {
        guard let pendingAction else { return [] }
        switch pendingAction {
        case .log(let s, _), .dismiss(let s):
            return [s.sourceKey]
        case .mute(let s, let rule):
            var keys = Set(suggestions.filter { $0.isPending && rule.mutes($0) }.map(\.sourceKey))
            keys.insert(s.sourceKey)
            return keys
        }
    }

    // MARK: Lifecycle

    /// Re-reads the store. Re-checks pending items against current entries first, so a manual
    /// log or an iCloud pull updates "might already be logged" and hides recorded items.
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

    // MARK: Row actions

    /// Swipe right. Logs (held for Undo) only when `canQuickLog`; otherwise opens the sheet.
    /// Re-checks "might already be logged" at tap time against current entries.
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
        hold(.log(current, SuggestionEdits()))
        return .logged
    }

    /// Swipe left / "Not landlord work". Held for Undo.
    func dismiss(_ suggestion: Suggestion) {
        hold(.dismiss(latest(suggestion)))
    }

    /// The confirm sheet's "Log Xh". Missing values come back as `.needsInput` and nothing is held.
    @discardableResult
    func log(_ suggestion: Suggestion, edits: SuggestionEdits) -> CaptureConfirmResult? {
        let missing = missingFields(suggestion, edits: edits)
        guard missing.isEmpty else { return .needsInput(missing: missing) }
        hold(.log(latest(suggestion), edits))
        return nil
    }

    /// "Don't suggest events like this". Held for Undo; hides every matching pending item.
    func mute(_ suggestion: Suggestion, rule: CaptureMuteRule) {
        hold(.mute(latest(suggestion), rule))
    }

    func undo() {
        commitTask?.cancel()
        commitTask = nil
        animateChange { pendingAction = nil }
    }

    /// Writes the held action now (the toast timed out, another action started, the inbox
    /// closed, or the app went to the background).
    func commitPending() {
        commitTask?.cancel()
        commitTask = nil
        guard let action = pendingAction else { return }
        pendingAction = nil
        guard let store else { return }
        switch action {
        case .log(let suggestion, let edits):
            if let app {
                _ = app.confirm(suggestion, edits: edits, store: store)
            }
        case .dismiss(let suggestion):
            store.dismiss(key: suggestion.sourceKey, reason: .notLandlordWork)
        case .mute(let suggestion, let rule):
            store.addMuteRule(rule)
            store.dismiss(key: suggestion.sourceKey, reason: .muted)
        }
        reload()
        NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
    }

    func missingFields(_ suggestion: Suggestion, edits: SuggestionEdits) -> Set<CaptureConfirmField> {
        var missing = Set<CaptureConfirmField>()
        let property = edits.propertyId ?? suggestion.proposedPropertyId
        if property == nil || !properties.contains(where: { $0.id == property }) { missing.insert(.property) }
        if (edits.category ?? suggestion.proposedCategory) == nil { missing.insert(.category) }
        if (edits.hours ?? suggestion.proposedHours ?? 0) <= 0 { missing.insert(.hours) }
        return missing
    }

    // MARK: Private

    private func latest(_ suggestion: Suggestion) -> Suggestion {
        suggestions.first { $0.sourceKey == suggestion.sourceKey } ?? suggestion
    }

    private func hold(_ action: InboxPendingAction) {
        // One action behind Undo at a time: the previous one is written first.
        if pendingAction != nil { commitPending() }
        if sheetSuggestion?.sourceKey == action.suggestion.sourceKey { sheetSuggestion = nil }
        animateChange { pendingAction = action }
        guard undoWindow.isFinite, undoWindow > 0 else { return }
        let window = undoWindow
        commitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.commitPending()
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
