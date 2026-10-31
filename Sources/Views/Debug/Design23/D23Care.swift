import SwiftUI

#if DEBUG
// MARK: - Care plan A (2.3 design sandbox)
//
// Today: "This season · <rental>" with the 3 most timely items, under To confirm, far from the
// pace line, and built as browse rows (a glyph tile, a "when" line, a chevron), never as
// confirm rows (no 22pt circle, no hours). See plan pushes the per-rental checklist. A whole-row
// tap opens Log time prefilled with the item (the rental and kind fill; the hours stay empty).
// Done = the glyph tile turns positive with a checkmark and the line says what was logged.
// Copy rule: "Log it when it's done. You set the hours." No hour estimates anywhere.

enum D23CareRental: Equatable {
    case pine, lakeside

    var name: String {
        switch self {
        case .pine: return "Pine Cabin"
        case .lakeside: return "Lakeside A-Frame"
        }
    }

    /// Rental type and the climate the plan is picked for.
    var basis: String {
        switch self {
        case .pine: return "Long stays · Wet winters"
        case .lakeside: return "Short stays · Snowy winters"
        }
    }

    var footnote: String {
        switch self {
        case .pine: return "Picked for long stays in a place with wet winters. Log it when it’s done. You set the hours."
        case .lakeside: return "Picked for short stays in a place with snowy winters. Log it when it’s done. You set the hours."
        }
    }

    var seasons: [D23CareSeason] {
        switch self {
        case .pine:
            return [
                D23CareSeason(title: "This season · Fall", items: [
                    D23CareItem(title: "Clear the gutters", when: "Before the rains", symbol: "cloud.rain"),
                    D23CareItem(title: "Shut off the outdoor taps", when: "Before the first frost", symbol: "spigot"),
                    D23CareItem(title: "Test smoke and CO alarms", when: "Twice a year · due now", symbol: "sensor"),
                    D23CareItem(title: "Swap the furnace filter", when: "Logged 1h · Oct 4", symbol: "wind", done: true),
                ]),
                D23CareSeason(title: "Winter", items: [
                    D23CareItem(title: "Check under sinks for leaks", when: "After a hard freeze", symbol: "pipe.and.drop"),
                    D23CareItem(title: "Service the water heater", when: "Once a year", symbol: "flame"),
                    D23CareItem(title: "Look in the attic for damp", when: "After a big storm", symbol: "house"),
                ]),
                D23CareSeason(title: "Spring", items: [
                    D23CareItem(title: "Clean the dryer vent", when: "Once a year", symbol: "fan"),
                    D23CareItem(title: "Reseal the tub and windows", when: "When the caulk cracks", symbol: "bathtub"),
                ]),
            ]
        case .lakeside:
            return [
                D23CareSeason(title: "This season · Fall", items: [
                    D23CareItem(title: "Stock ice melt and shovels", when: "Before the first snow", symbol: "snowflake"),
                    D23CareItem(title: "Winterize the hot tub", when: "When guests stop using it", symbol: "thermometer.snowflake"),
                    D23CareItem(title: "Test smoke and CO alarms", when: "Between stays · due now", symbol: "sensor"),
                    D23CareItem(title: "Check the heat tape on pipes", when: "Logged 30m · Oct 12", symbol: "bolt", done: true),
                ]),
                D23CareSeason(title: "Between stays", items: [
                    D23CareItem(title: "Walk through after checkout", when: "Every stay", symbol: "figure.walk"),
                    D23CareItem(title: "Restock the first aid kit", when: "Every few stays", symbol: "cross.case"),
                ]),
                D23CareSeason(title: "Winter", items: [
                    D23CareItem(title: "Clear snow from the roof edge", when: "After heavy snow", symbol: "house"),
                    D23CareItem(title: "Service the furnace", when: "Once a year", symbol: "flame"),
                ]),
            ]
        }
    }

    /// The three most timely open items: what Today shows.
    var todayItems: [D23CareItem] {
        Array((seasons.first?.items ?? []).filter { !$0.done }.prefix(3))
    }
}

struct D23CareSeason: Identifiable {
    let title: String
    let items: [D23CareItem]
    var id: String { title }
}

struct D23CareItem: Identifiable {
    let title: String
    let when: String
    let symbol: String
    var done = false
    var id: String { title }
}

/// One care item: `LHRow.Browse` with an SF glyph in a 36 wash tile (slate for open, the done
/// tile when logged). The whole row is the target.
struct D23CareRow: View {
    let item: D23CareItem
    var action: () -> Void = {}

    var body: some View {
        LHRow.Browse(title: item.title, meta: item.when, action: action) {
            if item.done {
                D23DoneTile()
            } else {
                LHRowGlyph(systemImage: item.symbol, tint: .informational)
            }
        }
        .accessibilityHint(item.done ? "Opens what you logged" : "Opens Log time with this filled in")
        .contextMenu {
            Button { } label: { Label("Log it", systemImage: "plus") }
            Button { } label: { Label("Not for this rental", systemImage: "eye.slash") }
        }
    }
}

// MARK: Today section

struct D23CareTodaySection: View {
    let rental: D23CareRental
    var onSeePlan: () -> Void
    var onItem: (D23CareItem) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let items = rental.todayItems
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            D23TodayHeader(title: "This season · \(rental.name)", trailing: "See plan", action: onSeePlan)
            LHRowGroup(onPage: true) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    D23CareRow(item: item) { onItem(item) }
                }
            }
            Text("Log it when it’s done. You set the hours.")
                .font(.footnote)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.care")
    }
}

// MARK: Care plan (pushed)

struct D23CarePlanView: View {
    let rental: D23CareRental
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                ForEach(rental.seasons) { season in
                    D23Section(title: season.title) {
                        LHRowGroup {
                            ForEach(Array(season.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                                D23CareRow(item: item)
                            }
                        }
                    }
                }
                LHFootnote(rental.footnote)
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhTabScreen("Care plan", subtitle: "\(rental.name) · \(rental.basis)",
                     back: LHBackAction(label: "Back", identifier: "care.back") { dismiss() })
        .hidesAppTabBar()
        .accessibilityIdentifier("care.screen")
    }
}
#endif
