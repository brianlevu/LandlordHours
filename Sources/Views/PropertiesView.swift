import SwiftUI
import MapKit
import CoreLocation

// MARK: - Properties (2.0 redesign, approved r4)
//
// List (tab root), detail (pushed) and add/edit (.large sheet). Spec: redesign-specs.md §4;
// approved sandbox: DesignSandbox/Screens2/S2Properties.swift at fc0cf6b. Numbers come from
// PropertyFigures.swift (per-rental countable hours, Today's stage mapping, the free limit).

enum PropertyRoute: Hashable {
    case detail(UUID)
    case records(UUID)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var path = NavigationPath()
    @State private var editor: PropertyEditorMode?
    @State private var showingPaywall = false
    @State private var deletion: PropertyDeletion?
    @State private var infoShown = false
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
        // iCloud pull (WP-L), so a returning owner never sees "Add your first property" by mistake.
        return viewModel.isAwaitingInitialPull && viewModel.properties.isEmpty
    }

    private var goal: HouseGoal { viewModel.houseGoal }
    private var perPropertyGoal: Bool { viewModel.propertyGoalIsPerProperty }
    private var atLimit: Bool { viewModel.propertiesAtFreeLimit }

    private var shownProperties: [RentalProperty] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return viewModel.properties }
        return viewModel.properties.filter { p in
            ([p.name, p.address] + p.aliases).contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    var body: some View {
        // Observing SubscriptionManager, TaxProfileManager and GoalManager re-renders the list
        // when Pro, the goal or spouse tracking change.
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if infoShown { infoNote }
                        if viewModel.properties.count > 8 && !isLoading { searchField }
                        if isLoading {
                            loadingCard
                        } else if viewModel.properties.isEmpty {
                            emptyCard
                        } else {
                            listCard
                        }
                        // Room for the floating tab bar; the scroll-to-bottom anchor is its foot.
                        Color.clear.frame(height: AppSpacing.tabContentBottomInset - 20).id("properties.bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .background(colors.background.ignoresSafeArea())
                .overlay(alignment: .top) { PropertyTopEdgeFade() }
#if DEBUG
                .onAppear { handleDebugLaunchSurfaceIfNeeded(proxy: proxy) }
#endif
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PropertyRoute.self) { route in
                switch route {
                case .detail(let id):
                    PropertyDetailView(propertyId: id, onEdit: { property in editor = .edit(property) })
                case .records(let id):
                    HistoryView(initialPropertyId: id)
                }
            }
        }
        .sheet(item: $editor, onDismiss: {
            NotificationCenter.default.post(name: .resumeGuidedOnboardingOverlay, object: nil)
        }) { mode in
            PropertyEditSheet(mode: mode, onDeleted: { _ in
                // The rental is gone: back to the list.
                path = NavigationPath()
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingPaywall) {
            // After a purchase, carry on to adding the property.
            PaywallView(
                context: PropertyLimit.paywallContext,
                onUnlocked: {
                    NotificationCenter.default.post(name: .suspendGuidedOnboardingOverlay, object: nil)
                    editor = .add
                },
                onClose: { showingPaywall = false }
            )
        }
        .alert(deletion?.title ?? "", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let deletion {
                    path = NavigationPath()
                    deletion.perform(in: viewModel)
                }
                deletion = nil
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: {
            Text(deletion?.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddProperty)) { _ in
            openAddProperty()
        }
    }

    // MARK: Header

    private var header: some View {
        let stack = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 4) {
            (stack ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center))) {
                BPScreenTitle(text: "Properties")
                if !stack { Spacer(minLength: 8) }
                if !viewModel.properties.isEmpty && !isLoading {
                    Button(action: openAddProperty) {
                        Label("Add property", systemImage: "plus")
                    }
                    .buttonStyle(PropertyTintedButtonStyle())
                    .fixedSize()
                    .guidedSpotlightTarget(.addProperty)
                    .accessibilityIdentifier("properties.add")
                }
            }
            if isLoading {
                PlaceholderBar(width: 170, height: 14)
                    .padding(.top, 8)
            } else if !viewModel.properties.isEmpty {
                let total = viewModel.properties.reduce(0) { $0 + viewModel.propertyCountableHours($1.id) }
                HStack(spacing: 6) {
                    Text("\(viewModel.properties.count) \(viewModel.properties.count == 1 ? "rental" : "rentals") · \(Int(total.rounded(.down)))h this year")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("properties.subtitle")
                    if !perPropertyGoal {
                        Button {
                            if reduceMotion { infoShown.toggle() } else { withAnimation(.easeOut(duration: 0.2)) { infoShown.toggle() } }
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(colors.action)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.lhPressable)
                        .padding(.vertical, -6)
                        .accessibilityLabel("About the house stages")
                        .accessibilityIdentifier("properties.info")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var infoNote: some View {
        Label("Each house shows that rental’s own hours: the slab at 100h, then the frame, and the roof on at 500h.", systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.informationalSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityIdentifier("properties.infoNote")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colors.textTertiary)
                .accessibilityHidden(true)
            TextField("Search rentals", text: $query)
                .foregroundStyle(colors.textPrimary)
                .submitLabel(.search)
                .accessibilityIdentifier("properties.search")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
    }

    // MARK: List

    private var listCard: some View {
        let shown = shownProperties
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, property in
                NavigationLink(value: PropertyRoute.detail(property.id)) {
                    PropertyRow(
                        property: property,
                        allProperties: viewModel.properties,
                        hours: viewModel.propertyCountableHours(property.id),
                        goal: goal,
                        perPropertyGoal: perPropertyGoal
                    )
                }
                .buttonStyle(.lhPressable)
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editor = .edit(property) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deletion = PropertyDeletion.make(for: property, in: viewModel)
                    }
                }
                .accessibilityAction(named: "Edit") { editor = .edit(property) }
                .accessibilityAction(named: "Delete") { deletion = PropertyDeletion.make(for: property, in: viewModel) }
                .accessibilityIdentifier("properties.row.\(index)")
                if index < shown.count - 1 || atLimit {
                    PropertyInsetDivider(leading: dynamicTypeSize.isAccessibilitySize ? 16 : 16 + 40 + 12)
                }
            }
            if shown.isEmpty {
                Text("No rentals match “\(query)”.")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 76)
            }
            if atLimit {
                PropertiesAtLimitRow(
                    firstPropertyName: viewModel.properties.first?.name,
                    onUnlock: { showingPaywall = true }
                )
            }
        }
        .propertyCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(colors.action)
                .frame(width: 56, height: 56)
                .background(Circle().fill(colors.actionSurface))
                .accessibilityHidden(true)
            Text("Add your first property")
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Once we know where your rentals are, every hour you confirm goes up on the house.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add property", action: openAddProperty)
                .buttonStyle(InboxPrimaryButtonStyle())
                .padding(.top, 8)
                .guidedSpotlightTarget(.addProperty)
                .accessibilityIdentifier("properties.add")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .propertyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.empty")
    }

    /// Loading never blocks and never spins: PlaceholderBar where the names and numbers go and a
    /// DraftingLoader house where the house goes.
    private var loadingCard: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    Circle().fill(colors.border.opacity(0.5))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceholderBar(width: i == 1 ? 150 : 120, height: 14)
                        PlaceholderBar(width: 170, height: 10)
                    }
                    Spacer()
                    // Same rule as PropertyRow: the house tile drops out from XXL.
                    if dynamicTypeSize < .xxLarge {
                        DraftingLoader(sketch: .house, lineWidth: 1.5).frame(width: 48, height: 48)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 76)
                if i < 2 { PropertyInsetDivider(leading: 68) }
            }
        }
        .propertyCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your rentals")
        .accessibilityIdentifier("properties.loading")
    }

    private func openAddProperty() {
        if viewModel.canAddProperty() {
            NotificationCenter.default.post(name: .suspendGuidedOnboardingOverlay, object: nil)
            editor = .add
        } else {
            showingPaywall = true
        }
    }

