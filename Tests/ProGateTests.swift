import XCTest
import StoreKit
@testable import LandlordHours
#if canImport(StoreKitTest)
import StoreKitTest
#endif

// WP-P: the one free-to-paid system. Rules per entry point, the context each opens, the paywall
// copy, the price ordering App Review asks for, the purchase/restore/Ask to Buy state machine,
// and the Inbox at-limit counts.

final class ProGateRuleTests: XCTestCase {
    func testPropertyLimitIsOneRentalOnFree() {
        XCTAssertFalse(ProGate.isAtPropertyLimit(isPro: false, propertyCount: 0))
        XCTAssertTrue(ProGate.isAtPropertyLimit(isPro: false, propertyCount: 1))
        XCTAssertTrue(ProGate.isAtPropertyLimit(isPro: false, propertyCount: 3), "A downgraded owner keeps rentals, still previewing")
        XCTAssertFalse(ProGate.isAtPropertyLimit(isPro: true, propertyCount: 1))
        XCTAssertTrue(ProGate.canAddProperty(isPro: false, propertyCount: 0))
        XCTAssertFalse(ProGate.canAddProperty(isPro: false, propertyCount: 1))
        XCTAssertTrue(ProGate.canAddProperty(isPro: true, propertyCount: 40))
    }

    func testEachEntryPointLocksOnlyForFreeUsers() {
        for entry in LockEntry.allCases {
            XCTAssertFalse(ProGate.isLocked(entry, isPro: true, propertyCount: 5, confirmedHours: 500), "\(entry) is open for Pro")
        }
        XCTAssertTrue(ProGate.isLocked(.exportPage, isPro: false))
        XCTAssertTrue(ProGate.isLocked(.reportsExport, isPro: false))
        XCTAssertTrue(ProGate.isLocked(.settingsPro, isPro: false))
        XCTAssertTrue(ProGate.isLocked(.propertiesLimit, isPro: false, propertyCount: 1))
        XCTAssertFalse(ProGate.isLocked(.propertiesLimit, isPro: false, propertyCount: 0), "The first rental is free")
        XCTAssertTrue(ProGate.isLocked(.inboxLimit, isPro: false, propertyCount: 1))
    }

    func testTodayRecordLockNeedsTenHours() {
        XCTAssertFalse(ProGate.showsTodayRecordLock(isPro: false, confirmedHours: 9.99))
        XCTAssertTrue(ProGate.showsTodayRecordLock(isPro: false, confirmedHours: 10))
        XCTAssertTrue(ProGate.showsTodayRecordLock(isPro: false, confirmedHours: 212))
        XCTAssertFalse(ProGate.showsTodayRecordLock(isPro: true, confirmedHours: 212))
        XCTAssertFalse(ProGate.showsTodayRecordLock(isPro: false, confirmedHours: .nan))
    }

    func testEveryEntryPointOpensThePaywallAboutIt() {
        XCTAssertEqual(ProGate.context(for: .exportPage), .export)
        XCTAssertEqual(ProGate.context(for: .reportsExport), .export)
        XCTAssertEqual(ProGate.context(for: .propertiesLimit), .secondProperty)
        XCTAssertEqual(ProGate.context(for: .inboxLimit), .secondProperty)
        XCTAssertEqual(ProGate.context(for: .settingsPro), .settings)
        XCTAssertEqual(ProGate.context(for: .todayRecord), .todayUnlock)
        // The paywall's default entry maps back to a gate that opens the same context.
        for context in PaywallContext.allCases {
            XCTAssertEqual(ProGate.context(for: PaywallView.defaultEntry(for: context)), context)
        }
    }

    func testEveryLockSaysWhatStaysActive() {
        for entry in LockEntry.allCases {
            XCTAssertFalse(ProGate.lockLine(entry).isEmpty)
            XCTAssertFalse(ProGate.keepsLine(entry).isEmpty, "\(entry) must say what stays free")
        }
        XCTAssertEqual(ProGate.keepsLine(.propertiesLimit, firstPropertyName: "Pine Cabin"), "Pine Cabin keeps tracking. Nothing is lost.")
        XCTAssertEqual(ProGate.keepsLine(.propertiesLimit, firstPropertyName: "  "), "Your rental keeps tracking. Nothing is lost.")
        XCTAssertEqual(ProGate.lockLine(.todayRecord, confirmedHours: 212.7), "Your 212 hours, ready to export.")
    }

