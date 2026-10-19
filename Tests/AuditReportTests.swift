import XCTest
import PDFKit
import UIKit
@testable import LandlordHours

// MARK: - Fixtures

private enum AuditFixture {
    static let calendar = Calendar.current

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func entry(
        property: RentalProperty,
        participant: Participant = .selfParticipant,
        category: ActivityCategory = .repairs,
        hours: Double,
        date: Date,
        notes: String = "",
        attachments: [TimeAttachment] = [],
        source: EntrySource = .manual,
        loggedAt: Date? = nil,
        editedAt: Date? = nil,
        detectedAt: Date? = nil,
        confirmedAt: Date? = nil,
        sourceDetail: String? = nil,
        rawImportSource: String? = nil
    ) -> TimeEntry {
        var entry = TimeEntry(
            propertyId: property.id,
            participant: participant,
            category: category,
            hours: hours,
            date: date,
            notes: notes,
            attachments: attachments,
            importSource: rawImportSource ?? source.storedValue,
            detectedAt: detectedAt,
            confirmedAt: confirmedAt,
            sourceDetail: sourceDetail
        )
        let logged = loggedAt ?? date.addingTimeInterval(3600)
        entry.createdAt = logged
        entry.modifiedAt = editedAt ?? logged
        return entry
    }

    static let oak = RentalProperty(name: "Oak Street Duplex", address: "123 Oak St, Portland, OR", propertyType: .ltr)
    static let pine = RentalProperty(name: "Pine Cabin", address: "9 Pine Rd, Bend, OR", propertyType: .str)
    static let idle = RentalProperty(name: "Idle Condo", address: "1 Idle Way", propertyType: .ltr)
}

// MARK: - Builder

final class AuditReportBuilderTests: XCTestCase {
    private typealias F = AuditFixture

    private func build(_ entries: [TimeEntry], participants: [Participant] = [.selfParticipant, .spouse], nonRE: [Participant: Double] = [.selfParticipant: 100], grouping: Bool = false) -> AuditReport {
        AuditReportBuilder.build(AuditReportBuilder.Input(
            entries: entries,
            properties: [F.oak, F.pine, F.idle],
            taxYear: 2026,
            participants: participants,
            nonRealEstateHours: nonRE,
            groupingElection: grouping,
            noOneParticipatedMore: nil,
            generatedAt: F.date(2026, 10, 17, 12)
        ))
    }

    func testTotalsAcrossPropertiesCategoriesAndSpouses() {
        let entries = [
            F.entry(property: F.oak, participant: .selfParticipant, category: .repairs, hours: 3, date: F.date(2026, 1, 5)),
            F.entry(property: F.oak, participant: .spouse, category: .management, hours: 2, date: F.date(2026, 2, 5)),
            F.entry(property: F.pine, participant: .selfParticipant, category: .investing, hours: 1.5, date: F.date(2026, 3, 5)),
            F.entry(property: F.pine, participant: .spouse, category: .repairs, hours: 4.25, date: F.date(2026, 4, 5)),
        ]
        let report = build(entries)

        XCTAssertEqual(report.summary.totalHours, 10.75, accuracy: 0.0001)
        XCTAssertEqual(report.summary.repsCountableHours, 9.25, accuracy: 0.0001)
        XCTAssertEqual(report.summary.nonCountableHours, 1.5, accuracy: 0.0001)
        XCTAssertEqual(report.summary.entryCount, 4)

        let oak = report.propertyTotals.first { $0.propertyId == F.oak.id }!
        XCTAssertEqual(oak.selfHours, 3)
        XCTAssertEqual(oak.spouseHours, 2)
        XCTAssertEqual(oak.totalHours, 5)
        let pine = report.propertyTotals.first { $0.propertyId == F.pine.id }!
        XCTAssertEqual(pine.selfHours, 1.5)
        XCTAssertEqual(pine.spouseHours, 4.25)
        XCTAssertEqual(pine.repsCountableHours, 4.25)

        let repairs = report.categoryTotals.first { $0.category == .repairs }!
        XCTAssertEqual(repairs.hours, 7.25, accuracy: 0.0001)
        XCTAssertEqual(repairs.entryCount, 2)
        XCTAssertFalse(report.categoryTotals.first { $0.category == .investing }!.countsForREPS)
        XCTAssertNil(report.categoryTotals.first { $0.category == .legal }, "unused categories are omitted")

        let selfTotal = report.participantTotals.first { $0.participant == .selfParticipant }!
        let spouseTotal = report.participantTotals.first { $0.participant == .spouse }!
        XCTAssertEqual(selfTotal.totalHours, 4.5)
        XCTAssertEqual(selfTotal.repsCountableHours, 3)
        XCTAssertEqual(spouseTotal.totalHours, 6.25)
        XCTAssertEqual(spouseTotal.repsCountableHours, 6.25)
    }

