import Foundation
import CryptoKit

// MARK: - Capture identity
//
// The same real-world event can be confirmed on two devices (iPhone and iPad read the same
// iCloud calendar). Deriving the TimeEntry id — which is also the CloudKit record name — from
// the profile id plus the suggestion's dedupe key makes both confirms land on ONE CloudKit
// record, so iCloud merges them instead of double-counting tax hours.
// The profile id is part of the name because every profile on an iCloud account shares one
// sync zone: two profiles confirming the same event must get DIFFERENT records, or one
// profile's edit/delete would hit the other's tax record.
enum CaptureIdentity {
    /// Fixed namespace for LandlordHours capture ids. Never change it: changing it would give
    /// already-confirmed events new ids and break cross-device dedupe.
    static let namespace = UUID(uuidString: "6C1B6E2A-4F0D-5B8E-9C3A-2D7E1F4A8B60")!

    /// RFC 4122 version-5 (SHA-1, name-based) UUID of `"<profileId>|<sourceKey>"` in `namespace`.
    static func entryId(profileId: String, sourceKey: String) -> UUID {
        var bytes = [UInt8]()
        withUnsafeBytes(of: namespace.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array("\(profileId)|\(sourceKey)".utf8))
        var digest = Array(Insecure.SHA1.hash(data: bytes)).prefix(16).map { $0 }
        digest[6] = (digest[6] & 0x0F) | 0x50   // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80   // RFC 4122 variant
        let t = (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                 digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15])
        return UUID(uuid: t)
    }
}

// MARK: - Dedupe keys

/// Stable dedupe keys. One real-world event always produces the same key on every device.
enum SuggestionKey {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// `cal:<calendarItemExternalIdentifier>:<occurrence start, UTC ISO-8601>`. The external id
    /// is shared across devices; the occurrence date separates repeats of a recurring event.
    static func calendar(externalId: String, occurrence: Date) -> String {
        "cal:\(externalId):\(iso.string(from: occurrence))"
    }

    /// One-off (non-recurring) event: `cal:<calendarItemExternalIdentifier>`. No date, so
    /// rescheduling the event keeps its key (and its confirmed entry).
    static func calendar(externalId: String) -> String { "cal:\(externalId)" }

    /// Fallback when the calendar gives no cross-device id: the device-local `eventIdentifier`.
    /// The `cal-local:` prefix marks the suggestion as device-local; another device will not
    /// produce the same key. `occurrence` is the original occurrence of a recurring event.
    static func calendarDeviceLocal(eventIdentifier: String, occurrence: Date?) -> String {
        guard let occurrence else { return "cal-local:\(eventIdentifier)" }
        return "cal-local:\(eventIdentifier):\(iso.string(from: occurrence))"
    }

    /// `rcpt:<sha256 of the file bytes>`.
    static func receipt(sha256: String) -> String { "rcpt:\(sha256.lowercased())" }

    static func receipt(data: Data) -> String {
        receipt(sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    /// `geo:<propertyId>:<arrival, UTC ISO-8601>`.
    static func geo(propertyId: UUID, arrival: Date) -> String {
        "geo:\(propertyId.uuidString):\(iso.string(from: arrival))"
    }
}

// MARK: - Suggestion
//
// A detected activity waiting in the inbox. LOCAL ONLY: suggestions never sync and never
// leave the device (calendar titles stay on the phone). Only a confirmed suggestion becomes a
// TimeEntry, through `AppViewModel.confirm(_:edits:)`.
struct Suggestion: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case calendar
        case receipt
        case location
        case gmail

        /// The EntrySource a confirmed suggestion of this kind is stored with. Calendar keeps
        /// the 1.x stored value "calendar" so 1.1 devices still show "Calendar import".
        var entrySource: EntrySource {
            switch self {
            case .calendar: return .calendar
            case .receipt: return .receipt
            case .location: return .location
            case .gmail: return .gmail
            }
        }
    }

    /// Where the proposed hours came from. Receipts never guess hours (`.none`).
    enum HoursBasis: String, Codable {
        case scheduled
        case dwellCap
        case none
    }

    /// Which classifier produced the proposal.
    enum Tier: String, Codable {
        case rules
        case onDevice
        case pcc
    }

    enum DismissReason: String, Codable {
        case notLandlordWork
        case duplicate
        case muted
        case other
    }

    enum State: Codable, Equatable {
        case pending
        /// A TimeEntry exists for this suggestion: confirmed here, on another device, or a
        /// matching 1.x calendar import already covers it.
        case confirmed(entryId: UUID)
        case dismissed(reason: DismissReason)
    }

