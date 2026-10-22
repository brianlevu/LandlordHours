import XCTest
import CloudKit
import UserNotifications
@testable import LandlordHours

// MARK: - Fakes

final class FakeCaptureNotificationCenter: CaptureNotificationCenter {
    var requests: [UNNotificationRequest] = []
    var allowed = true
    private(set) var addCount = 0
    private(set) var removedPending: [String] = []
    private(set) var removedDelivered: [String] = []

    func pendingRequests() async -> [UNNotificationRequest] { requests }

    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func removePending(identifiers: [String]) {
        removedPending += identifiers
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDelivered(identifiers: [String]) { removedDelivered += identifiers }

    func canDeliver() async -> Bool { allowed }

    var captureRequests: [UNNotificationRequest] {
        requests.filter { $0.identifier.hasPrefix(EndOfEventScheduler.identifierPrefix) }
    }

    /// Simulates delivery: fired requests leave the pending list.
    func deliver(before date: Date) {
        requests.removeAll { request in
            guard let fire = request.content.userInfo[EndOfEventScheduler.fireAtKey] as? TimeInterval else { return false }
            return Date(timeIntervalSince1970: fire) <= date
        }
    }
}

final class FakeEventChecker: CaptureEventChecking {
    var result: CaptureEventCheck = .unchanged
    private(set) var checked: [String] = []
    @MainActor func check(_ suggestion: Suggestion) async -> CaptureEventCheck {
        checked.append(suggestion.sourceKey)
        return result
    }
}

final class FakePullGate: InitialPullGating {
    var stateValue: InitialPullState = .completed
    /// What `waitForInitialPull` does: by default the pull doesn't finish in time.
    var onWait: (FakePullGate) -> Bool = { _ in false }
    private(set) var waits = 0

    @MainActor func state(for profileId: String) -> InitialPullState { stateValue }
    @MainActor func waitForInitialPull(profileId: String, timeout: TimeInterval) async -> Bool {
        waits += 1
        return onWait(self)
    }
}

final class FakeFollowUps: CaptureFollowUpPosting {
    private(set) var posted: [(CaptureFollowUp, String)] = []
    @MainActor func post(_ followUp: CaptureFollowUp, for suggestion: Suggestion, profileId: String) async {
        posted.append((followUp, suggestion.sourceKey))
    }
    var kinds: [CaptureFollowUp] { posted.map(\.0) }
}

extension CaptureActionEnvironment {
    /// Everything allowed: data unlocked, pull done, event unchanged.
    static func testing(
        eventChecker: FakeEventChecker = FakeEventChecker(),
        gate: FakePullGate = FakePullGate(),
        followUps: FakeFollowUps = FakeFollowUps(),
        notifier: CaptureNotifier? = nil,
        protectedData: @escaping @MainActor () -> Bool = { true },
        defaults: UserDefaults
    ) -> CaptureActionEnvironment {
        CaptureActionEnvironment(
            isProtectedDataAvailable: protectedData,
            eventChecker: eventChecker,
            pullGate: { _ in gate },
            followUps: followUps,
            notifier: notifier,
            pullWaitTimeout: 0.01,
            defaults: defaults
        )
    }
}

// MARK: - End-of-event scheduler

@MainActor
final class EndOfEventSchedulerTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var center: FakeCaptureNotificationCenter!
    private var now = Date()
    private var isPhone = true
    private let pineId = UUID()

