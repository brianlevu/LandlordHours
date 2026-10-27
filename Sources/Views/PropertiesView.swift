import SwiftUI

// MARK: - Rentals (v2, plan package F, row 10)
//
// The Rentals tab root, on the plain canvas (§H.4: lists are paper; the dusk page is for the house).
// Top to bottom: "Rentals" in Fraunces 34 (`LHScreenTitle(.collection)`) with "3 rentals · 312h this
// year" under it (hours only: "All rentals" never shows a goal, summed or otherwise, §H.1 H10) ·
// a search field from nine rentals · the two-column house gallery (`RentalGallery`, Brian
// 2026-10-26, standard §1.4 exception): each tile is the house at its stage (lit when hours were
// logged there today), the name, "88 of 100h" and one pace line; one column from XXL. With exactly
// one rental the tab opens straight on that rental's page. "Add rental" is the toolbar's trailing
// item (leading on the single rental's page, which owns the trailing Edit) and the empty state's
// action (§1.25: never a "+" in the title row). At the free limit, the one `.row` locked preview.
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

    private var tiles: [RentalTileModel] {
        let all = viewModel.rentalTiles()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let matches = Set(viewModel.properties.filter { p in
            ([p.name, p.address] + p.aliases).contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.map(\.id))
        return all.filter { matches.contains($0.id) }
    }

    /// Exactly one rental: the tab is that rental's page.
    private var singleRentalID: UUID? {
        guard !isLoading, viewModel.properties.count == 1 else { return nil }
        return viewModel.properties.first?.id
    }

    /// "3 rentals · 312h this year". The hours across rentals, never a goal across them.
    private var subtitle: String? {
        guard !isLoading, !viewModel.properties.isEmpty else { return nil }
        let whole = viewModel.rentalRows().reduce(0) { $0 + $1.wholeHours }
        return RentalsText.subtitle(count: viewModel.properties.count, wholeHours: whole)
    }

    var body: some View {
        NavigationStack(path: $path) {
            rootContent
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

    @ViewBuilder private var rootContent: some View {
        if let id = singleRentalID {
            PropertyDetailView(propertyId: id, onEdit: { property in editor = .edit(property) })
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(RentalsText.addRental, action: openAddProperty)
                            .accessibilityIdentifier("properties.add")
                    }
                }
#if DEBUG
                .onAppear { handleDebugLaunchSurfaceIfNeeded(proxy: nil) }
#endif
        } else {
            galleryRoot
        }
    }

    private var galleryRoot: some View {
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
                            galleryGroup
                        }
                    }
                    .padding(.top, 16)
                    Color.clear.frame(height: 0).id("properties.bottom")
                }
                .padding(.horizontal, LHMetrics.gutter(for: band))
                .frame(maxWidth: band == .a ? .infinity : LHMetrics.readingColumn)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            // A hard edge under the bar, as on the rental page: tiles scrolling up never read
            // through the "Add rental" button.
            .modifier(HardTopScrollEdge())
            .scrollDismissesKeyboard(.immediately)
            // Clear of the floating tab bar when scrolled to the end (same inset as Records, Settings).
            .contentMargins(.bottom, 104, for: .scrollContent)
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

    private var galleryGroup: some View {
        let shown = tiles
        return VStack(alignment: .leading, spacing: RentalGallery.spacing) {
            RentalGallery(tiles: shown,
                          open: { path.append(PropertyRoute.detail($0)) },
                          edit: { edit($0) },
                          delete: { delete($0) })
            if shown.isEmpty {
                Text(RentalsText.noMatch(query))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: LHMetrics.rowTargetHeight)
                    .padding(.horizontal, 16)
            }
            if atLimit {
                LHRowGroup {
                    PropertiesAtLimitRow(firstPropertyName: viewModel.properties.first?.name, onUnlock: { openPaywall() })
                }
            }
        }
    }

    private var emptyGroup: some View {
        LHRowGroup {
            LHEmptyState(systemImage: "house", tone: .action, headline: RentalsText.emptyHeadline,
                         message: RentalsText.emptyMessage, actionTitle: RentalsText.addRental, action: openAddProperty)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.empty")
    }

    /// Loading never blocks and never spins: a soft house shape and placeholder bars where each
    /// tile's art and words go.
    private var loadingGroup: some View {
        let columns = dynamicTypeSize >= .xxLarge
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: RentalGallery.spacing), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: RentalGallery.spacing) {
            ForEach(0..<4, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                        .fill(colors.backgroundTertiary)
                        .aspectRatio(1 / RentalTileHouse.heightRatio, contentMode: .fit)
                    PlaceholderBar(width: i % 2 == 0 ? 96 : 76, height: 14)
                    PlaceholderBar(width: 64, height: 10)
                    PlaceholderBar(width: 80, height: 10)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
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
    private func handleDebugLaunchSurfaceIfNeeded(proxy: ScrollViewProxy?) {
        guard !didHandleDebugLaunchSurface else { return }
        didHandleDebugLaunchSurface = true
        let args = ProcessInfo.processInfo.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let i = args.firstIndex(of: "-LHPropertiesQuery"), args.indices.contains(i + 1) {
                query = args[i + 1]
            }
            if args.contains("-LHPropertiesScrollBottom") {
                proxy?.scrollTo("properties.bottom", anchor: .bottom)
            }
            if args.contains("-LHOpenAddProperty") {
                openAddProperty()
            } else if let first = viewModel.properties.first {
                // With one rental the page is already the root: nothing to push.
                if singleRentalID != nil,
                   args.contains("-LHOpenFirstPropertyDetail") || args.contains("-LHOpenFirstPropertyDetailLower")
                    || args.contains("-LHOpenSecondPropertyDetail") || args.contains("-LHOpenPropertyDetail") {
                } else if let i = args.firstIndex(of: "-LHOpenPropertyDetail"), args.indices.contains(i + 1),
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
