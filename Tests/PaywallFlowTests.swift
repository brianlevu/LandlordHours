import XCTest
import UserNotifications
@testable import LandlordHours

// Package A (2.3 pricing): the paywall model's trial offer, the plan moments the shell shows, the
// words for each plan, the day-12 notification, and the free plan's view-only rentals at save.

// MARK: - The paywall model, trial first

@MainActor
private final class TrialStore: ProPurchasing {
    var plan: Plan = .free
    var isPro: Bool { plan.hasProAccess }
    var isPurchaseInFlight = false
    var proDisplayPrice: String? = "$49.99"
    var introTrialDays: Int? = 14
    var outcome: SubscriptionManager.PurchaseOutcome = .purchased
    var purchaseStartsTrial = true

    func loadProducts() async {}
    func purchasePro(lateOutcome: @escaping @MainActor (SubscriptionManager.PurchaseOutcome) -> Void) async -> SubscriptionManager.PurchaseOutcome {
        if outcome == .purchased {
            let now = Date()
            let sub = Plan.Subscription(startedAt: now, expiresAt: now.addingTimeInterval(14 * 86_400), willAutoRenew: true,
                                        inGracePeriod: false, originalTransactionID: 42)
            plan = purchaseStartsTrial ? .trial(sub) : .pro(sub)
            introTrialDays = nil
        }
        return outcome
    }
    func restorePurchases() async -> Bool { false }
}

@MainActor
final class PaywallTrialFlowTests: XCTestCase {
    func testAnEligibleFreeUserIsOfferedTheTrial() async {
        let store = TrialStore()
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: store)
        await model.start()
        XCTAssertEqual(model.offer, .freeTrial(days: 14))
        XCTAssertEqual(model.priceDisplay?.buttonTitle, "Start free trial")
        XCTAssertEqual(model.priceDisplay?.billed, "$49.99", "StoreKit's price, as given")
    }

    func testATrialAlreadyUsedSaysSubscribe() async {
        let store = TrialStore()
        store.introTrialDays = nil
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: store)
        await model.start()
        XCTAssertEqual(model.offer, .subscribe)
        XCTAssertNil(model.offeredTrialDays, "no timeline without a trial")
        XCTAssertEqual(model.priceDisplay?.buttonTitle, "Subscribe")
    }

    func testFoundingBuyersNeverSeeATrial() async {
        let store = TrialStore()
        store.plan = .founding(alsoSubscribed: false)
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: store)
        await model.start()
        XCTAssertEqual(model.offer, .owned)
        XCTAssertNil(model.offeredTrialDays)
        XCTAssertEqual(PlanCopy.title(store.plan), "Pro for life")
        XCTAssertFalse(PlanCopy.showsManage(store.plan))
        XCTAssertNil(PlanCopy.alsoSubscribedLine(store.plan))
    }

    func testAFoundingBuyerWhoAlsoSubscribedGetsOneLineToManageSubscriptions() {
        let plan = Plan.founding(alsoSubscribed: true)
        XCTAssertTrue(PlanCopy.showsManage(plan))
        XCTAssertNotNil(PlanCopy.alsoSubscribedLine(plan))
        XCTAssertEqual(PlanCopy.tag(plan), "Pro for life")
    }

    func testStartingTheTrialBecomesTheTrialStartMoment() async {
        let store = TrialStore()
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        let bought = await model.buy()
        XCTAssertTrue(bought)
        XCTAssertEqual(model.phase, .success)
        XCTAssertTrue(model.startedTrial, "the page becomes the trial start (p2)")
        XCTAssertEqual(model.offer, .freeTrial(days: 14), "the success keeps the offer the person saw")
    }

    func testSubscribingWithoutATrialShowsSuccessNotTheTrialStart() async {
        let store = TrialStore()
        store.introTrialDays = nil
        store.purchaseStartsTrial = false
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        await model.buy()
        XCTAssertEqual(model.phase, .success)
        XCTAssertFalse(model.startedTrial)
        XCTAssertEqual(model.offer, .subscribe)
    }

    func testTheTimelineIsDatedFromTodayAndTheTrialLength() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
        let steps = PaywallView.timeline(now: now, trialDays: 14, price: "$49.99", calendar: calendar)
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps[0].reached)
        XCTAssertFalse(steps[1].reached || steps[2].reached)
        XCTAssertTrue(steps[1].title.hasPrefix("In 12 days"), steps[1].title)
        XCTAssertTrue(steps[2].title.hasPrefix("In 14 days"), steps[2].title)
        XCTAssertEqual(steps[2].text, "Pro renews at $49.99 a year. Cancel at least a day before and you pay nothing.")
        XCTAssertFalse(steps.contains { $0.title.lowercased().contains("free") }, "the timeline never sells 'free'")
    }

    func testTheTitleNeverSaysFree() {
        for key in ["paywall.title.trial", "paywall.title.subscribe"] {
            let title = String(localized: String.LocalizationValue(key), table: "Pricing")
            XCTAssertFalse(title.lowercased().contains("free"), title)
        }
    }
}