    override func setUp() {
        super.setUp()
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        suiteName = "EndOfEventSchedulerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        center = FakeCaptureNotificationCenter()
        now = date(2026, 3, 2, 7)
        isPhone = true
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func makeScheduler() -> EndOfEventScheduler {
        EndOfEventScheduler(
            center: center,
            isPhone: { [unowned self] in self.isPhone },
            clock: { [unowned self] in self.now },
            calendar: { [unowned self] in self.calendar },
            defaults: defaults,
            propertyNames: { [pineId] in [pineId: "Pine Cabin"] }
        )
    }

    private func suggestion(
        _ id: String,
        end: Date,
        hours: Double = 2,
        title: String = "Plumber visit",
        confidence: Double = 0.9,
        flagged: Bool = false,
        backfill: Bool = false,
        state: Suggestion.State = .pending
    ) -> Suggestion {
        let start = end.addingTimeInterval(-hours * 3600)
        return Suggestion(
            sourceKey: SuggestionKey.calendar(externalId: id),
            kind: .calendar,
            detectedAt: start,
            start: start,
            end: end,
            title: title,
            externalId: id,
            containerId: "CAL-1",
            proposedPropertyId: pineId,
            proposedCategory: .repairs,
            proposedHours: hours,
            hoursBasis: .scheduled,
            confidence: confidence,
            tier: .rules,
            state: state,
            isBackfill: backfill,
            mightAlreadyBeLogged: flagged
        )
    }

    private func fireDate(_ request: UNNotificationRequest) -> Date? {
        (request.content.userInfo[EndOfEventScheduler.fireAtKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
    }

    func testFiresFiveMinutesAfterEndWithPlainCopyAndActions() async throws {
        let s = suggestion("A", end: date(2026, 3, 2, 12))
        await makeScheduler().schedule([s], profileId: "p1")

        let request = try XCTUnwrap(center.captureRequests.first)
        XCTAssertEqual(request.identifier, "capture.end.\(s.sourceKey)")
        XCTAssertEqual(request.content.title, "Plumber visit just ended")
        XCTAssertEqual(request.content.body, "Log 2h at Pine Cabin?")
        XCTAssertEqual(request.content.categoryIdentifier, CaptureNotificationAction.categoryIdentifier)
        XCTAssertEqual(request.content.userInfo[NotificationPayload.profileIdKey] as? String, "p1")
        XCTAssertEqual(request.content.userInfo[NotificationPayload.sourceKeyKey] as? String, s.sourceKey)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger, "Absolute time, not wall-clock components")
        XCTAssertEqual(trigger.timeInterval, date(2026, 3, 2, 12, 5).timeIntervalSince(now), accuracy: 0.5)
        XCTAssertEqual(fireDate(request), date(2026, 3, 2, 12, 5))
        for word in ["tax", "deduct", "IRS", "qualif"] {
            XCTAssertFalse(request.content.body.localizedCaseInsensitiveContains(word), "No tax claims in copy")
            XCTAssertFalse(request.content.title.localizedCaseInsensitiveContains(word), "No tax claims in copy")
        }
    }

    func testAcrossDSTTheTriggerIsAbsoluteAndNeverEarly() async throws {
        // US spring forward: 2026-03-08 02:00 PST → 03:00 PDT. "Now" is the evening before.
        now = date(2026, 3, 7, 22)
        let s = suggestion("DST", end: date(2026, 3, 8, 7))          // 07:05 PDT is quiet → 08:00 PDT
        await makeScheduler().schedule([s], profileId: "p1")
        let request = try XCTUnwrap(center.captureRequests.first)
        let fire = try XCTUnwrap(fireDate(request))
        XCTAssertEqual(fire, date(2026, 3, 8, 8))
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 9 * 3600, accuracy: 0.5, "22:00 PST → 08:00 PDT is 9 real hours, not 10")
        XCTAssertGreaterThan(now.addingTimeInterval(trigger.timeInterval), s.end!)
    }

    func testTimeZoneChangeRebuildsWithNewQuietHours() async throws {
        let scheduler = makeScheduler()
        // 20:30 Los Angeles end → 20:35 prompt, outside quiet hours there.
        let s = suggestion("TRAVEL", end: date(2026, 3, 2, 20, 30))
        let endInstant = s.end!
        await scheduler.schedule([s], profileId: "p1")
        let before = try XCTUnwrap(center.captureRequests.first)
        XCTAssertEqual(fireDate(before), endInstant.addingTimeInterval(300))
        XCTAssertEqual(before.content.userInfo[EndOfEventScheduler.timeZoneKey] as? String, "America/Los_Angeles")

        // The user flies to New York: the same instant is 23:35 there, inside quiet hours.
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        await scheduler.schedule([s], profileId: "p1")
        XCTAssertEqual(center.captureRequests.count, 1, "Old request replaced, not kept")
        let after = try XCTUnwrap(center.captureRequests.first)
        XCTAssertEqual(after.content.userInfo[EndOfEventScheduler.timeZoneKey] as? String, "America/New_York")
        XCTAssertEqual(fireDate(after), date(2026, 3, 3, 8), "08:00 New York time")
        XCTAssertGreaterThan(fireDate(after)!, endInstant, "Never before the event ends")

        // Same zone, same time: left alone.
        let adds = center.addCount
        await scheduler.schedule([s], profileId: "p1")
        XCTAssertEqual(center.addCount, adds)
    }

    func testTimeZoneChangeAloneReplacesTheRequest() async throws {
        // A mid-day event in a zone with the same offset logic: the absolute fire time is
        // unchanged, but the zone differs, so the rebuild still replaces it.
        let scheduler = makeScheduler()
        let s = suggestion("TZ", end: date(2026, 3, 2, 12))
        await scheduler.schedule([s], profileId: "p1")
        let adds = center.addCount
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        await scheduler.schedule([s], profileId: "p1")
        XCTAssertEqual(center.addCount, adds + 1)
        XCTAssertEqual(center.captureRequests.count, 1)
    }

    func testAtMostTwoPerDay() async {
        let items = [10, 12, 14, 16].map { suggestion("D\($0)", end: date(2026, 3, 2, $0)) }
        await makeScheduler().schedule(items, profileId: "p1")
        XCTAssertEqual(center.captureRequests.count, 2)
        XCTAssertEqual(Set(center.captureRequests.compactMap(fireDate)), [date(2026, 3, 2, 10, 5), date(2026, 3, 2, 12, 5)])
    }

    func testAtMostTwentyPending() async {
        var items: [Suggestion] = []
        for day in 2...16 {
            items.append(suggestion("M\(day)", end: date(2026, 3, day, 10)))
            items.append(suggestion("A\(day)", end: date(2026, 3, day, 15)))
        }
        await makeScheduler().schedule(items, profileId: "p1")
        XCTAssertEqual(items.count, 30)
        XCTAssertEqual(center.captureRequests.count, 20)
        // The soonest ones win.
        XCTAssertEqual(center.captureRequests.compactMap(fireDate).max(), date(2026, 3, 11, 15, 5))
    }

    func testQuietHoursDeferToEightAM() async throws {
        let late = suggestion("LATE", end: date(2026, 3, 2, 20, 58))     // 21:03 → next 08:00
        let early = suggestion("EARLY", end: date(2026, 3, 4, 6))         // 06:05 → 08:00
        let edge = suggestion("EDGE", end: date(2026, 3, 5, 20, 50))      // 20:55 stays
        await makeScheduler().schedule([late, early, edge], profileId: "p1")

        let byKey = Dictionary(uniqueKeysWithValues: center.captureRequests.map {
            ($0.content.userInfo[NotificationPayload.sourceKeyKey] as! String, $0)
        })
        let lateRequest = try XCTUnwrap(byKey[late.sourceKey])
        XCTAssertEqual(fireDate(lateRequest), date(2026, 3, 3, 8))
        XCTAssertEqual(lateRequest.content.title, "Plumber visit ended yesterday")
        XCTAssertEqual(lateRequest.content.body, "Log 2h at Pine Cabin?")
        let earlyRequest = try XCTUnwrap(byKey[early.sourceKey])
        XCTAssertEqual(fireDate(earlyRequest), date(2026, 3, 4, 8))
        XCTAssertEqual(earlyRequest.content.title, "Plumber visit ended earlier today")
        XCTAssertEqual(earlyRequest.content.body, "Log 2h at Pine Cabin?")
        XCTAssertEqual(fireDate(try XCTUnwrap(byKey[edge.sourceKey])), date(2026, 3, 5, 20, 55))
    }

    func testDeferredMorningStillCountsTowardThatDaysBudget() async {
        // Three late events all land at 08:00 the next day: only two notify.
        let items = (0..<3).map { suggestion("N\($0)", end: date(2026, 3, 2, 22, $0 * 10)) }
        await makeScheduler().schedule(items, profileId: "p1")
        XCTAssertEqual(center.captureRequests.count, 2)
    }

    func testOnlyLikelyPendingFutureCalendarItems() async {
        let items = [
            suggestion("OK", end: date(2026, 3, 2, 12)),
            suggestion("LOW", end: date(2026, 3, 3, 12), confidence: 0.59),
            suggestion("FLAG", end: date(2026, 3, 4, 12), flagged: true),
            suggestion("BACK", end: date(2026, 3, 5, 12), backfill: true),
            suggestion("DONE", end: date(2026, 3, 6, 12), state: .confirmed(entryId: UUID()))
        ]
        await makeScheduler().schedule(items, profileId: "p1")
        let keys = Set(center.captureRequests.compactMap { $0.content.userInfo[NotificationPayload.sourceKeyKey] as? String })
        XCTAssertTrue(keys.contains(SuggestionKey.calendar(externalId: "OK")))
        XCTAssertFalse(keys.contains(SuggestionKey.calendar(externalId: "LOW")))
        XCTAssertFalse(keys.contains(SuggestionKey.calendar(externalId: "FLAG")))
        XCTAssertFalse(keys.contains(SuggestionKey.calendar(externalId: "BACK")))
        XCTAssertFalse(keys.contains(SuggestionKey.calendar(externalId: "DONE")))
    }

    func testEventThatAlreadyEndedIsNotAnnounced() async {
        now = date(2026, 3, 2, 13)
        await makeScheduler().schedule([suggestion("OLD", end: date(2026, 3, 2, 12))], profileId: "p1")
        XCTAssertTrue(center.captureRequests.isEmpty)
    }

    func testIPadNeverSchedulesAndClearsAnyItHas() async {
        let scheduler = makeScheduler()
        await scheduler.schedule([suggestion("A", end: date(2026, 3, 2, 12))], profileId: "p1")
        XCTAssertEqual(center.captureRequests.count, 1)
        let engagement = UNNotificationRequest(identifier: "engagement.inactiveLogging",
                                               content: UNMutableNotificationContent(), trigger: nil)
        center.requests.append(engagement)

        isPhone = false
        let addsBefore = center.addCount
        await scheduler.schedule([suggestion("B", end: date(2026, 3, 3, 12))], profileId: "p1")
        XCTAssertTrue(center.captureRequests.isEmpty, "iPad: no end-of-event notifications")
        XCTAssertEqual(center.addCount, addsBefore)
        XCTAssertTrue(center.requests.contains { $0.identifier == "engagement.inactiveLogging" }, "Other notifications untouched")
    }

    func testRebuildCancelsStaleAndKeepsUnchanged() async throws {
        let scheduler = makeScheduler()
        let a = suggestion("A", end: date(2026, 3, 2, 12))
        var b = suggestion("B", end: date(2026, 3, 3, 12))
        let other = UNNotificationRequest(identifier: "engagement.yearEndExport", content: UNMutableNotificationContent(), trigger: nil)
        center.requests.append(other)
        await scheduler.schedule([a, b], profileId: "p1")
        XCTAssertEqual(center.captureRequests.count, 2)
        let addsAfterFirst = center.addCount

        // A confirmed elsewhere: gone from the pending list → cancelled. B unchanged → not re-added.
        await scheduler.schedule([b], profileId: "p1")
        XCTAssertEqual(center.captureRequests.map(\.identifier), [EndOfEventScheduler.identifier(forSourceKey: b.sourceKey)])
        XCTAssertEqual(center.addCount, addsAfterFirst)
        XCTAssertTrue(center.removedPending.contains(EndOfEventScheduler.identifier(forSourceKey: a.sourceKey)))

        // B moved an hour later: replaced with the new time.
        b.end = date(2026, 3, 3, 13)
        await scheduler.schedule([b], profileId: "p1")
        XCTAssertEqual(fireDate(try XCTUnwrap(center.captureRequests.first)), date(2026, 3, 3, 13, 5))
        XCTAssertEqual(center.captureRequests.count, 1)

        // Another profile became active with nothing pending: everything of p1's goes.
        await scheduler.schedule([], profileId: "p2")
        XCTAssertTrue(center.captureRequests.isEmpty)
        XCTAssertTrue(center.requests.contains { $0.identifier == other.identifier })
    }

    func testDeliveredCountsForItsDayAndIsNeverRepeated() async {
        let scheduler = makeScheduler()
        let a = suggestion("A", end: date(2026, 3, 2, 9))
        let b = suggestion("B", end: date(2026, 3, 2, 10))
        await scheduler.schedule([a, b], profileId: "p1")
        XCTAssertEqual(center.captureRequests.count, 2)

        // Both fire; the user ignores them (still pending). A third event comes up the same day.
        now = date(2026, 3, 2, 11)
        center.deliver(before: now)
        let c = suggestion("C", end: date(2026, 3, 2, 15))
        await scheduler.schedule([a, b, c], profileId: "p1")
        XCTAssertTrue(center.captureRequests.isEmpty, "Day budget used by delivered ones; A and B not repeated")

        // Next day the budget resets.
        let d = suggestion("D", end: date(2026, 3, 3, 15))
        await scheduler.schedule([a, b, c, d], profileId: "p1")
        XCTAssertEqual(center.captureRequests.compactMap { $0.content.userInfo[NotificationPayload.sourceKeyKey] as? String },
                       [d.sourceKey])
    }

    func testNotAuthorizedSchedulesNothing() async {
        center.allowed = false
        await makeScheduler().schedule([suggestion("A", end: date(2026, 3, 2, 12))], profileId: "p1")
        XCTAssertTrue(center.captureRequests.isEmpty)
    }

    func testCancelRemovesPendingAndDelivered() async {
        let scheduler = makeScheduler()
        let a = suggestion("A", end: date(2026, 3, 2, 12))
        await scheduler.schedule([a], profileId: "p1")
        await scheduler.cancel(sourceKeys: [a.sourceKey])
        XCTAssertTrue(center.captureRequests.isEmpty)
        XCTAssertEqual(center.removedDelivered, [EndOfEventScheduler.identifier(forSourceKey: a.sourceKey)])
    }

    func testCopyVariants() {
        let scheduler = makeScheduler()
        var s = suggestion("A", end: date(2026, 3, 2, 12), hours: 1.5)
        XCTAssertEqual(scheduler.content(for: s, fireDate: date(2026, 3, 2, 12, 5), deferred: false),
                       NotificationText(title: "Plumber visit just ended", body: "Log 1.5h at Pine Cabin?"))
        s.proposedPropertyId = nil
        s.proposedHours = 0.75
        XCTAssertEqual(scheduler.content(for: s, fireDate: date(2026, 3, 2, 12, 5), deferred: false).body, "Log 45 min?")
        s.proposedHours = nil
        XCTAssertEqual(scheduler.content(for: s, fireDate: date(2026, 3, 2, 12, 5), deferred: false).body, "Log it?")
        XCTAssertEqual(EndOfEventScheduler.hoursText(2), "2h")
        XCTAssertEqual(EndOfEventScheduler.hoursText(1.25), "1.25h")
        XCTAssertEqual(EndOfEventScheduler.shortTitle(String(repeating: "x", count: 80)).count, 60)
    }

    func testCategoriesHaveTheThreeActions() {
        let category = CaptureNotificationCategories.suggestion
        XCTAssertEqual(category.identifier, CaptureNotificationAction.categoryIdentifier)
        XCTAssertEqual(category.actions.map(\.title), ["Log it", "Edit…", "Not rental work"])
        let logIt = category.actions[0]
        XCTAssertTrue(logIt.options.contains(.authenticationRequired))
        XCTAssertFalse(logIt.options.contains(.foreground), "Log it runs in the background")
        XCTAssertTrue(category.actions[1].options.contains(.foreground), "Edit… opens the app")
        XCTAssertFalse(category.actions[2].options.contains(.foreground))
        XCTAssertEqual(CaptureNotificationCategories.all.count, 3)
    }

    func testBackgroundModesDeclared() throws {
        let modes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        XCTAssertTrue(modes.contains("fetch"), "BGAppRefreshTask needs the fetch mode")
        XCTAssertTrue(modes.contains("remote-notification"))
    }
}

// MARK: - Event re-check

final class CaptureEventCheckTests: XCTestCase {
    func testCompareFindsUnchangedMovedAndGone() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let key = SuggestionKey.calendar(externalId: "E")
        let suggestion = Suggestion(sourceKey: key, kind: .calendar, detectedAt: start, start: start,
                                    end: start.addingTimeInterval(3600), title: "Showing",
                                    proposedHours: 1, hoursBasis: .scheduled, confidence: 0.9, tier: .rules)
        func candidate(start s: Date, end e: Date, key k: String = key) -> CaptureCandidate {
            CaptureCandidate(sourceKey: k, kind: .calendar, start: s, end: e, title: "Showing", detectedAt: s)
        }
        XCTAssertEqual(CalendarCaptureEventChecker.compare(suggestion, with: [candidate(start: start, end: start.addingTimeInterval(3600))]), .unchanged)
        XCTAssertEqual(CalendarCaptureEventChecker.compare(suggestion, with: [candidate(start: start, end: start.addingTimeInterval(7200))]), .moved)
        XCTAssertEqual(CalendarCaptureEventChecker.compare(suggestion, with: [candidate(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400))]), .moved)
        XCTAssertEqual(CalendarCaptureEventChecker.compare(suggestion, with: [candidate(start: start, end: start.addingTimeInterval(3600), key: "cal:OTHER")]), .gone)
        XCTAssertEqual(CalendarCaptureEventChecker.compare(suggestion, with: []), .gone)
    }
}

