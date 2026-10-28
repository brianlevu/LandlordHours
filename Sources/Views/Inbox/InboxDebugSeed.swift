#if DEBUG
import Foundation

// MARK: - DEBUG launch hooks for the inbox (UI tests and frame captures)
//
// `-LHSeedSuggestions inbox|empty|backfill` (with `-LHMockScenario emptyMainTabs`) seeds two
// properties and a known set of suggestions into the profile's inbox:
// - inbox:    items in Today / This week / Earlier, incl. "Not sure", "Might already be logged",
//             a receipt with no hours, and a no-property item;
// - inbox-long: `inbox` plus more days and long titles, so the list scrolls (the pinned bar);
// - inbox-one: a single likely item (no "Confirm N likely");
// - empty:    an empty inbox with calendar suggestions on (`empty-lit`: and hours logged today);
// - backfill: an empty inbox; the backfill scan (fake) finds 22 items with progress.
// Frame hooks: `-LHInboxOpenSheet <key>` opens the confirm sheet for the item whose source key ends
// with <key> (`plumber`, `homedepot`, `call-sam`, `hardware`, `limit-showing`);
// `-LHInboxOpenSetup` opens the capture setup sheet (with `-LHCaptureSetupOn` both switches start
// on, with `-LHCaptureSetupPhase denied` it opens on the denied screen);
// `-LHInboxRunBackfill` starts the look-back (with `-LHHoldBackfillScan` it holds halfway,
// `-LHInboxCancelBackfill` stops it after 2 s, `-LHFakeScanBlocked` blocks it);
// `-LHInboxConfirmLikely` taps "Confirm N likely" 1.5 s after launch (the "Logged 3" toast).
// `-LHFakeCalendar granted|denied` and `-LHFakeNotifications granted|denied` replace the system
// permission prompts in the capture setup flow. Compiled out of Release.
@MainActor
enum InboxDebugSeed {
    static let seedArgument = "-LHSeedSuggestions"
    private static var didApply = false

    static var scenario: String? { value(after: seedArgument) }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    /// `-LHFixedNow 2026-10-16T15:00` pins the inbox clock (local time) for repeatable frames.
    static func pinClockIfRequested() {
        guard let raw = value(after: "-LHFixedNow") else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let fixed = formatter.date(from: raw) else { return }
        InboxClock.now = { fixed }
    }

    static func applyIfNeeded(app: AppViewModel) {
        pinClockIfRequested()
        guard !didApply, let scenario, let userId = UserScope.userId else { return }
        didApply = true
        app.suppressCelebrations = true
        defer { app.suppressCelebrations = false }

        // `limit` / `limit-waiting` (WP-P): a free user at the one-rental limit.
        let atLimit = scenario.hasPrefix("limit")
        if app.properties.isEmpty {
            app.addProperty(name: "Pine Cabin", address: "14 Pine Ridge Rd", type: .str)
            if !atLimit { app.addProperty(name: "Oak Street Duplex", address: "220 Oak St", type: .ltr) }
        }
        TaxProfileManager.shared.spouseTracking = true
        app.activeCelebration = nil

        SuggestionStore.removeAll(forUserId: userId)
        guard let store = AppModelHost.shared.suggestionStore else { return }
        store.pruneResolved(olderThan: .distantFuture)

        switch scenario {
        case "inbox":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
            let items = inboxItems(app: app, now: InboxClock.now())
            store.ingest(items, existingEntries: app.timeEntries)
        case "store":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
            store.ingest(storeItems(app: app, now: InboxClock.now()), existingEntries: app.timeEntries)
        case "inbox-long":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
            let now = InboxClock.now()
            store.ingest(inboxItems(app: app, now: now) + longItems(app: app, now: now), existingEntries: app.timeEntries)
        case "inbox-one":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
            let items = inboxItems(app: app, now: InboxClock.now()).filter { ["plumber", "homedepot", "call-sam"].contains($0.sourceKey.replacingOccurrences(of: "cal:debug-", with: "").replacingOccurrences(of: "rcpt:", with: "")) }
            store.ingest(items, existingEntries: app.timeEntries)
        case "limit", "limit-waiting":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
            let items = limitItems(app: app, now: InboxClock.now())
            store.ingest(items, existingEntries: app.timeEntries)
            if scenario == "limit-waiting" { ProWaitList.shared.add(items[0].sourceKey) }
            else { ProWaitList.shared.remove(items[0].sourceKey) }
        case "empty", "empty-lit":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
            // `empty-lit`: hours logged today at the first rental, so the diorama's windows are lit.
            if scenario == "empty-lit", let pine = app.properties.first?.id,
               !app.timeEntries.contains(where: { $0.notes == "Lit today" }) {
                app.timeEntries.append(TimeEntry(propertyId: pine, participant: .selfParticipant, category: .repairs,
                                                 hours: 2, date: InboxClock.now(), notes: "Lit today"))
                app.saveData()
            }
        default:
            break
        }
        NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
    }

