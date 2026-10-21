import SwiftUI

// MARK: - The shell toast for Log time and the timer
//
// Cross-lane decision (2026-10-19): one full-width Inbox-style toast app-wide. The r4 "Timer
// discarded" capsule is superseded. The shell draws it just above the tab bar with the same view
// as the Inbox's (`InboxUndoToast`), so the two can never drift apart.

@MainActor
final class AppToastCenter: ObservableObject {
    static let shared = AppToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let kind: InboxToast.Kind
        let hasUndo: Bool

        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    @Published private(set) var toast: Toast?
    /// Seconds a toast (and its Undo) stays (spec §0: 4s).
    var undoWindow: TimeInterval = 4
    private var undoAction: (() -> Void)?
    private var task: Task<Void, Never>?

    func show(_ message: String, kind: InboxToast.Kind = .success, undo: (() -> Void)? = nil) {
        task?.cancel()
        undoAction = undo
        toast = Toast(message: message, kind: kind, hasUndo: undo != nil)
        let window = undoWindow
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
        UIAccessibility.post(notification: .announcement, argument: undo == nil ? message : "\(message). Undo is available.")
    }

    func undo() {
        let action = undoAction
        dismiss()
        action?()
    }

    func dismiss() {
        task?.cancel()
        task = nil
        undoAction = nil
        toast = nil
    }

    /// The Inbox toast view, fed from this center.
    var inboxToast: InboxToast? {
        toast.map { InboxToast(message: $0.message, kind: $0.kind, undo: nil) }
    }
}