// MARK: - Action router: tap-time checks

@MainActor
final class CaptureActionRouterTests: CaptureTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CaptureActionRouterTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeHost() -> (AppModelHost, AppViewModel, UUID) {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak St", type: .ltr)
        let host = AppModelHost(viewModel: viewModel, backgroundTasks: FakeBackgroundTasks(), suggestionBaseDirectory: baseDir)
        return (host, viewModel, viewModel.properties[0].id)
    }

    private func request(_ action: String, _ s: Suggestion) -> NotificationActionRequest {
        NotificationActionRequest(actionIdentifier: action,
                                  categoryIdentifier: CaptureNotificationAction.categoryIdentifier,
                                  userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: s.sourceKey))
    }

    private func entryCount(_ viewModel: AppViewModel, _ s: Suggestion) -> Int {
        viewModel.timeEntries.filter { $0.id == s.entryId(profileId: profileId) }.count
    }

    func testDeletedEventWritesNothing() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let checker = FakeEventChecker()
        checker.result = .gone
        let followUps = FakeFollowUps()
        let router = NotificationActionRouter(host: host, environment: .testing(eventChecker: checker, followUps: followUps, defaults: defaults))

        var completed = false
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) { completed = true }
        XCTAssertEqual(outcome, .eventGone)
        XCTAssertTrue(completed)
        XCTAssertEqual(entryCount(viewModel, s), 0)
        XCTAssertTrue(host.suggestionStore!.suggestion(forKey: s.sourceKey)!.isPending)
        XCTAssertEqual(followUps.kinds, [.eventGone])
    }

    func testMovedEventRoutesToEdit() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let checker = FakeEventChecker()
        checker.result = .moved
        let router = NotificationActionRouter(host: host, environment: .testing(eventChecker: checker, defaults: defaults))
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) {}
        XCTAssertEqual(outcome, .routedToEdit(.eventMoved))
        XCTAssertEqual(entryCount(viewModel, s), 0)
        XCTAssertEqual(UserDefaults.standard.string(forKey: CaptureNotificationAction.pendingEditKey), s.sourceKey)

        checker.result = .unverifiable
        let blind = await router.handle(request(CaptureNotificationAction.logIt, s)) {}
        XCTAssertEqual(blind, .routedToEdit(.cannotVerify), "No calendar access: never write blind")
        XCTAssertEqual(entryCount(viewModel, s), 0)
    }

    func testItemFlaggedAtTapTimeRoutesToEdit() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        XCTAssertFalse(host.suggestionStore!.suggestion(forKey: s.sourceKey)!.mightAlreadyBeLogged, "Not flagged when scheduled")

        // After the notification went out, hours were logged by hand for the same property and day.
        viewModel.addTimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .leasing,
                               hours: 1.5, date: date(2026, 3, 2, 14), notes: "showing")
        let followUps = FakeFollowUps()
        let router = NotificationActionRouter(host: host, environment: .testing(followUps: followUps, defaults: defaults))
        var completed = false
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) { completed = true }

        XCTAssertEqual(outcome, .routedToEdit(.mightAlreadyBeLogged))
        XCTAssertTrue(completed)
        XCTAssertEqual(entryCount(viewModel, s), 0, "Never double count: the user decides in the app")
        XCTAssertEqual(UserDefaults.standard.string(forKey: CaptureNotificationAction.pendingEditKey), s.sourceKey)
        XCTAssertEqual(followUps.kinds, [.mightAlreadyBeLogged])
    }

    func testPullPendingQueuesThenConfirmsAfterThePull() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let gate = FakePullGate()
        gate.stateValue = .pending
        let checker = FakeEventChecker()
        let router = NotificationActionRouter(host: host, environment: .testing(eventChecker: checker, gate: gate, defaults: defaults))

        var completed = false
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) { completed = true }
        XCTAssertEqual(outcome, .queued)
        XCTAssertTrue(completed, "The system handler is still called")
        XCTAssertEqual(gate.waits, 1)
        XCTAssertEqual(entryCount(viewModel, s), 0, "Nothing saved before the initial pull")
        XCTAssertEqual(CaptureActionQueue.all(defaults: defaults).map(\.sourceKey), [s.sourceKey])
        XCTAssertTrue(checker.checked.isEmpty, "Checks run after the pull, on fresh data")

        // Still pending: a foreground drain leaves it queued.
        let early = await router.drainQueuedActions()
        XCTAssertEqual(early[s.sourceKey], .queued)
        XCTAssertEqual(entryCount(viewModel, s), 0)

        // The pull completes.
        gate.stateValue = .completed
        let drained = await router.drainQueuedActions()
        XCTAssertEqual(drained[s.sourceKey], .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(entryCount(viewModel, s), 1)
        XCTAssertTrue(CaptureActionQueue.all(defaults: defaults).isEmpty)
    }

    func testPullThatBringsAMatchingEntryMeansNoSecondRecord() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let gate = FakePullGate()
        gate.stateValue = .pending
        // During the wait the pull lands a confirm from the other device, then completes.
        gate.onWait = { [unowned self] g in
            var remote = TimeEntry(id: s.entryId(profileId: self.profileId), propertyId: propertyId, participant: .selfParticipant,
                                   category: .leasing, hours: 1.5, date: s.start, notes: s.title, importSource: "calendar",
                                   sourceKey: s.sourceKey)
            remote.modifiedAt = Date()
            viewModel.syncDidReceiveEntries([remote])
            g.stateValue = .completed
            return true
        }
        let router = NotificationActionRouter(host: host, environment: .testing(gate: gate, defaults: defaults))
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) {}
        XCTAssertEqual(outcome, .alreadyRecorded(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(entryCount(viewModel, s), 1)
        XCTAssertTrue(CaptureActionQueue.all(defaults: defaults).isEmpty)
    }

    func testQueuedTapOlderThanAWeekResurfacesInsteadOfVanishing() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let gate = FakePullGate()
        gate.stateValue = .pending                       // iCloud never finished
        let followUps = FakeFollowUps()
        let router = NotificationActionRouter(host: host, environment: .testing(gate: gate, followUps: followUps, defaults: defaults))
        let tappedAt = Date()
        CaptureActionQueue.enqueue(QueuedCaptureAction(profileId: profileId, sourceKey: s.sourceKey, kind: .confirm, queuedAt: tappedAt),
                                   defaults: defaults)
        // Another profile's old tap is left for that profile.
        CaptureActionQueue.enqueue(QueuedCaptureAction(profileId: "other", sourceKey: "cal:X", kind: .confirm,
                                                       queuedAt: tappedAt.addingTimeInterval(-30 * 86_400)), defaults: defaults)

        let sixDays = await router.drainQueuedActions(now: tappedAt.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(sixDays[s.sourceKey], .queued)
        XCTAssertTrue(followUps.kinds.isEmpty)

        let eightDays = await router.drainQueuedActions(now: tappedAt.addingTimeInterval(8 * 86_400))
        XCTAssertEqual(eightDays[s.sourceKey], .routedToEdit(.queuedTooLong))
        XCTAssertEqual(followUps.kinds, [.queuedTooLong], "The user is told, not left guessing")
        XCTAssertEqual(UserDefaults.standard.string(forKey: CaptureNotificationAction.pendingEditKey), s.sourceKey)
        XCTAssertTrue(host.suggestionStore!.suggestion(forKey: s.sourceKey)!.isPending, "Still in the inbox")
        XCTAssertEqual(entryCount(viewModel, s), 0, "Never written without the pull")
        XCTAssertEqual(CaptureActionQueue.all(defaults: defaults).map(\.profileId), ["other"])
    }

    func testNoICloudDiscoveredDuringWaitConfirmsRightAway() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let gate = FakePullGate()
        gate.stateValue = .pending
        gate.onWait = { g in g.stateValue = .notApplicable; return false }
        let router = NotificationActionRouter(host: host, environment: .testing(gate: gate, defaults: defaults))
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) {}
        XCTAssertEqual(outcome, .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(entryCount(viewModel, s), 1)
        XCTAssertTrue(CaptureActionQueue.all(defaults: defaults).isEmpty)
    }

    func testCompletionRunsAfterTheSave() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let notifier = FakeCaptureNotifier()
        let router = NotificationActionRouter(host: host, environment: .testing(notifier: notifier, defaults: defaults))
        let entriesKey = UserScope.key("LandlordHours.entries", userId: profileId)
        var savedAtCompletion = false
        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) {
            let data = UserDefaults.standard.data(forKey: entriesKey) ?? Data()
            let saved = (try? JSONDecoder().decode([TimeEntry].self, from: data)) ?? []
            savedAtCompletion = saved.contains { $0.id == s.entryId(profileId: self.profileId) }
        }
        XCTAssertEqual(outcome, .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertTrue(savedAtCompletion)
        XCTAssertEqual(entryCount(viewModel, s), 1)
        XCTAssertEqual(notifier.cancelled, [s.sourceKey], "Any duplicate pending notification is cancelled")
    }

    func testLockedDataQueuesWithoutTouchingTheStore() async {
        let (host, viewModel, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        var unlocked = false
        let router = NotificationActionRouter(host: host, environment: .testing(protectedData: { unlocked }, defaults: defaults))

        let outcome = await router.handle(request(CaptureNotificationAction.logIt, s)) {}
        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(entryCount(viewModel, s), 0)
        let stillLocked = await router.drainQueuedActions()
        XCTAssertTrue(stillLocked.isEmpty)

        unlocked = true
        let drained = await router.drainQueuedActions()
        XCTAssertEqual(drained[s.sourceKey], .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(entryCount(viewModel, s), 1)
    }

    func testNotLandlordWorkOffersMuteAndMuteSilencesLookalikes() async {
        let (host, viewModel, propertyId) = makeHost()
        let a = calendarSuggestion(externalId: "A", start: date(2026, 3, 2), title: "Dentist", propertyId: propertyId)
        let b = calendarSuggestion(externalId: "B", start: date(2026, 3, 9), title: "Dentist", propertyId: propertyId)
        let c = calendarSuggestion(externalId: "C", start: date(2026, 3, 10), title: "Plumber visit", propertyId: propertyId)
        host.suggestionStore!.ingest([a, b, c], existingEntries: [], calendar: calendar)
        let followUps = FakeFollowUps()
        let notifier = FakeCaptureNotifier()
        let router = NotificationActionRouter(host: host, environment: .testing(followUps: followUps, notifier: notifier, defaults: defaults))

        let dismissed = await router.handle(request(CaptureNotificationAction.notLandlordWork, a)) {}
        XCTAssertEqual(dismissed, .dismissed)
        XCTAssertTrue(host.suggestionStore!.isDismissed(a.sourceKey))
        XCTAssertEqual(followUps.kinds, [.offerMute])

        let muteTap = NotificationActionRequest(
            actionIdentifier: CaptureNotificationAction.mute,
            categoryIdentifier: CaptureNotificationAction.muteOfferCategoryIdentifier,
            userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: a.sourceKey))
        let muted = await router.handle(muteTap) {}
        XCTAssertEqual(muted, .muted)
        XCTAssertFalse(host.suggestionStore!.suggestion(forKey: b.sourceKey)!.isPending, "Lookalike muted")
        XCTAssertTrue(host.suggestionStore!.suggestion(forKey: c.sourceKey)!.isPending)
        XCTAssertEqual(notifier.cancelled, [b.sourceKey])
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
    }

    func testReviewFollowUpTapOpensTheConfirmSheet() async {
        let (host, _, propertyId) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        let router = NotificationActionRouter(host: host, environment: .testing(defaults: defaults))
        let outcome = await router.handle(NotificationActionRequest(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: CaptureNotificationAction.reviewCategoryIdentifier,
            userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: s.sourceKey))) {}
        XCTAssertEqual(outcome, .openedForEdit)
        XCTAssertEqual(UserDefaults.standard.string(forKey: CaptureNotificationAction.pendingEditKey), s.sourceKey)
    }
}

