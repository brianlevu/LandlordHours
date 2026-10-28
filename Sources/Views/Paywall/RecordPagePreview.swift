import SwiftUI

// MARK: - Page 1 of the record, drawn plain (the paywall preview and Today's lock)
//
// Built from the same `AuditReport` the PDF renderer uses, so with at least one entry the page
// shows the user's own rentals, hours and entries. With none it shows sample data under a
// "Sample" tag. It is drawn in SwiftUI (portrait, like the approved sandbox) rather than as a
// bitmap of the landscape PDF, so the context highlight (the new row, the total) can be drawn.

struct RecordPageModel: Equatable {
    struct Row: Equatable { let name: String; let kind: String; let hours: Double }
    struct Kind: Equatable { let label: String; let fraction: Double }
    struct Line: Equatable { let date: String; let title: String; let hours: Double }

    var year: Int
    var owner: String
    var range: String
    var rows: [Row]
    var total: Double
    var kinds: [Kind]
    var lines: [Line]
    var isSample: Bool

    static func from(report: AuditReport, owner: String, properties: [RentalProperty]) -> RecordPageModel {
        let kindFor: (UUID) -> String = { id in
            (properties.first { $0.id == id }?.propertyType == .str) ? String(localized: "A few nights", table: "ConversionPath") : String(localized: "Long stays", table: "ConversionPath")
        }
        let rows = report.propertyTotals.map { Row(name: $0.name, kind: kindFor($0.propertyId), hours: $0.repsCountableHours) }
        let total = report.summary.repsCountableHours
        let countable = report.categoryTotals.filter(\.countsForREPS).sorted { $0.hours > $1.hours }
        let maxHours = max(countable.first?.hours ?? 0, 0.0001)
        let kinds = countable.prefix(4).map { Kind(label: $0.category.inboxLabel, fraction: $0.hours / maxHours) }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let lines = report.entries.sorted { $0.date > $1.date }.prefix(6).map { row -> Line in
            let text = row.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return Line(date: df.string(from: row.date), title: text.isEmpty ? row.category.inboxLabel : text, hours: row.hours)
        }
        let first = report.summary.firstEntryDate ?? Date()
        let last = report.summary.lastEntryDate ?? Date()
        let range = "\(df.string(from: first)) – \(df.string(from: last)), \(String(report.taxYear))"
        let name = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecordPageModel(year: report.taxYear, owner: name.isEmpty || name == "User" ? String(localized: "Your name", table: "ConversionPath") : name,
                               range: range, rows: rows, total: total, kinds: Array(kinds), lines: Array(lines), isSample: false)
    }

    /// The rentals past the first `limit` rows: how many and their hours, or nil when every row shows.
    func overflow(limit: Int) -> (count: Int, hours: Double)? {
        let hidden = rows.dropFirst(max(0, limit))
        guard !hidden.isEmpty else { return nil }
        return (hidden.count, hidden.reduce(0) { $0 + $1.hours })
    }

    static func sample(year: Int) -> RecordPageModel {
        RecordPageModel(
            year: year, owner: String(localized: "Sample owner", table: "ConversionPath"), range: String(localized: "Jan 1 – Oct 19, \(String(year))", table: "ConversionPath"),
            rows: [Row(name: String(localized: "Sample Cabin", table: "ConversionPath"), kind: String(localized: "Long stays", table: "ConversionPath"), hours: 140.5)], total: 140.5,
            kinds: [Kind(label: "Repairs", fraction: 1), Kind(label: "Management", fraction: 0.64),
                    Kind(label: "Leasing", fraction: 0.43), Kind(label: "Bookkeeping", fraction: 0.31)],
            lines: [Line(date: "Oct 18", title: "Plumber", hours: 2), Line(date: "Oct 16", title: "Showing", hours: 1),
                    Line(date: "Oct 12", title: "Key handoff", hours: 0.5), Line(date: "Oct 8", title: "Monthly books", hours: 1.5),
                    Line(date: "Oct 4", title: "Gutter repair", hours: 3), Line(date: "Sep 30", title: "Tenant call", hours: 0.5)],
            isSample: true)
    }

    /// Builds page 1 from the user's records for `year`, or the sample when there are none.
    static func load(entries: [TimeEntry], properties: [RentalProperty], owner: String, year: Int) async -> RecordPageModel {
        let tax = TaxProfileManager.shared
        let input = AuditReportBuilder.inputFromTaxProfile(
            entries: entries, properties: properties, taxYear: year,
            spouseTracking: tax.spouseTracking, nonREWorkHours: tax.nonREWorkHours,
            groupingElection: tax.groupingElection, noOneParticipatedMore: tax.noOneParticipatedMore(forYear: year))
        return await Task.detached(priority: .userInitiated) {
            let report = AuditReportBuilder.build(input)
            return report.isEmpty ? .sample(year: year) : .from(report: report, owner: owner, properties: properties)
        }.value
    }
}

enum RecordPageHighlight: Equatable {
    case none
    /// The rental being added, drawn as a cyan dashed row.
    case newRow(String)
    /// The page total.
    case total

    static func forContext(_ context: PaywallContext, propertyName: String?) -> RecordPageHighlight {
        switch context {
        case .secondProperty:
            let name = propertyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .newRow(name?.isEmpty == false ? name! : "Your next rental")
        case .todayUnlock: return .total
        case .export, .settings: return .none
        }
    }
}

