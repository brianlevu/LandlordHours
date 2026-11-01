import XCTest
import UserNotifications
@testable import LandlordHours

/// 2.3 package D: pace and care nudges. The pure rules (`NudgePolicy`), the scheduler against a
/// fake notification center (quiet hours, cancel when off, relaunch, dedupe, never without an
/// opt-in), the settings model and the tap routing. Wording is checked by key shape and banned
/// words, never by pinning the English.

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private let pine = NudgeRental(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Pine Cabin")
private let lake = NudgeRental(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Lake House")

private func facts(now: Date = date(2026, 11, 4), hours: Double = 420, target: Double = 750,
                   care: [CareDueItem] = [], unlocked: Bool = true) -> NudgeFacts {
    NudgeFacts(now: now, calendar: utc, rentals: [pine, lake], yearHours: hours, targetHours: target,
               careItems: care, carePlanUnlocked: unlocked)
}

private func gutters(_ rental: NudgeRental = pine, id: String = "gutters", due: Date = date(2026, 11, 1)) -> CareDueItem {
    CareDueItem(id: id, rentalID: rental.id, title: "Clear the gutters", due: due)
}

private func allOn() -> NudgeSettings {
    var s = NudgeSettings()
    s.weeklyPace = true; s.behindPace = true; s.yearEnd = true; s.carePlan = true
    return s
}

final class NudgePolicyTests: XCTestCase {

    // MARK: Opt-in

    func testEverythingIsOffByDefault() {
        let s = NudgeSettings()
        XCTAssertFalse(s.anyKindOn)
        XCTAssertEqual(s.quietStartHour, 20)
        XCTAssertEqual(s.quietEndHour, 8)
        let out = NudgePolicy.plan(settings: s, facts: facts(care: [gutters()]), ledger: [])
        XCTAssertTrue(out.plans.isEmpty, "nothing is planned until a kind is on")
    }

    func testOnlyTheKindsTheyTurnedOnAreScheduled() {
        for kind in NudgeKind.allCases {
            var s = NudgeSettings()
            s.set(kind, true)
            let now = date(2026, 12, 10)
            let out = NudgePolicy.plan(settings: s, facts: facts(now: now, hours: 600, care: [gutters()]), ledger: [])
            XCTAssertFalse(out.plans.isEmpty, "\(kind) should plan something")
            XCTAssertTrue(out.plans.allSatisfy { $0.kind == kind }, "\(kind) switch leaked another kind")
        }
    }

    func testNoDataMeansNoPaceNudge() {
        var s = allOn(); s.carePlan = false
        let out = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 25), hours: 0), ledger: [])
        XCTAssertTrue(out.plans.isEmpty, "a nudge is always about the person's own hours")
    }

    // MARK: Weekly

    func testWeeklyGoesOutSundayAtSixInTheNextTwoWeeks() {
        var s = NudgeSettings(); s.weeklyPace = true
        let out = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 4)), ledger: [])
        XCTAssertEqual(out.plans.map(\.fireDate), [date(2026, 11, 8, 18), date(2026, 11, 15, 18)])
        XCTAssertTrue(out.plans.allSatisfy { $0.rentalID == nil })
    }

    func testWeeklyNumbersAreTheirOwn() {
        let f = facts(now: date(2026, 11, 4), hours: 420)
        XCTAssertEqual(NudgePolicy.wholeHours(420.9), 420)
        // 330h left over 57 days is 9 weeks (rounded up): 37h a week, rounded up.
        XCTAssertEqual(NudgePolicy.hoursPerWeek(f), 37)
        XCTAssertEqual(NudgePolicy.hoursPerWeek(facts(hours: 800)), 0, "a met goal asks for no more hours")
    }

    // MARK: Quiet hours

    func testNoPlanEverLandsInQuietHours() {
        let now = date(2026, 12, 10, 9)
        for start in 0..<24 {
            for end in 0..<24 {
                var s = allOn()
                s.quietStartHour = start; s.quietEndHour = end
                let out = NudgePolicy.plan(settings: s, facts: facts(now: now, hours: 500, care: [gutters()]), ledger: [])
                for plan in out.plans {
                    XCTAssertFalse(s.isQuiet(plan.fireDate, calendar: utc), "quiet \(start)-\(end): \(plan.kind) at \(plan.fireDate)")
                    XCTAssertGreaterThan(plan.fireDate, now)
                }
            }
        }
    }

    func testAWeeklyNoteInQuietHoursWaitsForTheWindowToEnd() {
        var s = NudgeSettings(); s.weeklyPace = true
        s.quietStartHour = 17; s.quietEndHour = 9
        let out = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 4)), ledger: [])
        XCTAssertEqual(out.plans.first?.fireDate, date(2026, 11, 9, 9), "Sunday 6 PM moves to Monday 9 AM")
    }

    func testDefaultQuietHoursKeepTheDaytimeSlots() {
        var s = allOn(); s.behindPace = false
        let out = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 4), care: [gutters()]), ledger: [])
        XCTAssertTrue(out.plans.contains { $0.kind == .weeklyPace && $0.fireDate == date(2026, 11, 8, 18) })
        XCTAssertTrue(out.plans.contains { $0.kind == .carePlan && utc.component(.hour, from: $0.fireDate) == 10 })
    }

    func testQuietStartEqualEndMeansNoQuietHours() {
        var s = NudgeSettings(); s.quietStartHour = 5; s.quietEndHour = 5
        XCTAssertFalse(s.isQuiet(date(2026, 11, 4, 5), calendar: utc))
    }

    // MARK: One a day, a few a month

    func testAtMostOneNudgeADay() {
        let now = date(2026, 12, 10)
        let out = NudgePolicy.plan(settings: allOn(), facts: facts(now: now, hours: 500, care: [gutters()]), ledger: [])
        let days = out.plans.map { utc.startOfDay(for: $0.fireDate) }
        XCTAssertEqual(days.count, Set(days).count, "two nudges on one day")
    }

    func testPaceAndCareAreNeverOneNotification() {
        let out = NudgePolicy.plan(settings: allOn(), facts: facts(now: date(2026, 11, 4), care: [gutters()]), ledger: [])
        for plan in out.plans {
            if plan.kind.isCare {
                XCTAssertNotNil(plan.rentalID)
                XCTAssertNil(plan.body.rangeOfCharacter(from: .decimalDigits), "care copy never carries hours: \(plan.body)")
            } else {
                XCTAssertNil(plan.rentalID)
            }
        }
        let kinds = Set(out.plans.map(\.kind))
        XCTAssertTrue(kinds.contains(.weeklyPace) && kinds.contains(.carePlan))
        // A Sunday weekly note and a care item that is due on it go out on different days.
        let weekly = out.plans.filter { $0.kind == .weeklyPace }.map { utc.startOfDay(for: $0.fireDate) }
        let care = out.plans.filter { $0.kind == .carePlan }.map { utc.startOfDay(for: $0.fireDate) }
        XCTAssertTrue(Set(weekly).isDisjoint(with: care))
    }

    func testYearEndBeatsWeeklyOnTheSameSunday() {
        var s = NudgeSettings(); s.yearEnd = true; s.weeklyPace = true
        let out = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 12, 14), hours: 600), ledger: [])
        let dec20 = out.plans.filter { utc.isDate($0.fireDate, inSameDayAs: date(2026, 12, 20)) }
        XCTAssertEqual(dec20.map(\.kind), [.yearEnd])
    }

    func testMonthlyCapStopsTheSixthNudge() {
        var s = NudgeSettings(); s.weeklyPace = true
        let sent = (0..<NudgePolicy.monthlyCap).map {
            NudgeLedgerEntry(kind: .carePlan, itemID: "x\($0)", fireDate: date(2026, 11, 1 + $0, 10))
        }
        let out = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 7, 12)), ledger: sent)
        XCTAssertTrue(out.plans.allSatisfy { utc.component(.month, from: $0.fireDate) != 11 }, "cap reached for November")
    }

    // MARK: Behind pace

    func testBehindPaceFiresOnceThenWaitsUntilCaughtUp() {
        var s = NudgeSettings(); s.behindPace = true
        let behind = facts(now: date(2026, 9, 1), hours: 300)
        let first = NudgePolicy.plan(settings: s, facts: behind, ledger: [])
        XCTAssertEqual(first.plans.map(\.kind), [.behindPace])
        // Later, the nudge has gone out: still behind, so no second one.
        let later = facts(now: date(2026, 9, 10), hours: 310)
        let second = NudgePolicy.plan(settings: s, facts: later, ledger: first.ledger)
        XCTAssertTrue(second.plans.isEmpty, "once only while behind")
        // Caught up clears it; falling behind again may fire again.
        let caughtUp = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 10, 1), hours: 700), ledger: first.ledger)
        XCTAssertFalse(caughtUp.ledger.contains { $0.kind == .behindPace })
        let again = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 20), hours: 300), ledger: caughtUp.ledger)
        XCTAssertEqual(again.plans.map(\.kind), [.behindPace])
    }

    func testNotBehindEarlyInTheYearOrWithNoHours() {
        var s = NudgeSettings(); s.behindPace = true
        XCTAssertTrue(NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 2, 1), hours: 5), ledger: []).plans.isEmpty)
        XCTAssertTrue(NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 9, 1), hours: 0), ledger: []).plans.isEmpty)
        XCTAssertTrue(NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 9, 1), hours: 520), ledger: []).plans.isEmpty, "on pace")
    }

    // MARK: Care

    func testCareReadsTheSeamOneItemAtATime() {
        var s = NudgeSettings(); s.carePlan = true
        let items = [gutters(pine, id: "b", due: date(2026, 11, 3)), gutters(lake, id: "a", due: date(2026, 11, 1))]
        let out = NudgePolicy.plan(settings: s, facts: facts(care: items), ledger: [])
        XCTAssertEqual(out.plans.count, 1)
        XCTAssertEqual(out.plans.first?.rentalID, lake.id, "the earliest due item goes first")
        XCTAssertEqual(out.plans.first?.title, "Lake House")
    }

    func testTheSameCareItemIsNotNudgedAgainWithinThirtyDays() {
        var s = NudgeSettings(); s.carePlan = true
        let item = gutters()
        let first = NudgePolicy.plan(settings: s, facts: facts(now: date(2026, 11, 4), care: [item]), ledger: [])
        let fire = first.plans[0].fireDate
        let soon = NudgePolicy.plan(settings: s, facts: facts(now: fire.addingTimeInterval(86_400 * 5), care: [item]), ledger: first.ledger)
        XCTAssertTrue(soon.plans.isEmpty)
        let late = NudgePolicy.plan(settings: s, facts: facts(now: fire.addingTimeInterval(86_400 * 31), care: [item]), ledger: first.ledger)
        XCTAssertEqual(late.plans.count, 1)
    }

    func testCareNeedsThePlanAndTheStubSeamSendsNothing() {
        var s = NudgeSettings(); s.carePlan = true
        XCTAssertTrue(NudgePolicy.plan(settings: s, facts: facts(care: [gutters()], unlocked: false), ledger: []).plans.isEmpty)
        XCTAssertTrue(CareDueSourceStub().dueItems(for: pine.id, on: Date()).isEmpty)
        XCTAssertTrue(NudgePolicy.plan(settings: s, facts: facts(care: []), ledger: []).plans.isEmpty)
    }

    // MARK: Dedupe

    func testRebuildingTwiceMakesTheSamePlans() {
        let f = facts(now: date(2026, 11, 4), care: [gutters()])
        let first = NudgePolicy.plan(settings: allOn(), facts: f, ledger: [])
        let second = NudgePolicy.plan(settings: allOn(), facts: f, ledger: first.ledger)
        XCTAssertEqual(first.plans, second.plans, "future ledger entries are remade, not counted twice")
        XCTAssertEqual(Set(first.plans.map(\.id)).count, first.plans.count, "ids are unique")
        XCTAssertTrue(first.plans.allSatisfy { $0.id.hasPrefix(NudgePolicy.idPrefix) })
    }

    // MARK: Copy

    func testCopyUsesNoBannedWords() {
        let texts = [NudgeCopy.weekly(hours: 420, target: 750, perWeek: 38), NudgeCopy.weekly(hours: 800, target: 750, perWeek: 0),
                     NudgeCopy.behind(hoursBehind: 24, target: 750), NudgeCopy.yearEnd(year: 2026, hours: 612),
                     NudgeCopy.care(rental: "Pine Cabin", item: "Clear the gutters")]
        let banned = ["qualif", "audit", "evidence", "proof", "compliance", "streak", "!"]
        for text in texts {
            for word in banned {
                XCTAssertFalse((text.title + " " + text.body).lowercased().contains(word), "\(word) in \(text)")
            }
            XCTAssertFalse(text.body.contains("'"), "straight apostrophe")
            XCTAssertFalse(text.body.isEmpty)
        }
    }
}

