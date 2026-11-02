import SwiftUI

#if DEBUG
// MARK: - Records, three directions (2.3.1 quiet sandbox)
//
// All three keep the row Dina asked for: what you did, date · rental, hours, the kind as the tile.
// They differ in where the rest goes.
//   A  Quiet list. One search row with one Filter chip; the year and total move into the subtitle;
//      the spouse-rule sentence is gone (it lives in Learn and Filing). The record page shows three
//      facts and one "History" row that opens the found / confirmed / changed timeline.
//   B  Open in place. Same header. Tapping a row opens its details under it (note, source, who),
//      with "Open record" as the way in. The record page folds "Where it came from" in place.
//   C  This month open, earlier folded. The last 30 days are rows; earlier months are one row each
//      (Apple Wallet's "Previous years"), and a month opens as its own list.

enum QuietDirection { case a, b, c }

private func qHours(_ h: Double) -> String { LHFormat.hours(h) }

private func qMeta(_ e: TimeEntry) -> String {
    var parts = [e.date.formatted(.dateTime.month(.abbreviated).day())]
    if e.participant == .spouse { parts.append("Spouse") }
    if !e.countsForREPS { parts.append("Doesn\u{2019}t count") }
    parts.append(QuietSeed.name(e.propertyId))
    return parts.joined(separator: " \u{00B7} ")
}

private func qTitle(_ e: TimeEntry) -> String { RecordsLogic.title(for: e, propertyName: QuietSeed.name(e.propertyId)) }

private func qSourceLine(_ e: TimeEntry) -> String {
    if let confirmed = e.confirmedAt {
        return "Calendar \u{00B7} confirmed \(confirmed.formatted(.dateTime.month(.abbreviated).day()))"
    }
    return "Logged by hand \u{00B7} \(e.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
}

// MARK: Header shared by A, B and C

/// One row: the search field and one Filter chip (year, rental, source, who live in its menu).
private struct QuietSearchRow: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            LHField("Search records", text: $text, accessibilityLabel: "Search records", identifier: "quiet.search")
            Menu {
                Section("Year") { Button("2026") {}; Button("2025") {} }
                Section("Rental") { Button("All rentals") {}; ForEach(QuietSeed.properties) { p in Button(p.name) {} } }
                Section("Who") { Button("Everyone") {}; Button("Me") {}; Button("Spouse") {} }
                Section("Source") { Button("All sources") {}; Button("By hand") {}; Button("Calendar") {} }
            } label: {
                LHChip("Filter", systemImage: "line.3.horizontal.decrease", isSelected: false) {}
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("Filter records")
        }
    }
}

private struct QuietRowLabel: View {
    let entry: TimeEntry
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LHRow.Browse(title: qTitle(entry), meta: qMeta(entry), value: qHours(entry.hours)) {
            if !typeSize.isAccessibilitySize { CategoryToolTile(category: entry.category, size: 36) }
        }
    }
}

// MARK: List

struct QuietRecordsList: View {
    let direction: QuietDirection
    var openId: UUID? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var open: UUID?
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var entries: [TimeEntry] { QuietSeed.entries.sorted { $0.date > $1.date } }
    private var total: Double { entries.reduce(0) { $0 + $1.hours } }
    private var subtitle: String { "2026 \u{00B7} \(qHours(total)) in \(entries.count) records" }