    func testEntriesOutsideTaxYearAreExcluded() {
        let entries = [
            F.entry(property: F.oak, hours: 2, date: F.date(2026, 6, 1)),
            F.entry(property: F.oak, hours: 50, date: F.date(2025, 12, 31, 23, 30)),
            F.entry(property: F.pine, hours: 70, date: F.date(2027, 1, 1, 0, 30)),
        ]
        let report = build(entries)
        XCTAssertEqual(report.summary.entryCount, 1)
        XCTAssertEqual(report.summary.totalHours, 2)
        XCTAssertEqual(report.propertyTotals.map(\.propertyId), [F.oak.id])
    }

    func testPropertiesWithZeroHoursInYearAreExcluded() {
        let entries = [
            F.entry(property: F.oak, hours: 2, date: F.date(2026, 6, 1)),
            F.entry(property: F.idle, hours: 5, date: F.date(2025, 6, 1)),
        ]
        let report = build(entries)
        XCTAssertEqual(report.propertyTotals.count, 1)
        XCTAssertFalse(report.propertyTotals.contains { $0.propertyId == F.idle.id })
        XCTAssertFalse(report.propertyTotals.contains { $0.propertyId == F.pine.id })
        XCTAssertEqual(report.summary.propertyCount, 1)
    }

    func testEntriesAreChronologicalAndNumbered() {
        let entries = [
            F.entry(property: F.oak, hours: 1, date: F.date(2026, 5, 1)),
            F.entry(property: F.oak, hours: 1, date: F.date(2026, 1, 1)),
            F.entry(property: F.pine, hours: 1, date: F.date(2026, 3, 1)),
        ]
        let report = build(entries)
        XCTAssertEqual(report.entries.map(\.date), [F.date(2026, 1, 1), F.date(2026, 3, 1), F.date(2026, 5, 1)])
        XCTAssertEqual(report.entries.map(\.reference), ["E1", "E2", "E3"])
        XCTAssertEqual(report.summary.firstEntryDate, F.date(2026, 1, 1))
        XCTAssertEqual(report.summary.lastEntryDate, F.date(2026, 5, 1))
    }

    func testLastEditedOnlyWhenEntryChangedAfterLogging() {
        let logged = F.date(2026, 2, 1, 18)
        let untouched = F.entry(property: F.oak, hours: 1, date: F.date(2026, 2, 1), loggedAt: logged, editedAt: logged.addingTimeInterval(0.002))
        let edited = F.entry(property: F.oak, hours: 1, date: F.date(2026, 2, 2), loggedAt: logged, editedAt: F.date(2026, 3, 1, 8))
        let report = build([untouched, edited])
        XCTAssertNil(report.entries[0].lastEditedAt)
        XCTAssertEqual(report.entries[1].lastEditedAt, F.date(2026, 3, 1, 8))
        XCTAssertEqual(report.entries[0].loggedAt, logged)
    }

    func testProvenanceLabelsForEverySourceType() {
        let day = F.date(2026, 5, 4)
        func row(_ raw: String?, confirmed: Date? = nil) -> AuditReport.EntryRow {
            build([F.entry(property: F.oak, hours: 1, date: day, confirmedAt: confirmed, rawImportSource: raw)]).entries[0]
        }
        XCTAssertEqual(row(nil).sourceLabel, "Manual")
        XCTAssertEqual(row("timer").sourceLabel, "Timer")
        XCTAssertEqual(row("voice").sourceLabel, "Voice")
        XCTAssertEqual(row("calendar").sourceLabel, "Calendar import")
        XCTAssertEqual(row("calendar", confirmed: day).sourceLabel, "Calendar suggestion")
        XCTAssertEqual(row("receipt").sourceLabel, "Receipt")
        XCTAssertEqual(row("from-the-future").sourceLabel, "Other")
        XCTAssertEqual(row("manual").sourceLabel, "Other", "a literal manual value is unknown data")
    }

    func testLegacyRowsCarryNoDetectedOrConfirmedDates() {
        let legacy = build([F.entry(property: F.oak, hours: 1, date: F.date(2026, 5, 4), source: .calendar)]).entries[0]
        XCTAssertNil(legacy.detectedAt)
        XCTAssertNil(legacy.confirmedAt)
        XCTAssertNil(legacy.confirmedDaysLater)
        XCTAssertNil(legacy.confirmationLagText)
        XCTAssertEqual(legacy.sourceLabel, "Calendar import")
    }

    func testConfirmationLagOnlyBeyondSevenDays() {
        func lag(_ days: Int) -> AuditReport.EntryRow {
            let detected = F.date(2026, 5, 1, 23, 30)
            let confirmed = F.calendar.date(byAdding: .day, value: days, to: detected)!
            return build([F.entry(property: F.oak, hours: 1, date: F.date(2026, 5, 1), source: .calendar, detectedAt: detected, confirmedAt: confirmed)]).entries[0]
        }
        XCTAssertNil(lag(0).confirmedDaysLater, "same-day confirmation shows no lag")
        XCTAssertNil(lag(7).confirmedDaysLater, "exactly 7 days is not beyond 7")
        XCTAssertEqual(lag(8).confirmedDaysLater, 8)
        XCTAssertEqual(lag(8).confirmationLagText, "confirmed 8 days later")
        XCTAssertEqual(lag(120).confirmationLagText, "confirmed 120 days later")
        // Unconfirmed suggestion: no lag.
        let pending = build([F.entry(property: F.oak, hours: 1, date: F.date(2026, 5, 1), source: .calendar, detectedAt: F.date(2026, 5, 1))]).entries[0]
        XCTAssertNil(pending.confirmedDaysLater)
    }