// MARK: - The scheduler, against a fake center

final class FakeNudgeCenter: CaptureNotificationCenter, @unchecked Sendable {
    var pending: [String: UNNotificationRequest] = [:]
    var deliver = true
    private(set) var addCalls = 0

    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }
    func add(_ request: UNNotificationRequest) async throws {
        addCalls += 1
        pending[request.identifier] = request   // the system replaces a request with the same id
    }
    func removePending(identifiers: [String]) { identifiers.forEach { pending[$0] = nil } }
    func removeDelivered(identifiers: [String]) {}
    func canDeliver() async -> Bool { deliver }
}

@MainActor
final class NudgeSchedulerTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!
    private var center: FakeNudgeCenter!
    private var clock = date(2026, 11, 4)
    private var care: [CareDueItem] = []
    private var scope = "profile-a"

    override func setUp() async throws {
        suiteName = "nudge-tests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
        center = FakeNudgeCenter()
        clock = date(2026, 11, 4)
        care = []
        scope = "profile-a"
    }

    override func tearDown() async throws {
        suite.removePersistentDomain(forName: suiteName)
        Analytics.testSpy = nil
    }

    private func makeStore() -> NudgeSettingsStore {
        NudgeSettingsStore(defaults: suite, scoped: { [unowned self] in "\(self.scope).\($0)" })
    }

    private func makeScheduler(store: NudgeSettingsStore? = nil) -> NudgeScheduler {
        NudgeScheduler(center: center, store: store ?? makeStore(), now: { [unowned self] in self.clock }, calendar: { utc },
                       facts: { [unowned self] now, cal in
                           NudgeFacts(now: now, calendar: cal, rentals: [pine, lake], yearHours: 420, targetHours: 750,
                                      careItems: self.care, carePlanUnlocked: true)
                       },
                       profileID: { [unowned self] in self.scope })
    }

    private func turnOn(_ kinds: NudgeKind..., quiet: (Int, Int)? = nil, store: NudgeSettingsStore? = nil) {
        let store = store ?? makeStore()
        var s = store.load()
        kinds.forEach { s.set($0, true) }
        if let quiet { s.quietStartHour = quiet.0; s.quietEndHour = quiet.1 }
        store.save(s)
    }

    func testNeverFiresWhenNotOptedIn() async {
        care = [gutters()]
        let scheduler = makeScheduler()
        await scheduler.rebuild(reason: "launch")
        XCTAssertEqual(center.addCalls, 0)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testNothingScheduledWithoutNotificationPermission() async {
        turnOn(.weeklyPace)
        center.deliver = false
        await makeScheduler().rebuild(reason: "launch")
        XCTAssertEqual(center.addCalls, 0)
    }

    func testScheduledRequestsCarryProfileKindAndCalendarTrigger() async throws {
        care = [gutters()]
        turnOn(.weeklyPace, .carePlan)
        await makeScheduler().rebuild(reason: "launch")
        XCTAssertFalse(center.pending.isEmpty)
        for request in center.pending.values {
            XCTAssertTrue(request.identifier.hasPrefix(NudgePolicy.idPrefix))
            XCTAssertEqual(request.content.userInfo[NotificationPayload.profileIdKey] as? String, "profile-a")
            XCTAssertEqual(request.content.categoryIdentifier, NudgeNotification.category)
            XCTAssertEqual(request.content.userInfo[NotificationPayload.destinationKey] as? String, "home")
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertFalse(trigger.repeats)
        }
        let carePlans = center.pending.values.filter { $0.content.threadIdentifier == NudgeNotification.careThread }
        let paces = center.pending.values.filter { $0.content.threadIdentifier == NudgeNotification.paceThread }
        XCTAssertEqual(carePlans.count, 1)
        XCTAssertEqual(carePlans.first?.content.userInfo[NudgeNotification.rentalIDKey] as? String, pine.id.uuidString)
        XCTAssertEqual(paces.count, 2)
    }

    func testQuietHoursAreRespectedInWhatTheSystemReceives() async throws {
        turnOn(.weeklyPace, quiet: (16, 9))
        await makeScheduler().rebuild(reason: "launch")
        var s = NudgeSettings(); s.quietStartHour = 16; s.quietEndHour = 9
        for request in center.pending.values {
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            let fire = try XCTUnwrap(utc.date(from: trigger.dateComponents))
            XCTAssertFalse(s.isQuiet(fire, calendar: utc))
            XCTAssertEqual(utc.component(.hour, from: fire), 9)
        }
    }

    func testTurningEverythingOffCancelsEveryPendingNudge() async {
        care = [gutters()]
        turnOn(.weeklyPace, .carePlan)
        let scheduler = makeScheduler()
        await scheduler.rebuild(reason: "launch")
        XCTAssertFalse(center.pending.isEmpty)
        // Something else is pending too: it must survive.
        center.pending["capture.other"] = UNNotificationRequest(identifier: "capture.other", content: UNMutableNotificationContent(), trigger: nil)
        var s = makeStore().load()
        s.weeklyPace = false; s.carePlan = false
        makeStore().save(s)
        await scheduler.rebuild(reason: "settings")
        XCTAssertEqual(Set(center.pending.keys), ["capture.other"])
    }

    func testTurningOneKindOffCancelsOnlyThatKind() async {
        care = [gutters()]
        turnOn(.weeklyPace, .carePlan)
        let scheduler = makeScheduler()
        await scheduler.rebuild(reason: "launch")
        var s = makeStore().load(); s.carePlan = false; makeStore().save(s)
        await scheduler.rebuild(reason: "settings")
        XCTAssertFalse(center.pending.isEmpty)
        XCTAssertTrue(center.pending.values.allSatisfy { $0.content.threadIdentifier == NudgeNotification.paceThread })
    }

    func testSurvivesRelaunch() async {
        care = [gutters()]
        turnOn(.weeklyPace, .carePlan)
        await makeScheduler().rebuild(reason: "launch")
        let before = Set(center.pending.keys)
        // Relaunch: a new scheduler and a new store on the same defaults.
        let relaunched = makeScheduler(store: makeStore())
        XCTAssertEqual(makeStore().load().enabledKinds, [.weeklyPace, .carePlan], "choices survive")
        await relaunched.rebuild(reason: "launch")
        XCTAssertEqual(Set(center.pending.keys), before, "the same requests, none lost, none doubled")
    }

    func testRebuildingManyTimesNeverDoublesARequest() async {
        care = [gutters()]
        turnOn(.weeklyPace, .carePlan)
        let scheduler = makeScheduler()
        async let a: Void = scheduler.rebuild(reason: "foreground")
        async let b: Void = scheduler.rebuild(reason: "background")
        async let c: Void = scheduler.rebuild(reason: "time-zone")
        _ = await (a, b, c)
        await scheduler.rebuild(reason: "launch")
        let ids = Array(center.pending.keys)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids.count, 3)
    }

    func testAProfileSwitchNeverReadsTheOtherProfilesChoices() async {
        turnOn(.weeklyPace)
        scope = "profile-b"
        let scheduler = makeScheduler()
        await scheduler.rebuild(reason: "profile")
        XCTAssertTrue(center.pending.isEmpty, "profile B never opted in")
        scope = "profile-a"
        await makeScheduler().rebuild(reason: "profile")
        XCTAssertFalse(center.pending.isEmpty)
        scope = "profile-b"
        await makeScheduler().rebuild(reason: "profile")
        XCTAssertTrue(center.pending.isEmpty, "switching away clears the first profile's nudges")
    }

    func testAnalyticsCarryOnlyTheKind() async {
        var seen: [(String, [String: Any])] = []
        Analytics.testSpy = { seen.append(($0, $1)) }
        turnOn(.weeklyPace)
        let scheduler = makeScheduler()
        await scheduler.rebuild(reason: "launch")
        let scheduled = seen.filter { $0.0 == "nudge_scheduled" }
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertTrue(scheduled.allSatisfy { ($0.1["kind"] as? String) == "weeklyPace" && $0.1.count == 1 })
        seen.removeAll()
        await scheduler.rebuild(reason: "foreground")
        XCTAssertTrue(seen.filter { $0.0 == "nudge_scheduled" }.isEmpty, "an unchanged plan is not scheduled twice")
    }

    func testPastNudgesCountTowardTheDailyCapAcrossRebuilds() async {
        turnOn(.weeklyPace)
        let scheduler = makeScheduler()
        await scheduler.rebuild(reason: "launch")           // Wed Nov 4: Nov 8 and Nov 15 pending
        clock = date(2026, 11, 8, 19)                         // the Nov 8 note has gone out
        care = [gutters()]
        turnOn(.carePlan)
        await scheduler.rebuild(reason: "foreground")
        let careDays = center.pending.values.filter { $0.content.threadIdentifier == NudgeNotification.careThread }.count
        XCTAssertEqual(careDays, 1)
        let ids = center.pending.keys.filter { $0.contains("2026-11-08") }
        XCTAssertTrue(ids.isEmpty, "a sent nudge is not scheduled again")
    }

    // MARK: Settings model

    private final class FakeAuthorizer: NudgeAuthorizing {
        var current: UNAuthorizationStatus
        var grantsOnRequest: Bool
        private(set) var requests = 0
        init(_ status: UNAuthorizationStatus, grants: Bool = true) { current = status; grantsOnRequest = grants }
        func status() async -> UNAuthorizationStatus { current }
        func request() async -> Bool {
            requests += 1
            current = grantsOnRequest ? .authorized : .denied
            return grantsOnRequest
        }
    }

    func testTurningAKindOnAsksForPermissionOnceAndSchedules() async {
        let auth = FakeAuthorizer(.notDetermined)
        var rebuilds: [String] = []
        let model = RemindersSettingsModel(store: makeStore(), authorizer: auth, rebuild: { rebuilds.append($0) })
        XCTAssertTrue(model.settings.enabledKinds.isEmpty)
        await model.set(.weeklyPace, on: true)
        XCTAssertEqual(auth.requests, 1)
        XCTAssertTrue(model.settings.weeklyPace)
        XCTAssertTrue(makeStore().load().weeklyPace, "saved")
        await model.set(.yearEnd, on: true)
        XCTAssertEqual(auth.requests, 1, "asked once")
        XCTAssertEqual(rebuilds, ["settings", "settings"])
    }

    func testDeniedPermissionLeavesTheSwitchOffAndSaysSo() async {
        let auth = FakeAuthorizer(.notDetermined, grants: false)
        let model = RemindersSettingsModel(store: makeStore(), authorizer: auth, rebuild: { _ in })
        await model.set(.carePlan, on: true)
        XCTAssertFalse(model.settings.carePlan)
        XCTAssertTrue(model.permissionBlocked)
        XCTAssertFalse(makeStore().load().carePlan)
    }

    func testTurningAKindOffReportsItAndRebuilds() async {
        var seen: [(String, [String: Any])] = []
        Analytics.testSpy = { seen.append(($0, $1)) }
        var rebuilds = 0
        let model = RemindersSettingsModel(store: makeStore(), authorizer: FakeAuthorizer(.authorized), rebuild: { _ in rebuilds += 1 })
        await model.set(.behindPace, on: true)
        await model.set(.behindPace, on: false)
        XCTAssertEqual(seen.filter { $0.0 == "nudge_disabled" }.compactMap { $0.1["kind"] as? String }, ["behindPace"])
        XCTAssertEqual(rebuilds, 2)
        XCTAssertFalse(makeStore().load().behindPace)
    }

    func testQuietHoursAreSavedAndReadable() async {
        let model = RemindersSettingsModel(store: makeStore(), authorizer: FakeAuthorizer(.authorized), rebuild: { _ in })
        await model.setQuietHours(start: 21, end: 7)
        XCTAssertEqual(makeStore().load().quietStartHour, 21)
        XCTAssertEqual(makeStore().load().quietEndHour, 7)
        XCTAssertTrue(model.quietHoursLabel().contains("–"))
    }

    // MARK: Tap routing

    func testTappingANudgeOpensTodayAndHandsOverTheRental() {
        var seen: [(String, [String: Any])] = []
        Analytics.testSpy = { seen.append(($0, $1)) }
        let router = NotificationActionRouter(host: AppModelHost.shared)
        let info: [AnyHashable: Any] = [
            NudgeNotification.kindKey: "carePlan",
            NudgeNotification.rentalIDKey: pine.id.uuidString,
            NotificationPayload.destinationKey: "home",
            NotificationPayload.profileIdKey: UserScope.userId ?? ""
        ]
        let outcome = router.routeNudge(NotificationActionRequest(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                                                  categoryIdentifier: NudgeNotification.category, userInfo: info))
        XCTAssertEqual(outcome, .navigated(.home))
        XCTAssertEqual(UserDefaults.standard.string(forKey: NudgeNotification.pendingRentalKey), pine.id.uuidString)
        XCTAssertEqual(seen.filter { $0.0 == "nudge_opened" }.compactMap { $0.1["kind"] as? String }, ["carePlan"])
        UserDefaults.standard.removeObject(forKey: NudgeNotification.pendingRentalKey)
    }

    func testANudgeFromAnotherProfileIsIgnored() {
        let router = NotificationActionRouter(host: AppModelHost.shared)
        let info: [AnyHashable: Any] = [
            NudgeNotification.kindKey: "weeklyPace",
            NotificationPayload.destinationKey: "home",
            NotificationPayload.profileIdKey: "someone-else"
        ]
        let outcome = router.routeNudge(NotificationActionRequest(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                                                  categoryIdentifier: NudgeNotification.category, userInfo: info))
        XCTAssertEqual(outcome, .rejectedWrongProfile)
    }
}
