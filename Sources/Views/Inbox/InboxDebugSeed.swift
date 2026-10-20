#if DEBUG
import Foundation

// MARK: - DEBUG launch hooks for the inbox (UI tests and frame captures)
//
// `-LHSeedSuggestions inbox|empty|backfill` (with `-LHMockScenario emptyMainTabs`) seeds two
// properties and a known set of suggestions into the profile's inbox:
// - inbox:    items in Today / This week / Earlier, incl. "Not sure", "Might already be logged",
//             a receipt with no hours, and a no-property item;
// - empty:    an empty inbox with calendar suggestions on;
// - backfill: an empty inbox; the backfill scan (fake) finds 22 items with progress.
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

        if app.properties.isEmpty {
            app.addProperty(name: "Pine Cabin", address: "14 Pine Ridge Rd", type: .str)
            app.addProperty(name: "Oak Street Duplex", address: "220 Oak St", type: .ltr)
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
        case "empty":
            CaptureOptIn.recordChoice(calendar: true, eventPrompts: false, userId: userId)
            CaptureOptIn.markBackfillCompleted(userId: userId)
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
            let (title, category) = titles[index % titles.count]
            let base = calendar.date(byAdding: .day, value: -(3 + index * 4), to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(bySettingHour: 9 + index % 8, minute: index % 2 == 0 ? 0 : 30, second: 0, of: base) ?? base
            let confidence = [0.95, 0.9, 0.84, 0.78, 0.71, 0.64, 0.55, 0.45, 0.38][index % 9]
            return item("bf-\(index)", title: title, start: start, hours: [1, 2, 1.5, 0.5, 3][index % 5],
                        property: index % 6 == 5 ? nil : ids[index % max(ids.count, 1)],
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
