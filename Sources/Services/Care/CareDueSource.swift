import Foundation

// MARK: - Care items that are due (2.3; owner: package B; read by package D)
//
// Package D's "Care plan" nudge reads `CareDue.source` and never imports B's views. The live
// source answers from the same plan Today shows (`CarePlan.make`): this season's open items for one
// rental. It reads a snapshot of the rentals and the care logs that B keeps current
// (`CareDue.update`, called when Today's care slot appears and whenever entries change), so it is
// safe to call off the main thread and never touches the view model.
//
// It answers whatever the plan says. Whether a nudge may fire (opt-in, Pro, quiet hours, one a
// day) is D's call. Before Today has appeared once in this launch the snapshot is empty and the
// source reports nothing, so a cold background wake can never fire a care nudge on stale data.

struct CareDueItem: Identifiable, Equatable, Sendable {
    let id: String
    let rentalID: UUID
    let title: String
    let due: Date
}

protocol CareDueSource {
    func dueItems(for rentalID: UUID, on date: Date) -> [CareDueItem]
}

struct CareDueSourceStub: CareDueSource {
    func dueItems(for rentalID: UUID, on date: Date) -> [CareDueItem] { [] }
}

/// What the live source reads: the rentals and the care logs, as of the last update.
struct CareDueSnapshot: Sendable {
    var rentals: [RentalProperty]
    var logs: [CareLog]

    static let empty = CareDueSnapshot(rentals: [], logs: [])
}

/// The plan's open items for this season, from a snapshot.
struct CarePlanDueSource: CareDueSource {
    let snapshot: @Sendable () -> CareDueSnapshot
    var calendar: Calendar = .current

    func dueItems(for rentalID: UUID, on date: Date) -> [CareDueItem] {
        let snap = snapshot()
        guard let rental = snap.rentals.first(where: { $0.id == rentalID }) else { return [] }
        let plan = CarePlan.make(rental: rental, logs: snap.logs, now: date, calendar: calendar)
        let due = CareSeason.start(of: date, calendar: calendar)
        return plan.dueNow.map { CareDueItem(id: $0.task.id, rentalID: rentalID, title: $0.task.title, due: due) }
    }
}

enum CareDue {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current = CareDueSnapshot.empty

    /// The live source, set at launch (this default) and read by D's care nudge.
    nonisolated(unsafe) static var source: CareDueSource = CarePlanDueSource(snapshot: { CareDue.snapshot })

    static var snapshot: CareDueSnapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Package B keeps the snapshot current (Today's care slot on appear and on every change).
    static func update(rentals: [RentalProperty], logs: [CareLog]) {
        lock.lock(); defer { lock.unlock() }
        current = CareDueSnapshot(rentals: rentals, logs: logs)
    }
}