    func testAnalyticsContextValuesStayContinuousWith1x() {
        XCTAssertEqual(PaywallContext.export.rawValue, "export")
        XCTAssertEqual(PaywallContext.secondProperty.rawValue, "secondProperty")
        XCTAssertEqual(PaywallContext.todayUnlock.rawValue, "dashboardUnlock")
        XCTAssertEqual(PaywallContext.settings.rawValue, "settingsUpgrade")
    }
}

final class PaywallCopyTests: XCTestCase {
    func testCopyByContext() {
        let export = PaywallCopy.make(.export, year: 2026)
        XCTAssertEqual(export.headline, "The record your accountant gets")
        XCTAssertEqual(export.planLine, "Export 2026 as a PDF or spreadsheet, any time.")
        XCTAssertEqual(export.nextStep, "Export 2026")

        let second = PaywallCopy.make(.secondProperty, year: 2026, propertyName: "Oak Street Duplex")
        XCTAssertEqual(second.headline, "Track every rental")
        XCTAssertEqual(second.planLine, "Add Oak Street Duplex and every place after it. Your hours stay put.")
        XCTAssertEqual(second.nextStep, "Add Oak Street Duplex")
        XCTAssertEqual(PaywallCopy.make(.secondProperty, year: 2026).nextStep, "Add a property")

        let today = PaywallCopy.make(.todayUnlock, year: 2026, confirmedHours: 212.4)
        XCTAssertEqual(today.headline, "Your hours, on paper")
        XCTAssertEqual(today.planLine, "Turn 212 confirmed hours into a clean record.")
        XCTAssertEqual(today.nextStep, "See your record")

        XCTAssertEqual(PaywallCopy.make(.settings, year: 2026).headline, "LandlordHours Pro")
        XCTAssertEqual(PaywallCopy.make(.settings, year: 2026).nextStep, "Done")
    }

    func testUnlockProIsSpelledTheSameEverywhere() {
        XCTAssertEqual(PriceDisplay(billed: "$29.99", intro: nil).buttonTitle(large: true), "Unlock Pro")
        XCTAssertEqual(UnlockProButton(entry: .exportPage, action: {}).title, "Unlock Pro")
    }

    func testHighlightFollowsContext() {
        XCTAssertEqual(RecordPageHighlight.forContext(.secondProperty, propertyName: "Oak"), .newRow("Oak"))
        XCTAssertEqual(RecordPageHighlight.forContext(.secondProperty, propertyName: nil), .newRow("Your next rental"))
        XCTAssertEqual(RecordPageHighlight.forContext(.todayUnlock, propertyName: nil), .total)
        XCTAssertEqual(RecordPageHighlight.forContext(.export, propertyName: nil), .none)
    }

    func testLegalLinksAreRealDocuments() {
        XCTAssertEqual(PaywallView.termsURL.absoluteString, "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
                       "Terms of Use is Apple's standard EULA")
        XCTAssertTrue(PaywallView.privacyURL.absoluteString.contains("privacy"), "Privacy points at the app's privacy policy")
    }

    func testSamplePageIsMarkedSample() {
        XCTAssertTrue(RecordPageModel.sample(year: 2026).isSample)
    }
}

final class PriceDisplayTests: XCTestCase {
    func testBilledAmountIsFirstAndLargest() {
        for large in [false, true] {
            let display = PriceDisplay(billed: "$29.99", intro: "Includes a free week")
            let elements = display.elements(large: large)
            XCTAssertEqual(elements.first?.role, .billed)
            XCTAssertTrue(display.billedIsMostProminent(large: large))
            let introIndex = elements.firstIndex { $0.role == .intro }!
            XCTAssertGreaterThan(introIndex, 0, "Intro copy sits below the billed amount")
            XCTAssertLessThan(elements[introIndex].pointSize, PriceDisplay.billedSize)
        }
    }

    func testButtonCarriesTheBilledPriceAtDefaultSizes() {
        let display = PriceDisplay(billed: "€34,99", intro: nil)
        XCTAssertEqual(display.buttonTitle(large: false), "Unlock for €34,99", "The localized App Store string, never a literal")
        XCTAssertEqual(display.buttonTitle(large: true), "Unlock Pro")
        XCTAssertLessThan(PriceDisplay.buttonSize, PriceDisplay.billedSize)
        XCTAssertLessThan(PriceDisplay.captionSize, PriceDisplay.billedSize)
    }

