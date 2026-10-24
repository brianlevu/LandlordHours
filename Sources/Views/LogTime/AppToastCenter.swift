import SwiftUI

// MARK: - Log time and timer toasts → the one toast
//
// Build 2 integration: Log time, the timer and Today show their toasts through the app's one toast
// system (`LHToastCenter` + `LHToast`, surfaces lane). This type keeps the build-1 call sites
// (`show(_:kind:undo:)`, `undo()`, `dismiss()`) and forwards them; it draws nothing itself.
// Identifiers stay `shell.toast` / `inbox.undo` so the build-1 UI tests keep finding them.
//
// v2 (plan package 0a): where the toast shows is the center's `placement` (`.top` in the rental
// chip's slot while a hero screen is on screen, `.bottom` elsewhere), and every toast is announced
// to VoiceOver by the center. Callers here never choose a placement themselves.

@MainActor
final class AppToastCenter {
    static let shared = AppToastCenter()

    /// The shared queue (tests may inject their own).
    var center: LHToastCenter = .shared
    /// DEBUG capture hooks set this to hold a toast on screen; nil uses the toast's own timing.
    var undoWindow: TimeInterval?
    /// Where the next toast shows (read-only; hero screens claim `.top` through `LHToastChipSlot`).
    var placement: LHToastPlacement { center.placement }
    /// The toast this facade last queued (so `dismiss()` never closes someone else's toast).
    private(set) var lastSpecId: UUID?

    func show(_ message: String, kind: InboxToast.Kind = .success, undo: (() -> Void)? = nil) {
        let mapped: LHToastSpec.Kind
        switch kind {
        case .success: mapped = .success
        case .neutral: mapped = .neutral
        case .problem: mapped = .problem
        }
        let spec = LHToastSpec(
            kind: mapped,
            message: message,
            actionTitle: undo == nil ? nil : String(localized: "Undo"),
            identifier: "shell.toast",
            actionIdentifier: "inbox.undo",
            holdSeconds: undoWindow
        )
        lastSpecId = center.show(spec, action: undo).id
    }

    /// Runs the Undo of the toast on screen, if it is ours.
    func undo() {
        guard let id = lastSpecId, center.current?.id == id else { return }
        center.performAction()
    }

    /// Closes our toast if it is on screen.
    func dismiss() {
        guard let id = lastSpecId, center.current?.id == id else { return }
        center.dismissCurrent()
    }
}
