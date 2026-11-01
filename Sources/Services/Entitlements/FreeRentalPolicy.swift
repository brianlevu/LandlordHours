import Foundation

// MARK: - The free rental (2.3)
//
// Everyone keeps one rental free forever. With one rental it is that one. With several, the user
// picks (the pick sheet shows when Pro ends); a swipe-down keeps the most-used rental without using
// up the pick. The pick can change once a calendar month. Other rentals are view-only on the free
// plan, and their hours stay in every total: access never changes what counts.

/// A rental as the policy sees it.
struct RentalUsage: Equatable, Sendable {
    let id: UUID
    /// Hours logged there (any span; used only to choose the default).
    let hours: Double
    let createdAt: Date
}

struct FreeRentalSelection: Equatable, Codable, Sendable {
    enum Source: String, Codable, Sendable {
        /// The user chose it. Starts the month before the next switch.
        case picked
        /// The pick sheet was swiped away: the most-used rental, kept. Doesn't use up the pick.
        case defaulted
    }
    var rentalID: UUID
    var chosenAt: Date
    var source: Source
}

enum RentalAccess: String, Equatable, Sendable {
    case full
    case viewOnly
}

enum FreeRentalSwitch: Equatable, Sendable {
    case allowed
    case tooSoon(next: Date)
    case sameRental
    case unknownRental
}

enum FreeRentalPolicy {
    /// A pick dated further ahead than this is clock skew, not a pick: it never locks the switch.
    static let clockSkewTolerance: TimeInterval = 86_400

    /// The rental a free user logs at: the pick if it still exists, else the most-used rental.
    static func freeRentalID(selection: FreeRentalSelection?, rentals: [RentalUsage]) -> UUID? {
        if let selection, rentals.contains(where: { $0.id == selection.rentalID }) { return selection.rentalID }
        return mostUsed(rentals)
    }

    /// Most hours; ties go to the oldest rental, then the lower id, so the answer never flips.
    static func mostUsed(_ rentals: [RentalUsage]) -> UUID? {
        func hours(_ r: RentalUsage) -> Double { r.hours.isFinite ? r.hours : 0 }
        return rentals.min { a, b in
            if hours(a) != hours(b) { return hours(a) > hours(b) }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }?.id
    }

    static func access(for rentalID: UUID, plan: Plan, selection: FreeRentalSelection?, rentals: [RentalUsage]) -> RentalAccess {
        if plan.allows(.allRentals) { return .full }
        return freeRentalID(selection: selection, rentals: rentals) == rentalID ? .full : .viewOnly
    }

    static func canLog(at rentalID: UUID, plan: Plan, selection: FreeRentalSelection?, rentals: [RentalUsage]) -> Bool {
        access(for: rentalID, plan: plan, selection: selection, rentals: rentals) == .full
    }

    /// Every rental's hours count, whatever its access.
    static func countedRentalIDs(plan: Plan, selection: FreeRentalSelection?, rentals: [RentalUsage]) -> [UUID] {
        rentals.map(\.id)
    }

    /// The first rental is free; more need Pro.
    static func canAddRental(plan: Plan, rentalCount: Int) -> Bool {
        plan.allows(.allRentals) || rentalCount <= 0
    }

    /// Free, several rentals, and no pick (or the picked rental is gone): show the pick sheet.
    static func needsPick(plan: Plan, selection: FreeRentalSelection?, rentals: [RentalUsage]) -> Bool {
        guard !plan.hasProAccess, rentals.count > 1 else { return false }
        guard let selection else { return true }
        return !rentals.contains { $0.id == selection.rentalID }
    }

    /// The swipe-down answer: keep the most-used rental, without starting the month.
    static func keepDefault(rentals: [RentalUsage], now: Date) -> FreeRentalSelection? {
        mostUsed(rentals).map { FreeRentalSelection(rentalID: $0, chosenAt: now, source: .defaulted) }
    }

    /// When the next switch is allowed. Nil when a switch is allowed any time.
    static func nextSwitchDate(selection: FreeRentalSelection?, calendar: Calendar = .current) -> Date? {
        guard let selection, selection.source == .picked else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: selection.chosenAt)
    }

    static func canSwitch(selection: FreeRentalSelection?, to rentalID: UUID, rentals: [RentalUsage],
                          now: Date, calendar: Calendar = .current) -> FreeRentalSwitch {
        guard rentals.contains(where: { $0.id == rentalID }) else { return .unknownRental }
        guard let selection else { return .allowed }
        if selection.rentalID == rentalID { return .sameRental }
        // The free rental was deleted: never lock the user out of logging.
        guard rentals.contains(where: { $0.id == selection.rentalID }) else { return .allowed }
        guard selection.source == .picked else { return .allowed }
        if selection.chosenAt.timeIntervalSince(now) > clockSkewTolerance { return .allowed }
        guard let next = nextSwitchDate(selection: selection, calendar: calendar) else { return .allowed }
        return now >= next ? .allowed : .tooSoon(next: next)
    }

    static func switched(to rentalID: UUID, now: Date) -> FreeRentalSelection {
        FreeRentalSelection(rentalID: rentalID, chosenAt: now, source: .picked)
    }
}
