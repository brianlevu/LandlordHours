import SwiftUI
import MapKit
import CoreLocation

// MARK: - The rental page (v2, plan package F, row 11)
//
// A hero screen (§H.5): the dusk page in light, night in dark (`LHPage`). Top to bottom, compact:
//   the rental's name (`.title1.semibold`, §1.14 `.detail`) in the toast's top slot (§1.19: a toast
//   replaces it while it shows) · `RentalHero`: the house at the medium size (frame
//   `min(W − 12, round(0.343 × H))` = 300 on 402×874, 220 at AX; §H.5) with the shared number block
//   under it (`HouseNumberBlock`, overlapping the frame by 44 × side/390 at default, 0 at AX; §H.1
//   H4) · `RentalBody`: the two stat tiles that left Today (this week, to finish), the newest records
//   as `LHRow.Browse` with the 36 tool, and the details (with the §F.1 "House" row reserved).
//
// J1 contract (plan §4 package J): the page is two views, `RentalHero` (hero + number block) and
// `RentalBody` (tiles, records, details), so compact stacks them and two-pane puts the hero in the
// house pane and the body in the work pane. Neither view reads widths to pick a mode.
//
// Motion is the house's own: a log that carries this rental from `frame70` to `framing` while the
// page is visible plays the timber drop (once per stage per rental, `CraftDropLedger`), and the
// number waits for the last timber; any other stage change is `stageFade`; the windows take
// `windowsOn`. Nothing animates on appear.

struct PropertyDetailView: View {
    let propertyId: UUID
    var onEdit: (RentalProperty) -> Void

    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutBand) private var band
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var window: CGSize = .zero
    @State private var heroSide: CraftHeroSide?

    private var property: RentalProperty? { viewModel.properties.first { $0.id == propertyId } }
    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if let property {
                page(property)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background { LHPage() }
        .background {
            // The window size (§H.5 uses the whole window, safe areas included).
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                           height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
                } action: { size in
                    window = size
                    resolveSide()
                }
        }
        .onChange(of: dynamicTypeSize) { _, _ in resolveSide() }
        .onChange(of: band) { _, _ in resolveSide() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(RentalsText.edit) { if let property { onEdit(property) } }
                    .accessibilityIdentifier("property.edit")
            }
        }
    }

    private var side: CGFloat {
        heroSide?.side ?? CraftHeroSize.medium(windowWidth: 402, windowHeight: 874, accessibility: ax)
    }

    private func resolveSide() {
        guard window.width > 0, window.height > 0 else { return }
        heroSide = CraftHeroSide.resolve(previous: heroSide, kind: .medium, window: window, band: band, accessibility: ax)
    }

#if DEBUG
    /// `-LHRentalLogAfter <s>` (`-LHRentalLogHours <h>`, default 2): s seconds after the page
    /// appears, log h hours today at this rental and post the log's toast, as the Log time sheet
    /// does. Clears the drop ledger first, so a log that reaches framing plays the drop (captures).
    @State private var didScheduleDebugLog = false

    private func scheduleDebugLog(_ property: RentalProperty) {
        let args = ProcessInfo.processInfo.arguments
        guard !didScheduleDebugLog, let i = args.firstIndex(of: "-LHRentalLogAfter"), args.indices.contains(i + 1),
              let delay = Double(args[i + 1]) else { return }
        didScheduleDebugLog = true
        let hours = args.firstIndex(of: "-LHRentalLogHours").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil } ?? 2
        UserDefaults.standard.removeObject(forKey: UserScope.key(CraftDropLedger.baseKey, userId: UserScope.userId))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            viewModel.addTimeEntry(propertyId: property.id, participant: .selfParticipant, category: .repairs,
                                   hours: hours, date: Date(), notes: "")
            AppToastCenter.shared.show(TodayText.logged(LHFormat.hours(hours), at: property.name), kind: .success)
        }
    }
#endif

    private func page(_ property: RentalProperty) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LHToastChipSlot {
                        LHScreenTitle(property.name, style: .detail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("property.title")
                    }
                    .padding(.horizontal, LHMetrics.gutter)
                    RentalHero(property: property, side: side, windowHeight: window.height)
                        .padding(.top, ax ? 8 : 0)
                    RentalBody(property: property)
                        .padding(.horizontal, LHMetrics.gutter)
                        .padding(.top, LHMetrics.sectionGap)
                    Color.clear.frame(height: 24).id("property.end")
                }
                .frame(maxWidth: band == .a ? .infinity : LHMetrics.readingColumn)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
#if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-LHOpenFirstPropertyDetailLower") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("details", anchor: .top) }
                }
                scheduleDebugLog(property)
                if ProcessInfo.processInfo.arguments.contains("-LHRentalPageScroll") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("property.end", anchor: .bottom) }
                    }
                }
            }
#endif
        }
    }
}

// MARK: - RentalHero: the house at the medium size and the number block

