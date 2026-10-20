import Foundation

// MARK: - Audit Report Model

struct AuditReport {
    struct Summary: Equatable {
        let totalHours: Double
        let repsCountableHours: Double
        let nonCountableHours: Double
        let entryCount: Int
        let propertyCount: Int
        let attachmentCount: Int
        let firstEntryDate: Date?
        let lastEntryDate: Date?
    }

    struct PropertyTotal: Equatable {
        let propertyId: UUID
        let name: String
        let address: String
        let propertyType: String
        let entryCount: Int
        let selfHours: Double
        let spouseHours: Double
        let totalHours: Double
        let repsCountableHours: Double
    }

    struct CategoryTotal: Equatable {
        let category: ActivityCategory
        let countsForREPS: Bool
        let entryCount: Int
        let hours: Double
    }

    struct ParticipantTotal: Equatable {
        let participant: Participant
        let entryCount: Int
        let totalHours: Double
        let repsCountableHours: Double
    }

    struct ParticipantQualification: Equatable {
        let participant: Participant
        let realEstateHours: Double
        /// nil = the user has not entered non-real-estate work hours for this person.
        let nonRealEstateHours: Double?
        let meets750HourTest: Bool
        /// nil = cannot be evaluated without non-real-estate work hours.
        let meetsMoreThanHalfTest: Bool?

        /// nil = 750-hour test met but the 50% test could not be evaluated.
        var isQualified: Bool? {
            if !meets750HourTest { return false }
            return meetsMoreThanHalfTest
        }

        var displayName: String {
            participant == .selfParticipant ? "You" : "Spouse"
        }

        /// Plain text for the more-than-half column.
        var moreThanHalfText: String {
            if let met = meetsMoreThanHalfTest { return met ? "Met" : "Not met" }
            return participant == .spouse
                ? "Not evaluated — spouse work hours aren't tracked in the app yet"
                : "Not evaluated — add your other work hours"
        }

        /// One calm, factual line for the cover page.
        var coverLine: String {
            let hours = AuditReportFormat.hours(realEstateHours)
            guard meets750HourTest else {
                return "\(displayName): \(hours) hours. The 750-hour test needs more than 750 hours."
            }
            switch meetsMoreThanHalfTest {
            case .some(true): return "\(displayName): \(hours) hours. Meets the 750-hour and more-than-half tests."
            case .some(false): return "\(displayName): \(hours) hours. Meets the 750-hour test; does not meet the more-than-half test."
            case .none: return "\(displayName): \(hours) hours. Meets the 750-hour test; more-than-half test not evaluated."
            }
        }

        var statusText: String {
            switch isQualified {
            case .some(true): return "Meets both REPS hour tests"
            case .some(false):
                return meets750HourTest ? "Does not meet the more-than-half test" : "Does not meet the 750-hour test"
            case .none: return "750-hour test met; more-than-half test not evaluated"
            }
        }
    }

    struct MaterialParticipationLine: Equatable {
        let label: String
        let ownerAndSpouseHours: Double
        let meets500HourTest: Bool
        let meets100HourTest: Bool
        let pendingConfirmation: Bool

        var statusText: String {
            if meets500HourTest { return "Meets 500-hour test" }
            if meets100HourTest { return "Meets 100-hour test" }
            if pendingConfirmation { return "Over 100 hours; confirm no one participated more" }
            return "Below material participation thresholds"
        }
    }

    struct EntryRow {
        let number: Int
        let entryId: UUID
        let date: Date
        let propertyName: String
        let category: ActivityCategory
        let participant: Participant
        let hours: Double
        let description: String
        let loggedAt: Date
        /// nil when the entry was never edited after it was logged.
        let lastEditedAt: Date?
        let source: EntrySource
        /// When the app first proposed the entry. nil for manual, timer, voice and pre-2.0 rows.
        let detectedAt: Date?
        /// When the user confirmed a suggestion. nil for entries that were never suggestions.
        let confirmedAt: Date?
        /// Free-text detail the source recorded (for example a calendar event title).
        let sourceDetail: String?
        /// Whole days between detection and confirmation, only when more than 7. Otherwise nil.
        let confirmedDaysLater: Int?
        let attachmentRefs: [String]
        let attachmentFilenames: [String]

