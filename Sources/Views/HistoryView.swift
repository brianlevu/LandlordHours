import SwiftUI

/// Records: every confirmed hour, newest first, grouped by month (Mercury's restraint, Remote's
/// rows). The tab root, and also pushed from Today's "See all". docs/design/2.0-hifi-reference-spec.md §g.
struct HistoryView: View {
    /// True when pushed onto another NavigationStack (Today's "See all"); the tab root owns its own.
    @Environment(\.isPresented) private var isPushed
    /// Opens narrowed to one rental (Properties' "See all in Records").
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var filter = RecordsFilter(year: Calendar.current.component(.year, from: Date()))
    @State private var appliedInitialFilter = false
    @State private var entryToDelete: TimeEntry?
    @State private var showExport = false
    @FocusState private var searchFocused: Bool

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

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                searchField
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                chips
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if sections.isEmpty {
                Section {
                    BPEmptyState(
                        symbol: yearHasEntries ? "line.3.horizontal.decrease.circle" : "list.bullet.rectangle",
                        title: yearHasEntries ? "Nothing matches" : "No records for \(String(filter.year))",
                        message: yearHasEntries
                            ? "Try another property, source or person."
                            : "Hours you log or confirm show up here, by month."
                    )
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("records.empty")
                }
            } else {
                Section {
                    totalCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        BPSectionHeader(
                            title: section.month.formatted(.dateTime.month(.wide).year()),
                            trailing: BPHours.short(section.totalHours),
                            trailingAccessibility: "\(BPHours.spoken(section.totalHours)) logged"
                        )
                        .accessibilityIdentifier("records.month.\(section.month.formatted(.dateTime.year().month(.twoDigits)))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .contentMargins(.bottom, 104, for: .scrollContent)
        .background { LHMobileCanvas() }
        .onAppear {
            guard !appliedInitialFilter else { return }
            appliedInitialFilter = true
            if let initialPropertyId { filter.propertyId = initialPropertyId }
        }
        .navigationBarHidden(!showsBackButton)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsBackButton ? .visible : .hidden, for: .navigationBar)
        .alert("Delete this record?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete { viewModel.deleteTimeEntry(entry) }
                entryToDelete = nil
            }
        } message: {
            Text("It comes off your hours and your export. This can't be undone.")
        }
        .sheet(isPresented: $showExport) {
            ExportPDFView(year: filter.year)
        }
        .accessibilityIdentifier("records.screen")
    }

    // MARK: Header

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            BPScreenTitle(text: "Records")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Button {
                // A free user sees the Export page as a locked preview (WP-P).
                showExport = true
            } label: {
                BPCapsuleButtonLabel(title: "Export", symbol: nil)
            }
            .buttonStyle(.lhPressable)
            .accessibilityLabel("Export records")
            .accessibilityIdentifier("records.export")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colors.textSecondary)
                .accessibilityHidden(true)
            TextField("", text: $filter.searchText, prompt: Text("Search records").foregroundStyle(colors.textTertiary))
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search records")
                .accessibilityIdentifier("records.search")
            if !filter.searchText.isEmpty {
                Button {
                    filter.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colors.textTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(colors.border, lineWidth: 1))
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Year", selection: $filter.year) {
                        ForEach(RecordsLogic.availableYears(viewModel.timeEntries), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } label: {
                    BPFilterChip(title: String(filter.year), isActive: true)
                }
                .accessibilityLabel("Year, \(String(filter.year))")
                .accessibilityIdentifier("records.filter.year")

                Menu {
                    Picker("Property", selection: $filter.propertyId) {
                        Text("All properties").tag(UUID?.none)
                        ForEach(viewModel.properties) { property in
                            Text(property.name).tag(UUID?.some(property.id))
                        }
                    }
                } label: {
                    BPFilterChip(
                        title: filter.propertyId.flatMap { propertyNames[$0] } ?? "Property",
                        isActive: filter.propertyId != nil
                    )
                }
                .accessibilityLabel("Property filter, \(filter.propertyId.flatMap { propertyNames[$0] } ?? "all properties")")
                .accessibilityIdentifier("records.filter.property")

                Menu {
                    Picker("Source", selection: $filter.source) {
                        Text("All sources").tag(RecordSourceBadge?.none)
                        ForEach(RecordSourceBadge.filterOrder, id: \.self) { source in
                            Label(source.title, systemImage: source.symbol).tag(RecordSourceBadge?.some(source))
                        }
                    }
                } label: {
                    BPFilterChip(title: filter.source?.title ?? "Source", isActive: filter.source != nil)
                }
                .accessibilityLabel("Source filter, \(filter.source?.title ?? "all sources")")
                .accessibilityIdentifier("records.filter.source")

                if showsWhoFilter {
                    Menu {
                        Picker("Who", selection: $filter.participant) {
                            Text("Everyone").tag(Participant?.none)
                            Text("Me").tag(Participant?.some(.selfParticipant))
                            Text("Spouse").tag(Participant?.some(.spouse))
                        }
                    } label: {
                        BPFilterChip(title: whoTitle, isActive: filter.participant != nil)
                    }
                    .accessibilityLabel("Who filter, \(filter.participant == nil ? "everyone" : whoTitle)")
                    .accessibilityIdentifier("records.filter.who")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var whoTitle: String {
        switch filter.participant {
        case .none: return "Who"
        case .some(.selfParticipant): return "Me"
        case .some(.spouse): return "Spouse"
        }
    }

    // MARK: Total

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                Text(BPHours.short(totalHours))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entries.count == 1 ? "in 1 record" : "in \(entries.count) records")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(colors.draftingInk)
                    .accessibilityHidden(true)
                Text(RecordsLogic.totalLabel(goal: HouseGoal(goalManager.globalGoalType), tracksSpouseJointly: taxProfile.spouseTracking))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("records.totalLabel")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
        .lhMotion(AppAnimation.standard, value: totalHours)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(BPHours.spoken(totalHours)) in \(entries.count) records. \(RecordsLogic.totalLabel(goal: HouseGoal(goalManager.globalGoalType), tracksSpouseJointly: taxProfile.spouseTracking))")
        .accessibilityIdentifier("records.total")
    }

    // MARK: Row

    private func row(_ entry: TimeEntry) -> some View {
        let propertyName = propertyNames[entry.propertyId] ?? "No property"
        return ZStack {
            NavigationLink {
                TimeEntryDetailView(entry: entry)
            } label: {
                EmptyView()
            }
            .opacity(0)
            RecordRowView(entry: entry, propertyName: propertyName)
        }
        .listRowBackground(colors.backgroundSecondary)
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                entryToDelete = entry
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                entryToDelete = entry
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RecordRowView.accessibilityLabel(entry: entry, propertyName: propertyName))
        .accessibilityHint("Opens the record")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Delete") { entryToDelete = entry }
        .accessibilityIdentifier("records.row.\(entry.id.uuidString)")
    }
}

