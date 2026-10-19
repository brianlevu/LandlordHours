import Foundation
import os.log

// MARK: - Property Entity
enum PropertyType: String, Codable, CaseIterable {
    case ltr = "LTR"
    case str = "STR"
    
    var displayName: String {
        rawValue
    }
    
    var fullName: String {
        switch self {
        case .ltr: return "Long-Term Rental"
        case .str: return "Short-Term Rental"
        }
    }
    
    var icon: String {
        switch self {
        case .ltr: return "house.fill"
        case .str: return "building.2.fill"
        }
    }
}

struct RentalProperty: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var propertyType: PropertyType
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, address: String, propertyType: PropertyType) {
        self.id = id
        self.name = name
        self.address = address
        self.propertyType = propertyType
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        propertyType = try c.decode(PropertyType.self, forKey: .propertyType)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }
    
    var shortAddress: String {
        let components = address.components(separatedBy: ",")
        return components.first ?? address
    }
}

// MARK: - Activity Types (IRS-Approved)
enum ActivityCategory: String, Codable, CaseIterable {
    // Material Participation Activities (IRS-approved)
    case repairs = "Repairs & Maintenance"
    case management = "Property Management"
    case leasing = "Leasing & Tenant Relations"
    case bookkeeping = "Bookkeeping & Financial"
    case legal = "Legal & Compliance"
    case insurance = "Insurance & Claims"
    case travel = "Travel to Property"
    case renovations = "Renovations & Improvements"
    
    // Investor-Level Tasks (don't count for REPS)
    case investing = "Investing Decisions"
    case financing = "Financing"
    case contractNegotiation = "Contract Negotiation"
    
    var countsForREPS: Bool {
        switch self {
        case .investing, .financing, .contractNegotiation:
            return false
        default:
            return true
        }
    }
    
    var description: String {
        switch self {
        case .repairs: return "Fixing leaks, HVAC, plumbing, electrical"
        case .management: return "Collecting rent, communications, scheduling"
        case .leasing: return "Showing units, screening tenants, signing leases"
        case .bookkeeping: return "Accounting, tax prep, financial records"
        case .legal: return "Evictions, compliance, permits"
        case .insurance: return "Claims, policy reviews"
        case .travel: return "Driving to property for activities"
        case .renovations: return "Major improvements, remodeling"
        case .investing: return "NOT countable - Investment decisions"
        case .financing: return "NOT countable - Loan decisions"
        case .contractNegotiation: return "NOT countable - Purchase/sale negotiations"
        }
    }
    
    var icon: String {
        switch self {
        case .repairs: return "wrench.fill"
        case .management: return "folder.fill"
        case .leasing: return "key.fill"
        case .bookkeeping: return "doc.text.fill"
        case .legal: return "building.columns.fill"
        case .insurance: return "shield.fill"
        case .travel: return "car.fill"
        case .renovations: return "hammer.fill"
        case .investing: return "chart.line.uptrend.xyaxis"
        case .financing: return "dollarsign.circle.fill"
        case .contractNegotiation: return "signature"
        }
    }
    
    static var repsQualified: [ActivityCategory] {
        allCases.filter { $0.countsForREPS }
    }
    
    static var nonREPS: [ActivityCategory] {
        allCases.filter { !$0.countsForREPS }
    }
}

// MARK: - Participant
enum Participant: String, Codable, CaseIterable {
    case selfParticipant = "Self"
    case spouse = "Spouse"
    
    var icon: String {
        switch self {
        case .selfParticipant: return "person.fill"
        case .spouse: return "person.2.fill"
        }
    }
}

// MARK: - Attachment Model
//
// Attachment bytes are stored as files under Application Support/Attachments,
// not inline in the persisted JSON blob (photos would otherwise blow past
// UserDefaults' practical size limits and fail to save silently). The struct
// keeps its identity/metadata; bytes load lazily from disk via `data`.
//
// `pendingData` is the transient in-memory buffer for bytes that have not yet
// been flushed to disk — either a freshly picked photo or a legacy inline blob
// decoded from an older store. It is never encoded; migration/save flushes it to
// a file and clears it. Old blobs that still carry an inline `data` key decode
// into `pendingData` so the one-time migration can move them to files.
struct TimeAttachment: Identifiable, Codable {
    let id: UUID
    var filename: String
    var mimeType: String
    var createdAt: Date
    var modifiedAt: Date

    /// Bytes not yet persisted to disk. Never encoded — file storage is the source of truth.
    private var pendingData: Data?