#if DEBUG
    /// -LHOpenAddProperty · -LHOpenFirstPropertyDetail · -LHOpenFirstPropertyDetailLower ·
    /// -LHOpenFirstPropertyEdit · -LHOpenFirstPropertyDelete · -LHOpenSecondPropertyDetail ·
    /// -LHPropertiesInfo · -LHPropertiesScrollBottom
    private func handleDebugLaunchSurfaceIfNeeded(proxy: ScrollViewProxy) {
        guard !didHandleDebugLaunchSurface else { return }
        didHandleDebugLaunchSurface = true
        let args = ProcessInfo.processInfo.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if args.contains("-LHPropertiesInfo") {
                withAnimation(.easeOut(duration: 0.2)) { infoShown = true }
            }
            if args.contains("-LHPropertiesScrollBottom") {
                proxy.scrollTo("properties.bottom", anchor: .bottom)
            }
            if args.contains("-LHOpenAddProperty") {
                openAddProperty()
            } else if let first = viewModel.properties.first {
                if args.contains("-LHOpenFirstPropertyDetail") || args.contains("-LHOpenFirstPropertyDetailLower") {
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

/// The whole Properties at-limit lock in one place: a ghost "Your next rental" row under the
/// `.row` locked preview, saying what stays active, with one Unlock Pro.
/// INTEGRATION (wp-paywall): swap this body for the app-wide ProGate lock; the caller keeps
/// passing the first rental's name and the unlock action (opens the .secondProperty paywall).
struct PropertiesAtLimitRow: View {
    let firstPropertyName: String?
    var onUnlock: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        PropertiesLockedPreviewRow(
            line: PropertyLimit.lockLine,
            keeps: PropertyLimit.keepsLine(firstPropertyName: firstPropertyName),
            onUnlock: onUnlock
        ) {
            HStack(spacing: 12) {
                PropertySeal(monogram: "", size: 40, dashed: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your next rental")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text("0h this year")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 76)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.lockRow")
    }
}

// MARK: - Row

struct PropertyRow: View {
    let property: RentalProperty
    let allProperties: [RentalProperty]
    let hours: Double
    let goal: HouseGoal
    var perPropertyGoal = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let ax = dynamicTypeSize.isAccessibilitySize
        let kind = PropertyMeta.kindLabel(property.propertyType)
        let line = PropertyMeta.hoursLine(hours, goal: goal, groupingElection: !perPropertyGoal)
        (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
            PropertySeal(property, in: allProperties, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(property.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(ax ? 5 : (dynamicTypeSize >= .xxLarge ? 4 : 2))
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
                // Non-breaking spaces keep "A few nights" on one line.
                Text("\(line) · \(kind.replacingOccurrences(of: " ", with: "\u{00A0}"))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            if !ax { Spacer(minLength: 8) }
            if dynamicTypeSize < .xxLarge { PropertyHouseTile(hours: hours, size: 48) }
            if !ax {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(property.name), \(line), \(kind). \(PropertyHouseStage.stage(for: hours).spokenName).")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Detail

struct PropertyDetailView: View {
    let propertyId: UUID
    var onEdit: (RentalProperty) -> Void

    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var geocodeState: GeocodeState = .idle
    @State private var geocodedAddress: String?

    private enum GeocodeState { case idle, loading, found, notFound }

    /// Future smart-layer slot (key contacts). Empty today, so the section never shows.
    private var people: [PropertyPerson] { [] }

    private var property: RentalProperty? { viewModel.properties.first { $0.id == propertyId } }

    var body: some View {
        Group {
            if let property {
                content(property)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(property?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { if let property { onEdit(property) } }
                    .accessibilityIdentifier("property.edit")
            }
        }
        .task(id: property?.address) { await geocode() }
    }

    private func content(_ property: RentalProperty) -> some View {
        let figures = viewModel.propertyFigures(for: property)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    hero(property, figures: figures)
                    if figures.kinds.isEmpty && figures.recent.isEmpty {
                        nothingYet(property)
                    } else {
                        if !figures.kinds.isEmpty { kinds(figures.kinds) }
                        if !figures.recent.isEmpty { recent(property, entries: figures.recent) }
                    }
                    if !people.isEmpty { peopleSection }
                    details(property).id("details")
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
#if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-LHOpenFirstPropertyDetailLower") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("details", anchor: .top) }
                }
            }
#endif
        }
    }

    // MARK: Hero

    private func hero(_ property: RentalProperty, figures: PropertyFigures) -> some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        // From XXL the text lines wrap into the house's corner, so the house moves below them.
        let stacked = dynamicTypeSize >= .xxLarge
        let stage = PropertyHouseStage.stage(for: figures.hours)
        let whole = Int(figures.hours.rounded(.down))
        let street = property.address.split(separator: ",").first.map(String.init) ?? ""
        let eyebrow = [PropertyMeta.kindLabel(property.propertyType), street].filter { !$0.isEmpty }.joined(separator: " · ")
        let last = figures.lastDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let entriesLine = figures.entryCount == 0
            ? "No entries yet"
            : "\(figures.entryCount) \(figures.entryCount == 1 ? "entry" : "entries")\(last.map { " · last on \($0)" } ?? "")"
        let text = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PropertySeal(property, in: viewModel.properties, size: 32)
                    .environment(\.colorScheme, .dark)
                Text(eyebrow)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(HouseTokens.drafting)
                    .lineLimit(ax ? 3 : 1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(whole)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("h this year")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HouseTokens.onHeroSecondary)
            }
            .padding(.top, 4)
            Text(entriesLine)
                .font(.subheadline)
                .foregroundStyle(HouseTokens.onHeroSecondary)
            Text(stage.spokenName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(figures.hours >= 500 ? HouseTokens.positiveOnHero : HouseTokens.onHeroPrimary)
        }
        let house = HouseHeroArt(keyframe: PropertyHouseStage.keyframe(for: figures.hours))

        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 12) {
                    text
                    house.frame(width: 140, height: 140).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                text
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
                    .background(alignment: .bottomTrailing) {
                        house
                            .frame(width: 150, height: 150)
                            .padding(.trailing, 4)
                            .padding(.bottom, 2)
                    }
            }
        }
        .background(InboxBlueprintPaper(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(property.name). \(whole) hours this year, \(entriesLine). \(stage.spokenName).")
        .accessibilityIdentifier("property.hero")
    }

    // MARK: Sections

    private func kinds(_ kinds: [PropertyFigures.Kind]) -> some View {
        let maxHours = max(1, kinds.map(\.hours).max() ?? 1)
        let ax = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 10) {
            PropertySectionHeader("By kind of work")
            VStack(spacing: 14) {
                ForEach(kinds, id: \.category) { kind in
                    let bar = GeometryReader { g in
                        Capsule()
                            .fill(colors.categoryInk(kind.category).opacity(0.85))
                            .frame(width: max(8, g.size.width * kind.hours / maxHours), height: 8)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 24)
                    let value = Text(BPHours.short(kind.hours))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                    Group {
                        if ax {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    CategoryToolTile(category: kind.category, size: 24)
                                    Text(kind.category.inboxLabel).font(.subheadline).foregroundStyle(colors.textPrimary)
                                    Spacer(minLength: 8)
                                    value
                                }
                                bar
                            }
                        } else {
                            HStack(spacing: 10) {
                                CategoryToolTile(category: kind.category, size: 24)
                                Text(kind.category.inboxLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(width: dynamicTypeSize >= .xxLarge ? 128 : 100, alignment: .leading)
                                bar
                                value.frame(minWidth: 40, alignment: .trailing)
                            }
                            .frame(minHeight: 24)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(kind.category.inboxLabel), \(BPHours.spoken(kind.hours))")
                }
            }
            .padding(16)
            .propertyCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.kinds")
    }

    private func recent(_ property: RentalProperty, entries: [TimeEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PropertySectionHeader(title: "Recent") {
                NavigationLink(value: PropertyRoute.records(property.id)) {
                    Text("See all in Records")
                        .font(.subheadline)
                        .foregroundStyle(colors.action)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.lhPressable)
                .accessibilityIdentifier("property.seeAllRecords")
            }
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink {
                        TimeEntryDetailView(entry: entry)
                    } label: {
                        recentRow(entry, propertyName: property.name)
                    }
                    .buttonStyle(.lhPressable)
                    if index < entries.count - 1 { PropertyInsetDivider(leading: 64) }
                }
            }
            .propertyCard()
        }
    }

    private func recentRow(_ entry: TimeEntry, propertyName: String) -> some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        let title = RecordsLogic.title(for: entry, propertyName: propertyName)
        let meta = "\(entry.date.formatted(.dateTime.month(.abbreviated).day())) · \(Self.sourceText(entry))"
        let hours = Text(BPHours.short(entry.hours))
            .font(.system(.body, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
        return HStack(alignment: ax ? .top : .center, spacing: 12) {
            CategoryToolTile(category: entry.category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(colors.textPrimary).multilineTextAlignment(.leading)
                Text(meta).font(.subheadline).foregroundStyle(colors.textSecondary).multilineTextAlignment(.leading)
                if ax { hours.padding(.top, 2) }
            }
            Spacer(minLength: 8)
            if !ax { hours }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(BPHours.spoken(entry.hours)), \(meta)")
        .accessibilityAddTraits(.isButton)
    }

    /// The one source vocabulary app-wide: Records' badge titles.
    static func sourceText(_ entry: TimeEntry) -> String {
        RecordSourceBadge(entry: entry).title
    }

    private func nothingYet(_ property: RentalProperty) -> some View {
        Text("Nothing logged at \(property.name) yet. Hours you confirm here go up on its house.")
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .propertyCard()
    }

    /// Smart-layer slot, data-driven: hidden while `people` is empty.
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PropertySectionHeader("People")
            VStack(spacing: 0) {
                ForEach(people) { person in
                    HStack(spacing: 12) {
                        PropertySeal(monogram: PropertySealStyle.monogram(person.name), palette: .slate, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(.body.weight(.semibold)).foregroundStyle(colors.textPrimary)
                            Text("\(person.role) · \(person.visits) visits").font(.subheadline).foregroundStyle(colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 60)
                }
            }
            .propertyCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.people")
    }

    private func details(_ property: RentalProperty) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PropertySectionHeader("Details")
            VStack(spacing: 0) {
                detail("Address", property.address.isEmpty ? "Not added" : property.address)
                PropertyInsetDivider()
                detail("How guests stay", property.propertyType == .ltr ? "Months or longer" : "A few nights at a time")
                PropertyInsetDivider()
                detail("Other names", property.aliases.isEmpty ? "None" : property.aliases.joined(separator: ", "))
                PropertyInsetDivider()
                detail("I live here", property.isOwnerOccupied ? "Yes" : "No")
                locationRow(property)
            }
            .propertyCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.details")
    }

    private func detail(_ label: String, _ value: String) -> some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        return (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))) {
            Text(label).foregroundStyle(colors.textPrimary)
            if !ax { Spacer(minLength: 8) }
            Text(value)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(ax ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// The location row: the address found on the map. While it looks the address up, a
    /// DraftingLoader holds the map's place (never a spinner).
    @ViewBuilder
    private func locationRow(_ property: RentalProperty) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous)
        switch geocodeState {
        case .found:
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                    Marker(property.name, coordinate: coordinate).tint(AppColors.brand)
                }
                .allowsHitTesting(false)
                .frame(height: 140)
                .clipShape(shape)
                .accessibilityLabel("Map of \(property.address)")
                .accessibilityIdentifier("property.map")
            }
        case .loading, .idle:
            if !property.address.isEmpty {
                ZStack {
                    shape.fill(colors.backgroundTertiary)
                    DraftingLoader(sketch: .house, subject: "the map", lineWidth: 1.5).frame(width: 64, height: 64)
                }
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Finding the address on the map")
                .accessibilityIdentifier("property.mapLoading")
            }
        case .notFound:
            PropertyInsetDivider()
            HStack(spacing: 10) {
                Image(systemName: "mappin.slash")
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityHidden(true)
                Text("We couldn’t find this address on the map.")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
        }
    }

    private func geocode() async {
        guard let address = property?.address.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else {
            geocodeState = .idle
            return
        }
        guard geocodedAddress != address else { return }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHPropertiesMapLoading") { geocodeState = .loading; return }
#endif
        geocodeState = .loading
        let placemarks = try? await CLGeocoder().geocodeAddressString(address)
        geocodedAddress = address
        if let location = placemarks?.first?.location {
            coordinate = location.coordinate
            geocodeState = .found
        } else {
            geocodeState = .notFound
        }
    }
}

/// The detail hero's house: the built pass with drafting linework over the unbuilt parts.
private struct HouseHeroArt: View {
    let keyframe: HouseKeyframe
    var body: some View {
        HouseArtView(keyframe: keyframe, canvas: .blueprintHero)
    }
}

// MARK: - Add / edit (.large sheet)

struct PropertyEditSheet: View {
    let mode: PropertyEditorMode
    var onDeleted: (UUID) -> Void = { _ in }

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private enum Field { case name, address, alias }

    @State private var name = ""
    @State private var address = ""
    @State private var propertyType: PropertyType = .ltr
    @State private var aliases: [String] = []
    @State private var newAlias = ""
    @State private var isOwnerOccupied = false
    @State private var addressResults: [MKMapItem] = []
    @State private var showDuplicateWarning = false
    @State private var deletion: PropertyDeletion?
    @State private var loaded = false
    @FocusState private var focused: Field?

    private var editing: RentalProperty? {
        if case .edit(let p, _) = mode { return viewModel.properties.first { $0.id == p.id } ?? p }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                titleRow
                nameAndAddress
                VStack(alignment: .leading, spacing: 8) {
                    PropertySectionHeader("How do guests stay?")
                    PropertyStaySegment(propertyType: $propertyType)
                    Text("This changes how hours are counted for this place.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                otherNames
                liveHereCard
                if editing != nil {
                    Button("Delete property", role: .destructive) {
                        if let editing { deletion = PropertyDeletion.make(for: editing, in: viewModel) }
                    }
                    .font(.body)
                    .foregroundStyle(colors.destructive)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("property.delete")
                }
            }
            .padding(20)
            // Clear the pinned footer (its 16pt fade + the 52pt button + 8pt), plus 12pt of air.
            .padding(.bottom, 44)
            Color.clear.frame(height: 1).id("propertySheet.bottom")
        }
#if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-LHPropertySheetScrollBottom") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo("propertySheet.bottom", anchor: .bottom) }
            }
        }
#endif
        }
        .scrollDismissesKeyboard(.interactively)
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(editing != nil ? "Save" : "Add property", action: save)
                .buttonStyle(InboxPrimaryButtonStyle())
                .disabled(!canSave)
                .accessibilityIdentifier("property.save")
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(stops: [.init(color: colors.background.opacity(0), location: 0),
                                           .init(color: colors.background, location: 0.14)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
        }
        .alert("You already have a rental called \(name.trimmingCharacters(in: .whitespacesAndNewlines))", isPresented: $showDuplicateWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Give this one a different name so its hours stay apart.")
        }
        .alert(deletion?.title ?? "", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let deletion {
                    let id = deletion.property.id
                    deletion.perform(in: viewModel)
                    onDeleted(id)
                    dismiss()
                }
                deletion = nil
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: {
            Text(deletion?.message ?? "")
        }
        .onAppear(perform: load)
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text(editing != nil ? "Edit property" : "New property")
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(colors.backgroundSecondary))
                    .overlay(Circle().strokeBorder(colors.border, lineWidth: 0.5))
            }
            .buttonStyle(.lhPressable)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("property.close")
        }
    }

    private var nameAndAddress: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                field("Name", text: $name, placeholder: "Pine Cabin", id: "property.name", field: .name)
                PropertyInsetDivider()
                field("Address", text: $address, placeholder: "Street, city", id: "property.address", field: .address)
                    .onChange(of: address) { _, value in
                        guard focused == .address else { return }
                        if value.count > 2 { searchAddress(query: value) } else { addressResults = [] }
                    }
            }
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if !addressResults.isEmpty && focused == .address {
                addressResultsMenu
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, id: String, field: Field) -> some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        return (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))) {
            Text(label)
                .foregroundStyle(colors.textPrimary)
                .frame(minWidth: ax ? nil : 76, alignment: .leading)
                .fixedSize()
                .accessibilityHidden(true)
            TextField(placeholder, text: text, axis: ax ? .vertical : .horizontal)
                .lineLimit(ax ? 4 : 1)
                .foregroundStyle(colors.textPrimary)
                .focused($focused, equals: field)
                .submitLabel(field == .name ? .next : .done)
                .onSubmit { if field == .name { focused = .address } else { focused = nil } }
                .textInputAutocapitalization(.words)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, ax ? 10 : 0)
        .frame(minHeight: 52)
    }

    private var addressResultsMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(addressResults.prefix(5).enumerated()), id: \.element) { index, item in
                Button { selectAddress(item) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Address").font(.body).foregroundStyle(colors.textPrimary)
                        if let line = item.placemark.title {
                            Text(line).font(.footnote).foregroundStyle(colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.lhPressable)
                if index < min(addressResults.count, 5) - 1 { PropertyInsetDivider() }
            }
        }
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
    }

    // MARK: Other names

    private var trimmedNewAlias: String { newAlias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddAlias: Bool {
        trimmedNewAlias.count >= RentalProperty.aliasMinLength && aliases.count < RentalProperty.maxAliases
    }
    private var aliasHint: String? {
        if aliases.count >= RentalProperty.maxAliases { return "You can add up to \(RentalProperty.maxAliases) other names." }
        if !trimmedNewAlias.isEmpty && trimmedNewAlias.count < RentalProperty.aliasMinLength {
            return "Use at least \(RentalProperty.aliasMinLength) characters."
        }
        return nil
    }

    private var otherNames: some View {
        VStack(alignment: .leading, spacing: 8) {
            PropertySectionHeader("Other names")
            VStack(alignment: .leading, spacing: 12) {
                if !aliases.isEmpty {
                    PropertyChipFlow(spacing: 8) {
                        ForEach(aliases, id: \.self) { alias in aliasChip(alias) }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add another name", text: $newAlias)
                        .foregroundStyle(colors.textPrimary)
                        .focused($focused, equals: .alias)
                        .submitLabel(.done)
                        .onSubmit(addAlias)
                        .accessibilityIdentifier("property.alias.field")
                    Button("Add", action: addAlias)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canAddAlias ? colors.action : colors.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!canAddAlias)
                        .accessibilityIdentifier("property.alias.add")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let aliasHint {
                    Text(aliasHint)
                        .font(.footnote)
                        .foregroundStyle(colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("property.alias.hint")
                }
            }
            .padding(16)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("The names you use for this place in your calendar, like “the cabin”. We use them to match events. Use at least 3 characters. You can add up to 10 other names.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func aliasChip(_ alias: String) -> some View {
        HStack(spacing: 2) {
            Text(alias)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .padding(.leading, 14)
                .padding(.vertical, 8)
            Button {
                if reduceMotion { aliases.removeAll { $0 == alias } } else {
                    withAnimation(.easeOut(duration: 0.18)) { aliases.removeAll { $0 == alias } }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle().inset(by: -4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(alias)")
        }
        .frame(minHeight: 36)
        .background(Capsule().fill(colors.backgroundTertiary))
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 0.5))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
    }

    private func addAlias() {
        guard canAddAlias else { return }
        let cleaned = RentalProperty.cleanedAliases(aliases + [newAlias])
        newAlias = ""
        guard cleaned != aliases else { return }
        if reduceMotion { aliases = cleaned } else { withAnimation(.easeOut(duration: 0.18)) { aliases = cleaned } }
    }

    private var liveHereCard: some View {
        Toggle(isOn: $isOwnerOccupied) {
            VStack(alignment: .leading, spacing: 2) {
                Text("I live here").font(.body).foregroundStyle(colors.textPrimary)
                Text("We won’t suggest time spent at home as work.")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(InboxSwitchStyle())
        .accessibilityIdentifier("property.ownerOccupied")
        .padding(16)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Save

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let p = editing {
            name = p.name
            address = p.address
            propertyType = p.propertyType
            aliases = p.aliases
            isOwnerOccupied = p.isOwnerOccupied
            if case .edit(_, let confirmDelete) = mode, confirmDelete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { deletion = PropertyDeletion.make(for: p, in: viewModel) }
            }
        } else {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-LHPropertySheetScrollBottom") { return }
#endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = .name }
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func save() {
        guard canSave else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.properties.contains(where: { $0.id != editing?.id && normalized($0.name) == normalized(cleanName) }) {
            showDuplicateWarning = true
            return
        }
        // Aliases and "I live here" are always written, so clearing them sticks.
        let cleanedAliases = RentalProperty.cleanedAliases(aliases + [newAlias])
        if let existing = editing {
            var updated = existing
            updated.name = cleanName
            updated.address = cleanAddress
            updated.propertyType = propertyType
            updated.aliases = cleanedAliases
            updated.isOwnerOccupied = isOwnerOccupied
            viewModel.updateProperty(updated)
        } else {
            viewModel.addProperty(name: cleanName, address: cleanAddress, type: propertyType)
            if var added = viewModel.properties.last, added.name == cleanName,
               !cleanedAliases.isEmpty || isOwnerOccupied {
                added.aliases = cleanedAliases
                added.isOwnerOccupied = isOwnerOccupied
                viewModel.updateProperty(added)
            }
        }
        dismiss()
    }

    private func searchAddress(query: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        MKLocalSearch(request: request).start { response, _ in
            Task { @MainActor in addressResults = response?.mapItems ?? [] }
        }
    }

    private func selectAddress(_ item: MKMapItem) {
        let placemark = item.placemark
        var parts = ""
        if let n = placemark.subThoroughfare { parts += n + " " }
        if let street = placemark.thoroughfare { parts += street + ", " }
        if let city = placemark.locality { parts += city + ", " }
        if let state = placemark.administrativeArea { parts += state + " " }
        if let zip = placemark.postalCode { parts += zip }
        focused = nil
        address = parts.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        addressResults = []
    }
}

#Preview {
    PropertiesView()
        .environmentObject(AppViewModel())
}