// MARK: - Plan moments (day 12, then the pick)

final class PlanMomentTests: XCTestCase {
    private let trial = Plan.trial(.init(startedAt: Date(), expiresAt: Date().addingTimeInterval(2 * 86_400), willAutoRenew: true,
                                         inGracePeriod: false, originalTransactionID: 9))

    func testDay12ComesFirstThenThePick() {
        XCTAssertEqual(PlanMoment.next(plan: trial, shouldShowDay12: true, needsPick: false, lastPlanKind: nil)?.id, "day12.9")
        XCTAssertNil(PlanMoment.next(plan: trial, shouldShowDay12: false, needsPick: false, lastPlanKind: "trial"))
        XCTAssertEqual(PlanMoment.next(plan: .free, shouldShowDay12: false, needsPick: true, lastPlanKind: "trial"), .pickFree(.trialEnded))
        XCTAssertEqual(PlanMoment.next(plan: .free, shouldShowDay12: false, needsPick: true, lastPlanKind: "pro"), .pickFree(.proEnded))
        XCTAssertEqual(PlanMoment.next(plan: .free, shouldShowDay12: false, needsPick: true, lastPlanKind: nil), .pickFree(.unknown))
        XCTAssertNil(PlanMoment.next(plan: .free, shouldShowDay12: true, needsPick: false, lastPlanKind: nil), "no reminder without a trial")
    }
}

// MARK: - The day-12 notification

@MainActor
private final class FakeReminderCenter: TrialReminderCenter {
    var allowed = true
    var pending: [String: UNNotificationRequest] = [:]
    func canSchedule() async -> Bool { allowed }
    func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }
    func removePending(_ identifiers: [String]) { identifiers.forEach { pending[$0] = nil } }
    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
}

