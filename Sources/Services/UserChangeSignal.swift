import Foundation

// MARK: - "Show the result where it happened" (memory item 6; DESIGN-STANDARD §E.1)
//
// AppViewModel records each change the user makes themselves (a Log time save, an Inbox confirm).
// The next time Today is on screen it takes the change once: it opens on that rental and plays the
// house catch-up there. Then the change is gone, so a manual pick afterwards is never overruled.
// Never record iCloud sync, Inbox scans or imports here: only the person's own action.
final class UserChangeSignal {
    static let shared = UserChangeSignal()

    enum Kind: String, Sendable {
        /// Log time saved hours.
        case logged
        /// An Inbox or To confirm suggestion was confirmed.
        case confirmed
    }

    /// One change the user made, and when.
    struct Change: Equatable, Sendable {
        let rentalID: UUID
        let kind: Kind
        let at: Date
    }

    /// A change older than this is no longer "the screen I open next": it is dropped, not shown.
    static let lifetime: TimeInterval = 30 * 60

    private let lock = NSLock()
    private let now: () -> Date
    private var latest: Change?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// The user changed this rental themselves. The latest change wins when several rentals change
    /// before Today is next seen.
    func record(rentalID: UUID, kind: Kind) {
        lock.lock()
        latest = Change(rentalID: rentalID, kind: kind, at: now())
        lock.unlock()
        NotificationCenter.default.post(name: .userChangeRecorded, object: nil)
    }
    /// The pending change, without taking it (Today's switch reads this, then takes it).
    func peek() -> Change? {
        lock.lock(); defer { lock.unlock() }
        return fresh(latest)
    }

    /// Takes the pending change: the first call returns it, every later call returns nil until
    /// the user changes something again. A stale change is dropped.
    @discardableResult
    func take() -> Change? {
        lock.lock(); defer { lock.unlock() }
        let change = fresh(latest)
        latest = nil
        return change
    }

    /// Today is already showing the result (the user changed it while looking at it): nothing to
    /// carry to a later visit.
    func discard() {
        lock.lock(); defer { lock.unlock() }
        latest = nil
    }

    /// Profile switch or sign-out: a change belongs to the profile that made it.
    func reset() { discard() }

    private func fresh(_ change: Change?) -> Change? {
        guard let change, now().timeIntervalSince(change.at) <= Self.lifetime else { return nil }
        return change
    }
}

extension Notification.Name {
    /// Posted after `UserChangeSignal.record`: a Today that is already on screen drops the change
    /// (the user is looking at the result), so it never carries to a later visit.
    static let userChangeRecorded = Notification.Name("LandlordHours.userChangeRecorded")
}
