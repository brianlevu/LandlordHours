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
            Group {
#if DEBUG
                // proto/rentals-layouts: with exactly one rental, the gallery opens on its page.
                if RentalsMockLayout.current == .gallery, viewModel.properties.count == 1, let only = viewModel.properties.first, !isLoading {
                    PropertyDetailView(propertyId: only.id, onEdit: { property in editor = .edit(property) })
                } else {
                    listRoot
                }
#else
                listRoot
#endif
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

    private var listRoot: some View {
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
                            contentGroup
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

    @ViewBuilder private var contentGroup: some View {
#if DEBUG
        switch RentalsMockLayout.current {
        case .gallery: RentalsGalleryMock(rows: rows, info: mockInfo, open: { path.append(PropertyRoute.detail($0)) })
        case .cards: RentalsCardsMock(rows: rows, info: mockInfo, open: { path.append(PropertyRoute.detail($0)) })
        case .list, .none: listGroup
        }
#else
        listGroup
#endif
    }

#if DEBUG
    private var mockInfo: [UUID: RentalMockInfo] {
        Dictionary(uniqueKeysWithValues: viewModel.properties.map { ($0.id, RentalMockInfo.make(for: $0, in: viewModel)) })
    }
#endif

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

#if DEBUG
// MARK: - proto/rentals-layouts (throwaway mock, DEBUG only)
//
// `-LHRentalsLayout gallery|cards|list` swaps the Rentals list for one of three layouts so the
// owner can compare them side by side. Not production: the gallery and the cards are a deliberate
// exception to the standard's "rows, not cards" rule (§1.4), and "to confirm" counts are mock data.

enum RentalsMockLayout: String {
    case gallery, cards, list

    static let current: RentalsMockLayout? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHRentalsLayout"), args.indices.contains(i + 1) else { return nil }
        return RentalsMockLayout(rawValue: args[i + 1])
    }()
}

struct RentalMockInfo {
    enum Tone { case behind, positive, neutral }
    let goal: Int
    let pace: String
    let tone: Tone
    let toConfirm: Int
    let lastLogged: Date?

    /// Mock pending counts by name (the real Inbox has no per-rental count yet).
    static let mockToConfirm: [String: Int] = ["Santa Ray Ave": 2, "Pine Cabin": 1, "Cedar Triplex": 3,
                                               "The Arroyo Seco Schoolhouse Lofts, Unit 4B": 1]

    @MainActor
    static func make(for property: RentalProperty, in vm: AppViewModel, now: Date = Date()) -> RentalMockInfo {
        let goal = vm.houseGoal
        let figures = vm.rentalPageFigures(for: property, now: now)
        let hours = vm.propertyCountableHours(property.id, goal: goal, year: Calendar.current.component(.year, from: now))
        let target = goal.targetHours
        let pace: String
        let tone: Tone
        if target > 0, hours >= target {
            pace = String(localized: "rentals.mock.done", defaultValue: "Done for the year", table: "Rentals"); tone = .positive
        } else if hours <= 0 {
            pace = String(localized: "rentals.mock.none", defaultValue: "No hours yet", table: "Rentals"); tone = .neutral
        } else if let lead = figures.pace.lead {
            pace = lead.hasSuffix(".") ? String(lead.dropLast()) : lead
            tone = figures.pace.tone == .behind ? .behind : .positive
        } else {
            let weekly = max(1, Int((max(target - hours, 0) / TodayPaceCards.weeksLeft(now: now)).rounded(.up)))
            pace = String(localized: "rentals.mock.weekly", defaultValue: "\(weekly)h a week to go", table: "Rentals"); tone = .neutral
        }
        let last = vm.timeEntries.filter { $0.propertyId == property.id }.map(\.date).max()
        return RentalMockInfo(goal: Int(target.rounded()), pace: pace, tone: tone,
                              toConfirm: mockToConfirm[property.name] ?? 0, lastLogged: last)
    }

    func ink(_ colors: AdaptiveColors) -> Color {
        switch tone {
        case .behind: return colors.behind
        case .positive: return colors.positive
        case .neutral: return colors.textSecondary
        }
    }

    static func ofGoal(_ whole: Int, _ goal: Int) -> String {
        String(localized: "rentals.mock.ofGoal", defaultValue: "\(whole) of \(goal)h", table: "Rentals")
    }

    func lastLoggedText(now: Date = Date()) -> String? {
        guard let lastLogged else { return nil }
        if Calendar.current.isDateInToday(lastLogged) {
            return String(localized: "rentals.mock.loggedToday", defaultValue: "Logged today", table: "Rentals")
        }
        let d = lastLogged.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "rentals.mock.lastLogged", defaultValue: "Last logged \(d)", table: "Rentals")
    }

    var toConfirmText: String {
        String(localized: "rentals.mock.toConfirm", defaultValue: "\(toConfirm) to confirm", table: "Rentals")
    }
}