// MARK: - Refresher

@MainActor
final class CaptureNotificationRefresherTests: CaptureTestCase {
    func testIPadAndKillSwitchRemoveInsteadOfScheduling() async {
        let center = FakeCaptureNotificationCenter()
        let suite = "refresher-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewModel = AppViewModel()
        let host = AppModelHost(viewModel: viewModel, backgroundTasks: FakeBackgroundTasks(), suggestionBaseDirectory: baseDir)
        let existing = UNNotificationRequest(identifier: EndOfEventScheduler.identifierPrefix + "cal:X",
                                             content: UNMutableNotificationContent(), trigger: nil)
        center.requests = [existing]
        let scheduler = EndOfEventScheduler(center: center, isPhone: { false }, defaults: defaults)
        let refresher = CaptureNotificationRefresher(
            scheduler: scheduler, host: { host }, isPhone: { false },
            isProtectedDataAvailable: { true }, canDeliver: { true },
            makeCoordinator: { _ in XCTFail("iPad never scans for notifications"); fatalError() }
        )
        await refresher.refresh(reason: "test")
        XCTAssertTrue(center.captureRequests.isEmpty)
        XCTAssertEqual(refresher.completedRuns, 1)
    }
}

private struct NoRemoteFlags: CaptureFlagRemoteSource {
    func value(for flag: CaptureFlag) -> Bool? { nil }
}