/// One record: the category's tool, what was done, the property on its own line, where it came
/// from, and the hours right-aligned in SF Pro Rounded tabular figures.
struct RecordRowView: View {
    let entry: TimeEntry
    let propertyName: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var badge: RecordSourceBadge { RecordSourceBadge(entry: entry) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryToolTile(category: entry.category, size: 36)
                .padding(.top, 2)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    details
                    trailing(alignment: .leading)
                }
            } else {
                details
                Spacer(minLength: 8)
                trailing(alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RecordsLogic.title(for: entry, propertyName: propertyName))
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .lineLimit(2)
            Text(propertyName)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            // Badges sit on one line while they fit, else stack. Fixed-size badges forced a row
            // wider than its cell at large text (the first row's hours clipped at the corner).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { badges }
                VStack(alignment: .leading, spacing: 4) { badges }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var badges: some View {
        Label(badge.title, systemImage: badge.symbol)
            .labelStyle(RecordBadgeLabelStyle(tint: badgeTint))
            .fixedSize()
        if entry.participant == .spouse {
            Label("Spouse", systemImage: "person.2")
                .labelStyle(RecordBadgeLabelStyle(tint: colors.rose))
                .fixedSize()
        }
        if !entry.countsForREPS {
            Label("Investor task", systemImage: "minus.circle")
                .labelStyle(RecordBadgeLabelStyle(tint: colors.textSecondary))
                .fixedSize()
        }
    }

    private func trailing(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(BPHours.short(entry.hours))
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private var badgeTint: Color {
        switch badge {
        case .calendarImport: return colors.informational
        case .suggested: return colors.draftingInk
        case .timer, .voice: return colors.timberInk
        case .receipt, .location, .shortcut, .gmail: return colors.informational
        case .manual, .other: return colors.textSecondary
        }
    }

    static func accessibilityLabel(entry: TimeEntry, propertyName: String) -> String {
        var parts = [
            RecordsLogic.title(for: entry, propertyName: propertyName),
            propertyName,
            BPHours.spoken(entry.hours),
            entry.date.formatted(.dateTime.month(.wide).day()),
            RecordSourceBadge(entry: entry).title
        ]
        if entry.participant == .spouse { parts.append("Spouse") }
        if !entry.countsForREPS { parts.append("Investor task, not counted") }
        return parts.joined(separator: ", ")
    }
}

/// Footnote badge: tinted glyph, secondary words (colour is never the only cue).
private struct RecordBadgeLabelStyle: LabelStyle {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            configuration.title
                .font(.footnote)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppViewModel())
}