    func testSourceTotalsCountEachSourceOnceInFixedOrder() {
        let day = F.date(2026, 5, 4)
        let report = build([
            F.entry(property: F.oak, hours: 1, date: day, source: .voice),
            F.entry(property: F.oak, hours: 1, date: day),
            F.entry(property: F.oak, hours: 1, date: day, source: .calendar, detectedAt: day, confirmedAt: day),
            F.entry(property: F.oak, hours: 1, date: day, source: .calendar, detectedAt: day, confirmedAt: day),
            F.entry(property: F.oak, hours: 1, date: day, source: .calendar),
            F.entry(property: F.oak, hours: 1, date: day, rawImportSource: "zzz"),
        ])
        XCTAssertEqual(report.sourceTotals, [
            .init(label: "Manual", entryCount: 1), .init(label: "Voice", entryCount: 1),
            .init(label: "Calendar import", entryCount: 1), .init(label: "Calendar suggestion", entryCount: 2),
            .init(label: "Other", entryCount: 1),
        ])
        XCTAssertEqual(report.sourceTotals.map(\.entryCount).reduce(0, +), report.summary.entryCount)
    }

    func testSourceMapping() {
        XCTAssertEqual(EntrySource(importSource: nil), .manual)
        XCTAssertEqual(EntrySource(importSource: "calendar"), .calendar)
        XCTAssertEqual(EntrySource(importSource: "timer"), .timer)
        XCTAssertEqual(EntrySource(importSource: "voice"), .voice)
        XCTAssertNil(EntrySource.manual.storedValue)

        let timerEntry = F.entry(property: F.oak, hours: 1, date: F.date(2026, 1, 1), source: .timer)
        XCTAssertFalse(timerEntry.isCalendarImport, "timer entries must not show as calendar imports")
        XCTAssertTrue(F.entry(property: F.oak, hours: 1, date: F.date(2026, 1, 1), source: .calendar).isCalendarImport)
    }

    func testPerParticipantQualification() {
        // Self: 800 RE hours, 100 non-RE hours entered -> qualifies.
        // Spouse: 200 RE hours, non-RE not entered -> fails 750, 50% test not evaluated.
        let entries = [
            F.entry(property: F.oak, participant: .selfParticipant, hours: 800, date: F.date(2026, 3, 1)),
            F.entry(property: F.oak, participant: .selfParticipant, category: .financing, hours: 40, date: F.date(2026, 3, 2)),
            F.entry(property: F.pine, participant: .spouse, hours: 200, date: F.date(2026, 3, 3)),
        ]
        let report = build(entries)
        let me = report.qualifications.first { $0.participant == .selfParticipant }!
        XCTAssertEqual(me.realEstateHours, 800, "investor-level hours are excluded")
        XCTAssertTrue(me.meets750HourTest)
        XCTAssertEqual(me.meetsMoreThanHalfTest, true)
        XCTAssertEqual(me.isQualified, true)

        let spouse = report.qualifications.first { $0.participant == .spouse }!
        XCTAssertEqual(spouse.realEstateHours, 200)
        XCTAssertFalse(spouse.meets750HourTest)
        XCTAssertNil(spouse.nonRealEstateHours)
        XCTAssertNil(spouse.meetsMoreThanHalfTest)
        XCTAssertEqual(spouse.isQualified, false)
    }

    func testQualificationPendingWhenNonREHoursMissing() {
        let entries = [F.entry(property: F.oak, hours: 760, date: F.date(2026, 3, 1))]
        let report = build(entries, nonRE: [:])
        let me = report.qualifications.first { $0.participant == .selfParticipant }!
        XCTAssertTrue(me.meets750HourTest)
        XCTAssertNil(me.isQualified)
    }

    func testTaxProfileInputTreatsZeroOtherWorkHoursAsNotEntered() {
        // Real export path: Tax Profile defaults nonREWorkHours to 0.
        let entries = [F.entry(property: F.oak, hours: 800, date: F.date(2026, 3, 1))]
        let input = AuditReportBuilder.inputFromTaxProfile(
            entries: entries, properties: [F.oak], taxYear: 2026,
            spouseTracking: true, nonREWorkHours: 0,
            groupingElection: false, noOneParticipatedMore: nil
        )
        let report = AuditReportBuilder.build(input)
        let me = report.qualifications.first { $0.participant == .selfParticipant }!
        XCTAssertNil(me.meetsMoreThanHalfTest, "0 other work hours must not pass the more-than-half test")
        XCTAssertNil(me.isQualified)
        XCTAssertEqual(me.moreThanHalfText, "Not evaluated — add your other work hours")
        let spouse = report.qualifications.first { $0.participant == .spouse }!
        XCTAssertTrue(spouse.moreThanHalfText.contains("spouse work hours aren't tracked"))

        let entered = AuditReportBuilder.build(AuditReportBuilder.inputFromTaxProfile(
            entries: entries, properties: [F.oak], taxYear: 2026,
            spouseTracking: false, nonREWorkHours: 300,
            groupingElection: false, noOneParticipatedMore: nil
        ))
        XCTAssertEqual(entered.qualifications.map(\.participant), [.selfParticipant])
        XCTAssertEqual(entered.qualifications[0].meetsMoreThanHalfTest, true)
        XCTAssertEqual(entered.qualifications[0].nonRealEstateHours, 300)
    }