struct RentalHero: View {
    let property: RentalProperty
    /// The frame side (`CraftHeroSide.resolve(kind: .medium)`): 300 on 402×874, 220 at AX.
    let side: CGFloat
    /// The window height, for the numeral cap (64 under 700pt, §H.1 H7).
    var windowHeight: CGFloat = 874

    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var goalManager = GoalManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var scaledNumeral: CGFloat = 84

    /// The hours on screen while a timber drop is landing (the number rolls as the last timber lands).
    @State private var settledHours: Double?
    @State private var isVisible = false

    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }
    private var year: Int { Calendar.current.component(.year, from: InboxClock.now()) }
    private var goal: Double { goalManager.houseGoal.targetHours }

    private var figures: RentalPageFigures { viewModel.rentalPageFigures(for: property) }
    private var liveHours: Double { viewModel.propertyCountableHours(property.id, goal: goalManager.houseGoal, year: year) }
    private var lit: Bool {
        TodayWindowState.loggedToday(entries: viewModel.timeEntries, rentalIDs: [property.id], now: InboxClock.now())
    }

    private var shownHours: Double {
        if let settledHours, dropPending(from: settledHours, to: liveHours) { return settledHours }
        return liveHours
    }

    private var dropAllowed: Bool {
        !CraftDropLedger().hasPlayed(rentalID: property.id, stage: .framing, year: year)
    }

    /// A save that will play the timber drop (the same test `CraftHouseView` makes).
    private func dropPending(from old: Double, to new: Double) -> Bool {
        guard isVisible, new > old, dropAllowed, !reduceMotion,
              CraftHouseView.buildClipURL(dark: colorScheme == .dark) != nil else { return false }
        return CraftMotion.stageMotion(from: CraftStage.stage(hours: old, goal: goal),
                                       to: CraftStage.stage(hours: new, goal: goal)) == .timberDrop
    }

    private var numeralSize: CGFloat {
        let cap = CraftHeroSize.numeralCap(windowHeight: windowHeight > 0 ? windowHeight : 874, accessibility: ax) ?? 84
        return min(scaledNumeral, cap)
    }

    /// The number block sits in the diorama's shadow: 44pt at the 390 hero, scaled to this frame (H4).
    private var overlap: CGFloat { ax ? 0 : (44 * side / CraftStage.referenceSide).rounded() }

    var body: some View {
        let f = figures
        VStack(spacing: 0) {
            CraftHouseView(stage: f.stage, windowsLit: lit, side: side, fillsStage: !ax,
                           dropAllowed: dropAllowed, onStageSettled: stageSettled)
                .id(property.id)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityIdentifier("property.hero")
            HouseNumberBlock(content: .rental(hours: shownHours, goal: goal, name: property.name, pace: pace(f)),
                             numeralSize: numeralSize, isPending: viewModel.isAwaitingInitialPull)
                .padding(.top, -overlap)
        }
        .onAppear {
            isVisible = true
            settledHours = liveHours
        }
        .onDisappear { isVisible = false }
        .onChange(of: liveHours) { _, new in
            if let settledHours, dropPending(from: settledHours, to: new) { return }
            settledHours = new
        }
    }

    /// The pace sentence for the number on screen (it follows the number through a drop).
    private func pace(_ f: RentalPageFigures) -> TodayPaceSentence {
        guard shownHours != liveHours else { return f.pace }
        let now = InboxClock.now()
        return RentalPageFigures.pace(hours: shownHours, goal: goal, isRecord: goalManager.goalChoice == .record, year: year,
                                      now: now, daysOfData: RentalWeek.daysOfData(entries: viewModel.propertyCountableEntries(property.id),
                                                                                  year: year, now: now))
    }

    private func stageSettled(_ motion: CraftStageMotion) {
        if motion == .timberDrop {
            CraftDropLedger().markPlayed(rentalID: property.id, stage: .framing, year: year)
        }
        settledHours = liveHours
    }
}

// MARK: - RentalBody: tiles, records, details

struct RentalBody: View {
    let property: RentalProperty

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var geocodeState: GeocodeState = .idle
    @State private var geocodedAddress: String?

