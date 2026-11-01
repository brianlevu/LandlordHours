import Foundation

// MARK: - Care items that are due (2.3 step-0 seam; owner: package B; read by package D)
//
// Package B implements `CareDueSource` from its climate- and type-aware catalog and sets
// `CareDue.source` at launch. Package D's "Care plan" nudge reads it and never imports B's views.
// Until B lands, the stub reports nothing, so no care nudge can fire.

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

enum CareDue {
    static var source: CareDueSource = CareDueSourceStub()
}