    // MARK: Fixtures

    private static func hoursAgo(_ hours: Double, from now: Date) -> Date {
        let date = now.addingTimeInterval(-hours * 3600)
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        return Calendar.current.date(from: c) ?? date
    }

    private static func item(
        _ key: String,
        title: String,
        start: Date,
        hours: Double?,
        property: UUID?,
        category: ActivityCategory?,
        confidence: Double,
        kind: Suggestion.Kind = .calendar,
        backfill: Bool = false
    ) -> Suggestion {
        Suggestion(
            sourceKey: kind == .receipt ? "rcpt:\(key)" : "cal:debug-\(key)",
            kind: kind,
            detectedAt: start.addingTimeInterval((hours ?? 0) * 3600),
            start: start,
            end: hours.map { start.addingTimeInterval($0 * 3600) },
            title: title,
            externalId: kind == .calendar ? "debug-\(key)" : nil,
            containerId: kind == .calendar ? "debug-calendar" : nil,
            proposedPropertyId: property,
            proposedCategory: category,
            proposedHours: hours,
            hoursBasis: hours == nil ? .none : .scheduled,
            confidence: confidence,
            tier: .rules,
            evidence: [ClassifierThresholds.landlordSignalEvidence],
            isBackfill: backfill
        )
    }

    static func inboxItems(app: AppViewModel, now: Date) -> [Suggestion] {
        let pine = app.properties.first { $0.name == "Pine Cabin" }?.id ?? app.properties.first?.id
        let oak = app.properties.first { $0.name == "Oak Street Duplex" }?.id ?? app.properties.last?.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // Today: ends before now so it is visible.
        let plumberStart = max(today, hoursAgo(3, from: now))
        let plumberHours = min(2, max(0.5, now.timeIntervalSince(plumberStart) / 3600 - 0.25))
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        // A hand-logged entry on the same day and property makes "Hardware run" look logged.
        let hardwareStart = day(4, 10)
        if let pine, !app.timeEntries.contains(where: { $0.notes == "Picked up supplies" }) {
            app.timeEntries.append(TimeEntry(propertyId: pine, participant: .selfParticipant, category: .travel,
                                             hours: 1, date: hardwareStart, notes: "Picked up supplies"))
            app.saveData()
        }

        return [
            item("plumber", title: "Plumber", start: plumberStart, hours: (plumberHours * 4).rounded() / 4,
                 property: pine, category: .repairs, confidence: 0.94),
            item("showing", title: "Showing", start: day(2, 17, 30), hours: 1,
                 property: oak, category: .leasing, confidence: 0.9),
            item("homedepot", title: "Home Depot", start: day(3, 13), hours: nil,
                 property: pine, category: .repairs, confidence: 0.8, kind: .receipt),
            item("call-sam", title: "Call with Sam", start: day(3, 16), hours: 0.5,
                 property: nil, category: .management, confidence: 0.42),
            item("hardware", title: "Hardware run", start: hardwareStart, hours: 1,
                 property: pine, category: .travel, confidence: 0.72),
            item("turnover", title: "Turnover clean", start: day(5, 11), hours: 3,
                 property: pine, category: .management, confidence: 0.86),
            item("inspection", title: "Annual inspection", start: day(12, 9), hours: 1.5,
                 property: oak, category: .legal, confidence: 0.91, backfill: true),
            item("hoa", title: "HOA meeting", start: day(20, 18), hours: 2,
                 property: oak, category: .management, confidence: 0.66, backfill: true),
        ]
    }

