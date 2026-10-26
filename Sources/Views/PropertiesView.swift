import SwiftUI

// MARK: - Rentals (v2, plan package F, row 10)
//
// The Rentals tab root, on the plain canvas (§H.4: lists are paper; the dusk page is for the house).
// Top to bottom: "Rentals" in Fraunces 34 (`LHScreenTitle(.collection)`) with "3 rentals · 312h this
// year" under it (hours only: "All rentals" never shows a goal, summed or otherwise, §H.1 H10) ·
// a search field from nine rentals · one grouped container of `LHRow.Browse` rows: the 44pt
// house-only thumbnail (`LHThumb.row`, lit when hours were logged there today), the name, the
// stage in words and the kind of stay, the hours and a chevron. One ornament per row (§1.4): no
// seal beside the house. "Add rental" is the toolbar's trailing item and the empty state's action
// (§1.25: never a "+" in the title row). At the free limit, the one `.row` locked preview.
//
// The rental page (`PropertyDetailView`, `Properties/RentalPage.swift`) pushes; the edit sheet
// (`PropertyEditSheet`, `Properties/RentalEditSheet.swift`) is a focused `.large` sheet.

enum PropertyRoute: Hashable {
    case detail(UUID)
    case records(UUID)
    case record(UUID)
}

enum PropertyEditorMode: Identifiable, Equatable {
    case add
    case edit(RentalProperty, confirmDelete: Bool = false)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let p, _): return "edit-\(p.id.uuidString)"
        }
    }
}

struct PropertiesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var subscription = SubscriptionManager.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutBand) private var band
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var path = NavigationPath()
    @State private var editor: PropertyEditorMode?
    @State private var paywall: ProPaywallRequest?
    @State private var deletion: PropertyDeletion?
    /// Set by the edit sheet's "Delete rental"; the alert asks once the sheet is gone.
    @State private var pendingDeletion: PropertyDeletion?
    @State private var query = ""
#if DEBUG
    @State private var didHandleDebugLaunchSurface = false
    @State private var debugLoading = ProcessInfo.processInfo.arguments.contains("-LHPropertiesLoading")