/// Page 1 of the record, at readable sizes (v2: the 5.5–13pt miniature is retired). Paper is
/// always the light tokens, in both appearances. The title is the PDF's own title (`pdf.title`,
/// "Rental hours record 2026"); the frame that holds it crops the page's foot.
struct RecordPagePreview: View {
    let model: RecordPageModel
    var highlight: RecordPageHighlight = .none
    /// Entry lines under the total (the paywall shows as many as fit).
    var entryLimit = 4
    /// Rental rows (up to 3).
    var rentalLimit = 3
    /// Fill the height it is given (Today's lock frames it); the paywall hugs the content.
    var fillsHeight = true
    /// The smallest form (accessibility sizes): the title wraps, the tag sits under it, the owner
    /// line goes, so nothing truncates mid-word.
    var compact = false

    /// The paper's ink set: the light tokens in both appearances.
    private let paper = AdaptiveColors(colorScheme: .light)

    /// `pdf.title`: one key for the PDF, the CSV file name and this preview (standard §C.5).
    static func title(year: Int) -> String {
        String(format: String(localized: "pdf.title", defaultValue: "Rental hours record %lld"), year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let header = compact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            header {
                Text(Self.title(year: model.year))
                    .font(.headline)
                    .foregroundStyle(paper.textPrimary)
                    // Compact (AX sizes): two lines reserved, so the title wraps instead of truncating.
                    .lineLimit(compact ? 2 : 1, reservesSpace: compact)
                    .minimumScaleFactor(compact ? 0.8 : 1)
                if !compact { Spacer(minLength: 8) }
                if model.isSample {
                    LHTag(String(localized: "Sample", table: "ConversionPath"), tone: .informational)
                        .accessibilityIdentifier("paywall.sampleStamp")
                } else {
                    Text(String(localized: "Page 1", table: "ConversionPath"))
                        .font(.caption)
                        .foregroundStyle(paper.textSecondary)
                }
            }
            if !compact {
                Text(verbatim: "\(model.owner) · \(model.range)")
                    .font(.caption)
                    .foregroundStyle(paper.textSecondary)
            }
            if !compact { LHDivider() }
            ForEach(Array(model.rows.prefix(rentalLimit).enumerated()), id: \.offset) { _, row in
                rentalRow(row.name, row.kind, value: hoursText(row.hours), isNew: false)
            }
            if let more = model.overflow(limit: rentalLimit) {
                Text(Self.overflowText(count: more.count, hours: more.hours, shownRows: min(rentalLimit, model.rows.count)))
                    .font(.footnote)
                    .foregroundStyle(paper.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityIdentifier("paywall.page.moreRentals")
            }
            if case .newRow(let name) = highlight {
                rentalRow(name, String(localized: "New rental", table: "ConversionPath"), value: "—", isNew: true)
            }
            LHDivider()
            HStack {
                Text(model.rows.count > 1 ? String(localized: "Total, all rentals", table: "ConversionPath")
                                          : String(localized: "Total", table: "ConversionPath"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: "\(hoursText(model.total))h")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }
            .foregroundStyle(paper.textPrimary)
            .padding(.horizontal, highlight == .total ? 8 : 0)
            .padding(.vertical, highlight == .total ? 6 : 0)
            .background {
                if highlight == .total {
                    RoundedRectangle(cornerRadius: LHTag.radius, style: .continuous).fill(paper.actionSurface)
                }
            }
            if !model.lines.isEmpty && entryLimit > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.lines.prefix(entryLimit).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 8) {
                            Text(line.date).frame(minWidth: 48, alignment: .leading)
                                .foregroundStyle(paper.textSecondary)
                            Text(line.title).lineLimit(1)
                            Spacer()
                            Text(hoursText(line.hours)).fontDesign(.rounded).monospacedDigit()
                        }
                        .font(.footnote)
                        .foregroundStyle(paper.textPrimary)
                    }
                }
                .padding(.top, 4)
            }
            if fillsHeight { Spacer(minLength: 0) }
        }
        .padding(LHMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .background(paper.backgroundSecondary)
        .environment(\.colorScheme, .light)
    }

    /// The line for rentals the page has no room to list, so the rows and the Total always agree:
    /// "+2 more rentals · 34.0h", or "4 rentals · 40.0h" when none are listed.
    static func overflowText(count: Int, hours: Double, shownRows: Int) -> String {
        let h = String(format: "%.1f", max(0, hours))
        if shownRows == 0 {
            return String(localized: "\(count) rentals \u{00B7}\u{00A0}\(h)h", table: "ConversionPath")
        }
        if count == 1 { return String(localized: "+1 more rental \u{00B7}\u{00A0}\(h)h", table: "ConversionPath") }
        return String(localized: "+\(count) more rentals \u{00B7}\u{00A0}\(h)h", table: "ConversionPath")
    }

    private func rentalRow(_ name: String, _ kind: String, value: String, isNew: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(kind).font(.caption).foregroundStyle(paper.textSecondary)
            }
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
        }
        .foregroundStyle(paper.textPrimary)
        .padding(.horizontal, isNew ? 8 : 0)
        .padding(.vertical, isNew ? 6 : 0)
        .background { if isNew { RoundedRectangle(cornerRadius: LHTag.radius, style: .continuous).fill(paper.actionSurface) } }
        .overlay {
            if isNew {
                RoundedRectangle(cornerRadius: LHTag.radius, style: .continuous)
                    .strokeBorder(paper.action, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    private func hoursText(_ h: Double) -> String { String(format: "%.1f", max(0, h)) }
}
