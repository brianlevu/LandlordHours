import Foundation
import Combine

// MARK: - What was logged for each care task (2.3, package B)
//
// When Log time saves an entry it opened from a care row, the entry's id is recorded against the
// task here. Everything shown (the done row's "Logged 1h · Oct 4", the "Last time" and "Typical"
// chips) is read back from the person's own entries through those ids, so an edited entry shows its
// new hours and a deleted (or undone) entry drops out on its own. Nothing here holds a number of
// its own: the app never invents hours.
//
// Stored per profile (`UserScope.key("careDone.v1")`), on this device.

/// One link: this entry was logged for this task.
struct CareRecord: Codable, Equatable, Sendable {
    let taskID: String
    let entryID: UUID
}

/// A care task's log, resolved against the live entry.
struct CareLog: Equatable, Sendable {
    let taskID: String
    let entryID: UUID
    let rentalID: UUID
    let hours: Double
    let date: Date
}

final class CareDoneLog: ObservableObject {
    static let shared = CareDoneLog()

    @Published private(set) var records: [CareRecord] = []

    private let defaults: UserDefaults
    private let key: () -> String
    private var loadedKey: String?

    static let baseKey = "careDone.v1"
    /// Enough for years of upkeep; the oldest go first.
    static let cap = 2000

    init(defaults: UserDefaults = .standard, key: @escaping () -> String = { UserScope.key(CareDoneLog.baseKey) }) {
        self.defaults = defaults
        self.key = key
        reload()
    }

    /// Reads the current profile's records (a profile switch changes the key).
    func reload() {
        let k = key()
        loadedKey = k
        guard let data = defaults.data(forKey: k), let decoded = try? JSONDecoder().decode([CareRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func reloadIfProfileChanged() {
        if loadedKey != key() { reload() }
    }

    /// Links a saved entry to a task.
    func record(task taskID: String, entry entryID: UUID) {
        reloadIfProfileChanged()
        guard CarePlanCatalog.task(id: taskID) != nil, !records.contains(where: { $0.entryID == entryID }) else { return }
        var next = records + [CareRecord(taskID: taskID, entryID: entryID)]
        if next.count > Self.cap { next.removeFirst(next.count - Self.cap) }
        records = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: key()) }
    }

    /// The records joined with the live entries, newest first. Safe inside a view's body: after a
    /// profile switch it reads that profile's records without publishing (`reload()` publishes).
    func logs(entries: [TimeEntry]) -> [CareLog] {
        Self.logs(records: currentRecords(), entries: entries)
    }

    private func currentRecords() -> [CareRecord] {
        let k = key()
        guard k != loadedKey else { return records }
        guard let data = defaults.data(forKey: k) else { return [] }
        return (try? JSONDecoder().decode([CareRecord].self, from: data)) ?? []
    }

    // MARK: Pure

    /// Joins records with entries: a record whose entry is gone is dropped. Newest first.
    static func logs(records: [CareRecord], entries: [TimeEntry]) -> [CareLog] {
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return records.compactMap { record -> CareLog? in
            guard let entry = byID[record.entryID] else { return nil }
            return CareLog(taskID: record.taskID, entryID: entry.id, rentalID: entry.propertyId, hours: entry.hours, date: entry.date)
        }
        .sorted { $0.date > $1.date }
    }

    /// The latest log of a task at a rental on or after `since`.
    static func latest(task: String, rental: UUID, since: Date, in logs: [CareLog]) -> CareLog? {
        logs.filter { $0.taskID == task && $0.rentalID == rental && $0.date >= since }.max { $0.date < $1.date }
    }

    /// Every log of a task, at any rental, newest first: the person's own history for it.
    /// The rental asked for comes first when it has one, so "Last time" means this rental.
    static func history(task: String, rental: UUID?, in logs: [CareLog]) -> [CareLog] {
        let all = logs.filter { $0.taskID == task }.sorted { $0.date > $1.date }
        guard let rental, let here = all.first(where: { $0.rentalID == rental }) else { return all }
        return [here] + all.filter { $0.entryID != here.entryID }
    }
}