#endif

    private var isLoading: Bool {
#if DEBUG
        if debugLoading { return true }
#endif
        // Rentals already on this iPhone show at once; only an empty list waits for the first
        // iCloud pull, so a returning owner never sees "Add your first rental" by mistake.
        return viewModel.isAwaitingInitialPull && viewModel.properties.isEmpty
    }

    private var atLimit: Bool { viewModel.propertiesAtFreeLimit }

    private var rows: [RentalRowModel] {
        let all = viewModel.rentalRows()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let matches = Set(viewModel.properties.filter { p in
            ([p.name, p.address] + p.aliases).contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.map(\.id))
        return all.filter { matches.contains($0.id) }
    }

    /// "3 rentals · 312h this year". The hours across rentals, never a goal across them.
    private var subtitle: String? {
        guard !isLoading, !viewModel.properties.isEmpty else { return nil }
        let whole = viewModel.rentalRows().reduce(0) { $0 + $1.wholeHours }
        return RentalsText.subtitle(count: viewModel.properties.count, wholeHours: whole)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LHScreenTitle(RentalsText.title, subtitle: subtitle, style: .collection)
                            .accessibilityIdentifier("properties.title")
                        if viewModel.properties.count > 8 && !isLoading {
                            searchField
                                .padding(.top, 8)
                        }
                        Group {
                            if isLoading {
                                loadingGroup
                            } else if viewModel.properties.isEmpty {
                                emptyGroup
                            } else {
                                listGroup
                            }
                        }
                        .padding(.top, 16)
                        Color.clear.frame(height: 24).id("properties.bottom")
                    }
                    .padding(.horizontal, LHMetrics.gutter(for: band))
                    .frame(maxWidth: band == .a ? .infinity : LHMetrics.readingColumn)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .background { LHCanvas() }
#if DEBUG
                .onAppear { handleDebugLaunchSurfaceIfNeeded(proxy: proxy) }
#endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.properties.isEmpty && !isLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(RentalsText.addRental, action: openAddProperty)
                            .accessibilityIdentifier("properties.add")
                    }
                }
            }
            .navigationDestination(for: PropertyRoute.self) { route in
                switch route {
                case .detail(let id):
                    PropertyDetailView(propertyId: id, onEdit: { property in editor = .edit(property) })
                case .records(let id):
                    HistoryView(initialPropertyId: id)
                case .record(let id):
                    if let entry = viewModel.timeEntries.first(where: { $0.id == id }) {
                        TimeEntryDetailView(entry: entry)
                    }
                }
            }
        }
        .sheet(item: $editor, onDismiss: {
            if let pendingDeletion { deletion = pendingDeletion }
            pendingDeletion = nil
        }) { mode in
            PropertyEditSheet(mode: mode, onDelete: { property in
                pendingDeletion = PropertyDeletion.make(for: property, in: viewModel)
            })
            .lhSheetPresentation(.focused)
        }
        // The one paywall, about adding a rental; after a purchase, Add rental opens.
        .proPaywall($paywall)
        .alert(deletion?.title ?? "", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button(RentalsText.delete, role: .destructive) {
                if let deletion {
                    path = NavigationPath()
                    deletion.perform(in: viewModel)
                }
                deletion = nil
            }
            Button(RentalsText.keep, role: .cancel) { deletion = nil }
        } message: {
            Text(deletion?.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddProperty)) { _ in
            openAddProperty()
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colors.textSecondary)
                .accessibilityHidden(true)
            TextField(RentalsText.searchPrompt, text: $query, prompt: Text(RentalsText.searchPrompt).foregroundStyle(colors.textTertiary))
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .submitLabel(.search)
                .accessibilityIdentifier("properties.search")
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: LHMetrics.minTap)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
    }

    // MARK: List

    private var listGroup: some View {
        let shown = rows
        return LHRowGroup {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                RentalRow(row: row) { path.append(PropertyRoute.detail(row.id)) }
                    .contextMenu {
                        Button(RentalsText.open, systemImage: "house") { path.append(PropertyRoute.detail(row.id)) }
                        Button(RentalsText.edit, systemImage: "pencil") { edit(row.id) }
                        Button(RentalsText.delete, systemImage: "trash", role: .destructive) { delete(row.id) }
                    }
                    .accessibilityAction(named: Text(RentalsText.edit)) { edit(row.id) }
                    .accessibilityAction(named: Text(RentalsText.delete)) { delete(row.id) }
                    .accessibilityIdentifier("properties.row.\(index)")
                if index < shown.count - 1 || atLimit {
                    LHDivider(leadingInset: RentalRow.dividerInset)
                }
            }
            if shown.isEmpty {
                Text(RentalsText.noMatch(query))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: LHMetrics.rowTargetHeight)
                    .padding(.horizontal, 16)
            }
            if atLimit {
                PropertiesAtLimitRow(firstPropertyName: viewModel.properties.first?.name, onUnlock: { openPaywall() })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.list")
    }

    private var emptyGroup: some View {
        LHRowGroup {
            LHEmptyState(systemImage: "house", tone: .action, headline: RentalsText.emptyHeadline,
                         message: RentalsText.emptyMessage, actionTitle: RentalsText.addRental, action: openAddProperty)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.empty")
    }

    /// Loading never blocks and never spins: placeholder bars where the names and numbers go, and a
    /// soft square where each thumbnail goes.
    private var loadingGroup: some View {
        LHRowGroup {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                        .fill(colors.backgroundTertiary)
                        .frame(width: CraftHeroSize.thumbnailRow, height: CraftHeroSize.thumbnailRow)
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceholderBar(width: i == 1 ? 150 : 120, height: 14)
                        PlaceholderBar(width: 170, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(LHRow.insets)
                .frame(minHeight: LHMetrics.rowTargetHeight)
                if i < 2 { LHDivider(leadingInset: RentalRow.dividerInset) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RentalsText.loading)
        .accessibilityIdentifier("properties.loading")
    }

    // MARK: Actions

    private func edit(_ id: UUID) {
        if let p = viewModel.properties.first(where: { $0.id == id }) { editor = .edit(p) }
    }

    private func delete(_ id: UUID) {
        if let p = viewModel.properties.first(where: { $0.id == id }) { deletion = PropertyDeletion.make(for: p, in: viewModel) }
    }

    private func openAddProperty() {
        if viewModel.canAddProperty() {
            editor = .add
        } else {
            openPaywall()
        }
    }

    private func openPaywall() {
        paywall = ProPaywallRequest(context: ProGate.context(for: .propertiesLimit), entry: .propertiesLimit, onUnlocked: {
            editor = .add
        })
    }

#if DEBUG
    /// -LHOpenAddProperty · -LHOpenFirstPropertyDetail · -LHOpenFirstPropertyDetailLower ·
    /// -LHOpenFirstPropertyEdit · -LHOpenFirstPropertyDelete · -LHOpenSecondPropertyDetail ·
    /// -LHOpenPropertyDetail <index> · -LHPropertiesScrollBottom · -LHPropertiesQuery <text>
    private func handleDebugLaunchSurfaceIfNeeded(proxy: ScrollViewProxy) {
        guard !didHandleDebugLaunchSurface else { return }
        didHandleDebugLaunchSurface = true
        let args = ProcessInfo.processInfo.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let i = args.firstIndex(of: "-LHPropertiesQuery"), args.indices.contains(i + 1) {
                query = args[i + 1]
            }
            if args.contains("-LHPropertiesScrollBottom") {
                proxy.scrollTo("properties.bottom", anchor: .bottom)
            }
            if args.contains("-LHOpenAddProperty") {
                openAddProperty()
            } else if let first = viewModel.properties.first {
                if let i = args.firstIndex(of: "-LHOpenPropertyDetail"), args.indices.contains(i + 1),
                   let n = Int(args[i + 1]), viewModel.properties.indices.contains(n) {
                    path.append(PropertyRoute.detail(viewModel.properties[n].id))
                } else if args.contains("-LHOpenFirstPropertyDetail") || args.contains("-LHOpenFirstPropertyDetailLower") {
                    path.append(PropertyRoute.detail(first.id))
                } else if args.contains("-LHOpenSecondPropertyDetail"), viewModel.properties.count > 1 {
                    path.append(PropertyRoute.detail(viewModel.properties[1].id))
                } else if args.contains("-LHOpenFirstPropertyEdit") {
                    editor = .edit(first)
                } else if args.contains("-LHOpenFirstPropertyDelete") {
                    editor = .edit(first, confirmDelete: true)
                }
            }
        }
    }
#endif
}

// MARK: - Row

/// One rental: the house-only thumbnail at 44 (§H.5), the name, "Frame going up · Long stays", the
/// hours and a chevron. 64pt at default (§1.4: 56–64).
struct RentalRow: View {
    let row: RentalRowModel
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    /// The divider starts at the text column: row inset 16 + thumbnail 44 + gap 12.
    static let dividerInset: CGFloat = 16 + CraftHeroSize.thumbnailRow + 12

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxLarge {
                large
            } else {
                LHRow.Browse(title: row.name, meta: row.meta, value: row.value, action: action) {
                    LHThumb.row(row.stage, lit: row.lit)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .hoverEffect(.highlight)
    }

    /// From XXL, `LHRow.Browse` keeps one line each for the name and the stage beside the hours and
    /// the chevron, so "Roof on, siding going up" and long names cut mid-word. Here the row keeps
    /// Browse's grid (insets 16/10, 44 thumbnail, gap 12, `.body` / `.subheadline`) and gives the
    /// words the width: the name and "stage · hours" wrap at words; the chevron stays until AX.
    private var large: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let ax = dynamicTypeSize.isAccessibilitySize
        return Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                LHThumb.row(row.stage, lit: row.lit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(ax ? nil : 2)
                    Text(RentalsText.axMeta(stage: row.meta, hours: row.value))
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !ax {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(colors.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(LHButton.press)
    }
}

// MARK: - At the free limit

/// The Rentals at-limit lock: a ghost "Your next rental" row (the started house, unlit) under THE
/// `.row` locked preview (ProGate, entry `.propertiesLimit`), saying what stays active, with one
/// Unlock Pro that opens the `.secondProperty` paywall.
struct PropertiesAtLimitRow: View {
    let firstPropertyName: String?
    var onUnlock: () -> Void

    var body: some View {
        LockedPreview(
            size: .row,
            entry: .propertiesLimit,
            line: ProGate.lockLine(.propertiesLimit),
            keeps: ProGate.keepsLine(.propertiesLimit, firstPropertyName: firstPropertyName),
            onUnlock: onUnlock
        ) {
            LHRow.Browse(title: RentalsText.nextRental, meta: RentalsText.hoursThisYear(0), showsChevron: false) {
                LHThumb.row(.started, lit: false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.lockRow")
    }
}

#Preview {
    PropertiesView()
        .environmentObject(AppViewModel())
}
