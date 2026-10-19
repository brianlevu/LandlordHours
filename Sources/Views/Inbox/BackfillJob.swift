import Foundation
import SwiftUI

// MARK: - Backfill scanning seam

struct BackfillScanOutcome: Equatable {
    var access: CalendarAccess
    /// Newly found pending items (for the count; the list reads the store).
    var foundCount: Int
    /// Stopped before finishing: nothing counts as done, the backfill can run again.
    var cancelled = false
}

/// Runs the day-1 90-day scan. Production: WP1's coordinator + WP2's `classifyBatch`.
///
/// WP-L: the scan streams. `found` is called on the main actor with each batch of items as soon
/// as they are in the profile's inbox store, so the Inbox can show them while the scan runs.
protocol BackfillScanning {
    @MainActor func scan(
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
        found: @escaping @MainActor ([Suggestion]) -> Void
    ) async -> BackfillScanOutcome
}

/// The real scan: calendar → classifier chain (batch, with progress) → the profile's inbox, one
/// suggestion at a time.
struct CalendarBackfillScanner: BackfillScanning {
    let store: SuggestionStore
    let properties: [RentalProperty]
    let entries: [TimeEntry]

    @MainActor func scan(
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
        found: @escaping @MainActor ([Suggestion]) -> Void
    ) async -> BackfillScanOutcome {
        let coordinator = CalendarCaptureCoordinator(
            detector: CalendarDetector(source: EventKitCalendarSource()),
            store: store
        )
        let result = await coordinator.scanBackfillBatched(
            chain: .forStore(store),
            properties: properties,
            entries: entries,
            progress: progress,
            onIngest: found
        )
        return BackfillScanOutcome(access: result.access, foundCount: result.added.count, cancelled: result.cancelled)
    }
}

// MARK: - The job

/// The day-1 90-day look-back, running in the background (WP-L). It is not tied to any screen:
/// the user can leave the Inbox, use the app, and come back to live progress. Suggestions stream
/// into the inbox as they are classified. The house reveal plays once when it finishes.
///
/// States: idle → scanning(completed, total) → finished(found) | blocked(access) | cancelled.
/// Cancel is always available while scanning. A cancelled or blocked run is never marked
/// complete (WP3), so the look-back can run again; suggestions already shown stay in the inbox
/// (nothing counts until confirmed, and a re-run updates them in place by source key).
@MainActor
final class BackfillJob: ObservableObject {
    static let shared = BackfillJob()

    enum Phase: Equatable {
        case idle
        case scanning(completed: Int, total: Int)
        case finished(found: Int)
        case blocked(CalendarAccess)
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    /// Suggestions this run has put in the inbox so far.
    @Published private(set) var foundCount = 0
    /// Their proposed hours (suggestions, not records).
    @Published private(set) var foundHours: Double = 0

    /// Called on the main actor after each batch of streamed items (default: tells the inbox and
    /// tab badge to reload).
    var onItems: @MainActor ([Suggestion]) -> Void
    /// Called once when a run finishes with full access (default: queues the house reveal).
    var onFinished: @MainActor (_ foundCount: Int, _ foundHours: Double) -> Void
    /// Marks the day-1 backfill done for the active profile (default: `CaptureOptIn`).
    var markCompleted: @MainActor () -> Void

    private var task: Task<Void, Never>?
    private var runID = UUID()

    init(
        onItems: @escaping @MainActor ([Suggestion]) -> Void = { _ in
            NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
        },
        onFinished: @escaping @MainActor (Int, Double) -> Void = { count, hours in
            TodayHouseEvents.shared.backfillFinished(foundHours: hours, suggestionCount: count)
        },
        markCompleted: @escaping @MainActor () -> Void = { CaptureOptIn.markBackfillCompleted() }
    ) {
        self.onItems = onItems
        self.onFinished = onFinished
        self.markCompleted = markCompleted
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    /// Starts a run unless one is already scanning (a second tap never starts a second scan).
    func start(_ scanner: BackfillScanning) {
        guard !isScanning else { return }
        let id = UUID()
        runID = id
        foundCount = 0
        foundHours = 0
        phase = .scanning(completed: 0, total: 0)
        task = Task { [weak self] in
            await self?.run(scanner, id: id)
        }
    }

    /// Stops a scan in flight. Marks nothing done; the inbox offers to run it again.
    func cancel() {
        guard isScanning else { return }
        task?.cancel()
        runID = UUID()
        phase = .cancelled
    }

    /// Profile switch / sign-out: stop and forget (the next profile starts clean).
    func reset() {
        task?.cancel()
        task = nil
        runID = UUID()
        phase = .idle
        foundCount = 0
        foundHours = 0
    }

    /// The header's "Not now" after a stop: hide it until the next run.
    func acknowledge() {
        switch phase {
        case .cancelled, .blocked, .finished: phase = .idle
        default: break
        }
    }

    /// Tests: wait for the current run to end.
    func waitUntilDone() async {
        await task?.value
    }

    private func run(_ scanner: BackfillScanning, id: UUID) async {
        let outcome = await scanner.scan(
            progress: { [weak self] progress in
                guard let self, self.runID == id, self.isScanning else { return }
                self.phase = .scanning(completed: progress.completed, total: progress.total)
            },
            found: { [weak self] items in
                guard let self, self.runID == id, !items.isEmpty else { return }
                self.foundCount += items.count
                self.foundHours += items.reduce(0) { $0 + ($1.proposedHours ?? 0) }
                self.onItems(items)
            }
        )
        // A cancel or reset already moved on; this run's ending changes nothing.
        guard runID == id else { return }
        if outcome.cancelled || Task.isCancelled {
            phase = .cancelled
            return
        }
        guard outcome.access == .fullAccess else {
            phase = .blocked(outcome.access)
            return
        }
        // Only a finished scan counts as the day-1 backfill.
        markCompleted()
        phase = .finished(found: foundCount)
        onItems([])
        onFinished(foundCount, foundHours)
    }
}
