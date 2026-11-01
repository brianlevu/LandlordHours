import XCTest
@testable import LandlordHours

/// A StoreClient double: returns what the test set, counts calls, never touches StoreKit.
final class FakeStoreClient: StoreClient, @unchecked Sendable {
    var entitlements: [EntitlementFact] = []
    var latest: [String: EntitlementFact] = [:]
    var renewal: RenewalFact?
    var eligible = true
    var productInfo: [StoreProductInfo] = []
    var purchaseResult: StorePurchaseResult = .userCancelled
    var purchaseError: Error?
    private(set) var purchased: [String] = []

    func currentEntitlements() async -> [EntitlementFact] { entitlements }
    func latestTransaction(for productID: String) async -> EntitlementFact? { latest[productID] }
    func renewalState(for productID: String) async -> RenewalFact? { renewal }
    func isEligibleForIntroOffer(productID: String) async -> Bool { eligible }
    func products(for ids: Set<String>) async throws -> [StoreProductInfo] { productInfo.filter { ids.contains($0.id) } }
    func purchase(productID: String) async throws -> StorePurchaseResult {
        purchased.append(productID)
        if let purchaseError { throw purchaseError }
        return purchaseResult
    }
}

/// The store that holds the plan: cache, cold start, refresh, the founding flag, the free rental.
final class EntitlementStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var now = Date(timeIntervalSince1970: 1_793_000_000)
    private let day: TimeInterval = 86_400
    private let pine = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let oak = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    override func setUp() {
        super.setUp()
        suite = "entitlement-store-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeStore() -> EntitlementStore {
        EntitlementStore(defaults: defaults, key: { "t.\($0)" }, clock: { [unowned self] in self.now })
    }

    private func trialFact(start: Date) -> EntitlementFact {
        EntitlementFact(productID: ProductIDs.yearly, transactionID: 20, originalTransactionID: 20, purchaseDate: start,
                        expirationDate: start.addingTimeInterval(14 * day), offer: .freeTrial)
    }

    private var rentals: [RentalUsage] {
        [RentalUsage(id: pine, hours: 80, createdAt: now), RentalUsage(id: oak, hours: 10, createdAt: now)]
    }

    func testFreshStoreIsFree() {
        XCTAssertEqual(makeStore().plan, .free)
    }

    @MainActor
    func testRefreshResolvesAndCaches() async {
        let client = FakeStoreClient()
        client.entitlements = [trialFact(start: now.addingTimeInterval(-day))]
        client.renewal = RenewalFact(state: .subscribed, willAutoRenew: true)
        let store = makeStore()
        let plan = await store.refresh(using: client)
        guard case .trial = plan else { return XCTFail("expected trial, got \(plan)") }
        XCTAssertEqual(store.plan, plan)

        // Cold start, offline: the cache answers.
        let cold = makeStore()
        cold.loadCached()
        XCTAssertEqual(cold.plan, plan)
    }

    @MainActor
    func testCachedTrialLapsesOnColdStartAfterItsEnd() async {
        let client = FakeStoreClient()
        client.entitlements = [trialFact(start: now.addingTimeInterval(-day))]
        _ = await makeStore().refresh(using: client)
        now = now.addingTimeInterval(20 * day)
        let cold = makeStore()
        cold.loadCached()
        XCTAssertEqual(cold.plan, .free, "a cached trial can't outlive its end date offline")
    }

    @MainActor
    func testRefreshWithNoSubscriptionClearsTheCache() async {
        let client = FakeStoreClient()
        client.entitlements = [trialFact(start: now.addingTimeInterval(-day))]
        let store = makeStore()
        _ = await store.refresh(using: client)
        client.entitlements = []
        let plan = await store.refresh(using: client)
        XCTAssertEqual(plan, .free)
        let cold = makeStore()
        cold.loadCached()
        XCTAssertEqual(cold.plan, .free)
    }

    func testFoundingFlagUnlocksAtOnceAndPersists() {
        let store = makeStore()
        store.setFoundingFlag(true)
        XCTAssertEqual(store.plan, .founding(alsoSubscribed: false))
        XCTAssertTrue(defaults.bool(forKey: "t.isProUser"), "the legacy key keeps its meaning")
        let cold = makeStore()
        cold.loadCached()
        XCTAssertEqual(cold.plan, .founding(alsoSubscribed: false))
    }

    func testLegacyFlagFromAnOlderBuildIsFounding() {
        defaults.set(true, forKey: "t.isProUser")
        let store = makeStore()
        store.loadCached()
        XCTAssertEqual(store.plan, .founding(alsoSubscribed: false))
    }

    @MainActor
    func testFoundingPurchaseSeenInStoreKitSetsTheFlag() async {
        let client = FakeStoreClient()
        client.entitlements = [EntitlementFact(productID: ProductIDs.founding, transactionID: 3, originalTransactionID: 3,
                                               purchaseDate: now.addingTimeInterval(-day))]
        let store = makeStore()
        let plan = await store.refresh(using: client)
        XCTAssertEqual(plan, .founding(alsoSubscribed: false))
        XCTAssertTrue(defaults.bool(forKey: "t.isProUser"))
        XCTAssertTrue(defaults.bool(forKey: "t.hasPurchasedPro"))
    }

    @MainActor
    func testFoundingRefundClearsTheFlag() async {
        defaults.set(true, forKey: "t.isProUser")
        defaults.set(true, forKey: "t.hasPurchasedPro")
        let client = FakeStoreClient()
        client.latest[ProductIDs.founding] = EntitlementFact(productID: ProductIDs.founding, transactionID: 3, originalTransactionID: 3,
                                                             purchaseDate: now.addingTimeInterval(-9 * day), revocationDate: now)
        let store = makeStore()
        store.loadCached()
        XCTAssertEqual(store.plan, .founding(alsoSubscribed: false))
        let plan = await store.refresh(using: client)
        XCTAssertEqual(plan, .free)
        XCTAssertFalse(defaults.bool(forKey: "t.isProUser"))
        XCTAssertFalse(defaults.bool(forKey: "t.hasPurchasedPro"))
    }

    @MainActor
    func testUnverifiedOrEmptyStoreKitKeepsTheFoundingFlag() async {
        // StoreKit knows nothing about the founding product (sandbox, offline, DEBUG seed): keep it.
        defaults.set(true, forKey: "t.isProUser")
        let store = makeStore()
        let plan = await store.refresh(using: FakeStoreClient())
        XCTAssertEqual(plan, .founding(alsoSubscribed: false))
    }

    func testResetIsFreeInMemoryOnly() {
        let store = makeStore()
        store.setFoundingFlag(true)
        store.reset()
        XCTAssertEqual(store.plan, .free)
        XCTAssertTrue(defaults.bool(forKey: "t.isProUser"), "sign-out doesn't erase the purchase")
    }

    // MARK: Free rental persistence

    func testFreeRentalPickPersistsAndRespectsTheMonth() {
        let store = makeStore()
        XCTAssertEqual(store.freeRentalID(rentals: rentals), pine, "default: most used")
        XCTAssertEqual(store.pickFreeRental(oak, rentals: rentals), .allowed)
        XCTAssertEqual(store.freeRentalID(rentals: rentals), oak)
        let cold = makeStore()
        XCTAssertEqual(cold.freeRentalID(rentals: rentals), oak)
        guard case .tooSoon = cold.pickFreeRental(pine, rentals: rentals) else { return XCTFail("one switch a month") }
        XCTAssertEqual(cold.freeRentalID(rentals: rentals), oak, "a refused switch changes nothing")
    }

    func testKeepDefaultRecordsTheMostUsed() {
        let store = makeStore()
        XCTAssertTrue(store.needsFreeRentalPick(rentals: rentals))
        store.keepDefaultFreeRental(rentals: rentals)
        XCTAssertFalse(store.needsFreeRentalPick(rentals: rentals))
        XCTAssertEqual(store.freeRentalID(rentals: rentals), pine)
        XCTAssertEqual(store.pickFreeRental(oak, rentals: rentals), .allowed, "the default doesn't use up the switch")
    }

    func testAccessUsesThePlanAndThePick() {
        let store = makeStore()
        _ = store.pickFreeRental(oak, rentals: rentals)
        XCTAssertEqual(store.access(for: pine, rentals: rentals), .viewOnly)
        XCTAssertEqual(store.access(for: oak, rentals: rentals), .full)
        store.setFoundingFlag(true)
        XCTAssertEqual(store.access(for: pine, rentals: rentals), .full)
        XCTAssertFalse(store.needsFreeRentalPick(rentals: rentals), "Pro never asks")
    }

    func testDay12ShownIsRememberedPerTrial() {
        let store = makeStore()
        XCTAssertFalse(store.day12ReminderShown(for: 20))
        store.markDay12ReminderShown(for: 20)
        XCTAssertTrue(makeStore().day12ReminderShown(for: 20))
        XCTAssertFalse(makeStore().day12ReminderShown(for: 21))
    }

    func testCorruptCacheIsIgnored() {
        defaults.set(Data("not json".utf8), forKey: "t.entitlement.v1")
        defaults.set(Data("nope".utf8), forKey: "t.freeRental.v1")
        let store = makeStore()
        store.loadCached()
        XCTAssertEqual(store.plan, .free)
        XCTAssertEqual(store.freeRentalID(rentals: rentals), pine)
    }

    // MARK: Products (no price literal anywhere: the paywall shows displayPrice)

    @MainActor
    func testProductInfoCarriesTheStorePriceAndTrial() async throws {
        let client = FakeStoreClient()
        client.productInfo = [StoreProductInfo(id: ProductIDs.yearly, displayName: "Dormer Pro", displayPrice: "€54,99",
                                               period: .year, introTrialDays: 14)]
        let infos = try await client.products(for: [ProductIDs.yearly])
        XCTAssertEqual(infos.first?.displayPrice, "€54,99")
        XCTAssertEqual(infos.first?.introTrialDays, 14)
    }
}
