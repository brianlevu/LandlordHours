import XCTest
@testable import LandlordHours

/// The 2.3 entitlement rules (free vs trial vs Pro vs founding), as pure functions.
/// Written before the implementation (docs/plans/2.3-build-plan.md, foundation).
final class EntitlementResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26
    private let day: TimeInterval = 86_400

    private func yearly(start: Date, days: Double, offer: EntitlementFact.Offer = .none,
                        revoked: Date? = nil, upgraded: Bool = false,
                        ownership: EntitlementFact.Ownership = .purchased, id: UInt64 = 10) -> EntitlementFact {
        EntitlementFact(productID: ProductIDs.yearly, transactionID: id, originalTransactionID: 1,
                        purchaseDate: start, expirationDate: start.addingTimeInterval(days * day),
                        revocationDate: revoked, isUpgraded: upgraded, ownership: ownership, offer: offer)
    }

    private func founding(revoked: Date? = nil, ownership: EntitlementFact.Ownership = .purchased) -> EntitlementFact {
        EntitlementFact(productID: ProductIDs.founding, transactionID: 5, originalTransactionID: 5,
                        purchaseDate: now.addingTimeInterval(-90 * day), expirationDate: nil,
                        revocationDate: revoked, ownership: ownership)
    }

    private func inputs(_ transactions: [EntitlementFact] = [], renewal: RenewalFact? = nil,
                        foundingLatest: EntitlementFact? = nil, cachedFounding: Bool = false,
                        at: Date? = nil) -> EntitlementInputs {
        EntitlementInputs(transactions: transactions, renewal: renewal, foundingLatest: foundingLatest,
                          cachedFounding: cachedFounding, now: at ?? now)
    }

    // MARK: Free

    func testNothingIsFree() {
        let plan = EntitlementResolver.resolve(inputs())
        XCTAssertEqual(plan, .free)
        XCTAssertFalse(plan.hasProAccess)
        for feature in ProFeature.allCases { XCTAssertFalse(plan.allows(feature), "\(feature)") }
    }

    // MARK: Trial

    func testFreeTrialInsideItsFourteenDaysIsTrial() {
        let start = now.addingTimeInterval(-3 * day)
        let plan = EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)],
                                                      renewal: RenewalFact(state: .subscribed, willAutoRenew: true)))
        guard case .trial(let sub) = plan else { return XCTFail("expected trial, got \(plan)") }
        XCTAssertEqual(sub.startedAt, start)
        XCTAssertEqual(sub.expiresAt, start.addingTimeInterval(14 * day))
        XCTAssertTrue(sub.willAutoRenew)
        XCTAssertTrue(plan.hasProAccess)
        for feature in ProFeature.allCases { XCTAssertTrue(plan.allows(feature), "\(feature)") }
    }

    func testLapsedTrialIsFree() {
        let start = now.addingTimeInterval(-15 * day)
        let plan = EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)],
                                                      renewal: RenewalFact(state: .expired, willAutoRenew: false)))
        XCTAssertEqual(plan, .free)
    }

    func testLapsedTrialIsFreeEvenWithNoRenewalInfo() {
        // Offline: StoreKit gave the old transaction but no status. The date alone decides.
        let start = now.addingTimeInterval(-15 * day)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)])), .free)
    }

    func testExpiryExactlyNowIsExpired() {
        let start = now.addingTimeInterval(-14 * day)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)])), .free)
    }

    func testOneSecondBeforeExpiryIsStillTrial() {
        let start = now.addingTimeInterval(-14 * day + 1)
        guard case .trial = EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)])) else {
            return XCTFail("expected trial")
        }
    }

    func testCancelledTrialKeepsAccessUntilItEnds() {
        let start = now.addingTimeInterval(-5 * day)
        let plan = EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)],
                                                      renewal: RenewalFact(state: .subscribed, willAutoRenew: false)))
        guard case .trial(let sub) = plan else { return XCTFail("expected trial") }
        XCTAssertFalse(sub.willAutoRenew)
    }

    func testExpiredStateWinsOverAFutureDate() {
        let start = now.addingTimeInterval(-2 * day)
        let plan = EntitlementResolver.resolve(inputs([yearly(start: start, days: 14, offer: .freeTrial)],
                                                      renewal: RenewalFact(state: .expired, willAutoRenew: false)))
        XCTAssertEqual(plan, .free)
    }

    // MARK: Pro (paid yearly)

    func testPaidYearAfterTheTrialIsPro() {
        let trial = yearly(start: now.addingTimeInterval(-20 * day), days: 14, offer: .freeTrial, id: 10)
        let paid = yearly(start: now.addingTimeInterval(-6 * day), days: 365, id: 11)
        let plan = EntitlementResolver.resolve(inputs([trial, paid], renewal: RenewalFact(state: .subscribed, willAutoRenew: true)))
        guard case .pro(let sub) = plan else { return XCTFail("expected pro, got \(plan)") }
        XCTAssertEqual(sub.startedAt, paid.purchaseDate)
        XCTAssertTrue(plan.hasProAccess)
    }

    func testGracePeriodKeepsPro() {
        let paid = yearly(start: now.addingTimeInterval(-366 * day), days: 365)
        let plan = EntitlementResolver.resolve(inputs([paid], renewal: RenewalFact(
            state: .inGracePeriod, willAutoRenew: true, gracePeriodExpirationDate: now.addingTimeInterval(5 * day))))
        guard case .pro(let sub) = plan else { return XCTFail("expected pro in grace, got \(plan)") }
        XCTAssertTrue(sub.inGracePeriod)
    }

    func testGracePeriodOverIsFree() {
        let paid = yearly(start: now.addingTimeInterval(-380 * day), days: 365)
        let plan = EntitlementResolver.resolve(inputs([paid], renewal: RenewalFact(
            state: .inGracePeriod, willAutoRenew: true, gracePeriodExpirationDate: now.addingTimeInterval(-1))))
        XCTAssertEqual(plan, .free)
    }

    func testBillingRetryWithoutGraceIsFree() {
        let paid = yearly(start: now.addingTimeInterval(-366 * day), days: 365)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([paid], renewal: RenewalFact(state: .inBillingRetryPeriod, willAutoRenew: true))), .free)
    }

    // MARK: Refunds and revocation

    func testRefundedSubscriptionIsFree() {
        let paid = yearly(start: now.addingTimeInterval(-30 * day), days: 365, revoked: now.addingTimeInterval(-day))
        XCTAssertEqual(EntitlementResolver.resolve(inputs([paid], renewal: RenewalFact(state: .revoked, willAutoRenew: false))), .free)
    }

    func testRefundedTrialIsFree() {
        let trial = yearly(start: now.addingTimeInterval(-2 * day), days: 14, offer: .freeTrial, revoked: now.addingTimeInterval(-60))
        XCTAssertEqual(EntitlementResolver.resolve(inputs([trial])), .free)
    }

    func testRefundedFoundingBeatsTheCachedFlag() {
        // Transaction.latest shows the founding purchase was refunded: the old cache can't keep Pro.
        let plan = EntitlementResolver.resolve(inputs([], foundingLatest: founding(revoked: now.addingTimeInterval(-day)), cachedFounding: true))
        XCTAssertEqual(plan, .free)
        XCTAssertTrue(EntitlementResolver.foundingWasRefunded(inputs([], foundingLatest: founding(revoked: now))))
    }

    func testUpgradedTransactionIsIgnored() {
        let old = yearly(start: now.addingTimeInterval(-3 * day), days: 365, upgraded: true)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([old])), .free)
    }

    func testUnknownProductIsIgnored() {
        var other = yearly(start: now.addingTimeInterval(-3 * day), days: 365)
        other.productID = "com.example.other"
        XCTAssertEqual(EntitlementResolver.resolve(inputs([other])), .free)
    }

    func testSubscriptionWithoutAnExpiryIsIgnored() {
        var odd = yearly(start: now.addingTimeInterval(-3 * day), days: 365)
        odd.expirationDate = nil
        XCTAssertEqual(EntitlementResolver.resolve(inputs([odd])), .free)
    }

    // MARK: Founding lifetime

    func testFoundingBuyerKeepsProForever() {
        let plan = EntitlementResolver.resolve(inputs([founding()], at: now.addingTimeInterval(20 * 365 * day)))
        XCTAssertEqual(plan, .founding(alsoSubscribed: false))
        XCTAssertTrue(plan.hasProAccess)
        for feature in ProFeature.allCases { XCTAssertTrue(plan.allows(feature)) }
    }

    func testFoundingFromTheCachedFlagWhenStoreKitKnowsNothing() {
        // Offline / no StoreKit answer: the device's founding flag (legacy isProUser) holds.
        XCTAssertEqual(EntitlementResolver.resolve(inputs(cachedFounding: true)), .founding(alsoSubscribed: false))
    }

    func testFoundingWinsOverASubscriptionAndFlagsIt() {
        let paid = yearly(start: now.addingTimeInterval(-3 * day), days: 365)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([founding(), paid])), .founding(alsoSubscribed: true))
    }

    func testFoundingWinsOverATrial() {
        let trial = yearly(start: now.addingTimeInterval(-3 * day), days: 14, offer: .freeTrial)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([trial], cachedFounding: true)), .founding(alsoSubscribed: true))
    }

    // MARK: Family Sharing is off

    func testFamilySharedSubscriptionIsIgnored() {
        let shared = yearly(start: now.addingTimeInterval(-3 * day), days: 365, ownership: .familyShared)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([shared])), .free)
    }

    func testFamilySharedFoundingIsIgnored() {
        XCTAssertEqual(EntitlementResolver.resolve(inputs([founding(ownership: .familyShared)])), .free)
        XCTAssertEqual(EntitlementResolver.resolve(inputs([], foundingLatest: founding(ownership: .familyShared))), .free)
    }

    // MARK: Kind (analytics)

    func testKinds() {
        XCTAssertEqual(Plan.free.kind, "free")
        XCTAssertEqual(Plan.founding(alsoSubscribed: false).kind, "founding")
        let sub = Plan.Subscription(startedAt: now, expiresAt: now, willAutoRenew: true, inGracePeriod: false, originalTransactionID: 1)
        XCTAssertEqual(Plan.trial(sub).kind, "trial")
        XCTAssertEqual(Plan.pro(sub).kind, "pro")
    }

    func testPlanRoundTripsThroughCodable() throws {
        let sub = Plan.Subscription(startedAt: now, expiresAt: now.addingTimeInterval(14 * day), willAutoRenew: true,
                                    inGracePeriod: false, originalTransactionID: 42)
        for plan in [Plan.free, .trial(sub), .pro(sub), .founding(alsoSubscribed: true)] {
            let data = try JSONEncoder().encode(plan)
            XCTAssertEqual(try JSONDecoder().decode(Plan.self, from: data), plan)
        }
    }
}
