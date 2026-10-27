import SwiftUI

/// Records: every confirmed hour, newest first, grouped by month. The tab root, and also pushed
/// from Today's "See all". Standard §1.4 (browse row), §1.16 (chips), §H.5 (no house on Records:
/// a record is about an activity, so the category's tool is the ornament) and §1.27 AD9 (the same
/// list in every mode; no `Table`).
struct HistoryView: View {
    /// True when pushed onto another NavigationStack (Today's "See all"); the tab root owns its own.
    @Environment(\.isPresented) private var isPushed
    /// Opens narrowed to one rental (the rental page's "See all in Records").
    var initialPropertyId: UUID? = nil

    var body: some View {
        if isPushed {
            RecordsScreen(showsBackButton: true, initialPropertyId: initialPropertyId)
        } else {
            NavigationStack {
                RecordsScreen(showsBackButton: false, initialPropertyId: initialPropertyId)
            }
        }
    }
}

private struct RecordsScreen: View {
    let showsBackButton: Bool
    var initialPropertyId: UUID? = nil

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var filter = RecordsFilter(year: Calendar.current.component(.year, from: Date()))
    @State private var appliedInitialFilter = false
    @State private var entryToDelete: TimeEntry?
    @State private var showExport = false

    private var propertyNames: [UUID: String] {
        Dictionary(viewModel.properties.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var entries: [TimeEntry] {
        let names = propertyNames
        return RecordsLogic.filtered(viewModel.timeEntries, filter: filter, propertyName: { names[$0] })
    }

    private var sections: [RecordsMonthSection] { RecordsLogic.monthSections(entries) }
    private var totalHours: Double { entries.reduce(0) { $0 + $1.hours } }

    private var showsWhoFilter: Bool {
        taxProfile.spouseTracking || viewModel.timeEntries.contains { $0.participant == .spouse }
    }

    private var yearHasEntries: Bool {
        viewModel.timeEntries.contains { Calendar.current.component(.year, from: $0.date) == filter.year }
    }

    private var totalLabel: String {
        RecordsLogic.totalLabel(goal: goalManager.houseGoal, tracksSpouseJointly: taxProfile.spouseTracking)
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    title: RR.t("records.title", "Records"),
                    back: showsBackButton
                        ? (label: RR.t("records.back", "Back"), identifier: "records.back", action: { dismiss() })
                        : nil,
                    trailing: (symbol: "square.and.arrow.up", label: RR.t("records.export.label", "Export records"),
                               identifier: "records.export", action: { showExport = true })
                )
                .listRowInsets(EdgeInsets(top: 8, leading: LHMetrics.gutter, bottom: 0, trailing: LHMetrics.gutter))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                LHField(
                    RR.t("records.search.placeholder", "Search records"),
                    text: $filter.searchText,
                    accessibilityLabel: RR.t("records.search.label", "Search records"),
                    identifier: "records.search"
                )
                .listRowInsets(EdgeInsets(top: 4, leading: LHMetrics.gutter, bottom: 0, trailing: LHMetrics.gutter))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                chips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if sections.isEmpty {
                Section {
                    LHEmptyState(
                        systemImage: yearHasEntries ? "line.3.horizontal.decrease.circle" : "list.bullet.rectangle",
                        tone: .action,
                        headline: yearHasEntries
                            ? RR.t("records.empty.filtered.title", "Nothing matches")
                            : RR.t("records.empty.year.title", "No records for \(String(filter.year))"),
                        message: yearHasEntries
                            ? RR.t("records.empty.filtered.message", "Try another rental, source or person.")
                            : RR.t("records.empty.year.message", "Hours you log or confirm show up here, by month.")
                    )
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("records.empty")
                }
            } else {
                Section {
                    summary
                        .listRowInsets(EdgeInsets(top: 0, leading: LHMetrics.gutter, bottom: 0, trailing: LHMetrics.gutter))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        LHSectionHeader(RecordsLogic.monthHeader(section.month, hours: section.totalHours))
                            .textCase(nil)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel(RR.t("records.month.spoken", "\(section.month.formatted(.dateTime.month(.wide).year())), \(LHFormat.spokenHours(section.totalHours)) logged"))
                            .accessibilityIdentifier("records.month.\(section.month.formatted(.dateTime.year().month(.twoDigits)))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background { LHCanvas() }
        .onAppear {
            guard !appliedInitialFilter else { return }
            appliedInitialFilter = true
            if let initialPropertyId { filter.propertyId = initialPropertyId }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert(RR.t("records.delete.title", "Delete this record?"), isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button(RR.t("records.delete.cancel", "Cancel"), role: .cancel) { entryToDelete = nil }
            Button(RR.t("records.delete.confirm", "Delete"), role: .destructive) {
                if let entry = entryToDelete { viewModel.deleteTimeEntry(entry) }
                entryToDelete = nil
            }
        } message: {
            Text(RR.t("records.delete.message", "It comes off your hours and your export. This can\u{2019}t be undone."))
        }
        .sheet(isPresented: $showExport) {
            ExportPDFView(year: filter.year)
        }
        .accessibilityIdentifier("records.screen")
    }

    // MARK: Filters

    private var chips: some View {
        LHChipStrip {
            Menu {
                Picker(RR.t("records.filter.year", "Year"), selection: $filter.year) {
                    ForEach(RecordsLogic.availableYears(viewModel.timeEntries), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
            } label: {
                LHChip(String(filter.year), systemImage: "calendar", isSelected: false) {}
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(RR.t("records.filter.year.spoken", "Year, \(String(filter.year))"))
            .accessibilityIdentifier("records.filter.year")

            Menu {
                Picker(RR.t("records.filter.rental", "Rental"), selection: $filter.propertyId) {
                    Text(RR.t("records.filter.rental.all", "All rentals")).tag(UUID?.none)
                    ForEach(viewModel.properties) { property in
                        Text(property.name).tag(UUID?.some(property.id))
                    }
                }
            } label: {
                LHChip(rentalTitle, systemImage: "house", isSelected: filter.propertyId != nil) {}
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(RR.t("records.filter.rental.spoken", "Rental filter, \(rentalSpoken)"))
            .accessibilityIdentifier("records.filter.property")

            Menu {
                Picker(RR.t("records.filter.source", "Source"), selection: $filter.source) {
                    Text(RR.t("records.filter.source.all", "All sources")).tag(RecordSourceBadge?.none)
                    ForEach(RecordSourceBadge.filterOrder, id: \.self) { source in
                        Label(source.title, systemImage: source.symbol).tag(RecordSourceBadge?.some(source))
                    }
                }
            } label: {
                LHChip(filter.source?.title ?? RR.t("records.filter.source", "Source"),
                       systemImage: "tray.and.arrow.down", isSelected: filter.source != nil) {}
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(RR.t("records.filter.source.spoken", "Source filter, \(sourceSpoken)"))
            .accessibilityIdentifier("records.filter.source")

            if showsWhoFilter {
                Menu {
                    Picker(RR.t("records.filter.who", "Who"), selection: $filter.participant) {
                        Text(RR.t("records.filter.who.everyone", "Everyone")).tag(Participant?.none)
                        Text(RR.t("records.filter.who.me", "Me")).tag(Participant?.some(.selfParticipant))
                        Text(RR.t("records.filter.who.spouse", "Spouse")).tag(Participant?.some(.spouse))
                    }
                } label: {
                    LHChip(whoTitle, systemImage: "person", isSelected: filter.participant != nil) {}
                        .allowsHitTesting(false)
                }
                .accessibilityLabel(RR.t("records.filter.who.spoken", "Who filter, \(whoSpoken)"))
                .accessibilityIdentifier("records.filter.who")
            }
        }
    }

    private var rentalTitle: String {
        filter.propertyId.flatMap { propertyNames[$0] } ?? RR.t("records.filter.rental", "Rental")
    }

    private var rentalSpoken: String {
        filter.propertyId.flatMap { propertyNames[$0] } ?? RR.t("records.filter.rental.allSpoken", "all rentals")
    }

    private var sourceSpoken: String {
        filter.source?.title ?? RR.t("records.filter.source.allSpoken", "all sources")
    }

    private var whoTitle: String {
        switch filter.participant {
        case .none: return RR.t("records.filter.who", "Who")
        case .some(.selfParticipant): return RR.t("records.filter.who.me", "Me")
        case .some(.spouse): return RR.t("records.filter.who.spouse", "Spouse")
        }
    }

    private var whoSpoken: String {
        filter.participant == nil ? RR.t("records.filter.who.everyoneSpoken", "everyone") : whoTitle
    }

    // MARK: Total

    /// The year's total as one line (the hours large, the record count beside it) with the one
    /// sentence that says what it is under it, so "All logged hours" is never read as the number on
    /// Today. A line rather than a Summary card: Records keeps its rows above the fold (D3).
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { totalValue; totalCount }
                VStack(alignment: .leading, spacing: 2) { totalValue; totalCount }
            }
            Text(totalLabel)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("records.totalLabel")
        }
        .padding(.horizontal, 4)
        .lhMotion(AppAnimation.standard, value: totalHours)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("records.total")
    }

    private var totalValue: some View {
        Text(LHFormat.hours(totalHours))
            .font(.title.weight(.bold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
            .contentTransition(.numericText())
            .lineLimit(1)
            .accessibilityLabel(RR.t("records.total.spoken", "\(LHFormat.spokenHours(totalHours)) in \(entries.count) records"))
    }

    private var totalCount: some View {
        Text(entries.count == 1
             ? RR.t("records.total.one", "in 1 record")
             : RR.t("records.total.many", "in \(entries.count) records"))
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
            .accessibilityHidden(true)
    }

    // MARK: Row

    private func row(_ entry: TimeEntry) -> some View {
        let propertyName = propertyNames[entry.propertyId] ?? RR.t("records.noRental", "No rental")
        return ZStack {
            NavigationLink {
                TimeEntryDetailView(entry: entry)
            } label: {
                EmptyView()
            }
            .opacity(0)
            RecordRowContent(
                title: RecordsLogic.title(for: entry, propertyName: propertyName),
                meta: RecordsLogic.meta(for: entry, propertyName: propertyName),
                value: LHFormat.hours(entry.hours),
                category: entry.category
            )
        }
        .listRowBackground(colors.backgroundSecondary)
        .listRowInsets(EdgeInsets())
        .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.browseDividerInset }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                entryToDelete = entry
            } label: {
                Label(RR.t("records.delete.confirm", "Delete"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                entryToDelete = entry
            } label: {
                Label(RR.t("records.delete.confirm", "Delete"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecordsLogic.spokenRow(entry, propertyName: propertyName))
        .accessibilityHint(RR.t("records.row.hint", "Opens the record"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: RR.t("records.delete.confirm", "Delete")) { entryToDelete = entry }
        .accessibilityIdentifier("records.row.\(entry.id.uuidString)")
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppViewModel())
}


/// One Records row. Same look as `LHRow.Browse` at regular sizes. At accessibility sizes the tile and
/// chevron go and the hours move onto the meta line, so the title gets the full width (no mid-word
/// breaks); the meta line wraps at AX (standard 1.4) so the rental name is never cut.
private struct RecordRowContent: View {
    let title: String
    let meta: String
    let value: String
    let category: ActivityCategory

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RR.t("records.row.metaWithHours", "\(value) \u{00B7} \(meta)"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .contentShape(Rectangle())
        } else {
            LHRow.Browse(title: title, meta: meta, value: value) {
                CategoryToolTile(category: category, size: 36)
            }
        }
    }
}
