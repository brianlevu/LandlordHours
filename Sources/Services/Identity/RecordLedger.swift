import Foundation
import CloudKit
import CryptoKit
import os.log

private let ledgerLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "RecordLedger")

// MARK: - The invariant (§2.3): no record version is ever lost
//
// Over (UUID, content hash) pairs: every distinct version of a record present at S1 (device) or
// S5 (zone) is, after the step, in exactly one of the live set, an archive group, Recently
// removed, or the backup (a last-writer-wins loser), and no UUID disappears without a place.
// The content hash is the sync fingerprint (`SyncChangeTracker.fingerprint`) over the record's
// fields without the owner tag, so a re-tag is not a new version.

struct RecordVersion: Hashable, Codable {
    var name: String
    var hash: String
}

struct RecordLedger {
    /// Fingerprint of a record without its `appUserId` (a re-tag is the same content).
    static func contentHash(_ record: CKRecord) -> String {
        SyncChangeTracker.fingerprint(record, excluding: ["appUserId"])
    }

    /// Entries are most of a record set: hashed straight from the model with the same field
    /// encoding `SyncChangeTracker.fingerprint` uses on the CKRecord `CloudKitSyncService.record(for:)`
    /// builds (no CKRecord allocation; S1–S4 must stay under 400 ms for 5,000 entries). A unit test
    /// pins it to the CKRecord path (`RecordLedgerTests.testFastEntryHashMatchesTheRecordPath`).
    static func version(_ entry: TimeEntry) -> RecordVersion {
        RecordVersion(name: entry.id.uuidString, hash: entryHash(entry))
    }