@MainActor
final class TrialReminderSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func trial(renews: Bool, id: UInt64 = 5, daysLeft: Double = 14) -> Plan {
        .trial(.init(startedAt: now, expiresAt: now.addingTimeInterval(daysLeft * 86_400), willAutoRenew: renews,
                     inGracePeriod: false, originalTransactionID: id))
    }

    func testSchedulesTwoDaysBeforeTheRenewalWhileItWillRenew() async {
        let center = FakeReminderCenter()
        let scheduler = TrialReminderScheduler(center: center, clock: { self.now })
        await scheduler.sync(plan: trial(renews: true), price: "$49.99")
        let request = center.pending[TrialReminderScheduler.identifier(5)]
        XCTAssertNotNil(request)
        let fire = (request?.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        let expected = TrialSchedule.reminderDate(renewal: now.addingTimeInterval(14 * 86_400))
        XCTAssertEqual(fire.map { Int($0.timeIntervalSince(expected)) }, 0)
        XCTAssertTrue(request?.content.body.contains("$49.99") == true, "StoreKit's price in the words")
    }

    func testCancelledWhenAutoRenewIsOffOrTheTrialEnds() async {
        let center = FakeReminderCenter()
        let scheduler = TrialReminderScheduler(center: center, clock: { self.now })
        await scheduler.sync(plan: trial(renews: true), price: nil)
        XCTAssertEqual(center.pending.count, 1)
        await scheduler.sync(plan: trial(renews: false), price: nil)
        XCTAssertTrue(center.pending.isEmpty, "auto-renew off: no reminder")
        await scheduler.sync(plan: trial(renews: true), price: nil)
        await scheduler.sync(plan: .free, price: nil)
        XCTAssertTrue(center.pending.isEmpty, "trial over: no reminder")
        await scheduler.sync(plan: trial(renews: true), price: nil)
        await scheduler.sync(plan: .founding(alsoSubscribed: true), price: nil)
        XCTAssertTrue(center.pending.isEmpty, "founding: no billing reminder")
    }

    func testNothingPastTheReminderDayAndNoPromptWithoutPermission() async {
        let center = FakeReminderCenter()
        let scheduler = TrialReminderScheduler(center: center, clock: { self.now })
        await scheduler.sync(plan: trial(renews: true, daysLeft: 1), price: nil)
        XCTAssertTrue(center.pending.isEmpty, "the reminder day has passed: the sheet covers it")
        center.allowed = false
        await scheduler.sync(plan: trial(renews: true), price: nil)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testANewTrialReplacesTheOldRequest() async {
        let center = FakeReminderCenter()
        let scheduler = TrialReminderScheduler(center: center, clock: { self.now })
        await scheduler.sync(plan: trial(renews: true, id: 1), price: nil)
        await scheduler.sync(plan: trial(renews: true, id: 2), price: nil)
        XCTAssertEqual(Set(center.pending.keys), [TrialReminderScheduler.identifier(2)])
    }
}

// MARK: - View-only rentals at save (acceptance 2)

@MainActor
final class ViewOnlyRentalSaveTests: CaptureTestCase {
    private var vm: AppViewModel!
    private var pine: UUID!
    private var oak: UUID!

    override func setUp() async throws {
        try await super.setUp()
        EntitlementStore.shared.setFoundingFlag(false)
        UserDefaults.standard.removeObject(forKey: UserScope.key("freeRental.v1"))
        vm = AppViewModel()
        vm.suppressCelebrations = true
        vm.addProperty(name: "Pine Cabin", address: "", type: .ltr)
        vm.addProperty(name: "Oak Street Duplex", address: "", type: .ltr)
        pine = vm.properties[0].id
        oak = vm.properties[1].id
        // Pine Cabin is the most used: it is the free rental by default.
        vm.timeEntries = [TimeEntry(propertyId: pine, participant: .selfParticipant, category: .repairs, hours: 20, date: Date(), notes: ""),
                          TimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 5, date: Date(), notes: "")]
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: UserScope.key("freeRental.v1"))
        EntitlementStore.shared.setFoundingFlag(false)
        try await super.tearDown()
    }

    func testFreePlanLogsOnlyAtTheFreeRental() {
        XCTAssertEqual(vm.freeRentalID, pine)
        XCTAssertEqual(vm.rentalAccess(oak), .viewOnly)
        let refused = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 2, date: Date(), notes: "")
        XCTAssertEqual(refused, .failed(vm.viewOnlyLogMessage))
        XCTAssertTrue(vm.viewOnlyLogMessage.contains("Pine Cabin"), "names the free rental")
        XCTAssertEqual(vm.timeEntries.count, 2, "nothing saved at the view-only rental")
        let saved = vm.logTimeEntry(propertyId: pine, participant: .selfParticipant, category: .repairs, hours: 2, date: Date(), notes: "")
        XCTAssertNotNil(saved.entryId)
    }

    func testTheOtherSavePathsRefuseToo() {
        vm.addTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 1, date: Date(), notes: "")
        XCTAssertEqual(vm.timeEntries.count, 2)
        var moved = vm.timeEntries[0]
        moved.propertyId = oak
        vm.updateTimeEntry(moved)
        XCTAssertEqual(vm.timeEntries[0].propertyId, pine, "an edit can't move hours onto a view-only rental")
        // At the view-only rental itself: no counted change, but notes stay editable.
        let oakIndex = vm.timeEntries.firstIndex { $0.propertyId == oak }!
        var more = vm.timeEntries[oakIndex]
        more.hours = 50
        vm.updateTimeEntry(more)
        XCTAssertEqual(vm.timeEntries[oakIndex].hours, 5, "hours at a view-only rental can't grow")
        var noted = vm.timeEntries[oakIndex]
        noted.notes = "fixed the gate"
        vm.updateTimeEntry(noted)
        XCTAssertEqual(vm.timeEntries[oakIndex].notes, "fixed the gate", "notes stay editable")
        let store = makeStore()
        let suggestion = calendarSuggestion(start: Date().addingTimeInterval(-3600), propertyId: oak)
        store.ingest([suggestion], existingEntries: vm.timeEntries, calendar: calendar)
        XCTAssertEqual(vm.confirm(suggestion, store: store), .needsInput(missing: [.plan]))
    }

    func testViewOnlyHoursStayCounted() {
        let total = vm.timeEntries.reduce(0) { $0 + $1.hours }
        XCTAssertEqual(total, 25)
        XCTAssertEqual(FreeRentalPolicy.countedRentalIDs(plan: .free, selection: nil, rentals: vm.rentalUsages).count, 2)
    }

    func testSwitchingTheFreeRentalMovesWhereYouLog() {
        XCTAssertEqual(EntitlementStore.shared.pickFreeRental(oak, rentals: vm.rentalUsages), .allowed)
        XCTAssertEqual(vm.rentalAccess(oak), .full)
        XCTAssertEqual(vm.rentalAccess(pine), .viewOnly)
        guard case .tooSoon = EntitlementStore.shared.pickFreeRental(pine, rentals: vm.rentalUsages) else {
            return XCTFail("a second switch in the same month is refused")
        }
    }

    func testProLogsEverywhere() {
        EntitlementStore.shared.setFoundingFlag(true)
        XCTAssertEqual(vm.rentalAccess(oak), .full)
        XCTAssertNotNil(vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 1,
                                        date: Date(), notes: "").entryId)
    }
}
