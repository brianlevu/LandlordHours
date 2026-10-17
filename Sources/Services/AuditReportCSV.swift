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
        "attachments",
    ]

    static func make(_ report: AuditReport) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = report.timeZone
        dateFormatter.formatOptions = [.withFullDate]

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = report.timeZone
        timestampFormatter.formatOptions = [.withInternetDateTime]

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
                AuditReportFormat.hours(row.hours),
                row.description,
                timestampFormatter.string(from: row.loggedAt),
                row.lastEditedAt.map { timestampFormatter.string(from: $0) } ?? "",
                row.source.displayName,
                attachments,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quote a field when it contains a comma, quote, CR or LF (or edge whitespace);
    /// embedded quotes are doubled.
    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
            || field.first?.isWhitespace == true
            || field.last?.isWhitespace == true
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