    func testCoverLinesAreFactual() {
        let entries = [
            F.entry(property: F.oak, participant: .selfParticipant, hours: 412, date: F.date(2026, 3, 1)),
            F.entry(property: F.oak, participant: .spouse, hours: 760, date: F.date(2026, 3, 2)),
        ]
        let report = build(entries, nonRE: [.selfParticipant: 100])
        let lines = report.qualifications.map(\.coverLine)
        XCTAssertEqual(lines[0], "You: 412.00 hours. The 750-hour test needs more than 750 hours.")
        XCTAssertEqual(lines[1], "Spouse: 760.00 hours. Meets the 750-hour test; more-than-half test not evaluated.")
        for line in lines {
            XCTAssertFalse(line.lowercased().contains("qualifies"))
            XCTAssertFalse(line.lowercased().contains("guarantee"))
        }
    }

    func testCoverLineAtExactly750Hours() {
        let report = build([F.entry(property: F.oak, hours: 750, date: F.date(2026, 3, 1))], participants: [.selfParticipant])
        let me = report.qualifications[0]
        XCTAssertFalse(me.meets750HourTest, "IRS test is more than 750 hours")
        XCTAssertEqual(me.coverLine, "You: 750.00 hours. The 750-hour test needs more than 750 hours.")
    }

    func testSpouseIncludedWhenTheyLoggedTimeEvenIfNotRequested() {
        let entries = [F.entry(property: F.oak, participant: .spouse, hours: 2, date: F.date(2026, 3, 1))]
        let report = build(entries, participants: [.selfParticipant])
        XCTAssertEqual(report.participantTotals.map(\.participant), [.selfParticipant, .spouse])
    }

    func testMaterialParticipationPerPropertyAndGrouped() {
        let entries = [
            F.entry(property: F.oak, participant: .selfParticipant, hours: 300, date: F.date(2026, 3, 1)),
            F.entry(property: F.oak, participant: .spouse, hours: 250, date: F.date(2026, 3, 2)),
            F.entry(property: F.pine, hours: 120, date: F.date(2026, 3, 3)),
        ]
        let perProperty = build(entries)
        XCTAssertEqual(perProperty.materialParticipation.count, 2)
        let oak = perProperty.materialParticipation.first { $0.label == F.oak.name }!
        XCTAssertEqual(oak.ownerAndSpouseHours, 550)
        XCTAssertTrue(oak.meets500HourTest)
        let pine = perProperty.materialParticipation.first { $0.label == F.pine.name }!
        XCTAssertFalse(pine.meets100HourTest, "100-hour test needs confirmation")
        XCTAssertTrue(pine.pendingConfirmation)

        let grouped = build(entries, grouping: true)
        XCTAssertEqual(grouped.materialParticipation.count, 1)
        XCTAssertEqual(grouped.materialParticipation[0].ownerAndSpouseHours, 670)
    }

    func testAttachmentsAreReferencedByEntry() {
        let photo = TimeAttachment(filename: "receipt.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")
        let entries = [
            F.entry(property: F.oak, hours: 1, date: F.date(2026, 1, 1)),
            F.entry(property: F.oak, hours: 1, date: F.date(2026, 2, 1), attachments: [photo]),
        ]
        let report = build(entries)
        XCTAssertEqual(report.attachments.count, 1)
        XCTAssertEqual(report.attachments[0].reference, "A1")
        XCTAssertEqual(report.attachments[0].entryReference, "E2")
        XCTAssertEqual(report.entries[1].attachmentRefs, ["A1"])
        XCTAssertEqual(report.summary.attachmentCount, 1)
    }

    func testEmptyYear() {
        let report = build([F.entry(property: F.oak, hours: 5, date: F.date(2025, 6, 1))])
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.summary.totalHours, 0)
        XCTAssertNil(report.summary.firstEntryDate)
        XCTAssertTrue(report.propertyTotals.isEmpty)
        XCTAssertTrue(report.categoryTotals.isEmpty)
        XCTAssertTrue(report.materialParticipation.isEmpty)
        XCTAssertEqual(report.qualifications.count, 2)
        XCTAssertEqual(AuditReportCSV.make(report), AuditReportCSV.header.joined(separator: ",") + "\r\n")

        let pdf = AuditReportPDFRenderer().render(report)
        let document = PDFDocument(data: pdf)
        XCTAssertEqual(document?.pageCount, 1)
        XCTAssertTrue(document?.string?.contains("No time entries were logged for 2026") == true)
    }
}

// MARK: - CSV

final class AuditReportCSVTests: XCTestCase {
    private typealias F = AuditFixture