/// The house still (with its lot), scaled up from the ground line like `LHThumb` but not clipped
/// to its own square: the tile's inner surface does the cropping, so the lot is cut only at the
/// surface's edge (LHThumb's interim crop draws a hard lot edge inside the tile).
struct RentalMockHouse: View {
    let stage: CraftStage
    let lit: Bool
    let side: CGFloat
    let scale: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(stage.assetName(lit: true))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
            .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: CraftStage.groundLine))
            .offset(y: side * (1 - CraftStage.groundLine))
            .colorMultiply(Color(white: CraftMotion.clipDim(windowsLit: lit, dark: colorScheme == .dark)))
            .accessibilityLabel(CraftHouseView.accessibilityLabel(stage: stage, lit: lit))
    }
}

/// Option 1: a two-column gallery of house tiles.
struct RentalsGalleryMock: View {
    let rows: [RentalRowModel]
    let info: [UUID: RentalMockInfo]
    var open: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = typeSize >= .accessibility1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if let i = info[row.id] {
                    RentalGalleryTile(row: row, info: i) { open(row.id) }
                        .accessibilityIdentifier("properties.tile.\(index)")
                }
            }
        }
        .accessibilityIdentifier("properties.gallery")
    }
}

struct RentalGalleryTile: View {
    let row: RentalRowModel
    let info: RentalMockInfo
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geo in
                    RentalMockHouse(stage: row.stage, lit: row.lit, side: geo.size.width * 0.86, scale: 1.3)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                }
                .aspectRatio(1.1, contentMode: .fit)
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(RentalMockInfo.ofGoal(row.wholeHours, info.goal))
                        .font(.subheadline.monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(colors.textSecondary)
                    Text(info.pace)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(info.ink(colors))
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                        .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(LHButton.press)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(RentalMockInfo.ofGoal(row.wholeHours, info.goal)), \(info.pace)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Option 2: one big card per rental.
struct RentalsCardsMock: View {
    let rows: [RentalRowModel]
    let info: [UUID: RentalMockInfo]
    var open: (UUID) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if let i = info[row.id] {
                    RentalBigCard(row: row, info: i) { open(row.id) }
                        .accessibilityIdentifier("properties.card.\(index)")
                }
            }
        }
        .accessibilityIdentifier("properties.cards")
    }
}

struct RentalBigCard: View {
    let row: RentalRowModel
    let info: RentalMockInfo
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RentalMockHouse(stage: row.stage, lit: row.lit, side: 200, scale: 1.3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 196, alignment: .bottom)
                    .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name).font(.title3.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 8)
                            hoursText
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.title3.weight(.semibold))
                            hoursText
                        }
                    }
                    .foregroundStyle(colors.textPrimary)
                    Text(info.pace)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(info.ink(colors))
                    HStack(spacing: 8) {
                        if info.toConfirm > 0 { LHTag(info.toConfirmText, tone: .caution) }
                        if let last = info.lastLoggedText() {
                            Text(last).font(.footnote).foregroundStyle(colors.textSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .multilineTextAlignment(.leading)
            }
            .padding(LHMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                        .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(LHButton.press)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(RentalMockInfo.ofGoal(row.wholeHours, info.goal)), \(info.pace)")
        .accessibilityAddTraits(.isButton)
    }

    private var hoursText: some View {
        Text(RentalMockInfo.ofGoal(row.wholeHours, info.goal))
            .font(.body.monospacedDigit())
            .fontDesign(.rounded)
            .foregroundStyle(colors.textSecondary)
    }
}
#endif