    /// App Store captures: rental work only, every item with a rental and hours.
    static func storeItems(app: AppViewModel, now: Date) -> [Suggestion] {
        let pine = app.properties.first { $0.name == "Pine Cabin" }?.id ?? app.properties.first?.id
        let oak = app.properties.first { $0.name == "Oak Street Duplex" }?.id ?? app.properties.last?.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        return [
            item("plumber", title: "Plumber", start: day(0, 7), hours: 2, property: pine, category: .repairs, confidence: 0.95),
            item("showing", title: "Showing", start: day(2, 17, 30), hours: 1, property: oak, category: .leasing, confidence: 0.92),
            item("gutters", title: "Gutter cleaning", start: day(5, 9), hours: 2, property: oak, category: .repairs, confidence: 0.9),
            item("inspection", title: "Smoke alarm check", start: day(6, 10), hours: 1, property: pine, category: .repairs, confidence: 0.88),
            item("lease", title: "Lease signing", start: day(9, 18), hours: 1, property: oak, category: .leasing, confidence: 0.91),
        ]
    }

    /// More days and long titles, so the card runs past the first screen.
    static func longItems(app: AppViewModel, now: Date) -> [Suggestion] {
        let pine = app.properties.first { $0.name == "Pine Cabin" }?.id ?? app.properties.first?.id
        let oak = app.properties.first { $0.name == "Oak Street Duplex" }?.id ?? app.properties.last?.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        return [
            item("lease-call", title: "Tenant call about the lease renewal", start: day(1, 9), hours: 1,
                 property: oak, category: .management, confidence: 0.88),
            item("gutters", title: "Gutter cleaning", start: day(1, 14), hours: 2,
                 property: pine, category: .repairs, confidence: 0.92),
            item("rent-review", title: "Rent review", start: day(4, 11), hours: 1.5,
                 property: oak, category: .bookkeeping, confidence: 0.87),
            item("smoke", title: "Smoke alarm check", start: day(6, 10), hours: 0.5,
                 property: pine, category: .repairs, confidence: 0.9),
            item("permit", title: "City permit office", start: day(8, 13), hours: 1,
                 property: oak, category: .legal, confidence: 0.84),
            item("paint", title: "Paint touch-up", start: day(9, 9), hours: 3,
                 property: pine, category: .renovations, confidence: 0.9),
        ]
    }

    /// A showing at a rental the user doesn't have (no property), plus work at Pine Cabin.
    static func limitItems(app: AppViewModel, now: Date) -> [Suggestion] {
        let pine = app.properties.first?.id
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        return [
            item("limit-showing", title: "Showing", start: day(1, 17, 30), hours: 1,
                 property: nil, category: .leasing, confidence: 0.9),
            item("limit-plumber", title: "Plumber", start: day(2, 10), hours: 2,
                 property: pine, category: .repairs, confidence: 0.94),
        ]
    }