    var id: UUID
    /// Dedupe key (see `SuggestionKey`). The confirmed entry's id is derived from it.
    var sourceKey: String
    var kind: Kind
    var detectedAt: Date
    var start: Date
    var end: Date?
    /// Event title. Local only — used for display and legacy-import matching, never synced
    /// and never written to `TimeEntry.sourceDetail`.
    var title: String
    /// Device-shared identifier of the source item (calendar external id), if any.
    var externalId: String?
    /// The calendar event's device-local `eventIdentifier`. Written to `importExternalId` on
    /// confirm, because that is the field 1.x's calendar import dedupes on.
    var legacyEventIdentifier: String?
    /// Container of the source item (calendar id), used by mute rules.
    var containerId: String?
    var proposedPropertyId: UUID?
    var proposedCategory: ActivityCategory?
    var proposedHours: Double?
    var hoursBasis: HoursBasis
    var confidence: Double
    var tier: Tier
    var state: State
    var evidence: [String]
    /// Came from the day-1 90-day calendar backfill rather than live detection.
    var isBackfill: Bool
    /// Hours already logged by hand look like this item. Shown with a hint, never pre-selected.
    var mightAlreadyBeLogged: Bool

    init(
        id: UUID = UUID(),
        sourceKey: String,
        kind: Kind,
        detectedAt: Date,
        start: Date,
        end: Date? = nil,
        title: String,
        externalId: String? = nil,
        legacyEventIdentifier: String? = nil,
        containerId: String? = nil,
        proposedPropertyId: UUID? = nil,
        proposedCategory: ActivityCategory? = nil,
        proposedHours: Double? = nil,
        hoursBasis: HoursBasis = .none,
        confidence: Double = 0,
        tier: Tier = .rules,
        state: State = .pending,
        evidence: [String] = [],
        isBackfill: Bool = false,
        mightAlreadyBeLogged: Bool = false
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.kind = kind
        self.detectedAt = detectedAt
        self.start = start
        self.end = end
        self.title = title
        self.externalId = externalId
        self.legacyEventIdentifier = legacyEventIdentifier
        self.containerId = containerId
        self.proposedPropertyId = proposedPropertyId
        self.proposedCategory = proposedCategory
        // Receipts never guess hours.
        self.proposedHours = kind == .receipt ? nil : proposedHours
        self.hoursBasis = kind == .receipt ? .none : hoursBasis
        self.confidence = confidence
        self.tier = tier
        self.state = state
        self.evidence = evidence
        self.isBackfill = isBackfill
        self.mightAlreadyBeLogged = mightAlreadyBeLogged
    }

    var isPending: Bool { state == .pending }

    /// Whether a bulk-review list may pre-select this item. Anything that might already be
    /// logged, or that lacks a property or hours, needs a deliberate tap.
    var isPreselectable: Bool {
        isPending && !mightAlreadyBeLogged && proposedPropertyId != nil && (proposedHours ?? 0) > 0
    }

    /// The TimeEntry id a confirm of this suggestion produces for `profileId`, on every device.
    func entryId(profileId: String) -> UUID {
        CaptureIdentity.entryId(profileId: profileId, sourceKey: sourceKey)
    }
}

/// The user's edits on the confirm sheet. Nil fields fall back to the suggestion's proposal.
struct SuggestionEdits: Equatable {
    var propertyId: UUID?
    var category: ActivityCategory?
    var hours: Double?
    var date: Date?
    var participant: Participant?
    var notes: String?

    init(
        propertyId: UUID? = nil,
        category: ActivityCategory? = nil,
        hours: Double? = nil,
        date: Date? = nil,
        participant: Participant? = nil,
        notes: String? = nil
    ) {
        self.propertyId = propertyId
        self.category = category
        self.hours = hours
        self.date = date
        self.participant = participant
        self.notes = notes
    }
}

// MARK: - Mute rules

/// "Stop suggesting things like this." Stored with the suggestions, local only.
struct CaptureMuteRule: Identifiable, Codable, Equatable {
    enum Match: String, Codable {
        /// Case-insensitive substring of the title.
        case titleContains
        /// Exact source container (calendar id).
        case containerId
    }

    var id: UUID
    var match: Match
    var value: String
    var createdAt: Date

    init(id: UUID = UUID(), match: Match, value: String, createdAt: Date = Date()) {
        self.id = id
        self.match = match
        self.value = value
        self.createdAt = createdAt
    }

    func mutes(_ suggestion: Suggestion) -> Bool {
        switch match {
        case .titleContains:
            let needle = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return false }
            return suggestion.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .containerId:
            return suggestion.containerId == value
        }
    }
}