    func testAccessibilityReadsAOneTimePurchase() {
        XCTAssertEqual(PriceDisplay(billed: "$29.99", intro: nil).accessibilityLabel, "$29.99, one-time purchase")
    }
}

final class PaywallFlowTests: XCTestCase {
    func testPriceLoad() {
        XCTAssertEqual(PaywallFlow.afterPriceLoad(found: true), .ready)
        XCTAssertEqual(PaywallFlow.afterPriceLoad(found: false), .priceFailed)
    }

    func testPurchaseOutcomes() {
        XCTAssertEqual(PaywallFlow.afterPurchase(.purchased), .success)
        XCTAssertEqual(PaywallFlow.afterPurchase(.cancelled), .ready, "Cancelled: nothing changes")
        XCTAssertEqual(PaywallFlow.afterPurchase(.pending), .askToBuy)
        XCTAssertEqual(PaywallFlow.afterPurchase(.failed), .failed)
        XCTAssertEqual(PaywallFlow.afterPurchase(.timedOut), .failed)
        XCTAssertNil(PaywallFlow.failureReason(.timedOut), "a timeout logs purchase_timeout, not purchase_failed")
    }

    func testRestore() {
        XCTAssertEqual(PaywallFlow.afterRestore(found: true), .success)
        XCTAssertEqual(PaywallFlow.afterRestore(found: false), .restoreNone)
    }

    func testAskToBuyApprovalUnlocksLater() {
        XCTAssertEqual(PaywallFlow.afterEntitlementChange(isPro: true, from: .askToBuy), .success)
        XCTAssertEqual(PaywallFlow.afterEntitlementChange(isPro: false, from: .askToBuy), .askToBuy)
    }

    func testWhatCanBeTappedInEachPhase() {
        let buyable: Set<PaywallPhase> = [.ready, .failed, .restoreNone]
        for phase in PaywallPhase.allCases {
            XCTAssertEqual(PaywallFlow.canBuy(phase), buyable.contains(phase), "\(phase)")
        }
        XCTAssertFalse(PaywallFlow.canRestore(.buying))
        XCTAssertFalse(PaywallFlow.canRestore(.restoring))
        XCTAssertTrue(PaywallFlow.canRestore(.priceFailed), "Restore never needs the price")
    }
}

// MARK: - Paywall model against a fake store

@MainActor
private final class FakeStore: ProPurchasing {
    var isPro = false
    var proDisplayPrice: String?
    var proIsFamilyShareable = false
    var priceAfterLoad: String? = "$29.99"
    var purchaseOutcome: SubscriptionManager.PurchaseOutcome = .purchased
    var restoreFinds = false
    var purchases = 0
    var isPurchaseInFlight = false
    /// For `.timedOut`: the late outcome the test delivers with `finishLate(_:)`.
    private var late: (@MainActor (SubscriptionManager.PurchaseOutcome) -> Void)?

    func loadProducts() async { proDisplayPrice = priceAfterLoad }
    func purchasePro(lateOutcome: @escaping @MainActor (SubscriptionManager.PurchaseOutcome) -> Void) async -> SubscriptionManager.PurchaseOutcome {
        purchases += 1
        if purchaseOutcome == .purchased { isPro = true }
        if purchaseOutcome == .timedOut { isPurchaseInFlight = true; late = lateOutcome }
        return purchaseOutcome
    }
    @MainActor func finishLate(_ outcome: SubscriptionManager.PurchaseOutcome) {
        isPurchaseInFlight = false
        if outcome == .purchased { isPro = true }
        late?(outcome)
    }
    func restorePurchases() async -> Bool {
        if restoreFinds { isPro = true }
        return restoreFinds
    }
}

@MainActor
final class PaywallModelTests: XCTestCase {
    private var events: [(String, [String: Any])] = []

    override func setUp() {
        super.setUp()
        events = []
        Analytics.testSpy = { [weak self] name, props in self?.events.append((name, props)) }
    }

    override func tearDown() {
        Analytics.testSpy = nil
        super.tearDown()
    }

