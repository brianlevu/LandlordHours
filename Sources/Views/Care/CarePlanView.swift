import SwiftUI

// MARK: - Care plan: one rental's seasonal checklist (2.3, package B; frames c2, c3)
//
// Pushed from Today's "See plan". A collection screen (`lhTabScreen`, Fraunces title, back) on the
// canvas: "This season · Fall", then "Between stays" for short stays, then the next two seasons,
// each one grouped container of `CareRow`s. Under them one footnote says what the plan was picked
// for and the rule: "Log it when it's done. You set the hours." Nothing here adds hours.

struct CarePlanView: View {
    let rentalID: UUID
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var doneLog = CareDoneLog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shownEntry: UUID?

    private var rental: RentalProperty? { viewModel.properties.first { $0.id == rentalID } }

    var body: some View {
        Group {
            if let rental {
                content(rental, plan: CarePlan.make(rental: rental, logs: doneLog.logs(entries: viewModel.timeEntries),
                                                    now: CareClock.now(), climate: CareClock.climateOverride))
            } else {
                Color.clear
            }
        }
        .background { LHCanvas() }
        .hidesAppTabBar()
        .navigationDestination(item: $shownEntry) { id in
            if let entry = viewModel.timeEntries.first(where: { $0.id == id }) {
                TimeEntryDetailView(entry: entry)
            }
        }
        .accessibilityIdentifier("care.screen")
    }

    private func content(_ rental: RentalProperty, plan: CarePlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                ForEach(plan.sections) { section in
                    VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                        LHSectionHeader(section.title)
                            .padding(.horizontal, 4)
                        CareRowGroup(items: section.items) { item in
                            CareAction.open(item, rental: rental) { shownEntry = $0 }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("care.section.\(section.id)")
                }
                LHFootnote(plan.footnote)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("care.footnote")
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .lhTabScreen(CareText.planTitle, subtitle: CareText.planSubtitle(rental.name, plan.basis),
                     back: LHBackAction(label: CareText.back, identifier: "care.back") { dismiss() })
    }
}

/// The care plan's "now" and, in DEBUG captures, a climate override. Release reads the real clock.
enum CareClock {
    static func now() -> Date {
        #if DEBUG
        return InboxClock.now()
        #else
        return Date()
        #endif
    }

    /// `-LHCareClimate snowy|wet|hotDry|humid|general` (DEBUG only): the plan's climate for every rental.
    static var climateOverride: CareClimate? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHCareClimate"), args.indices.contains(i + 1) else { return nil }
        return CareClimate(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }
}