    static func backfillItems(app: AppViewModel, now: Date) -> [Suggestion] {
        let ids = app.properties.map(\.id)
        let titles: [(String, ActivityCategory)] = [
            ("Plumber", .repairs), ("Showing", .leasing), ("Turnover clean", .management),
            ("Rent review", .bookkeeping), ("Gutter cleaning", .repairs), ("Lease signing", .leasing),
            ("City permit office", .legal), ("Drive to cabin", .travel), ("Paint touch-up", .renovations),
            ("Tenant call", .management), ("Smoke alarm check", .repairs),
        ]
        let calendar = Calendar.current
        return (0..<22).map { index in
            let (title, listedCategory) = titles[index % titles.count]
            // `-LHBackfillNonCountable`: a look-back that finds only work that never counts
            // (investing, financing, negotiation), for the honest "none count" state.
            let nonCountable: [ActivityCategory] = [.financing, .investing, .contractNegotiation]
            let category = ProcessInfo.processInfo.arguments.contains("-LHBackfillNonCountable")
                ? nonCountable[index % nonCountable.count] : listedCategory
            let base = calendar.date(byAdding: .day, value: -(3 + index * 4), to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(bySettingHour: 9 + index % 8, minute: index % 2 == 0 ? 0 : 30, second: 0, of: base) ?? base
            let confidence = [0.95, 0.9, 0.84, 0.78, 0.71, 0.64, 0.55, 0.45, 0.38][index % 9]
            return item("bf-\(index)", title: title, start: start, hours: [1, 2, 1.5, 0.5, 3][index % 5],
                        // Onboarding scans before the first property exists: no property then.
                        property: index % 6 == 5 || ids.isEmpty ? nil : ids[index % ids.count],
                        category: category, confidence: confidence, backfill: true)
        }
    }

    // MARK: Fake permissions + scan

    static func fakeSetupEnvironment() -> CaptureSetupEnvironment? {
        guard let calendarAnswer = value(after: "-LHFakeCalendar") else { return nil }
        let notifications = value(after: "-LHFakeNotifications") == "granted"
        return CaptureSetupEnvironment(
            requestCalendar: { calendarAnswer == "granted" ? .fullAccess : .denied },
            requestNotifications: { notifications },
            makeScanner: { app, store in DebugBackfillScanner(app: app, store: store) }
        )
    }
}

/// Feeds the fixture backfill through the real store one item at a time, with visible progress
/// (~1.3 s; `-LHBackfillStepMs <ms>` slows it for captures). `-LHHoldBackfillScan` holds it
/// halfway for a minute, with half the items already in the inbox.
struct DebugBackfillScanner: BackfillScanning {
    let app: AppViewModel
    let store: SuggestionStore

    @MainActor func scan(
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
        found: @escaping @MainActor ([Suggestion]) -> Void
    ) async -> BackfillScanOutcome {
        // `-LHFakeScanBlocked`: calendar access went away between the prompt and the scan.
        if ProcessInfo.processInfo.arguments.contains("-LHFakeScanBlocked") {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return BackfillScanOutcome(access: .denied, foundCount: 0)
        }
        let items = InboxDebugSeed.backfillItems(app: app, now: InboxClock.now())
        let holdAtHalf = ProcessInfo.processInfo.arguments.contains("-LHHoldBackfillScan")
        let stepMs = InboxDebugSeed.value(after: "-LHBackfillStepMs").flatMap(UInt64.init) ?? 60
        var addedCount = 0
        for step in 1...items.count {
            try? await Task.sleep(nanoseconds: stepMs * 1_000_000)
            if Task.isCancelled {
                return BackfillScanOutcome(access: .fullAccess, foundCount: addedCount, cancelled: true)
            }
            let added = store.ingest([items[step - 1]], existingEntries: app.timeEntries)
            addedCount += added.count
            if !added.isEmpty { found(added) }
            progress(ClassifierBatchProgress(completed: step, total: items.count))
            if holdAtHalf, step == items.count / 2 {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            if Task.isCancelled {
                return BackfillScanOutcome(access: .fullAccess, foundCount: addedCount, cancelled: true)
            }
        }
        return BackfillScanOutcome(access: .fullAccess, foundCount: addedCount)
    }
}
#endif