    func testLoadsThePriceFromTheStore() async {
        let store = FakeStore()
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        XCTAssertEqual(model.phase, .priceLoading)
        XCTAssertFalse(model.canBuy, "No buying before there is a real price")
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.price, "$29.99")
    }

    func testPriceFailureThenRetry() async {
        let store = FakeStore()
        store.priceAfterLoad = nil
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        XCTAssertEqual(model.phase, .priceFailed)
        XCTAssertFalse(model.canBuy)
        store.priceAfterLoad = "$29.99"
        await model.retryPrice()
        XCTAssertEqual(model.phase, .ready)
    }

    func testPurchaseSucceeds() async {
        let store = FakeStore()
        let model = PaywallModel(context: .secondProperty, entry: .propertiesLimit, store: store)
        await model.start()
        let unlocked = await model.buy()
        XCTAssertTrue(unlocked)
        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(events.map(\.0), ["paywall_cta_tapped", "purchase_completed", "purchase_succeeded"])
        XCTAssertEqual(events.last?.1["context"] as? String, "secondProperty")
    }

    func testTimedOutPurchaseLogsTimeoutThenTheLateCompletion() async {
        let store = FakeStore()
        store.purchaseOutcome = .timedOut
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        await model.buy()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.isFinishingPurchase)
        XCTAssertFalse(model.canBuy, "no second purchase while the first is still in flight")
        XCTAssertEqual(events.map(\.0), ["paywall_cta_tapped", "purchase_timeout"])
        store.finishLate(.purchased)
        XCTAssertEqual(events.map(\.0), ["paywall_cta_tapped", "purchase_timeout", "purchase_completed", "purchase_succeeded"])
        XCTAssertEqual(events.last?.1["context"] as? String, "export")
        model.entitlementChanged(isPro: store.isPro)
        XCTAssertEqual(model.phase, .success)
    }

    func testTimedOutPurchaseThatFailsLateCanBeRetried() async {
        let store = FakeStore()
        store.purchaseOutcome = .timedOut
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        await model.buy()
        store.finishLate(.cancelled)
        XCTAssertEqual(events.last?.0, "purchase_failed")
        XCTAssertEqual(events.last?.1["outcome"] as? String, "cancelled")
        XCTAssertFalse(model.isFinishingPurchase)
        XCTAssertTrue(model.canBuy, "Buy comes back once the App Store answers")
    }

    func testAskToBuyWaitsThenUnlocksOnApproval() async {
        let store = FakeStore()
        store.purchaseOutcome = .pending
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        await model.buy()
        XCTAssertEqual(model.phase, .askToBuy)
        XCTAssertEqual(events.last?.0, "purchase_failed")
        XCTAssertEqual(events.last?.1["outcome"] as? String, "pending")
        model.entitlementChanged(isPro: true)
        XCTAssertEqual(model.phase, .success)
    }

    func testFailureAllowsRetry() async {
        let store = FakeStore()
        store.purchaseOutcome = .failed
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        await model.buy()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.canBuy)
        store.purchaseOutcome = .purchased
        await model.buy()
        XCTAssertEqual(model.phase, .success)
        XCTAssertEqual(store.purchases, 2)
    }

    func testCancelChangesNothing() async {
        let store = FakeStore()
        store.purchaseOutcome = .cancelled
        let model = PaywallModel(context: .export, entry: .exportPage, store: store)
        await model.start()
        await model.buy()
        XCTAssertEqual(model.phase, .ready)
    }

    func testRestoreNoneThenFound() async {
        let store = FakeStore()
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: store)
        await model.start()
        await model.restore()
        XCTAssertEqual(model.phase, .restoreNone)
        XCTAssertTrue(model.canBuy, "Buying stays available after a restore finds nothing")
        store.restoreFinds = true
        await model.restore()
        XCTAssertEqual(model.phase, .success)
    }

    func testPinnedPhaseNeverTalksToTheStore() async {
        let store = FakeStore()
        store.proDisplayPrice = "$29.99"
        let model = PaywallModel(context: .export, entry: .exportPage, store: store, pinnedPhase: .buying)
        await model.start()
        await model.buy()
        XCTAssertEqual(model.phase, .buying)
        XCTAssertEqual(store.purchases, 0)
    }
}

// MARK: - Inbox at the free limit

final class InboxProLimitTests: XCTestCase {
    private let pine = UUID()