    var body: some View {
        List {
            Section {
                QuietSearchRow(text: $search)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            switch direction {
            case .a: monthSections(entries)
            case .b: monthSections(entries, expandable: true)
            case .c: recentThenMonths
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
        .scrollContentBackground(.hidden)
        .lhListGutter()
        .background { LHCanvas() }
        .lhTabScreen("Records", subtitle: subtitle, trailing: {
            LHHeaderAction(symbol: "square.and.arrow.up", label: "Export records", identifier: "quiet.export") {}
        })
        .onAppear { open = openId }
    }

    @ViewBuilder
    private func monthSections(_ list: [TimeEntry], expandable: Bool = false) -> some View {
        ForEach(RecordsLogic.monthSections(list)) { section in
            Section {
                ForEach(section.entries) { entry in
                    if expandable { expandableRow(entry) } else { pushRow(entry) }
                }
            } header: {
                LHSectionHeader(RecordsLogic.monthHeader(section.month, hours: section.totalHours)).textCase(nil)
            }
        }
    }

    private func pushRow(_ entry: TimeEntry) -> some View {
        ZStack {
            NavigationLink { QuietRecordPage(entry: entry, style: .history) } label: { EmptyView() }.opacity(0)
            QuietRowLabel(entry: entry)
        }
        .listRowBackground(colors.backgroundSecondary)
        .listRowInsets(EdgeInsets())
        .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.browseDividerInset }
    }

    // B: the row opens its details in place; "Open record" is the way to the page.
    @ViewBuilder
    private func expandableRow(_ entry: TimeEntry) -> some View {
        let isOpen = open == entry.id
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)) { open = isOpen ? nil : entry.id }
        } label: {
            QuietExpandRowFace(entry: entry, isOpen: isOpen)
        }
        .buttonStyle(LHButton.press)
        .listRowBackground(colors.backgroundSecondary)
        .listRowInsets(EdgeInsets())
        .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.browseDividerInset }
        .accessibilityHint(isOpen ? "Hides details" : "Shows details")
        if isOpen {
            ZStack {
                NavigationLink { QuietRecordPage(entry: entry, style: .inline) } label: { EmptyView() }.opacity(0)
                QuietInlineDetail(entry: entry)
            }
            .listRowBackground(colors.backgroundSecondary)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden, edges: .top)
            .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.browseDividerInset }
        }
    }

    // C: the last 30 days as rows, earlier months folded into one row each.
    @ViewBuilder
    private var recentThenMonths: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: entries.first?.date ?? Date())!
        let recent = entries.filter { $0.date >= cutoff }
        let earlier = RecordsLogic.monthSections(entries.filter { $0.date < cutoff })
        Section {
            ForEach(recent) { pushRow($0) }
        } header: {
            LHSectionHeader("Last 30 days \u{00B7} \(qHours(recent.reduce(0) { $0 + $1.hours }))").textCase(nil)
        }
        Section {
            ForEach(Array(earlier.enumerated()), id: \.element.id) { index, month in
                ZStack {
                    NavigationLink { QuietMonthPage(monthOffset: index + 1) } label: { EmptyView() }.opacity(0)
                    LHRow.Browse(title: month.month.formatted(.dateTime.month(.wide)),
                                 meta: "\(month.entries.count) records",
                                 value: qHours(month.totalHours),
                                 systemImage: "calendar", tint: .neutral)
                }
                .listRowBackground(colors.backgroundSecondary)
                .listRowInsets(EdgeInsets())
                .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.browseDividerInset }
            }
        } header: {
            LHSectionHeader("Earlier in 2026").textCase(nil)
        }
    }
}

