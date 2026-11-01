import XCTest
import StoreKit
@testable import LandlordHours

#if canImport(StoreKitTest)
import StoreKitTest

/// The real StoreKit2Client against LandlordHours.storekit: the yearly product with its 14-day
/// intro offer, a trial purchase, a lapse and a refund, mapped to the plan.
/// A unit-test host has no window for `Product.purchase()`, so purchases go through the test
/// session's `buyProduct`; `StoreKit2Client.purchase` itself runs in package A's UI journey.
@MainActor
final class SubscriptionStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private let client = StoreKit2Client()
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        session = try SharedStoreKitTestSession.session()
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        suite = "sub-storekit-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { await transaction.finish() }
        }
        session.clearTransactions()
        defaults.removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    private func makeStore() -> EntitlementStore {
        EntitlementStore(defaults: defaults, key: { "sk.\($0)" })
    }

    func testYearlyProductHasAFourteenDayFreeTrial() async throws {
        let infos = try await client.products(for: [ProductIDs.yearly, ProductIDs.founding])
        let yearly = try XCTUnwrap(infos.first { $0.id == ProductIDs.yearly })
        XCTAssertEqual(yearly.period, .year)
        XCTAssertEqual(yearly.introTrialDays, 14)
        XCTAssertFalse(yearly.displayPrice.isEmpty, "the paywall shows StoreKit's localized price")
        let founding = try XCTUnwrap(infos.first { $0.id == ProductIDs.founding })
        XCTAssertNil(founding.period)
        XCTAssertNil(founding.introTrialDays)
    }

    func testNewUserIsEligibleForTheTrial() async {
        let eligible = await client.isEligibleForIntroOffer(productID: ProductIDs.yearly)
        XCTAssertTrue(eligible)
    }

    func testBuyingTheYearlyStartsTheTrial() async throws {
        let fact = try await buy(ProductIDs.yearly)
        XCTAssertEqual(fact.productID, ProductIDs.yearly)
        XCTAssertEqual(fact.offer, .freeTrial)

        let plan = await waitForPlan(makeStore()) { if case .trial = $0 { return true }; return false }
        guard case .trial(let sub) = plan else { return XCTFail("expected trial, got \(plan)") }
        // Calendar days: a DST change inside the trial adds or drops an hour.
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: sub.startedAt, to: sub.expiresAt).day, 14)
        XCTAssertTrue(sub.willAutoRenew)
        // Intro eligibility after the purchase is StoreKit's own state and lags in the shared test
        // session (order-dependent in the full run), so it isn't asserted here; the paywall's use of
        // it is covered by PaywallOffer tests.
    }

    func testLapsedSubscriptionIsFree() async throws {
        // Cancel during the trial, then run the clock fast so the trial ends without renewing.
        // (`expireSubscription` doesn't reach the app's StoreKit view in a unit-test host.)
        session.timeRate = .oneRenewalEveryTwoSeconds
        defer { session.timeRate = .realTime }
        let fact = try await buy(ProductIDs.yearly)
        try session.disableAutoRenewForTransaction(identifier: UInt(fact.transactionID))
        let cancelled = await client.renewalState(for: ProductIDs.yearly)
        XCTAssertEqual(cancelled?.willAutoRenew, false, "a cancelled trial maps to willAutoRenew false")
        let plan = await waitForPlan(makeStore(), seconds: 15) { $0 == .free }
        let renewal = await client.renewalState(for: ProductIDs.yearly)
        XCTAssertEqual(plan, .free, "renewal=\(String(describing: renewal))")
    }

    func testRefundedSubscriptionIsFree() async throws {
        let fact = try await buy(ProductIDs.yearly)
        _ = await waitForPlan(makeStore()) { $0.hasProAccess }
        try session.refundTransaction(identifier: UInt(fact.transactionID))
        let plan = await waitForPlan(makeStore()) { $0 == .free }
        XCTAssertEqual(plan, .free)
    }

    func testFoundingPurchaseIsFounding() async throws {
        _ = try await buy(ProductIDs.founding)
        let plan = await waitForPlan(makeStore()) { $0.isFounding }
        XCTAssertEqual(plan, .founding(alsoSubscribed: false))
    }

    func testRefundedFoundingIsFree() async throws {
        let fact = try await buy(ProductIDs.founding)
        let store = makeStore()
        _ = await waitForPlan(store) { $0.isFounding }
        try session.refundTransaction(identifier: UInt(fact.transactionID))
        let plan = await waitForPlan(store) { $0 == .free }
        XCTAssertEqual(plan, .free)
    }

    private func buy(_ id: String) async throws -> EntitlementFact {
        StoreKit2Client.fact(try await session.buyProduct(identifier: id))
    }

    /// StoreKit test actions land asynchronously; poll briefly.
    private func waitForPlan(_ store: EntitlementStore, seconds: TimeInterval = 5, until done: (Plan) -> Bool) async -> Plan {
        var plan = await store.refresh(using: client)
        let deadline = Date().addingTimeInterval(seconds)
        while !done(plan) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
            plan = await store.refresh(using: client)
        }
        return plan
    }
}
#endif