    private func s(_ key: String, property: UUID?, pending: Bool = true) -> Suggestion {
        var item = Suggestion(sourceKey: "cal:\(key)", kind: .calendar, detectedAt: Date(), start: Date(), title: key,
                              proposedPropertyId: property, proposedHours: 1, hoursBasis: .scheduled)
        if !pending { item.state = .dismissed(reason: .notLandlordWork) }
        return item
    }

    func testOnlyNewRentalItemsCountWhileTheFreePlanIsFull() {
        let items = [s("a", property: pine), s("b", property: nil), s("c", property: UUID()),
                     s("d", property: nil, pending: false), s("e", property: nil)]
        let counts = InboxProLimit.counts(items, propertyIds: [pine], isPro: false, waitingKeys: ["cal:e", "cal:a", "cal:d"])
        XCTAssertEqual(counts, InboxProLimit.Counts(atLimit: 3, waiting: 1), "b, c, e are over the cap; only e is kept for Pro")
    }

    func testNothingIsOverTheCapForProOrBeforeTheFirstRental() {
        let items = [s("b", property: nil)]
        XCTAssertEqual(InboxProLimit.counts(items, propertyIds: [pine], isPro: true, waitingKeys: []).atLimit, 0)
        XCTAssertEqual(InboxProLimit.counts(items, propertyIds: [], isPro: false, waitingKeys: []).atLimit, 0)
        XCTAssertFalse(InboxProLimit.needsNewRental(s("a", property: pine), propertyIds: [pine], isPro: false))
        // A downgraded owner with several rentals picks among them: the regular Log stays.
        XCTAssertFalse(InboxProLimit.needsNewRental(s("b", property: nil), propertyIds: [pine, UUID()], isPro: false))
    }

    func testWaitListIsPerKeyAndPrunes() {
        let defaults = UserDefaults(suiteName: "ProWaitListTests-\(UUID().uuidString)")!
        let list = ProWaitList(defaults: defaults, keyProvider: { "k" })
        list.add("cal:a"); list.add("cal:b"); list.add("cal:a")
        XCTAssertEqual(list.keys, ["cal:a", "cal:b"])
        list.remove("cal:a")
        XCTAssertFalse(list.contains("cal:a"))
        list.add("cal:c")
        list.prune(keeping: ["cal:c"])
        XCTAssertEqual(list.keys, ["cal:c"])
    }
}

@MainActor
final class InboxAtLimitViewModelTests: CaptureTestCase {
    private var app: AppViewModel!
    private var propertyId: UUID!
    private var store: SuggestionStore!
    private var waitList: ProWaitList!

    override func setUp() async throws {
        try await super.setUp()
        (app, propertyId) = makeViewModel()
        store = makeStore()
        waitList = ProWaitList(defaults: UserDefaults(suiteName: "InboxAtLimit-\(UUID().uuidString)")!, keyProvider: { "k" })
    }

    private func model(isPro: Bool = false) -> InboxViewModel {
        let resolved = store
        let model = InboxViewModel(app: app, storeProvider: { resolved }, calendar: calendar, spouseTracking: { false },
                                   isPro: { isPro }, waitList: waitList, undoWindow: .infinity)
        model.reload()
        return model
    }

    private func item(_ id: String, property: UUID?) -> Suggestion {
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!.addingTimeInterval(10 * 3600)
        return calendarSuggestion(externalId: id, start: start, title: "Showing \(id)", propertyId: property, hours: 1, category: .leasing)
    }

    func testNewPlaceKeepForProAndCounts() {
        let atPine = item("A", property: propertyId)
        let newPlace = item("B", property: nil)
        store.ingest([atPine, newPlace], existingEntries: app.timeEntries, calendar: calendar)
        let model = model()
        XCTAssertFalse(model.needsNewRental(atPine))
        XCTAssertTrue(model.needsNewRental(newPlace))
        XCTAssertEqual(model.limitCounts, InboxProLimit.Counts(atLimit: 1, waiting: 0))

        model.keepForPro(newPlace)
        XCTAssertTrue(model.isWaitingOnPro(newPlace))
        XCTAssertEqual(model.limitCounts, InboxProLimit.Counts(atLimit: 1, waiting: 1))
        XCTAssertTrue(store.suggestion(forKey: newPlace.sourceKey)!.isPending, "Kept, never expired or logged")
        XCTAssertEqual(model.toast?.kind, .neutral)
        XCTAssertTrue(app.timeEntries.filter { $0.sourceKey != nil }.isEmpty, "Never logged to the wrong place")
    }