    func testEscaping() {
        XCTAssertEqual(AuditReportCSV.escape("plain"), "plain")
        XCTAssertEqual(AuditReportCSV.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(AuditReportCSV.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(AuditReportCSV.escape("line1\nline2"), "\"line1\nline2\"")
        XCTAssertEqual(AuditReportCSV.escape("line1\r\nline2"), "\"line1\r\nline2\"")
        XCTAssertEqual(AuditReportCSV.escape(" padded"), "\" padded\"")
        XCTAssertEqual(AuditReportCSV.escape(""), "")
    }

    func testFormulaInjectionIsNeutralized() {
        XCTAssertEqual(AuditReportCSV.escape("=HYPERLINK(\"x\")"), "\"'=HYPERLINK(\"\"x\"\")\"")
        XCTAssertEqual(AuditReportCSV.escape("=1+1"), "'=1+1")
        XCTAssertEqual(AuditReportCSV.escape("+15551234"), "'+15551234")
        XCTAssertEqual(AuditReportCSV.escape("-2 hours"), "'-2 hours")
        XCTAssertEqual(AuditReportCSV.escape("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(AuditReportCSV.escape("\tcmd"), "'\tcmd")
        XCTAssertEqual(AuditReportCSV.escape("\rcmd"), "\"'\rcmd\"")
        XCTAssertEqual(AuditReportCSV.escape("a=b"), "a=b", "only a leading trigger is neutralized")
        XCTAssertEqual(AuditReportCSV.escape("1.50"), "1.50")
    }

    func testRowsRoundTripThroughRFC4180Parser() {
        let notes = "Fixed sink, replaced \"P-trap\"\nTenant: Smith, J."
        let entry = F.entry(property: F.oak, hours: 1.5, date: F.date(2026, 4, 2), notes: notes, source: .voice)
        let report = AuditReportBuilder.build(AuditReportBuilder.Input(entries: [entry], properties: [F.oak], taxYear: 2026))
        let csv = AuditReportCSV.make(report)

        XCTAssertTrue(csv.hasSuffix("\r\n"))
        let rows = Self.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], AuditReportCSV.header)
        let row = rows[1]
        XCTAssertEqual(row.count, AuditReportCSV.header.count)
        func field(_ name: String) -> String { row[AuditReportCSV.header.firstIndex(of: name)!] }
        XCTAssertEqual(field("description"), notes)
        XCTAssertEqual(field("property"), "Oak Street Duplex")
        XCTAssertEqual(field("hours"), "1.50")
        XCTAssertEqual(field("source"), "Voice")
        XCTAssertEqual(field("counts_toward_reps"), "yes")
        XCTAssertEqual(field("entry_ref"), "E1")
    }

    func testProvenanceColumnsAndSourceDetailEscaping() {
        let detected = F.date(2026, 4, 2, 8, 0)
        let confirmed = F.date(2026, 4, 20, 9, 15)
        let suggested = F.entry(property: F.oak, hours: 1, date: F.date(2026, 4, 2), source: .calendar,
                                detectedAt: detected, confirmedAt: confirmed,
                                sourceDetail: "=HYPERLINK(\"http://x\"), \"Showing\"\nunit 2")
        let legacy = F.entry(property: F.oak, hours: 1, date: F.date(2026, 4, 3), source: .calendar, sourceDetail: "Plain, event")
        let report = AuditReportBuilder.build(AuditReportBuilder.Input(entries: [suggested, legacy], properties: [F.oak], taxYear: 2026))
        let rows = Self.parse(AuditReportCSV.make(report))
        XCTAssertEqual(rows.count, 3)
        let header = rows[0]
        XCTAssertEqual(header, AuditReportCSV.header)
        func field(_ row: [String], _ name: String) -> String { row[header.firstIndex(of: name)!] }
        XCTAssertEqual(rows[1].count, header.count)
        XCTAssertEqual(field(rows[1], "source"), "Calendar suggestion")
        XCTAssertEqual(field(rows[1], "confirmation_lag"), "confirmed 18 days later")
        XCTAssertEqual(field(rows[1], "source_detail"), "'=HYPERLINK(\"http://x\"), \"Showing\"\nunit 2", "guarded and round-trips through quoting")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(parser.date(from: field(rows[1], "detected_at")), detected)
        XCTAssertEqual(parser.date(from: field(rows[1], "confirmed_at")), confirmed)
        XCTAssertEqual(field(rows[2], "source"), "Calendar import")
        XCTAssertEqual(field(rows[2], "detected_at"), "")
        XCTAssertEqual(field(rows[2], "confirmed_at"), "")
        XCTAssertEqual(field(rows[2], "confirmation_lag"), "")
        XCTAssertEqual(field(rows[2], "source_detail"), "Plain, event")
    }

    func testHoursColumnStaysNumericForNegativeOrNegativeZero() {
        let negZero = F.entry(property: F.oak, hours: -0.0, date: F.date(2026, 4, 1))
        let negative = F.entry(property: F.oak, hours: -2, date: F.date(2026, 4, 2))
        let normal = F.entry(property: F.oak, hours: 1.25, date: F.date(2026, 4, 3))
        let report = AuditReportBuilder.build(AuditReportBuilder.Input(entries: [negZero, negative, normal], properties: [F.oak], taxYear: 2026))
        let rows = Self.parse(AuditReportCSV.make(report))
        let index = rows[0].firstIndex(of: "hours")!
        XCTAssertEqual(rows[1...].map { $0[index] }, ["0.00", "0.00", "1.25"])
        for row in rows.dropFirst() {
            XCTAssertNotNil(Double(row[index]), "hours must parse as a number, got \(row[index])")
            XCTAssertFalse(row[index].hasPrefix("'"))
        }
    }

    func testTimestampColumnsAreISO8601() {
        let logged = F.date(2026, 4, 2, 18, 30)
        let edited = F.date(2026, 4, 9, 7, 5)
        let entry = F.entry(property: F.oak, hours: 1, date: F.date(2026, 4, 2), loggedAt: logged, editedAt: edited)
        let unedited = F.entry(property: F.oak, hours: 1, date: F.date(2026, 4, 3), loggedAt: logged)
        let report = AuditReportBuilder.build(AuditReportBuilder.Input(entries: [entry, unedited], properties: [F.oak], taxYear: 2026))
        let rows = Self.parse(AuditReportCSV.make(report))
        let header = rows[0]
        let first = rows[1]
        let second = rows[2]

        XCTAssertEqual(first[header.firstIndex(of: "date")!], "2026-04-02")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(parser.date(from: first[header.firstIndex(of: "logged_at")!]), logged)
        XCTAssertEqual(parser.date(from: first[header.firstIndex(of: "last_edited_at")!]), edited)
        XCTAssertEqual(second[header.firstIndex(of: "last_edited_at")!], "", "unedited entries leave last_edited_at blank")
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#
        XCTAssertNotNil(first[header.firstIndex(of: "logged_at")!].range(of: pattern, options: .regularExpression))
    }

    /// Minimal RFC 4180 parser used to prove the writer's output is well-formed.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\r\n" || c == "\n" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        chars.removeAll()
        return rows
    }
}

// MARK: - PDF + samples

final class AuditReportPDFTests: XCTestCase {
    private typealias F = AuditFixture

