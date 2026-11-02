import SwiftUI

#if DEBUG
// MARK: - 2.3.1 "quiet" design sandbox (DEBUG only; never ships)
//
// Mockups for Dina's ask: the event log (Records and the record page) shows too much text and needs
// progressive disclosure. Same fixed sample data for the BEFORE frames (the real HistoryView,
// TimeEntryDetailView, TaxProfileView and RemindersSettingsView) and the AFTER sandbox views, so a
// board compares like with like. Nothing here is feature code; strings are literals on purpose.
//
//   -LHQuiet <scene>
//     before-records · before-record · before-filing · before-reminders
//     a-records · a-record · a-history          Direction A: quiet list, details one tap away
//     b-records · b-records-open · b-record     Direction B: open in place
//     c-records · c-month                       Direction C: this month open, earlier months folded
//     after-reminders · after-reminders-open · after-filing · after-filing-sheet

enum QuietLaunch {
    static var current: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHQuiet"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}

/// Fixed sample data: three rentals and 24 records from June to late October, relative to today so
/// month headers stay current. Names are store-art names, never the owner's real streets.
enum QuietSeed {
    static let pine = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
    static let oak = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
    static let delaney = UUID(uuidString: "11111111-0000-0000-0000-000000000003")!

    static let properties: [RentalProperty] = [
        RentalProperty(id: pine, name: "Pine Cabin", address: "12 Pine Rd", propertyType: .str),
        RentalProperty(id: oak, name: "Oak Street Duplex", address: "40 Oak St", propertyType: .ltr),
        RentalProperty(id: delaney, name: "Delaney Ct", address: "7 Delaney Ct", propertyType: .ltr)
    ]

    static func name(_ id: UUID) -> String { properties.first { $0.id == id }?.name ?? "No rental" }

    /// The record the record-page scenes open: found in the calendar, confirmed, then edited, with a
    /// two-line note. The worst case for text on the record page.
    static let featuredId = UUID(uuidString: "22222222-0000-0000-0000-000000000001")!

    private static func day(_ offset: Int, hour: Int = 10) -> Date {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: hour))!
        return cal.date(byAdding: .day, value: -offset, to: base)!
    }

    static var entries: [TimeEntry] {
        var list: [TimeEntry] = []
        func add(_ offset: Int, _ rental: UUID, _ cat: ActivityCategory, _ hours: Double, _ note: String,
                 who: Participant = .selfParticipant, calendar: Bool = false, id: UUID = UUID()) {
            var e = TimeEntry(id: id, propertyId: rental, participant: who, category: cat, hours: hours,
                              date: day(offset), notes: note,
                              importSource: calendar ? "calendar" : nil,
                              detectedAt: calendar ? day(offset, hour: 17) : nil,
                              confirmedAt: calendar ? day(offset, hour: 19) : nil)
            e.createdAt = calendar ? day(offset, hour: 19) : day(offset, hour: 20)
            e.modifiedAt = id == featuredId ? day(offset - 1, hour: 8) : e.createdAt
            list.append(e)
        }
        add(1, pine, .repairs, 2, "Fixed the sink and the kitchen tap\nThe trap was cracked; new one from the hardware store.",
            calendar: true, id: featuredId)
        add(2, oak, .leasing, 1, "Showing for the upstairs unit", calendar: true)
        add(3, pine, .travel, 1.5, "Drove up to meet the plumber")
        add(3, delaney, .management, 0.5, "Called the tenant about rent", who: .spouse)
        add(5, oak, .bookkeeping, 1, "October books and receipts")
        add(6, pine, .repairs, 3, "Cleared the gutters", calendar: true)
        add(8, delaney, .repairs, 2, "Replaced the smoke alarms")
        add(10, oak, .investing, 1, "Looked at a refinance quote")
        add(12, pine, .management, 1, "Turnover clean check", who: .spouse)
        add(15, delaney, .leasing, 1.5, "Lease renewal with Sam", calendar: true)
        add(19, pine, .renovations, 4, "Painted the deck")
        add(23, oak, .repairs, 2, "Furnace service")
        add(33, pine, .repairs, 2.5, "Fixed the porch step")
        add(36, oak, .management, 1, "HOA meeting", calendar: true)
        add(41, delaney, .bookkeeping, 1, "September books")
        add(47, pine, .travel, 2, "Drove up for the inspection")
        add(55, oak, .leasing, 1, "Showing for the downstairs unit")
        add(66, pine, .repairs, 3, "Replaced the water heater valve")
        add(72, delaney, .management, 1, "Rent follow-ups", who: .spouse)
        add(84, oak, .repairs, 2, "Patched the fence")
        add(96, pine, .renovations, 5, "New bathroom fan")
        add(110, delaney, .leasing, 2, "New tenant move-in")
        add(118, oak, .bookkeeping, 1, "Q2 books")
        add(131, pine, .repairs, 1.5, "Checked the roof after the storm")
        return list
    }

    static var featured: TimeEntry { entries.first { $0.id == featuredId }! }

    /// Puts the sample into the live model and the shared managers so the real views render it.
    @MainActor static func apply(to viewModel: AppViewModel) {
        viewModel.properties = properties
        viewModel.timeEntries = entries
        TaxProfileManager.shared.spouseTracking = true
        TaxProfileManager.shared.filingStatus = .marriedJoint
        TaxProfileManager.shared.taxYear = 2026
    }
}