/// B's row: the same two lines, with a down chevron that turns up when open.
private struct QuietExpandRowFace: View {
    let entry: TimeEntry
    let isOpen: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let ax = typeSize.isAccessibilitySize
        HStack(alignment: ax ? .top : .center, spacing: 12) {
            if !ax { CategoryToolTile(category: entry.category, size: 36) }
            VStack(alignment: .leading, spacing: 2) {
                Text(qTitle(entry)).font(.body).foregroundStyle(colors.textPrimary).lineLimit(ax ? nil : 2)
                Text(qMeta(entry)).font(.subheadline).foregroundStyle(colors.textSecondary)
                    .lineLimit(ax ? nil : (typeSize >= .xxLarge ? 2 : 1))
                if ax { Text(qHours(entry.hours)).font(.subheadline.weight(.semibold)).fontDesign(.rounded) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !ax {
                Text(qHours(entry.hours)).font(.subheadline).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(colors.textSecondary)
            }
            LHChevron(systemName: "chevron.down")
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(LHRow.insets)
        .frame(minHeight: LHMetrics.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// B's open details: read-only lines under the title column, then "Open record".
private struct QuietInlineDetail: View {
    let entry: TimeEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let lines: [(String, String)] = [
            ("text.alignleft", entry.notes.replacingOccurrences(of: "\n", with: " ")),
            ("tray.and.arrow.down", qSourceLine(entry)),
            ("person", entry.participant == .spouse ? "Your spouse" : "You")
        ]
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: line.0).font(.footnote).foregroundStyle(colors.textSecondary)
                        .frame(width: 16).accessibilityHidden(true)
                    Text(line.1).font(.subheadline).foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 6) {
                Text("Open record").font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                LHChevron()
            }
            .padding(.top, 4)
        }
        .padding(.leading, typeSize.isAccessibilitySize ? 16 : LHRow.browseDividerInset)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
        .padding(.top, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the record")
    }
}

// MARK: C: one month as its own list

struct QuietMonthPage: View {
    let monthOffset: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let entries = QuietSeed.entries.sorted { $0.date > $1.date }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: entries.first?.date ?? Date())!
        let months = RecordsLogic.monthSections(entries.filter { $0.date < cutoff })
        let month = months[min(monthOffset - 1, months.count - 1)]
        List {
            Section {
                ForEach(month.entries) { entry in
                    ZStack {
                        NavigationLink { QuietRecordPage(entry: entry, style: .history) } label: { EmptyView() }.opacity(0)
                        QuietRowLabel(entry: entry)
                    }
                    .listRowBackground(colors.backgroundSecondary)
                    .listRowInsets(EdgeInsets())
                    .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.browseDividerInset }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .lhListGutter()
        .background { LHCanvas() }
        .lhTabScreen(month.month.formatted(.dateTime.month(.wide)),
                     subtitle: "\(qHours(month.totalHours)) in \(month.entries.count) records",
                     back: LHBackAction(label: "Records", identifier: "quiet.month.back") { dismiss() })
    }
}

// MARK: Record page

struct QuietRecordPage: View {
    enum Style { case history, inline }
    let entry: TimeEntry
    let style: Style
    var inlineOpen = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LHRowGroup {
                    HStack(spacing: 16) {
                        CategoryToolTile(category: entry.category, size: 56)
                        QuietHoursReadout(hours: entry.hours)
                        Spacer(minLength: 0)
                    }
                    .padding(LHMetrics.cardPadding)
                }
                LHRowGroup {
                    QuietFact(label: "Rental", value: QuietSeed.name(entry.propertyId))
                    LHDivider(leadingInset: 16)
                    QuietFact(label: "Kind of work", value: entry.category.inboxLabel)
                    LHDivider(leadingInset: 16)
                    QuietFact(label: "Who", value: entry.participant == .spouse ? "Spouse" : "Me")
                }
                if entry.notes.contains("\n") {
                    VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                        LHSectionHeader("Notes").padding(.horizontal, 4)
                        LHRowGroup {
                            Text(entry.notes)
                                .font(.body).foregroundStyle(colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(LHMetrics.cardPadding)
                        }
                    }
                }
                switch style {
                case .history:
                    LHRowGroup {
                        NavigationLink { QuietHistoryPage(entry: entry) } label: {
                            LHRow.Browse(title: "History", meta: qSourceLine(entry),
                                         systemImage: "clock.arrow.circlepath", tint: .neutral)
                        }
                        .buttonStyle(LHButton.press)
                    }
                case .inline:
                    LHRowGroup {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)) { open.toggle() }
                        } label: {
                            HStack(spacing: 12) {
                                LHRowGlyph(systemImage: "clock.arrow.circlepath", tint: .neutral)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Where it came from").font(.body).foregroundStyle(colors.textPrimary)
                                    Text(qSourceLine(entry)).font(.subheadline).foregroundStyle(colors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                LHChevron(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                            }
                            .padding(LHRow.insets)
                            .frame(minHeight: LHMetrics.rowMinHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(LHButton.press)
                        if open {
                            ForEach(Array(QuietHistory.facts(entry).enumerated()), id: \.offset) { _, fact in
                                LHDivider(leadingInset: 16)
                                QuietFact(label: fact.0, value: fact.1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
        }
        .background { LHCanvas() }
        .lhDetailScreen(qTitle(entry), subtitle: entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                        back: LHBackAction(label: "Back", identifier: "quiet.record.back") { dismiss() },
                        trailing: { LHHeaderAction(title: "Edit", identifier: "quiet.record.edit") {} })
        .hidesAppTabBar()
        .onAppear { open = inlineOpen }
    }
}

enum QuietHistory {
    static func stamp(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    static func facts(_ e: TimeEntry) -> [(String, String)] {
        var out: [(String, String)] = []
        if let found = e.detectedAt { out.append(("Found in your calendar", stamp(found))) }
        if let confirmed = e.confirmedAt { out.append(("Confirmed by you", stamp(confirmed))) }
        else { out.append(("Added", stamp(e.createdAt))) }
        if e.modifiedAt > e.createdAt.addingTimeInterval(60) { out.append(("Last changed", stamp(e.modifiedAt))) }
        return out
    }
}

/// A: the provenance as a timeline, one tap under the record. The PDF note lives here only.
struct QuietHistoryPage: View {
    let entry: TimeEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let symbols = ["calendar", "checkmark", "pencil"]
        let steps = QuietHistory.facts(entry).enumerated().map { i, f in
            LHTimelineStep(id: i, symbol: symbols[min(i, symbols.count - 1)], title: f.0, text: f.1, reached: true)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LHRowGroup {
                    LHTimeline(steps: steps).padding(LHMetrics.cardPadding)
                }
                LHFootnote("Your PDF shows these dates for every record.").padding(.horizontal, 4)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
        }
        .background { LHCanvas() }
        .lhDetailScreen("History", subtitle: qTitle(entry),
                        back: LHBackAction(label: "Back", identifier: "quiet.history.back") { dismiss() })
        .hidesAppTabBar()
    }
}

/// One read-only fact, the record page's FactRow (label left, value right; stacked at AX).
struct QuietFact: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let ax = typeSize.isAccessibilitySize
        let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(label).font(ax ? .subheadline : .body).foregroundStyle(colors.textSecondary)
            if !ax { Spacer(minLength: 12) }
            Text(value).font(.body).foregroundStyle(colors.textPrimary).multilineTextAlignment(ax ? .leading : .trailing)
        }
        .padding(LHRow.insets)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "2h 00m": the record page's readout (rounded, tabular, small unit letters).
struct QuietHoursReadout: View {
    let hours: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let total = LHFormat.minutes(hours) ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(total / 60)").font(.largeTitle.weight(.bold)).fontDesign(.rounded)
            Text("h").font(.title3).foregroundStyle(colors.textSecondary)
            Text(String(format: "%02d", total % 60)).font(.largeTitle.weight(.bold)).fontDesign(.rounded).padding(.leading, 6)
            Text("m").font(.title3).foregroundStyle(colors.textSecondary)
        }
        .monospacedDigit()
        .foregroundStyle(colors.textPrimary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hours")
        .accessibilityValue(LHFormat.spokenHours(hours))
    }
}
#endif
