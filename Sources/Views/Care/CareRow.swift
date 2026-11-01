import SwiftUI

// MARK: - One care item (2.3, package B)
//
// A browse row (standard §1.4): a slate glyph in a 36pt tile, the task, a "when" line and the
// chevron. The whole row is the target (2.3 amendment 2): an open item opens Log time with the
// rental and the kind filled in; a done item (§1.4a) shows `LHRow.DoneTile` and "Logged 1h · Oct 4"
// and opens what was logged. Never a confirm row: no 22pt circle, no hours, no button inside.

struct CareRow: View {
    let item: CarePlanItem
    var action: () -> Void

    var body: some View {
        LHRow.Browse(title: item.task.title, meta: item.meta, action: action) {
            if item.isDone {
                LHRow.DoneTile()
            } else {
                LHRowGlyph(systemImage: item.task.symbol, tint: .informational)
            }
        }
        .accessibilityHint(item.isDone ? CareText.doneHint : CareText.openHint)
        .accessibilityIdentifier("care.row.\(item.id)")
    }
}

/// Rows in one grouped container with hairline dividers (§1.1).
struct CareRowGroup: View {
    let items: [CarePlanItem]
    var onPage = false
    var onTap: (CarePlanItem) -> Void

    var body: some View {
        LHRowGroup(onPage: onPage) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                CareRow(item: item) { onTap(item) }
            }
        }
    }
}

/// What a care row does when tapped: an open item opens Log time prefilled (How long empty); a
/// done item opens the entry that was logged.
enum CareAction {
    static func open(_ item: CarePlanItem, rental: RentalProperty, showEntry: (UUID) -> Void) {
        if let done = item.done {
            showEntry(done.entryID)
        } else {
            NotificationCenter.default.post(name: .openLogSheet, object: LogSheetRoute.care(CarePrefill.make(task: item.task, rental: rental)))
        }
    }
}
