import Foundation
import StoreKit

// MARK: - StoreKit 2 behind a protocol (2.3)
//
// `EntitlementStore` and the paywall talk to `StoreClient`, never to StoreKit, so every rule is
// unit-tested with a fake and the real client is tested once against LandlordHours.storekit
// (SubscriptionStoreKitTests). The real client only maps StoreKit types to plain values.

/// A product as the paywall needs it. `displayPrice` is StoreKit's localized string: the only
/// price text the app ever shows.
struct StoreProductInfo: Equatable, Sendable {
    enum Period: String, Equatable, Sendable { case week, month, year }
    let id: String
    let displayName: String
    let displayPrice: String
    /// Nil for the lifetime non-consumable.
    let period: Period?
    /// Days of the free intro offer, nil when there is none.
    let introTrialDays: Int?
}

enum StorePurchaseResult: Equatable, Sendable {
    case success(EntitlementFact)
    case userCancelled
    /// Ask to Buy or SCA: approved later through `Transaction.updates`.
    case pending
    /// The App Store's receipt didn't verify. Nothing unlocks.
    case unverified
}

protocol StoreClient: Sendable {
    func currentEntitlements() async -> [EntitlementFact]
    func latestTransaction(for productID: String) async -> EntitlementFact?
    func renewalState(for productID: String) async -> RenewalFact?
    func isEligibleForIntroOffer(productID: String) async -> Bool
    func products(for ids: Set<String>) async throws -> [StoreProductInfo]
    func purchase(productID: String) async throws -> StorePurchaseResult
}

enum StoreClientError: Error, Equatable {
    case productNotFound(String)
}

/// The real client. Callers in a unit-test host must attach the StoreKit test session first
/// (`SubscriptionManager.isStoreKitAttached`): the first StoreKit call binds the environment.
struct StoreKit2Client: StoreClient {
    func currentEntitlements() async -> [EntitlementFact] {
        var facts: [EntitlementFact] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, ProductIDs.all.contains(transaction.productID) {
                facts.append(Self.fact(transaction))
            }
        }
        return facts
    }

    func latestTransaction(for productID: String) async -> EntitlementFact? {
        guard let result = await Transaction.latest(for: productID), case .verified(let transaction) = result else { return nil }
        return Self.fact(transaction)
    }

    func renewalState(for productID: String) async -> RenewalFact? {
        guard let result = await Transaction.latest(for: productID), case .verified(let transaction) = result,
              let status = await transaction.subscriptionStatus else { return nil }
        let renewalInfo: Product.SubscriptionInfo.RenewalInfo?
        if case .verified(let info) = status.renewalInfo { renewalInfo = info } else { renewalInfo = nil }
        return RenewalFact(state: Self.state(status.state),
                           willAutoRenew: renewalInfo?.willAutoRenew ?? true,
                           gracePeriodExpirationDate: renewalInfo?.gracePeriodExpirationDate)
    }

    func isEligibleForIntroOffer(productID: String) async -> Bool {
        guard let product = try? await Product.products(for: [productID]).first,
              let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    func products(for ids: Set<String>) async throws -> [StoreProductInfo] {
        try await Product.products(for: ids).map(Self.info)
    }

    func purchase(productID: String) async throws -> StorePurchaseResult {
        guard let product = try await Product.products(for: [productID]).first else {
            throw StoreClientError.productNotFound(productID)
        }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            await transaction.finish()
            return .success(Self.fact(transaction))
        case .success(.unverified):
            return .unverified
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .userCancelled
        }
    }

    // MARK: Mapping

    static func fact(_ t: Transaction) -> EntitlementFact {
        EntitlementFact(productID: t.productID, transactionID: t.id, originalTransactionID: t.originalID,
                        purchaseDate: t.purchaseDate, expirationDate: t.expirationDate,
                        revocationDate: t.revocationDate, isUpgraded: t.isUpgraded,
                        ownership: t.ownershipType == .familyShared ? .familyShared : .purchased,
                        offer: offer(t))
    }

    static func offer(_ t: Transaction) -> EntitlementFact.Offer {
        guard let offer = t.offer else { return .none }
        switch offer.type {
        case .introductory: return offer.paymentMode == .freeTrial ? .freeTrial : .introPaid
        case .promotional: return .promotional
        case .code: return .code
        case .winBack: return .winBack
        default: return .none
        }
    }

    static func state(_ s: Product.SubscriptionInfo.RenewalState) -> RenewalFact.State {
        switch s {
        case .subscribed: return .subscribed
        case .expired: return .expired
        case .inGracePeriod: return .inGracePeriod
        case .inBillingRetryPeriod: return .inBillingRetryPeriod
        case .revoked: return .revoked
        default: return .expired
        }
    }

    static func info(_ p: Product) -> StoreProductInfo {
        let period: StoreProductInfo.Period?
        switch p.subscription?.subscriptionPeriod.unit {
        case .week?: period = .week
        case .month?: period = .month
        case .year?: period = .year
        default: period = nil
        }
        var trialDays: Int?
        if let intro = p.subscription?.introductoryOffer, intro.paymentMode == .freeTrial {
            trialDays = days(intro.period)
        }
        return StoreProductInfo(id: p.id, displayName: p.displayName, displayPrice: p.displayPrice,
                                period: period, introTrialDays: trialDays)
    }

    static func days(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }
}
