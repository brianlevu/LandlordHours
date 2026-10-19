import Foundation

/// RFC 4180 CSV for the audit export: one row per time entry, CRLF line endings,
/// ISO-8601 dates and timestamps (with UTC offset) in the report's time zone.
enum AuditReportCSV {
    static let header: [String] = [
        "entry_ref",
        "date",
        "property",
        "category",
        "counts_toward_reps",
        "participant",
        "hours",
        "description",
        "logged_at",
        "last_edited_at",
        "source",
        "detected_at",
        "confirmed_at",
        "confirmation_lag",
        "source_detail",
        "attachments",
    ]

    static func make(_ report: AuditReport) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = report.timeZone
        dateFormatter.formatOptions = [.withFullDate]

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = report.timeZone
        timestampFormatter.formatOptions = [.withInternetDateTime]

        let hoursIndex = header.firstIndex(of: "hours")!
        var lines = [header.map(escape).joined(separator: ",")]
        for row in report.entries {
            let attachments = zip(row.attachmentRefs, row.attachmentFilenames)
                .map { "\($0) \($1)" }
                .joined(separator: "; ")
            let fields = [
                row.reference,
                dateFormatter.string(from: row.date),
                row.propertyName,
                row.category.rawValue,
                row.category.countsForREPS ? "yes" : "no",
                row.participant.rawValue,
                numeric(row.hours),
                row.description,
                timestampFormatter.string(from: row.loggedAt),
                row.lastEditedAt.map { timestampFormatter.string(from: $0) } ?? "",
                row.sourceLabel,
                row.detectedAt.map { timestampFormatter.string(from: $0) } ?? "",
                row.confirmedAt.map { timestampFormatter.string(from: $0) } ?? "",
                row.confirmationLagText ?? "",
                row.sourceDetail ?? "",
                attachments,
            ]
            // Numeric columns skip the formula guard so they stay numbers in spreadsheets.
            let cells = fields.enumerated().map { index, field in
                index == hoursIndex ? field : escape(field)
            }
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Hours as a plain non-negative number ("-0.00" and negatives clamp to "0.00").
    static func numeric(_ hours: Double) -> String {
        AuditReportFormat.hours(hours > 0 ? hours : 0)
    }

    /// Characters that make spreadsheet apps treat a cell as a formula.
    static let formulaTriggers: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "\r\n"]

    /// Neutralize formula injection by prefixing a single quote, then quote the field when
    /// it contains a comma, quote, CR or LF (or edge whitespace); embedded quotes are doubled.
    static func escape(_ raw: String) -> String {
        var field = raw
        if let first = field.first, formulaTriggers.contains(first) {
            field = "'" + field
        }
        let needsQuoting = field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            || field.first?.isWhitespace == true
            || field.last?.isWhitespace == true
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