        var reference: String { "E\(number)" }

        /// Plain source label: "Calendar suggestion" for a confirmed calendar suggestion.
        var sourceLabel: String { AuditReportFormat.sourceLabel(source: source, confirmedAt: confirmedAt) }

        /// "confirmed N days later", shown only when the gap is more than 7 days.
        var confirmationLagText: String? {
            confirmedDaysLater.map { "confirmed \($0) days later" }
        }
    }

    struct SourceTotal: Equatable {
        let label: String
        let entryCount: Int
    }

    struct AttachmentRef {
        let number: Int
        let entryNumber: Int
        let entryDate: Date
        let attachment: TimeAttachment

        var reference: String { "A\(number)" }
        var entryReference: String { "E\(entryNumber)" }
    }

    let taxYear: Int
    let generatedAt: Date
    let timeZone: TimeZone
    let summary: Summary
    let qualifications: [ParticipantQualification]
    let materialParticipation: [MaterialParticipationLine]
    let groupingElection: Bool
    let propertyTotals: [PropertyTotal]
    let categoryTotals: [CategoryTotal]
    let participantTotals: [ParticipantTotal]
    let entries: [EntryRow]
    /// Entry counts per source, in a fixed order, only sources that appear.
    let sourceTotals: [SourceTotal]
    let attachments: [AttachmentRef]

    var isEmpty: Bool { entries.isEmpty }
}

// MARK: - Builder

/// Pure data assembly for the audit-ready export. No UI, no singletons: everything the
/// report needs comes in through `Input`, so it is fully unit-testable.
enum AuditReportBuilder {
    struct Input {
        var entries: [TimeEntry]
        var properties: [RentalProperty]
        var taxYear: Int
        /// People to report on. Anyone with entries in the year is added automatically.
        var participants: [Participant] = [.selfParticipant]
        /// Non-real-estate work hours per person, as entered in the Tax Profile.
        /// A missing person means "not entered": the more-than-half test is not evaluated.
        var nonRealEstateHours: [Participant: Double] = [:]
        var groupingElection: Bool = false
        var noOneParticipatedMore: Bool? = nil
        var generatedAt: Date = Date()
        var calendar: Calendar = .current
    }

    /// Builds the export input from the user's Tax Profile settings — the exact path the
    /// export screen uses. Non-real-estate work hours of 0 or less mean "not entered", so the
    /// more-than-half test is reported as not evaluated instead of silently passing.
    /// Spouse work hours are not tracked in the app, so the spouse's test is never evaluated.
    static func inputFromTaxProfile(
        entries: [TimeEntry],
        properties: [RentalProperty],
        taxYear: Int,
        spouseTracking: Bool,
        nonREWorkHours: Double,
        groupingElection: Bool,
        noOneParticipatedMore: Bool?,
        generatedAt: Date = Date()
    ) -> Input {
        var participants: [Participant] = [.selfParticipant]
        if spouseTracking { participants.append(.spouse) }
        var nonRE: [Participant: Double] = [:]
        if nonREWorkHours > 0 { nonRE[.selfParticipant] = nonREWorkHours }
        return Input(
            entries: entries,
            properties: properties,
            taxYear: taxYear,
            participants: participants,
            nonRealEstateHours: nonRE,
            groupingElection: groupingElection,
            noOneParticipatedMore: noOneParticipatedMore,
            generatedAt: generatedAt
        )
    }

    /// Edits less than this long after logging are treated as part of creation.
    static let editThreshold: TimeInterval = 60