@MainActor
final class EventPromptOptInTests: CaptureTestCase {
    func testUpgradeWithPermissionsGrantedGetsNoPromptsUntilOptedIn() async throws {
        let suite = "optin-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = FakeCaptureNotificationCenter()      // notifications already allowed (1.x)
        let (viewModel, propertyId) = makeViewModel()
        let host = AppModelHost(viewModel: viewModel, backgroundTasks: FakeBackgroundTasks(), suggestionBaseDirectory: baseDir)
        let start = Date().addingTimeInterval(3600)
        var s = calendarSuggestion(start: start, propertyId: propertyId)
        s.end = start.addingTimeInterval(3600)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        // A prompt left over from before (e.g. a beta build) is cleared too.
        center.requests = [UNNotificationRequest(identifier: EndOfEventScheduler.identifierPrefix + "cal:OLD",
                                                 content: UNMutableNotificationContent(), trigger: nil)]

        let scheduler = EndOfEventScheduler(center: center, isPhone: { true }, defaults: defaults)
        let refresher = CaptureNotificationRefresher(
            scheduler: scheduler, host: { host },
            flags: CaptureFlags(remote: NoRemoteFlags(), defaults: defaults),
            isPhone: { true }, isProtectedDataAvailable: { true }, canDeliver: { true },
            makeCoordinator: { store in
                CalendarCaptureCoordinator(detector: CalendarDetector(source: FakeCalendarSource(access: .fullAccess)), store: store)
            },
            promptsEnabled: { CapturePromptConsent.isEnabled(profileId: $0, defaults: defaults) }
        )

        XCTAssertFalse(CapturePromptConsent.isEnabled(profileId: profileId, defaults: defaults), "Off by default")
        await refresher.refresh(reason: "launch")
        XCTAssertTrue(center.captureRequests.isEmpty, "Calendar + notifications granted, but no opt-in: no prompts")

        CapturePromptConsent.set(true, profileId: profileId, defaults: defaults)
        await refresher.refresh(reason: "opt-in")
        XCTAssertEqual(center.captureRequests.map(\.identifier), [EndOfEventScheduler.identifier(forSourceKey: s.sourceKey)])

        CapturePromptConsent.set(false, profileId: profileId, defaults: defaults)
        await refresher.refresh(reason: "opt-out")
        XCTAssertTrue(center.captureRequests.isEmpty, "Opting out clears pending prompts")
    }

