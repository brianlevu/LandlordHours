import Foundation

// MARK: - 2.3 entitlements: the one source of truth for free vs trial vs Pro vs founding
//
// Everything here is pure: StoreKit facts in, a `Plan` out. `EntitlementStore` holds the current
// plan, `StoreClient` talks to StoreKit, `FreeRentalPolicy` decides which rental a free user logs
// at, `TrialSchedule` dates the 14-day trial. Plan: docs/plans/2.3-build-plan.md (foundation).
//
//   Free      everyone, forever: one rental (picked; switch once a month), the rest view-only.
//   Trial     the yearly subscription inside Apple's free intro offer.
//   Pro       the yearly subscription, paid (grace period counts).
//   Founding  the 2.2 lifetime non-consumable. Pro forever.
//
// Never a price here: the paywall shows StoreKit's localized `displayPrice`.

enum ProductIDs {
    /// The 2.x founding lifetime (non-consumable). Its buyers keep Pro forever.
    static let founding = "com.openclaw.landlordhours.pro"
    /// 2.3 Pro: auto-renewing yearly subscription with a 14-day free trial.
    static let yearly = "com.openclaw.landlordhours.pro.yearly"
    static let all: Set<String> = [founding, yearly]
}

/// What Pro unlocks. Every lock in 2.3 asks `Plan.allows(_:)`.
enum ProFeature: String, CaseIterable {
    /// Logging at more than the one free rental, and adding rentals.
    case allRentals
    /// PDF and spreadsheet export.
    case export
    /// The seasonal care plan.
    case carePlan
    /// Lessons (Learning).
    case learning
}

/// One verified StoreKit transaction, reduced to what the rules read.
struct EntitlementFact: Equatable, Codable, Sendable {
    enum Ownership: String, Codable, Sendable { case purchased, familyShared }
    enum Offer: String, Codable, Sendable { case none, freeTrial, introPaid, promotional, code, winBack }

    var productID: String
    var transactionID: UInt64
    var originalTransactionID: UInt64
    var purchaseDate: Date
    var expirationDate: Date? = nil
    var revocationDate: Date? = nil
    var isUpgraded: Bool = false
    var ownership: Ownership = .purchased
    var offer: Offer = .none
}

/// The yearly subscription's renewal status (`Product.SubscriptionInfo.Status`), reduced.
struct RenewalFact: Equatable, Codable, Sendable {
    enum State: String, Codable, Sendable { case subscribed, expired, inGracePeriod, inBillingRetryPeriod, revoked }
    var state: State
    var willAutoRenew: Bool
    var gracePeriodExpirationDate: Date? = nil
}

struct EntitlementInputs: Equatable, Sendable {
    /// Verified transactions from `Transaction.currentEntitlements` (or the cache).
    var transactions: [EntitlementFact]
    var renewal: RenewalFact?
    /// The founding product's latest verified transaction, to see a refund. Nil when StoreKit has none.
    var foundingLatest: EntitlementFact?
    /// The device's founding flag (legacy `isProUser`): a founding purchase seen earlier, or a DEBUG seed.
    var cachedFounding: Bool
    var now: Date
}

enum Plan: Equatable, Codable, Sendable {
    case free
    case trial(Subscription)
    case pro(Subscription)
    /// `alsoSubscribed`: a founding buyer who also holds the yearly subscription (tell them they needn't).
    case founding(alsoSubscribed: Bool)

    struct Subscription: Equatable, Codable, Sendable {
        /// Start of the current period: the trial start for a trial.
        var startedAt: Date
        var expiresAt: Date
        var willAutoRenew: Bool
        var inGracePeriod: Bool
        var originalTransactionID: UInt64
    }

    var hasProAccess: Bool {
        if case .free = self { return false }
        return true
    }

    func allows(_ feature: ProFeature) -> Bool { hasProAccess }

    var isFounding: Bool {
        if case .founding = self { return true }
        return false
    }

    var subscription: Subscription? {
        switch self {
        case .trial(let s), .pro(let s): return s
        case .free, .founding: return nil
        }
    }

    /// Analytics value.
    var kind: String {
        switch self {
        case .free: return "free"
        case .trial: return "trial"
        case .pro: return "pro"
        case .founding: return "founding"
        }
    }
}

