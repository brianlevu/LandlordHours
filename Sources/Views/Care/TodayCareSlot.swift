import SwiftUI

// MARK: - Today › "This season" (2.3, package B; frames c1, t1)
//
// Under the Learn slot, far from the pace line: "This season · <rental>" with "See plan", the 3 most
// timely items of that rental's care plan as browse rows, and one quiet line: "Log it when it's
// done. You set the hours." A row opens Log time with the rental and kind filled in (How long
// empty); "See plan" pushes `CarePlanView`. The care plan is Pro (`ProFeature.carePlan`): a free
// person sees one blurred row under the standard row lock, which opens the paywall.
//
// The rental: the one Today is focused on; with one rental, that one; on "All rentals", the rental
// with the most hours this year. This slot owns its padding and keeps `CareDue`'s snapshot current
// for package D's care nudge.

struct TodayCareSlot: View {
    /// The rental Today is focused on (nil with one rental, or "All").
    let rentalID: UUID?

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var entitlements = EntitlementStore.shared
    @ObservedObject private var doneLog = CareDoneLog.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The rental whose plan is pushed.
    @State private var planRental: UUID?
    @State private var shownEntry: UUID?

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var rental: RentalProperty? {
        Self.rental(for: rentalID, properties: viewModel.properties, entries: viewModel.timeEntries, now: CareClock.now())
    }

    var body: some View {
        Group {
            if let rental {
                let logs = doneLog.logs(entries: viewModel.timeEntries)
                let plan = CarePlan.make(rental: rental, logs: logs, now: CareClock.now(), climate: CareClock.climateOverride)
                if !plan.todayItems.isEmpty {
                    Group {
                        if entitlements.plan.allows(.carePlan) {
                            section(rental, plan: plan)
                        } else {
                            locked(rental, plan: plan)
                        }
                    }
                    .padding(.horizontal, LHMetrics.gutter)
                    .padding(.top, LHMetrics.sectionGap)
                    .id("today.section.care")
                }
            }
        }
        .navigationDestination(item: $planRental) { id in CarePlanView(rentalID: id) }
        .navigationDestination(item: $shownEntry) { id in
            if let entry = viewModel.timeEntries.first(where: { $0.id == id }) { TimeEntryDetailView(entry: entry) }
        }
        .task(id: snapshotKey) {
            doneLog.reload()
            #if DEBUG
            CareDebugSeed.applyIfNeeded(app: viewModel, openPlan: { planRental = $0 })
            #endif
            CareDue.update(rentals: viewModel.properties, logs: doneLog.logs(entries: viewModel.timeEntries))
        }
    }

    /// Changes whenever the rentals, the entries or the care links change (refreshes `CareDue`).
    private var snapshotKey: String {
        let rentals = viewModel.properties.map { "\($0.id.uuidString)\($0.propertyType.rawValue)\($0.address)" }.joined()
        var hours = 0.0, dates = 0.0
        for entry in viewModel.timeEntries {
            hours += entry.hours
            dates += entry.date.timeIntervalSinceReferenceDate
        }
        return "\(rentals)|\(viewModel.timeEntries.count)|\(hours)|\(dates)|\(doneLog.records.count)"
    }

    // MARK: Pro

    private func section(_ rental: RentalProperty, plan: CarePlan) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(CareText.todayTitle(rental.name), onPage: true,
                            trailingTitle: CareText.seePlan, trailingAction: { planRental = rental.id })
                .padding(.horizontal, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.care.header")
            CareRowGroup(items: plan.todayItems, onPage: true) { item in
                CareAction.open(item, rental: rental) { shownEntry = $0 }
            }
            Text(CareText.rule)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .accessibilityIdentifier("today.care.rule")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.care")
    }

    // MARK: Free