    func testViewModelSetterIsPerProfileAndDefaultsOff() {
        let (viewModel, _) = makeViewModel()
        XCTAssertFalse(viewModel.eventPromptsEnabled)
        viewModel.eventPromptsEnabled = true
        XCTAssertTrue(CapturePromptConsent.isEnabled(profileId: profileId))
        XCTAssertFalse(CapturePromptConsent.isEnabled(profileId: "another-profile"))
        AppViewModel.clearScopedAccountData(for: profileId)
        XCTAssertFalse(viewModel.eventPromptsEnabled, "Cleared with the profile")
    }
}

final class InitialPullStateTests: XCTestCase {
    func testOnlyADefiniteNoICloudSkipsTheWait() {
        func state(checked: Bool = true, available: Bool = false, unknown: Bool = false, running: Bool = false) -> InitialPullState {
            CloudKitSyncService.pullState(completed: false, cloudKitAvailable: true, accountChecked: checked,
                                          accountAvailable: available, accountStatusUnknown: unknown,
                                          isRunningInitialSync: running)
        }
        XCTAssertEqual(state(), .notApplicable, "iCloud definitely off")
        XCTAssertEqual(state(unknown: true), .pending, "Network error while checking: wait and queue")
        XCTAssertEqual(state(checked: false), .pending)
        XCTAssertEqual(state(available: true), .pending)
        XCTAssertEqual(state(running: true), .pending)
        XCTAssertEqual(CloudKitSyncService.pullState(completed: true, cloudKitAvailable: true, accountChecked: true,
                                                     accountAvailable: true, accountStatusUnknown: false,
                                                     isRunningInitialSync: false), .completed)
        XCTAssertEqual(CloudKitSyncService.pullState(completed: false, cloudKitAvailable: false, accountChecked: false,
                                                     accountAvailable: false, accountStatusUnknown: false,
                                                     isRunningInitialSync: false), .notApplicable)
    }

    func testBackgroundWaitIsCappedWellUnderThirtySeconds() {
        let env = CaptureActionEnvironment(isProtectedDataAvailable: { true }, eventChecker: FakeEventChecker(),
                                           pullGate: { _ in FakePullGate() }, followUps: FakeFollowUps(), notifier: nil)
        XCTAssertLessThanOrEqual(env.pullWaitTimeout, 8)
    }
}

// MARK: - Push changed records only