    static func build(_ input: Input) -> AuditReport {
        let calendar = input.calendar
        let yearEntries = input.entries
            .filter { calendar.component(.year, from: $0.date) == input.taxYear }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let propertiesById = Dictionary(input.properties.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func propertyName(_ id: UUID) -> String { propertiesById[id]?.name ?? "Unknown property" }

        // Entries + attachment appendix (numbered in chronological order).
        var rows: [AuditReport.EntryRow] = []
        var attachmentRefs: [AuditReport.AttachmentRef] = []
        for (index, entry) in yearEntries.enumerated() {
            let number = index + 1
            var refs: [String] = []
            for attachment in entry.attachments {
                let ref = AuditReport.AttachmentRef(
                    number: attachmentRefs.count + 1,
                    entryNumber: number,
                    entryDate: entry.date,
                    attachment: attachment
                )
                attachmentRefs.append(ref)
                refs.append(ref.reference)
            }
            let edited = entry.modifiedAt.timeIntervalSince(entry.createdAt) >= editThreshold
            rows.append(AuditReport.EntryRow(
                number: number,
                entryId: entry.id,
                date: entry.date,
                propertyName: propertyName(entry.propertyId),
                category: entry.category,
                participant: entry.participant,
                hours: entry.hours,
                description: entry.recordDescription ?? entry.notes,
                loggedAt: entry.createdAt,
                lastEditedAt: edited ? entry.modifiedAt : nil,
                source: entry.source,
                detectedAt: entry.detectedAt,
                confirmedAt: entry.confirmedAt,
                sourceDetail: entry.sourceDetail,
                confirmedDaysLater: confirmedDaysLater(entry, calendar: calendar),
                attachmentRefs: refs,
                attachmentFilenames: entry.attachments.map(\.filename)
            ))
        }

        // Counts per source label, in a stable order.
        let sourceCounts = Dictionary(grouping: rows, by: \.sourceLabel).mapValues(\.count)
        let sourceTotals = AuditReportFormat.sourceLabelOrder.compactMap { label in
            sourceCounts[label].map { AuditReport.SourceTotal(label: label, entryCount: $0) }
        }

        // Per-property totals: only properties with entries this year, in first-seen-by-name order.
        let byProperty = Dictionary(grouping: yearEntries, by: \.propertyId)
        let propertyTotals = byProperty.map { propertyId, entries -> AuditReport.PropertyTotal in
            let property = propertiesById[propertyId]
            return AuditReport.PropertyTotal(
                propertyId: propertyId,
                name: property?.name ?? "Unknown property",
                address: property?.address ?? "",
                propertyType: property?.propertyType.fullName ?? "",
                entryCount: entries.count,
                selfHours: sum(entries.filter { $0.participant == .selfParticipant }),
                spouseHours: sum(entries.filter { $0.participant == .spouse }),
                totalHours: sum(entries),
                repsCountableHours: sum(entries.filter(\.countsForREPS))
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalHours != rhs.totalHours { return lhs.totalHours > rhs.totalHours }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        // Per-category totals, in the app's category order, only categories used.
        let categoryTotals = ActivityCategory.allCases.compactMap { category -> AuditReport.CategoryTotal? in
            let entries = yearEntries.filter { $0.category == category }
            guard !entries.isEmpty else { return nil }
            return AuditReport.CategoryTotal(
                category: category,
                countsForREPS: category.countsForREPS,
                entryCount: entries.count,
                hours: sum(entries)
            )
        }

        // Participants: requested ones plus anyone who logged time, in a stable order.
        let requested = Set(input.participants).union(yearEntries.map(\.participant))
        let participants = Participant.allCases.filter { requested.contains($0) }

        let participantTotals = participants.map { participant -> AuditReport.ParticipantTotal in
            let entries = yearEntries.filter { $0.participant == participant }
            return AuditReport.ParticipantTotal(
                participant: participant,
                entryCount: entries.count,
                totalHours: sum(entries),
                repsCountableHours: sum(entries.filter(\.countsForREPS))
            )
        }

        let qualifications = participants.map { participant -> AuditReport.ParticipantQualification in
            let nonRE = input.nonRealEstateHours[participant]
            let result = TaxQualificationEngine.repsStatus(
                entries: yearEntries,
                participant: participant,
                year: input.taxYear,
                nonRealEstateHours: nonRE ?? 0
            )
            return AuditReport.ParticipantQualification(
                participant: participant,
                realEstateHours: result.realEstateHours,
                nonRealEstateHours: nonRE,
                meets750HourTest: result.meets750HourTest,
                meetsMoreThanHalfTest: nonRE == nil ? nil : result.meetsMoreThanHalfPersonalServicesTest
            )
        }

        // Material participation: one line for the grouped activity, or one per active property.
        var mpLines: [AuditReport.MaterialParticipationLine] = []
        if !yearEntries.isEmpty {
            if input.groupingElection {
                let result = TaxQualificationEngine.materialParticipationStatus(
                    entries: yearEntries, year: input.taxYear, propertyId: nil,
                    groupingElection: true, noOneParticipatedMore: input.noOneParticipatedMore
                )
                mpLines.append(mpLine(label: "All properties (grouping election)", result))
            } else {
                for total in propertyTotals {
                    let result = TaxQualificationEngine.materialParticipationStatus(
                        entries: yearEntries, year: input.taxYear, propertyId: total.propertyId,
                        groupingElection: false, noOneParticipatedMore: input.noOneParticipatedMore
                    )
                    mpLines.append(mpLine(label: total.name, result))
                }
            }
        }

        let summary = AuditReport.Summary(
            totalHours: sum(yearEntries),
            repsCountableHours: sum(yearEntries.filter(\.countsForREPS)),
            nonCountableHours: sum(yearEntries.filter { !$0.countsForREPS }),
            entryCount: yearEntries.count,
            propertyCount: propertyTotals.count,
            attachmentCount: attachmentRefs.count,
            firstEntryDate: yearEntries.first?.date,
            lastEntryDate: yearEntries.last?.date
        )

        return AuditReport(
            taxYear: input.taxYear,
            generatedAt: input.generatedAt,
            timeZone: calendar.timeZone,
            summary: summary,
            qualifications: qualifications,
            materialParticipation: mpLines,
            groupingElection: input.groupingElection,
            propertyTotals: propertyTotals,
            categoryTotals: categoryTotals,
            participantTotals: participantTotals,
            entries: rows,
            sourceTotals: sourceTotals,
            attachments: attachmentRefs
        )
    }

    /// Days from detection to confirmation (calendar days in the report's zone) when more than 7.
    static let lagThresholdDays = 7

    private static func confirmedDaysLater(_ entry: TimeEntry, calendar: Calendar) -> Int? {
        guard let detected = entry.detectedAt, let confirmed = entry.confirmedAt else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: detected), to: calendar.startOfDay(for: confirmed)).day ?? 0
        return days > lagThresholdDays ? days : nil
    }

    private static func sum(_ entries: [TimeEntry]) -> Double {
        entries.reduce(0) { $0 + $1.hours }
    }

    private static func mpLine(
        label: String,
        _ result: TaxQualificationEngine.MaterialParticipationResult
    ) -> AuditReport.MaterialParticipationLine {
        AuditReport.MaterialParticipationLine(
            label: label,
            ownerAndSpouseHours: result.ownerAndSpouseHours,
            meets500HourTest: result.meets500HourTest,
            meets100HourTest: result.meets100HourTest,
            pendingConfirmation: result.meets100HourThresholdPendingConfirmation
        )
    }
}

// MARK: - Shared formatting

enum AuditReportFormat {
    static let disclaimer = "LandlordHours is a record-keeping tool, not tax advice. Review your qualification with a tax professional."

    static let suggestionExplanation = "Suggested entries were proposed by the app (for example, from your calendar or a receipt) and added to your record only when you confirmed them."

    static let calendarSuggestionLabel = "Calendar suggestion"

    /// Labels in report order. Sources added after 2.0 ship use their own display name.
    static let sourceLabelOrder: [String] = [
        "Manual", "Timer", "Voice", "Calendar import", calendarSuggestionLabel,
        "Receipt", "Location", "Shortcut", "Gmail", "Other",
    ]

    static func sourceLabel(source: EntrySource, confirmedAt: Date?) -> String {
        if source == .calendar, confirmedAt != nil { return calendarSuggestionLabel }
        return source.displayName
    }

    static func hours(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func dateFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