    /// The standard row lock: one blurred care row, what Pro adds, what stays free, "Unlock Pro".
    /// At accessibility sizes the ghost row is left out so the lock stays one item's share (§2 D2).
    private func locked(_ rental: RentalProperty, plan: CarePlan) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(CareText.todayTitle(rental.name), onPage: true)
                .padding(.horizontal, 4)
            LHRowGroup(onPage: true) {
                LockedPreview(
                    size: .row,
                    // Placeholder until package A adds `LockEntry.carePlan` (build plan §2, integration order).
                    entry: .settingsPro,
                    line: CareText.lockLine,
                    keeps: dynamicTypeSize.isAccessibilitySize ? "" : CareText.lockKeeps,
                    surface: colors.backgroundSecondary,
                    onUnlock: { ProPaywallPresenter.shared.present(entry: .settingsPro) }
                ) {
                    if !dynamicTypeSize.isAccessibilitySize, let first = plan.todayItems.first {
                        CareRow(item: first) {}
                    }
                }
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.care.locked")
    }

    // MARK: Which rental

    /// The focused rental; the only rental; else the rental with the most hours this year (the
    /// first one on a tie or with no hours).
    static func rental(for focused: UUID?, properties: [RentalProperty], entries: [TimeEntry], now: Date,
                       calendar: Calendar = .current) -> RentalProperty? {
        if let focused, let match = properties.first(where: { $0.id == focused }) { return match }
        guard properties.count > 1 else { return properties.first }
        let year = calendar.component(.year, from: now)
        var hours: [UUID: Double] = [:]
        for entry in entries where calendar.component(.year, from: entry.date) == year {
            hours[entry.propertyId, default: 0] += entry.hours
        }
        return properties.enumerated().max { a, b in
            let ha = hours[a.element.id] ?? 0, hb = hours[b.element.id] ?? 0
            return ha == hb ? a.offset > b.offset : ha < hb
        }?.element
    }
}

#if DEBUG
// MARK: - DEBUG launch hooks for the care plan (UI tests and frame captures; compiled out of Release)
//
//   -LHCareSeed hifi        the approved frames' data on top of the Today seed (`-LHTodayHours`):
//                           Pine Cabin gets a Portland, OR address (wet winters) and a 1h
//                           "Swap the furnace filter" log on Oct 4 (split off that day's entry, so
//                           the total is unchanged); with `-LHCareSeed hifi-str` a short-stay
//                           "Lakeside A-Frame" (Lake Placid, NY: snowy winters) with a 30m
//                           "Check the heat tape" log on Oct 12 is added too.
//   -LHCarePro              Pro before Today draws (the care plan is Pro)
//   -LHCareOpen plan|plan-str|log
//                           1.2 s after Today appears: push Pine Cabin's plan, push Lakeside's,
//                           or open Log time from the first open item
//   -LHCareHistory 1.33,1,2 add own past logs of the first open item (hours, a year apart, newest
//                           first) so the "Last time" and "Typical" chips show
//   -LHCareClimate <c>      the plan's climate for every rental (see `CareClock`)
@MainActor
enum CareDebugSeed {
    private static var didApply = false

    static func value(_ flag: String) -> String? { InboxDebugSeed.value(after: flag) }

