import Foundation
import Combine

// MARK: - The plan, held (2.3)
//
// One instance (`shared`) per process; `SubscriptionManager.isPro` mirrors `plan.hasProAccess`, so
// every existing lock keeps working and counts a trial as Pro. Per profile (`UserScope.key`):
//   isProUser / hasPurchasedPro   the founding flag (legacy keys, same meaning as 2.2)
//   entitlement.v1                the last StoreKit answer for the subscription, for an offline cold start
//   freeRental.v1                 the free-rental pick
//   trialDay12Shown.v1            original transaction ids whose day-12 sheet was shown
// The cache never outlives its dates: a cached trial past its end resolves to free.

final class EntitlementStore: ObservableObject {
    static let shared = EntitlementStore()

    @Published private(set) var plan: Plan = .free

    private let defaults: UserDefaults
    private let key: (String) -> String
    private let clock: () -> Date
    private let calendar: Calendar

    private struct Cache: Codable {
        var transactions: [EntitlementFact]
        var renewal: RenewalFact?
    }

    init(defaults: UserDefaults = .standard,
         key: @escaping (String) -> String = { UserScope.key($0) },
         clock: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.defaults = defaults
        self.key = key
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Plan

    /// Cold start and profile switches: resolve from the cache and the founding flag, no StoreKit.
    func loadCached() {
        let cache = readCache()
        publish(EntitlementResolver.resolve(EntitlementInputs(
            transactions: cache?.transactions ?? [], renewal: cache?.renewal, foundingLatest: nil,
            cachedFounding: foundingFlag, now: clock())))
    }

    /// Asks StoreKit, resolves, caches the subscription facts and keeps the founding flag in step.
    @MainActor
    @discardableResult
    func refresh(using client: StoreClient) async -> Plan {
        let transactions = await client.currentEntitlements()
        let foundingLatest = await client.latestTransaction(for: ProductIDs.founding)
        let hasSubscription = transactions.contains { $0.productID == ProductIDs.yearly }
        let renewal = hasSubscription ? await client.renewalState(for: ProductIDs.yearly) : nil
        let inputs = EntitlementInputs(transactions: transactions, renewal: renewal, foundingLatest: foundingLatest,
                                       cachedFounding: foundingFlag, now: clock())
        if EntitlementResolver.foundingWasRefunded(inputs) {
            writeFoundingFlag(false)
        } else if EntitlementResolver.foundingSeen(inputs) {
            writeFoundingFlag(true)
        }
        writeCache(Cache(transactions: transactions.filter { $0.productID == ProductIDs.yearly }, renewal: renewal))
        let resolved = EntitlementResolver.resolve(EntitlementInputs(
            transactions: transactions, renewal: renewal, foundingLatest: foundingLatest,
            cachedFounding: foundingFlag, now: clock()))
        publish(resolved)
        return resolved
    }

    /// The founding purchase path (and DEBUG seeds): unlock at once, persist the legacy keys.
    func setFoundingFlag(_ on: Bool) {
        writeFoundingFlag(on)
        loadCached()
    }

    /// Sign-out: free in memory; nothing on disk is erased (the next profile loads its own cache).
    func reset() { publish(.free) }

    var foundingFlag: Bool { defaults.bool(forKey: key("isProUser")) }

    private func writeFoundingFlag(_ on: Bool) {
        defaults.set(on, forKey: key("isProUser"))
        defaults.set(on, forKey: key("hasPurchasedPro"))
    }

    private func publish(_ new: Plan) {
        if plan != new { plan = new }
    }

    private func readCache() -> Cache? {
        guard let data = defaults.data(forKey: key("entitlement.v1")) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func writeCache(_ cache: Cache) {
        if cache.transactions.isEmpty {
            defaults.removeObject(forKey: key("entitlement.v1"))
        } else if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: key("entitlement.v1"))
        }
    }

    // MARK: Free rental

    var freeRentalSelection: FreeRentalSelection? {
        guard let data = defaults.data(forKey: key("freeRental.v1")) else { return nil }
        return try? JSONDecoder().decode(FreeRentalSelection.self, from: data)
    }

    private func save(_ selection: FreeRentalSelection) {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: key("freeRental.v1"))
            objectWillChange.send()
        }
    }

    func freeRentalID(rentals: [RentalUsage]) -> UUID? {
        FreeRentalPolicy.freeRentalID(selection: freeRentalSelection, rentals: rentals)
    }

    func access(for rentalID: UUID, rentals: [RentalUsage]) -> RentalAccess {
        FreeRentalPolicy.access(for: rentalID, plan: plan, selection: freeRentalSelection, rentals: rentals)
    }

    func canAddRental(rentalCount: Int) -> Bool {
        FreeRentalPolicy.canAddRental(plan: plan, rentalCount: rentalCount)
    }

    func needsFreeRentalPick(rentals: [RentalUsage]) -> Bool {
        FreeRentalPolicy.needsPick(plan: plan, selection: freeRentalSelection, rentals: rentals)
    }

    func nextFreeRentalSwitch() -> Date? {
        FreeRentalPolicy.nextSwitchDate(selection: freeRentalSelection, calendar: calendar)
    }

    /// Picks (or switches) the free rental. Saves only when allowed.
    @discardableResult
    func pickFreeRental(_ rentalID: UUID, rentals: [RentalUsage]) -> FreeRentalSwitch {
        let now = clock()
        let decision = FreeRentalPolicy.canSwitch(selection: freeRentalSelection, to: rentalID, rentals: rentals,
                                                  now: now, calendar: calendar)
        if decision == .allowed { save(FreeRentalPolicy.switched(to: rentalID, now: now)) }
        return decision
    }

    /// The pick sheet was swiped away: keep the most-used rental.
    func keepDefaultFreeRental(rentals: [RentalUsage]) {
        if let kept = FreeRentalPolicy.keepDefault(rentals: rentals, now: clock()) { save(kept) }
    }

    // MARK: Day-12 reminder

    func day12ReminderShown(for originalTransactionID: UInt64) -> Bool {
        shownReminders.contains(originalTransactionID)
    }

    func markDay12ReminderShown(for originalTransactionID: UInt64) {
        var all = shownReminders
        all.insert(originalTransactionID)
        defaults.set(all.map { String($0) }.sorted(), forKey: key("trialDay12Shown.v1"))
    }

    func shouldShowDay12Reminder() -> Bool {
        TrialSchedule.shouldShowDay12Reminder(plan: plan, now: clock(), shown: shownReminders, calendar: calendar)
    }

    private var shownReminders: Set<UInt64> {
        Set((defaults.stringArray(forKey: key("trialDay12Shown.v1")) ?? []).compactMap(UInt64.init))
    }
}