enum EntitlementResolver {
    /// Apple's longest billing grace period (16 days for yearly plans). A grace record without an
    /// end date never grants more than this past the expiry, so an offline cache can't keep Pro.
    static let maxGracePeriod: TimeInterval = 16 * 86_400

    static func resolve(_ inputs: EntitlementInputs) -> Plan {
        let usable = inputs.transactions.filter(isUsable)
        let subscription = activeSubscription(usable, renewal: inputs.renewal, now: inputs.now)
        if hasFounding(inputs, usable: usable) {
            return .founding(alsoSubscribed: subscription != nil)
        }
        guard let subscription else { return .free }
        return subscription.isTrial ? .trial(subscription.info) : .pro(subscription.info)
    }

    /// StoreKit says the founding purchase was refunded (the cached flag must be cleared).
    static func foundingWasRefunded(_ inputs: EntitlementInputs) -> Bool {
        guard let latest = inputs.foundingLatest, latest.productID == ProductIDs.founding else { return false }
        return latest.revocationDate != nil
    }

    /// StoreKit knows the founding product but it doesn't count (refunded, or family-shared while
    /// Family Sharing is off): the cached flag must be cleared.
    static func foundingInvalid(_ inputs: EntitlementInputs) -> Bool {
        guard let latest = inputs.foundingLatest, latest.productID == ProductIDs.founding else { return false }
        return !isUsable(latest) && !inputs.transactions.contains { $0.productID == ProductIDs.founding && isUsable($0) }
    }

    /// StoreKit shows a live founding purchase (the cached flag can be set).
    static func foundingSeen(_ inputs: EntitlementInputs) -> Bool {
        inputs.transactions.contains { $0.productID == ProductIDs.founding && isUsable($0) }
            || (inputs.foundingLatest.map { $0.productID == ProductIDs.founding && isUsable($0) } ?? false)
    }

    /// Verified, not refunded, not upgraded away, bought by this account (Family Sharing is off),
    /// and one of our products.
    static func isUsable(_ fact: EntitlementFact) -> Bool {
        fact.revocationDate == nil && !fact.isUpgraded && fact.ownership == .purchased
            && ProductIDs.all.contains(fact.productID)
    }

    private static func hasFounding(_ inputs: EntitlementInputs, usable: [EntitlementFact]) -> Bool {
        if usable.contains(where: { $0.productID == ProductIDs.founding }) { return true }
        if let latest = inputs.foundingLatest, latest.productID == ProductIDs.founding {
            // StoreKit knows this product: it decides, whatever the cache says.
            return isUsable(latest)
        }
        return inputs.cachedFounding
    }

    private static func activeSubscription(_ usable: [EntitlementFact], renewal: RenewalFact?, now: Date)
        -> (info: Plan.Subscription, isTrial: Bool)? {
        let subs = usable.filter { $0.productID == ProductIDs.yearly && $0.expirationDate != nil }
        guard let latest = subs.max(by: { ($0.expirationDate!, $0.purchaseDate) < ($1.expirationDate!, $1.purchaseDate) }),
              let expires = latest.expirationDate else { return nil }
        var active = now < expires
        var inGrace = false
        if let renewal {
            switch renewal.state {
            case .revoked, .expired:
                return nil
            case .inGracePeriod:
                let graceEnd = renewal.gracePeriodExpirationDate ?? expires.addingTimeInterval(maxGracePeriod)
                inGrace = now >= expires && now < graceEnd
                active = active || inGrace
            case .inBillingRetryPeriod, .subscribed:
                break // The date decides.
            }
        }
        guard active else { return nil }
        let info = Plan.Subscription(startedAt: latest.purchaseDate, expiresAt: expires,
                                     // Unknown renewal (offline, unverified): assume it won't
                                     // renew, so no "Keep Pro" reminder runs on a guess.
                                     willAutoRenew: renewal?.willAutoRenew ?? false,
                                     inGracePeriod: inGrace, originalTransactionID: latest.originalTransactionID)
        // A trial that failed to bill and sits in grace is a lapsed trial being retried: Pro in grace.
        return (info, latest.offer == .freeTrial && !inGrace)
    }
}