    enum CodingKeys: String, CodingKey {
        case id, filename, data, mimeType, createdAt, modifiedAt
    }

    init(id: UUID = UUID(), filename: String, data: Data, mimeType: String) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.pendingData = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        mimeType = try c.decode(String.self, forKey: .mimeType)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        // Legacy inline bytes (pre file-based storage) decode here so migration can flush them.
        pendingData = try c.decodeIfPresent(Data.self, forKey: .data)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(filename, forKey: .filename)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        // Intentionally omit `data`: bytes live in files, not in the persisted blob.
    }

    /// True while inline bytes are still waiting to be written to disk.
    var hasPendingData: Bool { pendingData != nil }

    /// Inline bytes awaiting a disk flush, if any.
    var pendingBytes: Data? { pendingData }

    /// Attachment bytes, from the pending buffer or from disk. `nil` if the file is missing/unreadable.
    var data: Data? {
        if let pendingData { return pendingData }
        return AttachmentStore.shared.read(self)
    }

    /// Drop the in-memory copy once the bytes are safely on disk.
    mutating func clearPendingData() { pendingData = nil }

    /// File extension used for the on-disk file, derived from the filename, then the MIME type.
    var fileExtension: String {
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty { return ext.lowercased() }
        if let sub = mimeType.split(separator: "/").last, !sub.isEmpty {
            return String(sub).lowercased()
        }
        return "dat"
    }
}

// MARK: - Attachment File Store

enum AttachmentStoreError: Error {
    /// The file written to disk did not read back at the expected size.
    case verificationFailed(UUID)
}

/// Stores time-entry attachment bytes as files under
/// `Application Support/Attachments/<attachment-uuid>.<ext>`, keeping the
/// persisted JSON blob small. Photos never enter UserDefaults.
///
/// `shared` is a settable `static var` so tests can point it at an isolated
/// temporary directory and restore it afterward.
final class AttachmentStore {
    static var shared = AttachmentStore()