    /// Fixture photos render at 2x: a 600x800 pt receipt is a 1200x1600 px JPEG, like a phone photo crop.
    static let fixtureFormat: UIGraphicsImageRendererFormat = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return format
    }()

    func testPortraitReceiptIsDrawnLargeEnoughToRead() throws {
        let (report, images) = Self.sampleReport()
        let receipt = try XCTUnwrap(report.attachments.first { $0.attachment.filename == "water-heater-receipt.jpg" })
        let data = try XCTUnwrap(images[receipt.attachment.id])
        let pixels = try XCTUnwrap(AuditReportPDFRenderer.pixelSize(of: data))
        XCTAssertEqual(pixels, CGSize(width: 1200, height: 1600))

        let drawn = AuditReportPDFRenderer.appendixImageSize(pixelSize: pixels)
        XCTAssertGreaterThanOrEqual(drawn.width, 240, "receipt text must print at a readable size")
        XCTAssertLessThanOrEqual(drawn.width, 340)
        XCTAssertLessThanOrEqual(drawn.height, AuditReportPDFRenderer.appendixBox.height)
        XCTAssertEqual(drawn.width / drawn.height, 0.75, accuracy: 0.01, "aspect ratio preserved")
        // Source has enough pixels for 200 ppi at the drawn size.
        XCTAssertGreaterThanOrEqual(pixels.height / (drawn.height / 72), 200)
    }

    func testAppendixNeverUpscalesSmallImages() {
        XCTAssertEqual(AuditReportPDFRenderer.appendixImageSize(pixelSize: CGSize(width: 200, height: 300)), CGSize(width: 200, height: 300))
        let landscape = AuditReportPDFRenderer.appendixImageSize(pixelSize: CGSize(width: 4032, height: 3024))
        XCTAssertEqual(landscape.width, 340)
        XCTAssertEqual(landscape.height, 255)
    }