    private enum GeocodeState { case idle, loading, found, notFound }

    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let page = viewModel.rentalPageFigures(for: property)
        let figures = viewModel.propertyFigures(for: property)
        VStack(alignment: .leading, spacing: 0) {
            if figures.entryCount > 0 || page.weekTile.trend != nil {
                tiles(page)
            }
            if !figures.recent.isEmpty {
                recent(figures.recent, total: viewModel.timeEntries.filter { $0.propertyId == property.id }.count)
                    .padding(.top, LHMetrics.sectionGap)
            }
            details
                .padding(.top, figures.entryCount > 0 || !figures.recent.isEmpty ? LHMetrics.sectionGap : 0)
                .id("details")
        }
        .task(id: property.address) { await geocode() }
    }

    // MARK: Tiles

    private func tiles(_ page: RentalPageFigures) -> some View {
        let layout = ax ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            LHTile.Stat(value: page.weekTile.value, label: page.weekTile.label, trend: page.weekTile.trend)
                .modifier(RentalPageCardEdge(radius: LHMetrics.tileRadius))
                .accessibilityIdentifier("property.tile.week")
            LHTile.Stat(value: page.finishTile.value, label: page.finishTile.label)
                .modifier(RentalPageCardEdge(radius: LHMetrics.tileRadius))
                .accessibilityIdentifier("property.tile.finish")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.tiles")
    }

    // MARK: Records

    /// The newest three, then a "See all N" foot that opens Records filtered to this rental (the
    /// same foot as Today's To confirm, §H.8).
    private func recent(_ entries: [TimeEntry], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LHSectionHeader(RentalsText.recent, onPage: true)
            LHRowGroup(onPage: true) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: PropertyRoute.record(entry.id)) {
                        recordRow(entry)
                    }
                    .buttonStyle(LHButton.press)
                    .accessibilityIdentifier("property.record.\(index)")
                    if index < entries.count - 1 { LHDivider(leadingInset: 16 + 36 + 12) }
                }
                LHDivider(leadingInset: 16)
                NavigationLink(value: PropertyRoute.records(property.id)) {
                    Text(RentalsText.seeAll(total))
                }
                .buttonStyle(LHButton.tertiary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("property.seeAllRecords")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.recent")
    }

    private func recordRow(_ entry: TimeEntry) -> some View {
        let title = RecordsLogic.title(for: entry, propertyName: property.name)
        let meta = RentalsText.recordMeta(date: entry.date.formatted(.dateTime.month(.abbreviated).day()),
                                          source: RecordSourceBadge(entry: entry).title)
        return LHRow.Browse(title: title, meta: meta, value: LHFormat.hours(entry.hours)) {
            CategoryToolTile(category: entry.category, size: 36)
        }
        .accessibilityLabel("\(title), \(LHFormat.spokenHours(entry.hours)), \(meta)")
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            LHSectionHeader(RentalsText.details, onPage: true)
            LHRowGroup(onPage: true) {
                detailRow(RentalsText.address, property.address.isEmpty ? RentalsText.notAdded : property.address)
                LHDivider(leadingInset: 16)
                detailRow(RentalsText.howGuestsStay, RentalsText.kind(property.propertyType))
                LHDivider(leadingInset: 16)
                detailRow(RentalsText.otherNames, property.aliases.isEmpty ? RentalsText.none : property.aliases.joined(separator: ", "))
                LHDivider(leadingInset: 16)
                detailRow(RentalsText.liveHere, property.isOwnerOccupied ? RentalsText.yes : RentalsText.no)
                RentalHouseLookSlot(property: property)
                locationRow
            }
            .clipShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.details")
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(label).foregroundStyle(colors.textPrimary)
            if !ax { Spacer(minLength: 8) }
            Text(value)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(ax ? .leading : .trailing)
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(minHeight: LHMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }

    /// The address on the map. While it looks the address up, the drafting loader holds the map's
    /// place (never a spinner).
    @ViewBuilder private var locationRow: some View {
        switch geocodeState {
        case .found:
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                    Marker(property.name, coordinate: coordinate).tint(colors.action)
                }
                .allowsHitTesting(false)
                .frame(height: 140)
                .accessibilityLabel(RentalsText.mapOf(property.address))
                .accessibilityIdentifier("property.map")
            }
        case .loading, .idle:
            if !property.address.isEmpty {
                ZStack {
                    colors.backgroundTertiary
                    DraftingLoader(sketch: .house, subject: "the map", lineWidth: 1.5).frame(width: 64, height: 64)
                }
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RentalsText.findingMap)
                .accessibilityIdentifier("property.mapLoading")
            }
        case .notFound:
            LHDivider(leadingInset: 16)
            Label(RentalsText.mapNotFound, systemImage: "mappin.slash")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: LHMetrics.rowMinHeight)
                .accessibilityElement(children: .combine)
        }
    }

    private func geocode() async {
        let address = property.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            geocodeState = .idle
            return
        }
        guard geocodedAddress != address else { return }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHPropertiesMapLoading") { geocodeState = .loading; return }
        if ProcessInfo.processInfo.arguments.contains("-LHPropertiesNoMap") { geocodeState = .notFound; return }
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

/// A card on the page takes the 1pt `pageCardEdge` (§H.4: a white card is 1.31:1 on the dusk page).
struct RentalPageCardEdge: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(AdaptiveColors(colorScheme: colorScheme).pageCardEdge, lineWidth: 1)
        }
    }
}

// MARK: - §F.1 slot (reserved, renders nothing)

/// The "House" `LHRow.Value` slot of §F.1 (a house of their own). It renders nothing and takes no
/// space while `RentalHouseLook.isBuilt` is false; when §F.1 is built it shows the rental's look
/// and opens the swatch sheet (plan backlog F1-d). Used on the rental page's details and in the edit
/// sheet, so the row lands in both places at once.
struct RentalHouseLookSlot: View {
    let property: RentalProperty?
    var body: some View {
        if RentalHouseLook.isBuilt {
            // F1-d builds the row here: LHRow.Value(RentalHouseLook.rowLabel, value: <the look's name>) { … }
            EmptyView()
        }
    }
}