    private let directory: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "AttachmentStore")

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.directory = base.appendingPathComponent("Attachments", isDirectory: true)
        }
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func fileURL(for attachment: TimeAttachment) -> URL {
        directory.appendingPathComponent("\(attachment.id.uuidString).\(attachment.fileExtension)", isDirectory: false)
    }

    /// True if a non-empty file already exists for this attachment.
    func fileExists(for attachment: TimeAttachment) -> Bool {
        let url = fileURL(for: attachment)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return false }
        return size > 0
    }

    /// Write bytes atomically and verify the file reads back at the expected size.
    /// Throws (never silently succeeds) so callers can hold the inline copy until the file is proven.
    func write(_ data: Data, for attachment: TimeAttachment) throws {
        try ensureDirectory()
        let url = fileURL(for: attachment)
        try data.write(to: url, options: .atomic)
        let written = try Data(contentsOf: url)
        guard written.count == data.count else {
            throw AttachmentStoreError.verificationFailed(attachment.id)
        }
    }

    func read(_ attachment: TimeAttachment) -> Data? {
        let url = fileURL(for: attachment)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read attachment \(attachment.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func delete(_ attachment: TimeAttachment) {
        try? fileManager.removeItem(at: fileURL(for: attachment))
    }
}

// MARK: - Time Entry
struct TimeEntry: Identifiable, Codable {
    let id: UUID
    var propertyId: UUID
    var participant: Participant
    var category: ActivityCategory
    var hours: Double
    var date: Date
    var notes: String
    var attachments: [TimeAttachment]
    var createdAt: Date
    var modifiedAt: Date
    var importSource: String? // nil = manual, "calendar" = calendar import
    var importExternalId: String?
    var importCalendarId: String?
    // 2.0 auto-capture provenance. Additive and optional: 1.1 builds ignore these keys when
    // decoding, never write them, and CloudKit `.changedKeys` pushes from 1.1 leave them alone.
    /// When the app first noticed the activity (for calendar: max(firstSeen, eventEnd)).
    var detectedAt: Date?
    /// When the user confirmed the suggestion. Non-nil marks a confirm-first record.
    var confirmedAt: Date?
    /// Short machine detail about the source (e.g. "backfill"). Never an event title.
    var sourceDetail: String?
    /// The suggestion's dedupe key. The entry's `id` is derived from it (see `CaptureIdentity`).
    var sourceKey: String?

    init(
        id: UUID = UUID(),
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double,
        date: Date = Date(),
        notes: String = "",
        attachments: [TimeAttachment] = [],
        importSource: String? = nil,
        importExternalId: String? = nil,
        importCalendarId: String? = nil,
        detectedAt: Date? = nil,
        confirmedAt: Date? = nil,
        sourceDetail: String? = nil,
        sourceKey: String? = nil
    ) {
        self.id = id
        self.propertyId = propertyId
        self.participant = participant
        self.category = category
        self.hours = hours
        self.date = date
        self.notes = notes
        self.attachments = attachments
        self.importSource = importSource
        self.importExternalId = importExternalId
        self.importCalendarId = importCalendarId
        self.detectedAt = detectedAt
        self.confirmedAt = confirmedAt
        self.sourceDetail = sourceDetail
        self.sourceKey = sourceKey
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        participant = try c.decode(Participant.self, forKey: .participant)
        category = try c.decode(ActivityCategory.self, forKey: .category)
        hours = try c.decode(Double.self, forKey: .hours)
        date = try c.decode(Date.self, forKey: .date)
        notes = try c.decode(String.self, forKey: .notes)
        attachments = try c.decodeIfPresent([TimeAttachment].self, forKey: .attachments) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        importSource = try c.decodeIfPresent(String.self, forKey: .importSource)
        importExternalId = try c.decodeIfPresent(String.self, forKey: .importExternalId)
        importCalendarId = try c.decodeIfPresent(String.self, forKey: .importCalendarId)
        detectedAt = try c.decodeIfPresent(Date.self, forKey: .detectedAt)
        confirmedAt = try c.decodeIfPresent(Date.self, forKey: .confirmedAt)
        sourceDetail = try c.decodeIfPresent(String.self, forKey: .sourceDetail)
        sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey)
    }
    
    // Helper to get property name - call this when needed
    func getPropertyName(from properties: [RentalProperty]) -> String {
        properties.first { $0.id == propertyId }?.name ?? "Unknown"
    }
    
    var countsForREPS: Bool {
        category.countsForREPS
    }
    
    var formattedDuration: String {
        String(format: "%.1fh", hours)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - REPS Requirements
struct REPSRequirements {
    static let annualHourThreshold: Double = 750.0
    static let workingTimePercentage: Double = 0.50
    
    static var weeklyGoal: Double {
        annualHourThreshold / 52.0
    }
    
    static var monthlyGoal: Double {
        annualHourThreshold / 12.0
    }
}

// MARK: - Tax Qualification Engine
//
// Law baseline checked against IRS Publication 925 (2025):
// - Real estate professional status is measured for one spouse at a time.
// - Spouse hours can count for material participation in an activity.
// - Investor-level tasks do not count as participation for these thresholds.
struct TaxQualificationEngine {
    struct REPSResult: Equatable {
        let participant: Participant
        let realEstateHours: Double
        let nonRealEstateHours: Double
        let meets750HourTest: Bool
        let meetsMoreThanHalfPersonalServicesTest: Bool

        /// Both REPS tests met. Other work hours of 0 or less count as "not entered", so an
        /// empty field never reads as qualified (the same rule the audit export uses).
        var isQualified: Bool {
            meets750HourTest && moreThanHalfStatus == .met
        }

        /// 750 hours reached, but the 50% rule is not met or can't be checked yet.
        var hoursMetButRuleOpen: Bool {
            meets750HourTest && moreThanHalfStatus != .met
        }

        var realEstateWorkPercentage: Double {
            let total = realEstateHours + nonRealEstateHours
            guard total > 0 else { return 0 }
            return realEstateHours / total
        }

        /// The more-than-half test as the app shows it. Other work hours of 0 or less mean
        /// "not entered", the same rule the audit export uses, so the test is never shown as
        /// met just because the field is empty.
        var moreThanHalfStatus: MoreThanHalfStatus {
            guard nonRealEstateHours > 0 else { return .notEntered }
            return meetsMoreThanHalfPersonalServicesTest ? .met : .notMet
        }

    }

    enum MoreThanHalfStatus: Equatable {
        case met
        case notMet
        case notEntered

        static let notEnteredPrompt = "Add your other work hours to check this"
        /// The one short label for "other work hours not entered", used on Home and Reports.
        static let notEnteredValue = "Not checked"
    }

    struct MaterialParticipationResult: Equatable {
        let propertyId: UUID?
        let ownerAndSpouseHours: Double
        let meets500HourTest: Bool
        let meets100HourTest: Bool
        /// Per-tax-year answer to IRS Test 3's second prong: did no other individual
        /// (property manager, contractor, co-owner) participate more?
        /// nil = unanswered, true = no one did more, false = someone did more.
        let noOneParticipatedMore: Bool?

        var isMateriallyParticipating: Bool {
            meets500HourTest || meets100HourTest
        }

        /// Hours clear the 100-hour threshold, but the "did anyone participate more?"
        /// question is still unanswered — Test 3 can't be asserted until the user confirms.
        var meets100HourThresholdPendingConfirmation: Bool {
            ownerAndSpouseHours > 100 && noOneParticipatedMore == nil
        }
    }

    /// Reports and Home wording when 750 hours are met but the 50% rule is still open.
    /// nil when that isn't the situation.
    static func hoursMetRuleOpenStatus(_ result: REPSResult) -> (label: String, detail: String)? {
        guard result.hoursMetButRuleOpen else { return nil }
        switch result.moreThanHalfStatus {
        case .notEntered: return ("Hours target met", "Add your other work hours to check the 50% rule")
        case .notMet: return ("Hours target met", "50% rule not met yet")
        case .met: return nil
        }
    }

    static func qualifyingRealEstateHours(
        entries: [TimeEntry],
        participant: Participant,
        year: Int
    ) -> Double {
        entriesForYear(entries, year: year)
            .filter { $0.participant == participant && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }

    static func repsStatus(
        entries: [TimeEntry],
        participant: Participant,
        year: Int,
        nonRealEstateHours: Double
    ) -> REPSResult {
        let hours = qualifyingRealEstateHours(entries: entries, participant: participant, year: year)
        return REPSResult(
            participant: participant,
            realEstateHours: hours,
            nonRealEstateHours: nonRealEstateHours,
            meets750HourTest: hours > REPSRequirements.annualHourThreshold,
            meetsMoreThanHalfPersonalServicesTest: hours > nonRealEstateHours
        )
    }

    static func materialParticipationStatus(
        entries: [TimeEntry],
        year: Int,
        propertyId: UUID?,
        groupingElection: Bool,
        noOneParticipatedMore: Bool? = nil
    ) -> MaterialParticipationResult {
        let scoped = entriesForYear(entries, year: year)
            .filter { $0.countsForREPS }
            .filter { entry in
                if groupingElection { return true }
                guard let propertyId else { return false }
                return entry.propertyId == propertyId
            }
        let hours = scoped.reduce(0) { $0 + $1.hours }

        // IRS Test 3 requires >100 hours AND that no other individual participated more.
        // An unanswered confirmation (nil) is treated as not-yet-met, not as a pass.
        return MaterialParticipationResult(
            propertyId: groupingElection ? nil : propertyId,
            ownerAndSpouseHours: hours,
            meets500HourTest: hours > 500,
            meets100HourTest: hours > 100 && noOneParticipatedMore == true,
            noOneParticipatedMore: noOneParticipatedMore
        )
    }

    /// Single source of truth for the material participation figure shown on
    /// Dashboard, Reports, widget and Siri. With a grouping election all properties
    /// count as one activity; without it, the best single property counts.
    static func materialParticipationOverview(
        entries: [TimeEntry],
        properties: [RentalProperty],
        year: Int,
        groupingElection: Bool,
        noOneParticipatedMore: Bool? = nil
    ) -> MaterialParticipationResult {
        func status(_ id: UUID?) -> MaterialParticipationResult {
            materialParticipationStatus(
                entries: entries,
                year: year,
                propertyId: id,
                groupingElection: groupingElection,
                noOneParticipatedMore: noOneParticipatedMore
            )
        }
        if groupingElection { return status(nil) }
        return properties
            .map { status($0.id) }
            .max { $0.ownerAndSpouseHours < $1.ownerAndSpouseHours }
            ?? status(nil)
    }

    private static func entriesForYear(_ entries: [TimeEntry], year: Int) -> [TimeEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.component(.year, from: $0.date) == year }
    }
}

// MARK: - Date Extensions
extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var startOfWeek: Date? {
        Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self))
    }
    
    var startOfMonth: Date? {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isThisWeek: Bool {
        guard let weekStart = startOfWeek else { return false }
        return self >= weekStart
    }
    
    var isThisMonth: Bool {
        guard let monthStart = startOfMonth else { return false }
        return self >= monthStart
    }
    
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
}