/// The sandbox root: the native tab shell (Records selected) for list scenes, a bare stack for
/// pushed settings scenes. Same seed for BEFORE and AFTER.
struct QuietRoot: View {
    let scene: String
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var seeded = false

    var body: some View {
        Group {
            if seeded { content } else { Color.clear }
        }
        .task {
            QuietSeed.apply(to: viewModel)
            seeded = true
        }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case "before-records": QuietShell { HistoryView() }
        case "before-record": QuietShell { TimeEntryDetailView(entry: QuietSeed.featured) }
        case "before-filing": NavigationStack { TaxProfileView() }
        case "before-reminders": NavigationStack { RemindersSettingsView() }
        case "a-records": QuietShell { QuietRecordsList(direction: .a) }
        case "a-record": QuietShell { QuietRecordPage(entry: QuietSeed.featured, style: .history) }
        case "a-history": QuietShell { QuietHistoryPage(entry: QuietSeed.featured) }
        case "b-records": QuietShell { QuietRecordsList(direction: .b) }
        case "b-records-open": QuietShell { QuietRecordsList(direction: .b, openId: QuietSeed.featuredId) }
        case "b-record": QuietShell { QuietRecordPage(entry: QuietSeed.featured, style: .inline, inlineOpen: true) }
        case "c-records": QuietShell { QuietRecordsList(direction: .c) }
        case "c-month": QuietShell { QuietMonthPage(monthOffset: 1) }
        case "after-reminders": NavigationStack { QuietRemindersView() }
        case "after-reminders-open": NavigationStack { QuietRemindersView(sampleOpen: true) }
        case "after-filing": NavigationStack { QuietFilingView() }
        case "after-filing-sheet": NavigationStack { QuietFilingView(showsHalfSheet: true) }
        default: Text("Unknown -LHQuiet scene \(scene)")
        }
    }
}

/// The native tab bar with the shell's five items, Records selected, the scene in a stack.
struct QuietShell<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var tab: ShellItem = .records

    var body: some View {
        TabView(selection: $tab) {
            Tab(ShellItem.today.title, systemImage: ShellItem.today.systemImage, value: ShellItem.today) { Color.clear }
            Tab(ShellItem.inbox.title, systemImage: ShellItem.inbox.systemImage, value: ShellItem.inbox) { Color.clear }
            Tab(ShellItem.records.title, systemImage: ShellItem.records.systemImage, value: ShellItem.records) {
                NavigationStack { content }
            }
            Tab(ShellItem.rentals.title, systemImage: ShellItem.rentals.systemImage, value: ShellItem.rentals) { Color.clear }
            Tab(ShellItem.logTime.title, systemImage: ShellItem.logTime.systemImage, value: ShellItem.logTime, role: .search) { Color.clear }
        }
    }
}
#endif
