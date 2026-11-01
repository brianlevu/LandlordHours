import XCTest
import StoreKit
@testable import LandlordHours

#if canImport(StoreKitTest)
import StoreKitTest

/// The real StoreKit2Client against LandlordHours.storekit: the yearly product with its 14-day
/// intro offer, a trial purchase, a lapse and a refund, mapped to the plan.
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
        let result = try await client.purchase(productID: ProductIDs.yearly)
        guard case .success(let fact) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(fact.productID, ProductIDs.yearly)
        XCTAssertEqual(fact.offer, .freeTrial)

        let plan = await makeStore().refresh(using: client)
        guard case .trial(let sub) = plan else { return XCTFail("expected trial, got \(plan)") }
        let days = sub.expiresAt.timeIntervalSince(sub.startedAt) / 86_400
        XCTAssertEqual(days, 14, accuracy: 0.01)
        XCTAssertTrue(sub.willAutoRenew)
        let eligibleAfter = await client.isEligibleForIntroOffer(productID: ProductIDs.yearly)
        XCTAssertFalse(eligibleAfter, "one trial per Apple Account")
    }

    func testLapsedSubscriptionIsFree() async throws {
        _ = try await client.purchase(productID: ProductIDs.yearly)
        try session.expireSubscription(productIdentifier: ProductIDs.yearly)
        let plan = await waitForPlan(makeStore()) { $0 == .free }
        XCTAssertEqual(plan, .free)
    }

    func testRefundedSubscriptionIsFree() async throws {
        let result = try await client.purchase(productID: ProductIDs.yearly)
        guard case .success(let fact) = result else { return XCTFail("purchase failed") }
        try session.refundTransaction(identifier: UInt(fact.transactionID))
        let plan = await waitForPlan(makeStore()) { $0 == .free }
        XCTAssertEqual(plan, .free)
    }

    func testFoundingPurchaseIsFounding() async throws {
        let result = try await client.purchase(productID: ProductIDs.founding)
        guard case .success = result else { return XCTFail("purchase failed") }
        let plan = await makeStore().refresh(using: client)
        XCTAssertEqual(plan, .founding(alsoSubscribed: false))
    }

    func testRefundedFoundingIsFree() async throws {
        let result = try await client.purchase(productID: ProductIDs.founding)
        guard case .success(let fact) = result else { return XCTFail("purchase failed") }
        let store = makeStore()
        _ = await store.refresh(using: client)
        try session.refundTransaction(identifier: UInt(fact.transactionID))
        let plan = await waitForPlan(store) { $0 == .free }
        XCTAssertEqual(plan, .free)
    }

    /// StoreKit test actions land asynchronously; poll briefly.
    private func waitForPlan(_ store: EntitlementStore, until done: (Plan) -> Bool) async -> Plan {
        var plan = await store.refresh(using: client)
        let deadline = Date().addingTimeInterval(5)
        while !done(plan) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
            plan = await store.refresh(using: client)
        }
        return plan
    }
}
#endif