    func testLoggingAtTheUsersRentalClearsTheWait() {
        let newPlace = item("B", property: nil)
        store.ingest([newPlace], existingEntries: app.timeEntries, calendar: calendar)
        let model = model()
        model.keepForPro(newPlace)
        let result = model.log(newPlace, edits: SuggestionEdits(propertyId: propertyId))
        XCTAssertNotNil(result.entryId, "\"Was this at Pine Cabin? Pick it above.\" logs it there")
        XCTAssertFalse(waitList.contains(newPlace.sourceKey))
    }

    func testProUserIsNeverAtTheLimit() {
        let newPlace = item("B", property: nil)
        store.ingest([newPlace], existingEntries: app.timeEntries, calendar: calendar)
        let model = model(isPro: true)
        XCTAssertFalse(model.needsNewRental(newPlace))
        XCTAssertEqual(model.limitCounts.atLimit, 0)
    }

    func testLogReportsFailureInsteadOfNil() {
        let a = item("A", property: nil)
        store.ingest([a], existingEntries: app.timeEntries, calendar: calendar)
        let model = model()
        XCTAssertEqual(model.log(a, edits: SuggestionEdits()), .needsInput(missing: [.property]))
        let saved = model.log(a, edits: SuggestionEdits(propertyId: propertyId))
        guard case .created = saved else { return XCTFail("Expected created, got \(saved)") }
    }
}

// MARK: - StoreKit test configuration: real purchase, Ask to Buy, failure, restore

#if canImport(StoreKitTest)
/// The test process's single StoreKit test session (see ProPurchaseStoreKitTests.setUp).
///
/// StoreKit binds a process to a store on its first call. In a unit-test host the app keeps
/// StoreKit untouched until this session exists (`SubscriptionManager.attachStoreKit()`);
/// otherwise, on a freshly created simulator, the host app's launch-time calls bound it to the
/// Sandbox store, `buyProduct` came back as transaction 0 that never reached the app, and
/// `AppStore.sync()` waited on a sign-in forever.
enum SharedStoreKitTestSession {
    nonisolated(unsafe) private static var shared: SKTestSession?
    @MainActor
    static func session() throws -> SKTestSession {
        if let shared { return shared }
        let made = try SKTestSession(configurationFileNamed: "LandlordHours")
        shared = made
        SubscriptionManager.shared.attachStoreKit()
        return made
    }
}