    static func entryHash(_ entry: TimeEntry) -> String {
        func d(_ date: Date) -> String { "d:\(Int64((date.timeIntervalSince1970 * 1000).rounded()))" }
        var fields: [(String, String)] = [
            ("propertyId", "s:" + entry.propertyId.uuidString),
            ("participant", "s:" + entry.participant.rawValue),
            ("category", "s:" + entry.category.rawValue),
            ("hours", "n:" + NSNumber(value: entry.hours).stringValue),
            ("date", d(entry.date)),
            ("notes", "s:" + entry.notes),
            ("createdAt", d(entry.createdAt)),
            ("modifiedAt", d(entry.modifiedAt))
        ]
        if let v = entry.importSource { fields.append(("importSource", "s:" + v)) }
        if let v = entry.importExternalId { fields.append(("importExternalId", "s:" + v)) }
        if let v = entry.importCalendarId { fields.append(("importCalendarId", "s:" + v)) }
        if let v = entry.detectedAt { fields.append((CloudKitSyncService.CaptureEntryField.detectedAt, d(v))) }
        if let v = entry.confirmedAt { fields.append((CloudKitSyncService.CaptureEntryField.confirmedAt, d(v))) }
        if let v = entry.sourceDetail { fields.append((CloudKitSyncService.CaptureEntryField.sourceDetail, "s:" + v)) }
        if let v = entry.sourceKey { fields.append((CloudKitSyncService.CaptureEntryField.sourceKey, "s:" + v)) }
        if let v = entry.recordDescription { fields.append((CloudKitSyncService.CaptureEntryField.recordDescription, "s:" + v)) }
        fields.sort { $0.0 < $1.0 }
        let joined = (["type=TimeEntry"] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: "\u{1F}")
        return hex(SHA256.hash(data: Data(joined.utf8)))
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// Lowercase hex without `String(format:)` per byte (the slow part on an A12 in S4).
    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        var out = [UInt8]()
        out.reserveCapacity(64)
        for byte in digest {
            out.append(hexDigits[Int(byte >> 4)])
            out.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func version(_ property: RentalProperty) -> RecordVersion {
        RecordVersion(name: property.id.uuidString,
                      hash: contentHash(CloudKitSyncService.record(for: property, zoneID: IdentityZone.zoneID, appUserId: nil)))
    }

    static func version(_ category: CustomCategory) -> RecordVersion {
        RecordVersion(name: category.id.uuidString,
                      hash: contentHash(CloudKitSyncService.record(for: category, zoneID: IdentityZone.zoneID, appUserId: nil)))
    }

    static func versions(entries: [TimeEntry], properties: [RentalProperty], categories: [CustomCategory] = []) -> Set<RecordVersion> {
        Set(entries.map(version) + properties.map(version) + categories.map(version))
    }

    struct Places {
        var live: Set<RecordVersion> = []
        var archived: Set<RecordVersion> = []
        var removed: Set<RecordVersion> = []
        /// Versions written to the backup (S2 holds every device version; LWW cloud losers too).
        var backup: Set<RecordVersion> = []
        /// Record names tombstoned (a delete the user made); must have a copy in removed or backup.
        var tombstoned: Set<String> = []
        /// Names kept raw because they could not be parsed (R6b): present, never deleted.
        var unparsed: Set<String> = []
    }

    struct Violation: Equatable, CustomStringConvertible {
        var name: String
        var reason: String
        var description: String { "\(name): \(reason)" }
    }

    /// Checks `before` (S1 ∪ S5 versions) against where things are now.
    static func check(before: Set<RecordVersion>, places: Places) -> [Violation] {
        let placedNames = Set((places.live.union(places.archived).union(places.removed)).map(\.name))
        var violations: [Violation] = []
        for version in before {
            if places.live.contains(version) || places.archived.contains(version) || places.removed.contains(version) { continue }
            if places.unparsed.contains(version.name) { continue }
            if places.tombstoned.contains(version.name) {
                if places.backup.contains(version) { continue }
                violations.append(Violation(name: version.name, reason: "tombstoned with no copy in Recently removed or the backup"))
                continue
            }
            if placedNames.contains(version.name) {
                // A last-writer-wins loser: the newer version is placed; this one must be in the backup.
                if places.backup.contains(version) { continue }
                violations.append(Violation(name: version.name, reason: "older version dropped without a backup copy"))
                continue
            }
            violations.append(Violation(name: version.name, reason: "record disappeared (not live, archived, removed or tombstoned)"))
        }
        // "Exactly one": a version may not be both live and archived/removed.
        for version in places.live where places.archived.contains(version) || places.removed.contains(version) {
            violations.append(Violation(name: version.name, reason: "in the live set and also archived or removed"))
        }
        return violations.sorted { $0.name < $1.name }
    }

    /// DEBUG: a violation is a crash. Release: one anonymous event with counts (no ids).
    #if DEBUG
    /// The last check per step (unit tests assert it is empty).
    nonisolated(unsafe) static var lastChecks: [String: [Violation]] = [:]
    #endif

    static func enforce(_ violations: [Violation], step: String) {
        #if DEBUG
        lastChecks[step] = violations
        #endif
        guard !violations.isEmpty else { return }
        ledgerLogger.fault("Invariant violated at \(step, privacy: .public): \(violations.count) record(s)")
        Analytics.identityInvariantViolation(step: step, count: violations.count)
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            assertionFailure("Record invariant violated at \(step): \(violations.prefix(5))")
        }
        #endif
    }
}

/// The snapshot files the verifier script (`scripts/qa/identity_invariant.py`) recomputes from.
struct LedgerSnapshot: Codable {
    var step: String
    var takenAt: Date
    var live: [RecordVersion]
    var archived: [RecordVersion]
    var removed: [RecordVersion]
    var tombstoned: [String]

    static func url(_ name: String, root: URL) -> URL {
        MigrationFiles.migrationDirectory(root: root).appendingPathComponent(name)
    }

    func save(_ name: String, root: URL) {
        do { try MigrationFiles.writeDurably(JSONEncoder.identity.encode(self), to: Self.url(name, root: root)) } catch {
            ledgerLogger.error("Could not write \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