    static func applyIfNeeded(app: AppViewModel, openPlan: @escaping (UUID) -> Void) {
        guard !didApply else { return }
        didApply = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LHCarePro") { SubscriptionManager.shared.unlockPro() }
        if let seed = value("-LHCareSeed") { seedHifi(app: app, shortStay: seed == "hifi-str") }
        if let raw = value("-LHCareHistory") { seedHistory(app: app, hours: raw.split(separator: ",").compactMap { Double($0) }) }
        guard let open = value("-LHCareOpen") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            switch open {
            case "plan":
                if let rental = TodayCareSlot.rental(for: nil, properties: app.properties, entries: app.timeEntries, now: CareClock.now()) {
                    openPlan(rental.id)
                }
            case "plan-str":
                if let lakeside = app.properties.first(where: { $0.name == "Lakeside A-Frame" }) { openPlan(lakeside.id) }
            case "log":
                if let rental = TodayCareSlot.rental(for: nil, properties: app.properties, entries: app.timeEntries, now: CareClock.now()),
                   let item = plan(app: app, rental: rental).todayItems.first(where: { !$0.isDone }) {
                    CareAction.open(item, rental: rental) { _ in }
                }
            default: break
            }
        }
    }

    private static func plan(app: AppViewModel, rental: RentalProperty) -> CarePlan {
        CarePlan.make(rental: rental, logs: CareDoneLog.shared.logs(entries: app.timeEntries), now: CareClock.now(),
                      climate: CareClock.climateOverride)
    }

    private static func seedHifi(app: AppViewModel, shortStay: Bool) {
        let wasSuppressed = app.suppressCelebrations
        app.suppressCelebrations = true
        defer { app.suppressCelebrations = wasSuppressed }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: CareClock.now())
        guard let pineIndex = app.properties.firstIndex(where: { $0.name == "Pine Cabin" }) ?? app.properties.indices.first else { return }
        app.properties[pineIndex].address = "12 Pine Rd, Portland, OR"
        let pine = app.properties[pineIndex].id
        if let oct4 = calendar.date(from: DateComponents(year: year, month: 10, day: 4, hour: 10)) {
            let link = split(app: app, rental: pine, day: oct4, hours: 1)
            CareDoneLog.shared.record(task: "furnaceFilter", entry: link)
        }
        if shortStay, !app.properties.contains(where: { $0.name == "Lakeside A-Frame" }) {
            app.addProperty(name: "Lakeside A-Frame", address: "3 Shore Rd, Lake Placid, NY", type: .str)
            if let lakeside = app.properties.first(where: { $0.name == "Lakeside A-Frame" })?.id,
               let oct12 = calendar.date(from: DateComponents(year: year, month: 10, day: 12, hour: 10)) {
                let entry = TimeEntry(propertyId: lakeside, participant: .selfParticipant, category: .repairs,
                                      hours: 0.5, date: oct12, notes: "Checked the heat tape on the pipes")
                app.timeEntries.append(entry)
                CareDoneLog.shared.record(task: "heatTape", entry: entry.id)
            }
        }
        app.saveData()
    }

    /// Takes `hours` off that day's entry at the rental (if any) and logs them as their own entry,
    /// so the year's total stays the same. Returns the new entry's id.
    private static func split(app: AppViewModel, rental: UUID, day: Date, hours: Double) -> UUID {
        let calendar = Calendar.current
        if let i = app.timeEntries.firstIndex(where: { $0.propertyId == rental && calendar.isDate($0.date, inSameDayAs: day) && $0.hours > hours }) {
            app.timeEntries[i].hours -= hours
        }
        let entry = TimeEntry(propertyId: rental, participant: .selfParticipant, category: .repairs, hours: hours, date: day,
                              notes: "Swapped the furnace filter")
        app.timeEntries.append(entry)
        return entry.id
    }

    /// Past logs of the first open item, a year apart, so the chips have history to show.
    private static func seedHistory(app: AppViewModel, hours: [Double]) {
        let now = CareClock.now()
        guard let rental = TodayCareSlot.rental(for: nil, properties: app.properties, entries: app.timeEntries, now: now),
              let item = plan(app: app, rental: rental).todayItems.first(where: { !$0.isDone }) else { return }
        let wasSuppressed = app.suppressCelebrations
        app.suppressCelebrations = true
        defer { app.suppressCelebrations = wasSuppressed }
        for (i, h) in hours.enumerated() {
            guard let date = Calendar.current.date(byAdding: .year, value: -(i + 1), to: now) else { continue }
            let entry = TimeEntry(propertyId: rental.id, participant: .selfParticipant, category: item.task.kind,
                                  hours: h, date: date, notes: item.task.doneNote)
            app.timeEntries.append(entry)
            CareDoneLog.shared.record(task: item.task.id, entry: entry.id)
        }
        app.saveData()
    }
}
#endif
