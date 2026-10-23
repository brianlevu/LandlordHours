import SwiftUI

// MARK: - Page 1 of the record, drawn plain (the paywall hero and Today's lock)
//
// Built from the same `AuditReport` the PDF renderer uses, so with at least one entry the page
// shows the user's own rentals, hours and entries. With none it shows sample data under a
// "SAMPLE" stamp. It is drawn in SwiftUI (portrait, like the approved sandbox) rather than as a
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
            (properties.first { $0.id == id }?.propertyType == .str) ? "A few nights" : "Long stays"
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
        return RecordPageModel(year: report.taxYear, owner: name.isEmpty || name == "User" ? "Your name" : name,
                               range: range, rows: rows, total: total, kinds: Array(kinds), lines: Array(lines), isSample: false)
    }

    static func sample(year: Int) -> RecordPageModel {
        RecordPageModel(
            year: year, owner: "Sample owner", range: "Jan 1 – Oct 19, \(String(year))",
            rows: [Row(name: "Sample Cabin", kind: "Long stays", hours: 140.5)], total: 140.5,
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
            groupingElection: tax.groupingElection, noOneParticipatedMore: tax.noOneParticipatedMore(forYear: year),
            propertyAnswers: tax.participationAnswers(forYear: year, properties: properties))
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

/// The page itself: always white paper with dark ink, in both themes.
struct RecordPagePreview: View {
    let model: RecordPageModel
    var highlight: RecordPageHighlight = .none

    // The page is paper: always the light tokens, in both themes.
    private let ink = Color(hex: AppColors.Hex.textPrimary)
    private let grey = Color(hex: AppColors.Hex.textSecondary)
    private let rule = Color(hex: AppColors.Hex.border)
    private let draftingInk = Color(hex: AppColors.Hex.draftingInk)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("LANDLORDHOURS").font(.system(size: 6.5, weight: .semibold, design: .monospaced)).tracking(0.8).foregroundStyle(AppColors.brand)
                Spacer()
                if model.isSample {
                    // The stamp sits in the header's own slot, so it never covers the title.
                    Text("SAMPLE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(draftingInk)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(draftingInk, lineWidth: 1.2))
                        .rotationEffect(.degrees(-4))
                        .accessibilityIdentifier("paywall.sampleStamp")
                } else {
                    Text("Page 1").font(.system(size: 6)).foregroundStyle(grey)
                }
            }
            Text("\(String(model.year)) hours record").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(ink)
            Text("\(model.owner) · \(model.range)").font(.system(size: 6.5)).foregroundStyle(grey).lineLimit(1)
            Rectangle().fill(rule).frame(height: 0.5)
            HStack { Text("PROPERTY"); Spacer(); Text("HOURS") }
                .font(.system(size: 5.5, weight: .semibold)).foregroundStyle(grey)
            ForEach(Array(model.rows.prefix(3).enumerated()), id: \.offset) { _, row in
                propertyRow(row.name, row.kind, value: hoursText(row.hours), isNew: false)
            }
            if case .newRow(let name) = highlight {
                propertyRow(name, "New rental", value: "—", isNew: true)
            }
            Rectangle().fill(rule).frame(height: 0.5)
            HStack {
                Text("Total").font(.system(size: 7.5, weight: .semibold))
                Spacer()
                Text("\(hoursText(model.total))h").font(.system(size: 9, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, highlight == .total ? 4 : 0).padding(.vertical, highlight == .total ? 3 : 0)
            .background { if highlight == .total { RoundedRectangle(cornerRadius: 3).fill(HouseTokens.drafting.opacity(0.28)) } }
            if !model.kinds.isEmpty {
                Text("BY KIND OF WORK").font(.system(size: 5.5, weight: .semibold)).foregroundStyle(grey).padding(.top, 4)
                ForEach(model.kinds, id: \.label) { kind in
                    HStack(spacing: 4) {
                        Text(kind.label).font(.system(size: 6)).lineLimit(1).frame(width: 52, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(draftingInk.opacity(0.7)).frame(width: max(3, g.size.width * kind.fraction))
                        }
                        .frame(height: 3.5)
                    }
                    .foregroundStyle(ink)
                }
            }
            if !model.lines.isEmpty {
                Text("ENTRIES").font(.system(size: 5.5, weight: .semibold)).foregroundStyle(grey).padding(.top, 4)
                ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text(line.date).frame(width: 28, alignment: .leading)
                        Text(line.title).lineLimit(1)
                        Spacer()
                        Text(hoursText(line.hours)).monospacedDigit()
                    }
                    .font(.system(size: 6)).foregroundStyle(ink)
                    Rectangle().fill(rule.opacity(0.6)).frame(height: 0.3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.top, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    private func propertyRow(_ name: String, _ kind: String, value: String, isNew: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 7.5, weight: .semibold)).lineLimit(1)
                Text(kind).font(.system(size: 5.5)).foregroundStyle(grey)
            }
            Spacer()
            Text(value).font(.system(size: 7.5, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, isNew ? 4 : 0).padding(.vertical, isNew ? 3 : 0)
        .background { if isNew { RoundedRectangle(cornerRadius: 3).fill(HouseTokens.drafting.opacity(0.28)) } }
        .overlay { if isNew { RoundedRectangle(cornerRadius: 3).strokeBorder(draftingInk, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])) } }
    }

    private func hoursText(_ h: Double) -> String { String(format: "%.1f", max(0, h)) }
}