@MainActor
final class ProPurchaseStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private let testUserID = "storekit-wp-p-test-user"

    override func setUpWithError() throws {
        try super.setUpWithError()
        // One shared session for the whole test process: a second SKTestSession, or a released
        // one, detaches the StoreKit test environment, so later purchases come back empty
        // (transaction id 0) and the suite turned order-dependent.
        session = try SharedStoreKitTestSession.session()
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        resetScoped()
        // One listener per test, cancelled in tearDown, so no update from an earlier test lands here.
        SubscriptionManager.shared.startTransactionListener()
    }

    override func tearDown() async throws {
        let manager = SubscriptionManager.shared
        manager.stopTransactionListener()
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { await transaction.finish() }
        }
        manager.syncWithAppStore = { try await AppStore.sync() }
        manager.purchaseProduct = { try await $0.purchase() }
        SubscriptionManager.restoreSyncTimeout = Self.defaultSyncTimeout
        SubscriptionManager.purchaseTimeout = Self.defaultPurchaseTimeout
        session.askToBuyEnabled = false
        session.failTransactionsEnabled = false
        session.clearTransactions()
        resetScoped()
        try await super.tearDown()
    }

    private static let defaultSyncTimeout = SubscriptionManager.restoreSyncTimeout
    private static let defaultPurchaseTimeout = SubscriptionManager.purchaseTimeout

    private func waitForPro(_ manager: SubscriptionManager) async {
        let deadline = Date().addingTimeInterval(5)
        while !manager.isPro && Date() < deadline {
            await manager.refreshEntitlements()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func entitlementsDump() async -> String {
        var parts: [String] = []
        for await r in Transaction.currentEntitlements {
            switch r {
            case .verified(let t): parts.append("ok \(t.productID) rev=\(String(describing: t.revocationDate))")
            case .unverified(let t, let e): parts.append("unverified \(t.productID) \(e)")
            }
        }
        return "entitlements: [\(parts.joined(separator: ", "))]"
    }

    private func resetScoped() {
        UserDefaults.standard.set(testUserID, forKey: "emailUserId")
        UserDefaults.standard.set(LoginType.email.rawValue, forKey: "loginType")
        UserDefaults.standard.removeObject(forKey: UserScope.key("isProUser"))
        UserDefaults.standard.removeObject(forKey: UserScope.key("hasPurchasedPro"))
        SubscriptionManager.shared.resetForSignOut()
    }

    func testPriceComesFromStoreKitNotALiteral() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        let product = try XCTUnwrap(manager.proProduct)
        XCTAssertEqual(manager.proDisplayPrice, product.displayPrice)
        XCTAssertEqual(manager.proIsFamilyShareable, product.isFamilyShareable)
    }

    // A unit-test host has no window to confirm `Product.purchase()` in, so these drive the
    // StoreKit test session's own purchase API and check the paywall model and SubscriptionManager
    // react the way they do in the app. The full tap-through purchase runs in the UI journeys.

    func testPurchaseUnlocksProAndThePaywallShowsSuccess() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        let model = PaywallModel(context: .export, entry: .exportPage, store: manager)
        await model.start()
        XCTAssertEqual(model.phase, .ready)
        let bought = try await session.buyProduct(identifier: "com.openclaw.landlordhours.pro")
        await waitForPro(manager)
        let dump = await entitlementsDump()
        XCTAssertTrue(manager.isPro, "bought \(bought.id) revoked=\(String(describing: bought.revocationDate)) upgraded=\(bought.isUpgraded); \(dump)")
        model.entitlementChanged(isPro: manager.isPro)
        XCTAssertEqual(model.phase, .success)
    }

    // Ask to Buy and failed transactions: `SKTestSession.buyProduct` ignores those switches, so
    // they run through the app's real purchase path in FreeUserPaywallUITests
    // (testAskToBuyShowsWaitingForApproval, testFailedPurchaseCanBeRetried); the transitions are
    // covered against a fake store in PaywallModelTests.

    func testRestoreFindsAnEarlierPurchase() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        _ = try await session.buyProduct(identifier: "com.openclaw.landlordhours.pro")
        // Let the purchase land in the test session's entitlements before signing "out".
        await waitForPro(manager)
        resetScoped()
        XCTAssertFalse(manager.isPro)
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: manager)
        await model.start()
        await model.restore()
        XCTAssertEqual(model.phase, .success)
        XCTAssertTrue(manager.isPro)
    }

    func testRestoreWithNothingToRestore() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: manager)
        await model.start()
        await model.restore()
        XCTAssertEqual(model.phase, .restoreNone)
        XCTAssertFalse(manager.isPro)
        XCTAssertNil(manager.restoreFailureMessage, "nothing found is not a failure")
    }

    // MARK: Restore and purchase always end

    func testTheTestSessionReachesTheApp() async throws {
        // Guards the root cause: a purchase in the test session must be a real transaction the
        // app sees, not the id-0 placeholder a Sandbox-bound process gets.
        let bought = try await session.buyProduct(identifier: "com.openclaw.landlordhours.pro")
        XCTAssertNotEqual(bought.id, 0)
        XCTAssertTrue(SubscriptionManager.shared.isStoreKitAttached)
    }

    func testRestoreThatNeverHearsBackTimesOutWithAClearError() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        SubscriptionManager.restoreSyncTimeout = 0.3
        manager.syncWithAppStore = { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
        let model = PaywallModel(context: .settings, entry: .settingsPro, store: manager)
        await model.start()
        let started = Date()
        let found = await model.restore()
        XCTAssertFalse(found)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(model.phase, .restoreNone)
        XCTAssertFalse(manager.isLoading, "the restore button must come back")
        XCTAssertEqual(manager.restoreFailureMessage, "The App Store didn't answer. Try again in a moment.")
    }

    func testRestoreErrorIsShownAsAFailureNotAsNothingFound() async throws {
        let manager = SubscriptionManager.shared
        manager.syncWithAppStore = { throw StoreKitError.networkError(URLError(.notConnectedToInternet)) }
        let found = await manager.restorePurchases()
        XCTAssertFalse(found)
        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(manager.restoreFailureMessage, "Couldn't reach the App Store. Check your connection and try again.")
    }

    func testRestoreFindsAPurchaseOnThisDeviceWithoutAskingTheAppStore() async throws {
        let manager = SubscriptionManager.shared
        _ = try await session.buyProduct(identifier: "com.openclaw.landlordhours.pro")
        resetScoped()
        var synced = false
        manager.syncWithAppStore = { synced = true }
        let found = await manager.restorePurchases()
        XCTAssertTrue(found)
        XCTAssertFalse(synced, "no Apple Account sign-in when the purchase is already here")
        XCTAssertTrue(manager.isPro)
    }

    func testPurchaseThatHearsBackLateKeepsBuyOffUntilItAnswers() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        SubscriptionManager.purchaseTimeout = 0.3
        let gate = ReleaseGate()
        var appStoreCalls = 0
        manager.purchaseProduct = { _ in
            appStoreCalls += 1
            await gate.wait()
            return .userCancelled
        }
        let model = PaywallModel(context: .export, entry: .exportPage, store: manager)
        await model.start()
        let started = Date()
        let bought = await model.buy()
        XCTAssertFalse(bought)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertFalse(manager.isLoading, "the paywall stops spinning")
        XCTAssertTrue(manager.isPurchaseInFlight)
        XCTAssertTrue(model.isFinishingPurchase)
        XCTAssertFalse(model.canBuy, "no second purchase while the first is in flight")
        XCTAssertEqual(manager.purchaseError, "Still finishing your purchase…")

        // A direct second purchase is refused without reaching the App Store.
        let second = await manager.purchasePro()
        XCTAssertEqual(second, .failed)
        XCTAssertEqual(appStoreCalls, 1)

        // The App Store answers: Buy comes back.
        gate.release()
        let deadline = Date().addingTimeInterval(5)
        while manager.isPurchaseInFlight && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(manager.isPurchaseInFlight)
        XCTAssertFalse(model.isFinishingPurchase)
        XCTAssertTrue(model.canBuy, "the user can try again")
    }

    func testALateCompletionReportsTheRealOutcome() async throws {
        let manager = SubscriptionManager.shared
        await manager.loadProducts()
        SubscriptionManager.purchaseTimeout = 0.2
        let gate = ReleaseGate()
        manager.purchaseProduct = { _ in
            await gate.wait()
            return .userCancelled
        }
        var late: [SubscriptionManager.PurchaseOutcome] = []
        let first = await manager.purchasePro(lateOutcome: { late.append($0) })
        XCTAssertEqual(first, .timedOut)
        XCTAssertTrue(late.isEmpty)
        gate.release()
        let deadline = Date().addingTimeInterval(5)
        while late.isEmpty && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(late, [.cancelled])
    }

    func testListenerStartsOnceAndStops() {
        let manager = SubscriptionManager.shared
        manager.startTransactionListener()
        manager.startTransactionListener()   // idempotent: still one listener
        manager.stopTransactionListener()
        manager.stopTransactionListener()
    }
}

/// A call that waits until the test lets it go, so no test leaves a purchase in flight.
@MainActor
final class ReleaseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class StoreDeadlineTests: XCTestCase {
    func testOnLateGetsTheValueOnlyWhenTheDeadlinePassed() async throws {
        var lateValues: [Int] = []
        let onTime = await StoreDeadline.run(seconds: 5, onLate: { lateValues.append($0) }) { 1 }
        XCTAssertEqual(onTime, 1)
        let missed: Int? = await StoreDeadline.run(seconds: 0.1, onLate: { lateValues.append($0) }) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            return 2
        }
        XCTAssertNil(missed)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(lateValues, [2])
    }

    func testReturnsTheValueWhenTheCallFinishesInTime() async {
        let value = await StoreDeadline.run(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testReturnsNilWhenTheCallNeverFinishes() async {
        let started = Date()
        let value: Int? = await StoreDeadline.run(seconds: 0.2) {
            try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testALateFinishStillRunsItsWork() async throws {
        var ranToEnd = false
        let value: Int? = await StoreDeadline.run(seconds: 0.1) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            ranToEnd = true
            return 1
        }
        XCTAssertNil(value)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(ranToEnd, "a purchase that lands late must still be unlocked and finished")
    }
}
#endif