    static func sampleReport() -> (AuditReport, [UUID: Data]) {
        var images: [UUID: Data] = [:]
        /// A small JPEG "photo" of a paper receipt or note lying on a table, slightly rotated.
        func photo(_ name: String, title: String, lines: [String], tint: UIColor) -> TimeAttachment {
            let size = CGSize(width: 600, height: 800)
            let image = UIGraphicsImageRenderer(size: size, format: Self.fixtureFormat).jpegData(withCompressionQuality: 0.75) { ctx in
                let cg = ctx.cgContext
                // Table surface with a soft gradient.
                let colors = [tint.withAlphaComponent(0.55).cgColor, UIColor.darkGray.cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                // Paper, rotated a few degrees, with a shadow.
                cg.translateBy(x: size.width / 2, y: size.height / 2)
                cg.rotate(by: -0.05)
                let paper = CGRect(x: -210, y: -330, width: 420, height: 660)
                cg.setShadow(offset: CGSize(width: 6, height: 10), blur: 18, color: UIColor.black.withAlphaComponent(0.45).cgColor)
                UIColor(white: 0.97, alpha: 1).setFill()
                cg.fill(paper)
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                let mono = UIFont(name: "Courier-Bold", size: 26) ?? .boldSystemFont(ofSize: 26)
                let body = UIFont(name: "Courier", size: 20) ?? .systemFont(ofSize: 20)
                (title as NSString).draw(in: CGRect(x: paper.minX + 24, y: paper.minY + 30, width: paper.width - 48, height: 70),
                                         withAttributes: [.font: mono, .foregroundColor: UIColor.black])
                var lineY = paper.minY + 110
                for line in lines {
                    (line as NSString).draw(at: CGPoint(x: paper.minX + 24, y: lineY), withAttributes: [.font: body, .foregroundColor: UIColor(white: 0.15, alpha: 1)])
                    lineY += 34
                }
            }
            let attachment = TimeAttachment(filename: name, data: image, mimeType: "image/jpeg")
            images[attachment.id] = image
            return attachment
        }

        var entries: [TimeEntry] = []
        let categories: [ActivityCategory] = [.repairs, .management, .leasing, .bookkeeping, .travel, .renovations, .legal, .investing]
        for i in 0..<46 {
            let property = [F.oak, F.pine][i % 2]
            let participant: Participant = i % 3 == 0 ? .spouse : .selfParticipant
            let day = F.date(2026, 1 + (i % 9), 1 + (i * 3) % 27, 8 + i % 8)
            var attachments: [TimeAttachment] = []
            if i == 4 {
                attachments = [photo("water-heater-receipt.jpg", title: "CASCADE PLUMBING\nSUPPLY CO.", lines: [
                    "2026-05-13  08:12", "--------------------------", "40 GAL WATER HEATER  612.00", "FLEX CONNECTOR x2     18.40",
                    "TEFLON TAPE            3.29", "--------------------------", "SUBTOTAL             633.69", "TAX                    0.00",
                    "TOTAL                633.69", "", "VISA ****4417", "THANK YOU",
                ], tint: .systemBlue)]
            }
            if i == 11 {
                attachments = [
                    photo("roof-before.jpg", title: "ROOF INSPECTION\nNOTES", lines: [
                        "Oak Street Duplex", "2026-03-07", "", "- NE corner: 3 shingles", "  missing", "- Flashing lifted at", "  chimney",
                        "- Gutter clogged (west)", "", "Before photos: 4",
                    ], tint: .systemOrange),
                    photo("roof-after.jpg", title: "RIDGELINE ROOFING\nINVOICE #20431", lines: [
                        "2026-03-07", "--------------------------", "Shingle repair       240.00", "Re-seal flashing     160.00",
                        "Gutter clean-out      85.00", "--------------------------", "TOTAL                485.00", "", "PAID - CHECK 1182",
                    ], tint: .systemGreen),
                ]
            }
            let notes: String
            switch i {
            case 4: notes = "Replaced water heater, \"40 gal\" unit; met plumber at 8am"
            case 9: notes = "Showed unit 2 to three applicants.\nScreened credit reports, called references."
            case 2: notes = "=SUM(1+1) pasted from a spreadsheet"
            case 17: notes = String(repeating: "Long description of a full renovation day, demo and haul-off. ", count: 8)
            default: notes = "\(categories[i % categories.count].rawValue) at \(property.name)"
            }
            let source: EntrySource = [.manual, .timer, .voice, .calendar][i % 4]
            // Mixed provenance: some calendar rows are 2.0 suggestions (same-day, late, bulk), a few are other sources.
            var detectedAt: Date?, confirmedAt: Date?, detail: String?
            var rawSource: String?
            if source == .calendar {
                switch i % 12 {
                case 3: detectedAt = day.addingTimeInterval(2 * 3600); confirmedAt = day.addingTimeInterval(5 * 3600); detail = "Showing unit 2, Oak St"
                case 7: detectedAt = day.addingTimeInterval(2 * 3600); confirmedAt = F.date(2026, 10, 14, 20, 5); detail = "=Plumber visit"
                default: break
                }
            }
            if i == 5 { rawSource = "receipt"; detectedAt = day; confirmedAt = day.addingTimeInterval(7200) }
            if i == 14 { rawSource = "from-a-newer-build" }
            let editedAt: Date? = i % 7 == 0 ? day.addingTimeInterval(86_400 * 3) : nil
            entries.append(F.entry(
                property: property, participant: participant,
                category: categories[i % categories.count],
                hours: [1.5, 2, 3.25, 4, 0.75][i % 5],
                date: day, notes: notes, attachments: attachments,
                source: source, loggedAt: day.addingTimeInterval(3 * 3600), editedAt: editedAt,
                detectedAt: detectedAt, confirmedAt: confirmedAt, sourceDetail: detail, rawImportSource: rawSource
            ))
        }
        entries.append(F.entry(property: F.idle, hours: 9, date: F.date(2025, 11, 2)))

        let report = AuditReportBuilder.build(AuditReportBuilder.Input(
            entries: entries,
            properties: [F.oak, F.pine, F.idle],
            taxYear: 2026,
            participants: [.selfParticipant, .spouse],
            nonRealEstateHours: [.selfParticipant: 40],
            groupingElection: false,
            noOneParticipatedMore: nil,
            generatedAt: F.date(2026, 10, 17, 12)
        ))
        return (report, images)
    }

    func testPDFTextIsSearchableWithoutLigatureGaps() throws {
        let (report, images) = Self.sampleReport()
        let pdf = AuditReportPDFRenderer(attachmentData: { images[$0.id] }).render(report)
        let text = try XCTUnwrap(PDFDocument(data: pdf)?.string)
        XCTAssertTrue(text.contains("financing"), "\"fi\" ligature must extract as text")
        XCTAssertTrue(text.contains("Tax Profile"))
        XCTAssertFalse(text.contains("Tax Pro le"))
    }

    func testMaterialParticipationNoteStaysWithItsTable() throws {
        let (report, images) = Self.sampleReport()
        let document = try XCTUnwrap(PDFDocument(data: AuditReportPDFRenderer(attachmentData: { images[$0.id] }).render(report)))
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let notePage = try XCTUnwrap(pages.firstIndex { $0.contains("The 100-hour test also requires") })
        XCTAssertTrue(pages[notePage].contains("500-hour test"), "note must share a page with the material participation table")
        XCTAssertTrue(pages[notePage].contains("Material participation by property"), "small tables move whole instead of splitting")
    }

    func testPDFShowsProvenanceColumnsAndSourceAppendix() throws {
        let (report, images) = Self.sampleReport()
        let document = try XCTUnwrap(PDFDocument(data: AuditReportPDFRenderer(attachmentData: { images[$0.id] }).render(report)))
        let all = document.string ?? ""
        for expected in ["Detected", "Confirmed", "Calendar suggestion", "Calendar import", "Receipt", "Other",
                         "Appendix: where entries came from", AuditReportFormat.suggestionExplanation, "days later"] {
            XCTAssertTrue(all.contains(expected), "missing \(expected)")
        }
        for banned in ["audit-proof", "audit proof", "score", "%"] {
            XCTAssertFalse(all.lowercased().contains(banned), "report must stay factual: \(banned)")
        }
        XCTAssertTrue(report.sourceTotals.contains { $0.label == "Calendar suggestion" })
    }

    func testPDFHasFooterOnEveryPageAndAllSections() throws {
        let (report, images) = Self.sampleReport()
        let pdf = AuditReportPDFRenderer(attachmentData: { images[$0.id] }).render(report)
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThan(document.pageCount, 2)

        for index in 0..<document.pageCount {
            let text = document.page(at: index)?.string ?? ""
            XCTAssertTrue(text.contains("Generated by LandlordHours on"), "page \(index + 1) footer")
            XCTAssertTrue(text.contains("Page \(index + 1) of \(document.pageCount)"), "page \(index + 1) number")
            XCTAssertTrue(text.contains("not tax advice"), "page \(index + 1) disclaimer")
        }
        let all = document.string ?? ""
        for expected in ["Qualification by participant", "Hours by property", "Hours by category", "Hours by participant",
                         "Time entries (chronological)", "Appendix: photos and receipts", "Oak Street Duplex", "Pine Cabin",
                         "water-heater-receipt.jpg", "Calendar", "Timer", "Voice", "E46"] {
            XCTAssertTrue(all.contains(expected), "missing \(expected)")
        }
        XCTAssertFalse(all.contains("Idle Condo"), "properties without hours in the year are left out")
    }

    /// Writes reviewer samples. On a simulator the host's ~/AgentScratch is reachable via
    /// SIMULATOR_HOST_HOME; elsewhere the files land in the test's temporary directory.
    func testWriteSampleExports() throws {
        let (report, images) = Self.sampleReport()
        let directory: URL
        if let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            directory = URL(fileURLWithPath: hostHome).appendingPathComponent("AgentScratch/landlordhours/2026-10-19/wp5-samples", isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-samples", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdf = AuditReportPDFRenderer(attachmentData: { images[$0.id] }).render(report)
        try pdf.write(to: directory.appendingPathComponent("LandlordHours_2026_Activity_Log.pdf"), options: .atomic)
        try Data(AuditReportCSV.make(report).utf8).write(to: directory.appendingPathComponent("LandlordHours_2026_Activity_Log.csv"), options: .atomic)
        XCTAssertNotNil(PDFDocument(url: directory.appendingPathComponent("LandlordHours_2026_Activity_Log.pdf")))
        XCTAssertLessThan(pdf.count, 3_000_000, "thumbnails should keep the PDF small")
    }
}

// MARK: - Gating

@MainActor
final class AuditExportGatingTests: XCTestCase {
    func testCanExportFollowsProEntitlement() {
        let manager = SubscriptionManager.shared
        let original = manager.isPro
        defer { manager.isPro = original }
        let viewModel = AppViewModel()

        manager.isPro = false
        XCTAssertFalse(viewModel.canExportPDF())
        manager.isPro = true
        XCTAssertTrue(viewModel.canExportPDF())
    }

    func testExportSharedHookFiresWithFormat() {
        let viewModel = AppViewModel()
        var shared: [ExportFormat] = []
        viewModel.onExportShared = { shared.append($0) }
        viewModel.exportShared(format: .pdf)
        viewModel.exportShared(format: .csv)
        XCTAssertEqual(shared, [.pdf, .csv])
    }
}
