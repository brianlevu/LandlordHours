import Foundation

// MARK: - The free-rental pick, synced through iCloud (2.3, plan package A acceptance 11)
//
// The pick lives in the user's CloudKit private database, in the zone the app already syncs to,
// as one `FreeRental` record per record set (`FreeRental-<owner>`). The engine ignores the type;
// this file reads and writes it on its own, after each successful pull and on each local change.
//
// The rules (pure, `merge`):
//   - the pick with the later `chosenAt` wins on every device, and the month clock follows the
//     winner's `chosenAt` (the clock IS `chosenAt`);
//   - a `.defaulted` pick (the sheet swiped away) never overwrites a `.picked` one, whatever the dates;
//   - offline, the local pick holds: a change marks the pick dirty, and the next sync sends it.
// Unit tests run against a fake cloud store and a fake local store (FreeRentalSyncTests).

/// The pick in iCloud. `fetch` returns nil when there is no record yet.
protocol FreeRentalCloudStore: AnyObject {
    func fetch() async throws -> FreeRentalSelection?
    /// Saves only if the server record is unchanged since the fetch; otherwise throws `.conflict`.
    func save(_ selection: FreeRentalSelection) async throws
}

enum FreeRentalCloudError: Error, Equatable {
    /// Someone else saved first: merge with this and try again.
    case conflict(FreeRentalSelection?)
    case unavailable
}

/// The pick on this device (EntitlementStore's per-profile `freeRental.v1`).
protocol FreeRentalLocalStore: AnyObject {
    var selection: FreeRentalSelection? { get }
    func adopt(_ selection: FreeRentalSelection)
    var isDirty: Bool { get set }
}

/// The real local store: the same per-profile key and encoding `EntitlementStore` uses, so the
/// policy reads what sync adopted. (EntitlementStore has no setter for an arbitrary selection:
/// its own writes go through the switch rules, which an adopted iCloud pick must not re-run.)
final class EntitlementFreeRentalLocal: FreeRentalLocalStore {
    private let defaults: UserDefaults
    private let key: (String) -> String
    private let changed: () -> Void

    init(defaults: UserDefaults = .standard, key: @escaping (String) -> String = { UserScope.key($0) },
         changed: @escaping () -> Void = { EntitlementStore.shared.objectWillChange.send() }) {
        self.defaults = defaults
        self.key = key
        self.changed = changed
    }

    var selection: FreeRentalSelection? {
        guard let data = defaults.data(forKey: key("freeRental.v1")) else { return nil }
        return try? JSONDecoder().decode(FreeRentalSelection.self, from: data)
    }

    func adopt(_ selection: FreeRentalSelection) {
        guard selection != self.selection, let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: key("freeRental.v1"))
        changed()
    }

    var isDirty: Bool {
        get { defaults.bool(forKey: key("freeRental.dirty.v1")) }
        set { defaults.set(newValue, forKey: key("freeRental.dirty.v1")) }
    }
}

@MainActor
final class FreeRentalSync {
    static let shared = FreeRentalSync()

    /// Set by `CloudKitSyncService` once iCloud is reachable for this record set.
    var cloud: FreeRentalCloudStore?
    let local: FreeRentalLocalStore
    private var running: Task<Void, Never>?

    init(local: FreeRentalLocalStore = EntitlementFreeRentalLocal(), cloud: FreeRentalCloudStore? = nil) {
        self.local = local
        self.cloud = cloud
    }

    // MARK: Rules

    /// The pick both devices keep.
    nonisolated static func merge(local: FreeRentalSelection?, remote: FreeRentalSelection?) -> FreeRentalSelection? {
        guard let local else { return remote }
        guard let remote else { return local }
        if local.source != remote.source {
            return local.source == .picked ? local : remote
        }
        if local.chosenAt != remote.chosenAt { return local.chosenAt > remote.chosenAt ? local : remote }
        // Same time: a fixed order, so both devices land on the same answer.
        return local.rentalID.uuidString <= remote.rentalID.uuidString ? local : remote
    }

    // MARK: Events

    /// The person picked, switched or swiped the sheet away on this device.
    func localPickChanged() {
        local.isDirty = true
        schedule()
    }

    /// After a pull (or when iCloud comes back): read the record, adopt the winner, send ours if it won.
    func syncNow() async {
        if let running {
            await running.value
            guard local.isDirty, self.running == nil else { return }
        }
        let task = Task { await run() }
        running = task
        await task.value
        running = nil
    }

    private func schedule() {
        guard cloud != nil else { return }   // stays dirty; the next pull sends it
        Task { await syncNow() }
    }

    private func run() async {
        guard let cloud else { return }
        for _ in 0..<3 {
            do {
                let remote = try await cloud.fetch()
                guard let winner = Self.merge(local: local.selection, remote: remote) else { return }
                if winner != local.selection { local.adopt(winner) }
                if winner != remote {
                    try await cloud.save(winner)
                }
                local.isDirty = false
                return
            } catch FreeRentalCloudError.conflict(let server) {
                // Another device saved between our read and write: fold theirs in and go again.
                if let merged = Self.merge(local: local.selection, remote: server), merged != local.selection {
                    local.adopt(merged)
                }
                continue
            } catch {
                return   // offline or iCloud unavailable: the local pick holds, still dirty if it was
            }
        }
    }
}
