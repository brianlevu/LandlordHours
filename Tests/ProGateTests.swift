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

    func loadProducts() async { proDisplayPrice = priceAfterLoad }
    func purchasePro() async -> SubscriptionManager.PurchaseOutcome {
        purchases += 1
        if purchaseOutcome == .purchased { isPro = true }
        return purchaseOutcome
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
@MainActor
final class ProPurchaseStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private let testUserID = "storekit-wp-p-test-user"

    override func setUpWithError() throws {
        try super.setUpWithError()
        session = try SKTestSession(configurationFileNamed: "LandlordHours")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        resetScoped()
    }

    override func tearDownWithError() throws {
        session.askToBuyEnabled = false
        session.failTransactionsEnabled = false
        session.clearTransactions()
        resetScoped()
        session = nil
        try super.tearDownWithError()
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
        _ = try await session.buyProduct(identifier: "com.openclaw.landlordhours.pro")
        await manager.refreshEntitlements()
        XCTAssertTrue(manager.isPro)
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
    }
}
#endif