@MainActor
final class SyncPushChangedOnlyTests: CaptureTestCase {
    private var trackerDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        trackerDir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: trackerDir)
        try await super.tearDown()
    }

    private func makeModel() -> (AppViewModel, CloudKitSyncService, UUID) {
        let (viewModel, propertyId) = makeViewModel()
        viewModel.addTimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: date(2026, 3, 2), notes: "Fix sink")
        viewModel.addTimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .leasing,
                               hours: 1, date: date(2026, 3, 3), notes: "Showing")
        let service = viewModel.syncService
        service.changeTrackerBaseDirectory = trackerDir
        return (viewModel, service, propertyId)
    }

    /// Record names sent as deletes by `push`.
    private var deleted: [String] = []

    private func push(_ service: CloudKitSyncService) async throws -> [CKRecord] {
        var sent: [CKRecord] = []
        var gone: [String] = []
        try await service.pushChangedRecords(save: { sent = $0 }, delete: { gone += $0.map(\.recordName) })
        deleted += gone
        return sent
    }

    func testOfflineDeleteIsPushedLaterAndNeverResurrects() async throws {
        let (viewModel, service, _) = makeModel()
        _ = try await push(service)
        let entry = viewModel.timeEntries[0]
        viewModel.deleteTimeEntry(entry)
        service.deleteEntryFromCloud(entry)   // offline in tests: the delete can't reach iCloud
        XCTAssertEqual(service.changeTracker!.pendingDeletes, [entry.id.uuidString], "Tombstone kept")

        // A failed delete keeps the tombstone.
        struct Boom: Error {}
        do {
            try await service.pushChangedRecords(save: { _ in }, delete: { _ in throw Boom() })
            XCTFail("Expected the delete to throw")
        } catch {}
        XCTAssertEqual(service.changeTracker!.pendingDeletes, [entry.id.uuidString])

        // Survives relaunch.
        let reopened = SyncChangeTracker(userId: profileId, baseDirectory: trackerDir)
        XCTAssertEqual(reopened.pendingDeletes, [entry.id.uuidString])

        // Next sync sends the delete and clears it.
        deleted = []
        let saved = try await push(service)
        XCTAssertEqual(deleted, [entry.id.uuidString])
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(service.changeTracker!.pendingDeletes.isEmpty)
    }

    func testReAddedRecordCancelsItsTombstone() async throws {
        let (viewModel, service, _) = makeModel()
        _ = try await push(service)
        let entry = viewModel.timeEntries[0]
        service.deleteEntryFromCloud(entry)
        // Same id is still (or again) local, e.g. a re-confirmed suggestion.
        deleted = []
        let saved = try await push(service)
        XCTAssertTrue(deleted.isEmpty, "Never delete a record that exists locally")
        XCTAssertEqual(saved.map(\.recordID.recordName), [entry.id.uuidString])
        XCTAssertTrue(service.changeTracker!.pendingDeletes.isEmpty)
    }

    /// A minimal server: record names it holds.
    private final class FakeServer {
        var names = Set<String>()
        func save(_ records: [CKRecord]) { names.formUnion(records.map(\.recordID.recordName)) }
        func delete(_ ids: [CKRecord.ID]) { names.subtract(ids.map(\.recordName)) }
    }

    func testDeleteInFlightNeverRemovesARecordReConfirmedMeanwhile() async throws {
        let (viewModel, service, _) = makeModel()
        let server = FakeServer()
        _ = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        let entry = viewModel.timeEntries[0]
        let name = entry.id.uuidString
        XCTAssertTrue(server.names.contains(name))

        // Delete (tombstone only: nothing is sent outside the push).
        viewModel.deleteTimeEntry(entry)
        XCTAssertTrue(server.names.contains(name), "Deletes are not fired immediately")
        XCTAssertEqual(service.changeTracker!.pendingDeletes, [name])

        // Push A sends the delete and is held mid-flight...
        var release = false
        var deleteStarted = false
        let pushA = Task { @MainActor in
            try await service.pushChangedRecords(
                save: { server.save($0) },
                delete: { ids in
                    deleteStarted = true
                    while !release { await Task.yield() }
                    server.delete(ids)
                })
        }
        while !deleteStarted { await Task.yield() }
        // ...while the same suggestion is re-confirmed (same derived id) and push B starts.
        viewModel.timeEntries.append(entry)
        let pushB = Task { @MainActor in
            try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(server.names.contains(name), "B waits for A: it can't save before A's delete lands")

        release = true
        _ = try await pushA.value
        _ = try await pushB.value
        XCTAssertTrue(server.names.contains(name), "The re-confirmed record is on the server after the late delete")
        XCTAssertTrue(service.changeTracker!.hasBaseline(for: name))
        XCTAssertTrue(service.changeTracker!.pendingDeletes.isEmpty)

        // And a later push changes nothing (no lost or duplicate work).
        let again = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        XCTAssertTrue(again.isEmpty)
    }

    func testRecordDeletedWhileItsSaveIsInFlightIsDeletedNextPush() async throws {
        let (viewModel, service, _) = makeModel()
        let server = FakeServer()
        _ = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        var edited = viewModel.timeEntries[1]
        edited.hours = 7
        edited.modifiedAt = Date()
        viewModel.updateTimeEntry(edited)
        // The save is in flight when the user deletes the entry.
        _ = try await service.pushChangedRecords(save: { records in
            viewModel.deleteTimeEntry(edited)
            server.save(records)
        }, delete: { server.delete($0) })
        XCTAssertFalse(service.changeTracker!.hasBaseline(for: edited.id.uuidString), "No baseline for a tombstoned record")
        _ = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        XCTAssertFalse(server.names.contains(edited.id.uuidString))

        // Re-created later with identical content: still uploaded.
        viewModel.timeEntries.append(edited)
        let saved = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        XCTAssertEqual(saved.map(\.recordID.recordName), [edited.id.uuidString])
        XCTAssertTrue(server.names.contains(edited.id.uuidString))
    }

    func testAccountDeleteWaitsForInFlightPushAndBlocksLaterOnes() async throws {
        let (viewModel, service, _) = makeModel()
        let server = FakeServer()
        var events: [String] = []
        var release = false
        var saveStarted = false
        // Push A is mid-save when the user taps "Delete Account and Data".
        let pushA = Task { @MainActor in
            try await service.pushChangedRecords(
                save: { records in
                    saveStarted = true
                    events.append("save-start")
                    while !release { await Task.yield() }
                    server.save(records)
                    events.append("save-end")
                },
                delete: { server.delete($0) })
        }
        while !saveStarted { await Task.yield() }
        // Push B is already queued behind A.
        let pushB = Task { @MainActor in
            try await service.pushChangedRecords(save: { server.save($0); events.append("B-saved") },
                                                 delete: { server.delete($0) })
        }
        let deletion = Task { @MainActor in
            await service.quiescePushes()
            events.append("quiesced")
            server.names.removeAll()                     // the account's records are deleted
            events.append("deleted")
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(events.contains("quiesced"), "The delete waits for the push in flight")

        release = true
        _ = try await pushA.value
        let sentByB = try await pushB.value
        await deletion.value
        XCTAssertEqual(events, ["save-start", "save-end", "quiesced", "deleted"])
        XCTAssertTrue(sentByB.isEmpty, "A queued push sends nothing once deletion has started")

        // Edits after the delete (or a debounced push) bring nothing back.
        viewModel.addTimeEntry(propertyId: viewModel.properties[0].id, participant: .selfParticipant,
                               category: .repairs, hours: 1, date: Date(), notes: "late")
        service.schedulePush()
        let late = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        XCTAssertTrue(late.isEmpty)
        XCTAssertTrue(server.names.isEmpty, "Nothing saved back after the account delete")
        XCTAssertTrue(service.pushesBlocked)
    }

    func testFailedAccountDeleteUnblocksPushing() async {
        let (viewModel, service, _) = makeModel()
        // iCloud can't be reached (the same on a simulator and on a signed-in device).
        service.accountDeleteOverride = .init(accountAvailable: { false }, fetchRecordIDs: { _ in [] }, deleteBatch: { _ in })
        do {
            try await service.deleteCurrentUserRecords(properties: viewModel.properties, entries: viewModel.timeEntries,
                                                       categories: [], userId: profileId)
            XCTFail("Expected iCloud to be unavailable in tests")
        } catch {}
        XCTAssertFalse(service.pushesBlocked, "The data stayed, so syncing can resume")
    }

    func testDeletingAPropertyAlsoDeletesItsEntriesInICloud() async throws {
        let (viewModel, service, propertyId) = makeModel()
        let server = FakeServer()
        _ = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        let entryNames = viewModel.timeEntries.filter { $0.propertyId == propertyId }.map(\.id.uuidString)
        XCTAssertEqual(entryNames.count, 2)
        let property = viewModel.properties.first { $0.id == propertyId }!

        viewModel.deleteProperty(property)
        XCTAssertEqual(Set(service.changeTracker!.pendingDeletes), Set([propertyId.uuidString] + entryNames))
        _ = try await service.pushChangedRecords(save: { server.save($0) }, delete: { server.delete($0) })
        XCTAssertFalse(server.names.contains(propertyId.uuidString))
        for name in entryNames {
            XCTAssertFalse(server.names.contains(name), "No orphaned entries left to come back on a re-pull")
        }
    }

    func testResetBaselinesReuploadsEverythingButKeepsTombstones() async throws {
        let (_, service, _) = makeModel()
        _ = try await push(service)
        service.changeTracker!.addTombstones(["GONE-1"])
        service.resetSyncBaselines()
        deleted = []
        let saved = try await push(service)
        XCTAssertEqual(saved.count, service.allLocalRecords().count, "Account change / zone gone: everything re-uploads")
        XCTAssertEqual(deleted, ["GONE-1"])
    }

    func testZoneGoneErrorsAreRecognized() {
        XCTAssertTrue(CloudKitSyncService.isZoneGone(CKError(.zoneNotFound)))
        XCTAssertTrue(CloudKitSyncService.isZoneGone(CKError(.userDeletedZone)))
        XCTAssertFalse(CloudKitSyncService.isZoneGone(CKError(.networkFailure)))
        XCTAssertFalse(CloudKitSyncService.isZoneGone(NSError(domain: "x", code: 1)))
    }

    func testProfileDeleteRemovesBaselines() async throws {
        let (_, service, _) = makeModel()
        _ = try await push(service)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.changeTracker!.fileURL.path))
        SyncChangeTracker.removeAll(forUserId: profileId, baseDirectory: trackerDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.changeTracker!.fileURL.path))
    }

    func testLegacyBaselineFileWithoutTombstonesStillLoads() throws {
        let dir = SuggestionStore.directory(forUserId: profileId, baseDirectory: trackerDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"version":1,"fingerprints":{"A":"x"}}"#.utf8).write(to: dir.appendingPathComponent("pushed-fingerprints.json"))
        let tracker = SyncChangeTracker(userId: profileId, baseDirectory: trackerDir)
        XCTAssertTrue(tracker.hasBaseline(for: "A"))
        XCTAssertTrue(tracker.pendingDeletes.isEmpty)
    }

    func testFirstPushSendsEverythingThenOnlyChanges() async throws {
        let (viewModel, service, _) = makeModel()
        let all = service.allLocalRecords()
        let first = try await push(service)
        XCTAssertEqual(Set(first.map(\.recordID.recordName)), Set(all.map(\.recordID.recordName)),
                       "No baseline yet (upgrade from 1.x): behaves like push-all once")

        let second = try await push(service)
        XCTAssertTrue(second.isEmpty, "Nothing changed: nothing sent, so nothing stale can overwrite the server")

        var edited = viewModel.timeEntries[0]
        edited.hours = 3
        edited.modifiedAt = Date()
        viewModel.updateTimeEntry(edited)
        let third = try await push(service)
        XCTAssertEqual(third.map(\.recordID.recordName), [edited.id.uuidString])
        // Records keep the 1.x shape: the full field set, not a partial record.
        let full = CloudKitSyncService.record(for: edited, zoneID: third[0].recordID.zoneID, appUserId: profileId)
        XCTAssertEqual(Set(third[0].allKeys()), Set(full.allKeys()))
    }

    func testPulledEditsAreNotEchoedOrOverwritten() async throws {
        let (viewModel, service, _) = makeModel()
        _ = try await push(service)

        // Another device saved a newer copy of entry 0; this device pulls it.
        var remote = viewModel.timeEntries[0]
        remote.hours = 5
        remote.notes = "Fix sink and faucet"
        remote.modifiedAt = Date().addingTimeInterval(60)
        viewModel.syncDidReceiveEntries([remote])
        service.recordPulledBaselines(properties: [], entries: [remote], categories: [],
                                      deletedRecordNames: [], goalSettingsPulled: false, taxProfilePulled: false)
        XCTAssertEqual(viewModel.timeEntries[0].hours, 5)

        let afterPull = try await push(service)
        XCTAssertTrue(afterPull.isEmpty, "The pulled copy is the server's; this device sends nothing back")
    }

    func testLocalCopyKeptByMergeIsStillPushed() async throws {
        let (viewModel, service, _) = makeModel()
        _ = try await push(service)

        // Edited here after the last push...
        var local = viewModel.timeEntries[1]
        local.hours = 4
        local.modifiedAt = Date().addingTimeInterval(120)
        viewModel.updateTimeEntry(local)
        // ...then an OLDER remote copy (a stale 1.1 device's push-all) arrives. The merge keeps local.
        var stale = local
        stale.hours = 1
        stale.modifiedAt = Date().addingTimeInterval(-3600)
        viewModel.syncDidReceiveEntries([stale])
        service.recordPulledBaselines(properties: [], entries: [stale], categories: [],
                                      deletedRecordNames: [], goalSettingsPulled: false, taxProfilePulled: false)
        XCTAssertEqual(viewModel.timeEntries[1].hours, 4)

        let sent = try await push(service)
        XCTAssertEqual(sent.map(\.recordID.recordName), [local.id.uuidString], "The newer local copy repairs the server")
        XCTAssertEqual(sent.first?["hours"] as? Double, 4)
    }

    func testDeleteForgetsBaselineSoAReAddIsPushed() async throws {
        let (viewModel, service, _) = makeModel()
        _ = try await push(service)
        let entry = viewModel.timeEntries[0]
        service.deleteEntryFromCloud(entry)   // iCloud unavailable in tests: forgets, then returns
        XCTAssertFalse(service.changeTracker!.hasBaseline(for: entry.id.uuidString))
        let sent = try await push(service)
        XCTAssertEqual(sent.map(\.recordID.recordName), [entry.id.uuidString])
    }

    func testFailedSaveKeepsRecordsDirty() async throws {
        let (_, service, _) = makeModel()
        struct Boom: Error {}
        do {
            try await service.pushChangedRecords(save: { _ in throw Boom() }, delete: { _ in })
            XCTFail("Expected the save to throw")
        } catch {}
        let retry = try await push(service)
        XCTAssertEqual(retry.count, service.allLocalRecords().count, "Nothing was marked pushed")
    }

    func testBaselinesPersistAndSettingsTimestampIsIgnored() async throws {
        let (_, service, _) = makeModel()
        _ = try await push(service)
        let reopened = SyncChangeTracker(userId: profileId, baseDirectory: trackerDir)
        XCTAssertTrue(reopened.changedRecords(service.allLocalRecords()).isEmpty,
                      "Baselines survive relaunch; GoalSettings/TaxProfile modifiedAt=now is not a change")
    }
}

// MARK: - No digest

final class NoCalendarDigestTests: XCTestCase {
    func testCalendarDraftsNeverBecomeANotification() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 19))!
        let property = RentalProperty(name: "Oak", address: "1 Oak", propertyType: .ltr)
        let context = EngagementContext(
            now: now,
            taxYear: 2026,
            properties: [property],
            timeEntries: [TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .repairs,
                                    hours: 2, date: now.addingTimeInterval(-86_400))],
            calendarDraftCount: 5,
            isTimerRunning: false,
            timerStartTime: nil,
            notificationPermission: .authorized,
            recentDismissals: [],
            isProUser: false
        )
        let service = EngagementIntelligenceService()
        XCTAssertNotEqual(service.recommendation(for: context, calendar: calendar).surface, .notification)
        XCTAssertNil(EngagementNotificationScheduler(service: service).plan(for: context))
        XCTAssertTrue(EngagementNotificationScheduler.retiredReasons.contains(.calendarDraftsReady))
    }
}
