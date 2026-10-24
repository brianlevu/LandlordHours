import SwiftUI
import UIKit

#if DEBUG
// MARK: - Duo round 4: open = landscape 951x669pt, two panes, nothing on the fold (DEBUG mock, throwaway)
//
//   LEFT pane, "the workstation": To confirm over a warm, softly blurred interior. Tap an item: its detail pushes
//              inside the pane (back link). Log time opens in this pane. The system tab bar sits at its foot.
//              Unfolding plays the front door opening in this pane; you step through into the workstation.
//   RIGHT pane, "the house": the selected rental's lit diorama, its hours, "of X hours" and the pace sentence; under it,
//              a timber shelf of every rental ("All rentals" first). Tap or swipe the shelf to switch the house; the
//              workstation filters to that rental (plus items with no rental yet), with a chip to show all.
//   Propped up (upright 669x951, fold across): top half the house and shelf, bottom half the workstation.
//
//   -LHDirection CRAFT -LHDuoV2 render|motion   lays the open screen out in an off-screen window and writes
//                                                @3x frames to Documents/duo2/ (an agent cannot unfold the simulator).
//
// Production shape (iOS 27.1 SDK): ArrangementView { workstation } secondary: { house }
//   .arrangementViewStyle(.split.axes(.horizontal)); GeometryProxy.reservedRegions(kind: .division) gives the fold;
//   onHingeChange (DeviceHinge.status .closed -> .fullyOpen) starts the door clip (HEVC with alpha, round-1 B renders).

enum DuoV2Launch {
    static var mode: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let j = a.firstIndex(of: "-LHDuoV2"), a.indices.contains(j + 1) else { return nil }
        return a[j + 1].lowercased()
    }
}

enum DuoGeo {
    /// Held open, the inner display is LANDSCAPE: 951x669pt, the fold running top to bottom down the middle.
    /// Each half (~464x669) matches the closed outer display (466x678); the device profile has no fold geometry.
    static let open = CGSize(width: 951, height: 669)
    /// Propped up (tabletop): the same display upright, so the fold runs across it.
    static let propped = CGSize(width: 669, height: 951)
    /// Assumed division band (reserved rect plus margins). The real value comes from reservedRegions(kind: .division).
    static let hinge: CGFloat = 24
    static var pane: CGFloat { (open.width - hinge) / 2 }      // 463.5
    static let topInset: CGFloat = 24                           // landscape status bar (assumed)
    static let bottomInset: CGFloat = 20                        // home indicator (assumed)
}

enum DuoRight: Equatable { case list, detail(String), log }

struct DuoRental: Identifiable {
    let id: String
    let name: String
    let logged: Double
    let goal: Double
    let lit: Bool
    var stage: CraftArt? = nil
    var art: CraftArt { stage ?? CraftFocus.art(hours: logged, goal: goal) }
    var focus: CraftFocus { CraftFocus(id: id, name: name, logged: logged, goal: goal, art: art) }
    var isAll: Bool { id == "all" }
}

enum DuoV2Seed {
    static let three: [DuoRental] = [
        DuoRental(id: "santa", name: "Santa Ray Ave", logged: 46, goal: 100, lit: true, stage: .frame70),
        DuoRental(id: "delaney", name: "Delaney Ct", logged: 4, goal: 100, lit: false, stage: .started),
        DuoRental(id: "pine", name: "Pine Cabin", logged: 262, goal: 500, lit: false, stage: .half),
    ]
    static let eight: [DuoRental] = three + [
        DuoRental(id: "harbor", name: "Harbor Loft", logged: 88, goal: 100, lit: true),
        DuoRental(id: "elm", name: "12 Elm St", logged: 120, goal: 100, lit: false),
        DuoRental(id: "mesa", name: "Mesa Duplex", logged: 31, goal: 100, lit: false),
        DuoRental(id: "bay", name: "Bayview 4B", logged: 410, goal: 750, lit: true),
        DuoRental(id: "oak", name: "Oak Cottage", logged: 9, goal: 100, lit: false),
    ]
    static func all(_ rentals: [DuoRental]) -> DuoRental {
        DuoRental(id: "all", name: CL("All rentals"), logged: rentals.reduce(0) { $0 + $1.logged },
                  goal: rentals.reduce(0) { $0 + $1.goal }, lit: rentals.contains { $0.lit }, stage: .complete)
    }
    static var suggestions: [StdSuggestion] { StdSeed.make("brian").suggestions }

    /// Which rental an item belongs to: its `rental` field, else a rental named in its title. nil = no rental yet.
    static func rentalID(of item: StdSuggestion, in rentals: [DuoRental]) -> String? {
        if let r = item.rental { return r }
        return rentals.first { item.title.contains($0.name) }?.id
    }
}

// MARK: - The open layout

@available(iOS 26.0, *)
struct DuoOpenView: View {
    @State var tab: Int = 0
    @State var right: DuoRight
    @State var selectedID: String
    let rentals: [DuoRental]
    var annotate = false

    init(rentals: [DuoRental] = DuoV2Seed.three, selectedID: String = "santa", right: DuoRight = .list, annotate: Bool = false) {
        self.rentals = rentals; _selectedID = State(initialValue: selectedID); _right = State(initialValue: right)
        self.annotate = annotate
    }

    var body: some View {
        HStack(spacing: 0) {
            workstationTabs.frame(width: DuoGeo.pane)
            Color.clear.frame(width: DuoGeo.hinge)        // the division region: no text, no art crosses it
            DuoHousePane(rentals: rentals, selectedID: $selectedID).frame(width: DuoGeo.pane)
        }
        .background {
            HStack(spacing: 0) {
                DuoInterior().frame(width: DuoGeo.pane + DuoGeo.hinge / 2)
                CraftPage()
            }
            .ignoresSafeArea()
        }
        .overlay {
            if annotate {
                Rectangle().fill(Color.pink.opacity(0.28))
                    .overlay(Rectangle().strokeBorder(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: DuoGeo.hinge).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .onChange(of: tab) { old, new in if new == 4 { tab = old; right = .log } }
    }

    /// The system TabView, laid out at the left pane's compact width, so its bar sits at the foot of the workstation.
    private var workstationTabs: some View {
        TabView(selection: $tab) {
            Tab(CL("Today"), systemImage: "sun.horizon", value: 0) {
                DuoWorkstation(rentals: rentals, selectedID: $selectedID, right: $right)
            }
            Tab(CL("Inbox"), systemImage: "tray", value: 1) { DuoInterior() }.badge(7)
            Tab(CL("Records"), systemImage: "book.closed", value: 2) { DuoInterior() }
            Tab(CL("Rentals"), systemImage: "house", value: 3) { DuoInterior() }
            Tab(CL("Log time"), systemImage: "plus", value: 4, role: .search) { DuoInterior() }
        }
        .modifier(DuoTint())
    }
}

/// iOS 27.1: opt out of the Duo's vertical toolbar so the tab bar stays at the foot of the resting half.
private struct DuoNoVerticalBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) { content.toolbarVerticalBehavior(.disabled) } else { content }
    }
}

private struct DuoTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(CraftColors(dark: scheme == .dark).action) }
}

/// Round-1 A's warm interior (Blender, defocused): a calm backdrop. Text never sits on it; it sits on opaque cards.
struct DuoInterior: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { g in
            Image("duo_interior").resizable().scaledToFill()
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
        }
        .background(Color(hex: scheme == .dark ? "391602" : "582802"))
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - LEFT: the workstation

struct DuoWorkstation: View {
    let rentals: [DuoRental]
    @Binding var selectedID: String
    @Binding var right: DuoRight
    var maxRows: Int? = nil

    private var env = DAEnv()
    private var craft = CraftEnv()
    @State private var confirmed: Set<String> = []
    @State private var hours: Double = 2

    init(rentals: [DuoRental], selectedID: Binding<String>, right: Binding<DuoRight>, maxRows: Int? = nil) {
        self.rentals = rentals; _selectedID = selectedID; _right = right; self.maxRows = maxRows
    }

    private var c: DAColors { env.c }
    private var all: [StdSuggestion] { DuoV2Seed.suggestions }
    private var selected: DuoRental? { rentals.first { $0.id == selectedID } }
    /// Filter: the selected rental's items plus items with no rental yet. "All rentals" shows everything.
    private var items: [StdSuggestion] {
        guard let s = selected else { return all }
        return all.filter { let r = DuoV2Seed.rentalID(of: $0, in: rentals); return r == nil || r == s.id }
    }
    private var hidden: Int { all.count - items.count }

    var body: some View {
        ZStack { DuoInterior(); content }
    }

    @ViewBuilder private var content: some View {
        switch right {
        case .list: list
        case .detail(let id): detail(all.first { $0.id == id } ?? all[0])
        case .log:
            DALogTimeSheet(demo: nil, showsEyebrow: false, onLog: { _, _ in right = .list }, onClose: { right = .list })
                .background(c.sheet)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        }
    }

    private var list: some View {
        ScrollView {
            DuoCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(CL("To confirm · \(items.count - confirmed.count)")).font(.headline).foregroundStyle(c.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                    }
                    if let s = selected {
                        Button { selectedID = "all" } label: {
                            HStack(spacing: 6) {
                                Text(s.name).font(.subheadline.weight(.semibold))
                                Image(systemName: "xmark").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(c.action)
                            .padding(.horizontal, 12).frame(minHeight: 32)
                            .background(c.actionSurface, in: Capsule())
                        }
                        .buttonStyle(DAPress())
                        .accessibilityLabel(CL("Showing \(s.name). Show all rentals"))
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                ForEach(Array(items.prefix(maxRows ?? items.count).enumerated()), id: \.element.id) { i, item in
                    DAHairline().padding(.leading, i == 0 ? 0 : 50)
                    HStack(spacing: 0) {
                        DAActionRow(item: item, confirmed: confirmed.contains(item.id)) {
                            withAnimation(.easeOut(duration: 0.15)) { _ = confirmed.insert(item.id) }
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            .foregroundStyle(c.textTertiary).padding(.leading, 8).padding(.top, 4)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { right = .detail(item.id); hours = item.hours ?? 1 }
                }
                if let m = maxRows, items.count > m {
                    DAHairline()
                    Button(CL("See all \(items.count)")) {}
                        .font(.subheadline.weight(.semibold)).foregroundStyle(c.action)
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(DAPress())
                } else if hidden > 0 {
                    DAHairline()
                    Button(CL("\(hidden) more at other rentals")) { selectedID = "all" }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(c.action)
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(DAPress())
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func detail(_ item: StdSuggestion) -> some View {
        ScrollView {
            DuoCard {
                VStack(alignment: .leading, spacing: 4) {
                    Button { right = .list } label: {
                        Label(CL("To confirm"), systemImage: "chevron.left").font(.body.weight(.semibold)).frame(minHeight: 44)
                    }
                    .foregroundStyle(c.action).buttonStyle(DAPress())
                    Text(item.title).font(.title2.weight(.semibold)).foregroundStyle(c.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(CL("Calendar · \(item.when)"), systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(c.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 12)
                DAHairline()
                valueRow(CL("Rental"), rentals.first { $0.id == DuoV2Seed.rentalID(of: item, in: rentals) }?.name ?? CL("Choose"))
                DAHairline().padding(.leading, 16)
                HStack {
                    Text(CL("Kind of work")).font(.body).foregroundStyle(c.ink)
                    Spacer()
                    DATag(text: item.category?.stdLabel ?? CL("Other"),
                          ink: item.category.map { c.tagInk($0) } ?? c.textSecondary,
                          wash: item.category.map { c.tagWash($0) } ?? c.surfaceInner).fixedSize()
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
                DAHairline().padding(.leading, 16)
                valueRow(CL("Who"), CL("You"))
                DAHairline().padding(.leading, 16)
                HStack {
                    Text(CL("Hours")).font(.body).foregroundStyle(c.ink)
                    Spacer()
                    Text(StdFormat.hours(hours)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(c.ink)
                        .contentTransition(.numericText(value: hours)).padding(.trailing, 8)
                    stepper
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
                DAHairline()
                VStack(spacing: 4) {
                    Button(CL("Confirm \(StdFormat.hours(hours))")) { right = .list }.buttonStyle(DAPrimaryStyle())
                    Button(CL("Not rental work")) { right = .list }
                        .font(.body.weight(.semibold)).foregroundStyle(c.action)
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(DAPress())
                }
                .padding(16)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            Button { hours = max(0.25, hours - 0.25) } label: { Image(systemName: "minus").frame(width: 44, height: 36) }
                .accessibilityLabel(CL("Less"))
            Rectangle().fill(c.border).frame(width: 0.5, height: 20)
            Button { hours = min(12, hours + 0.25) } label: { Image(systemName: "plus").frame(width: 44, height: 36) }
                .accessibilityLabel(CL("More"))
        }
        .font(.body.weight(.semibold)).foregroundStyle(c.ink)
        .buttonStyle(DAPress())
        .background(c.surfaceInner, in: Capsule())
    }

    private func valueRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.body).foregroundStyle(c.ink)
            Spacer()
            Text(v).font(.body).foregroundStyle(c.textSecondary).multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}

// MARK: - RIGHT: the house and the shelf

@available(iOS 26.0, *)
struct DuoHousePane: View {
    let rentals: [DuoRental]
    @Binding var selectedID: String
    var heroSide: CGFloat = 290
    var compact = false
    private var env = CraftEnv()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rentals: [DuoRental], selectedID: Binding<String>, heroSide: CGFloat = 290, compact: Bool = false) {
        self.rentals = rentals; _selectedID = selectedID; self.heroSide = heroSide; self.compact = compact
    }

    private var c: CraftColors { env.c }
    private var shelfItems: [DuoRental] { [DuoV2Seed.all(rentals)] + rentals }
    private var focus: DuoRental { shelfItems.first { $0.id == selectedID } ?? shelfItems[0] }
    private var side: CGFloat { typeSize.isAccessibilitySize ? heroSide * 0.75 : heroSide }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if compact {
                    HStack(spacing: 0) { hero.frame(width: side); numberBlock.padding(.horizontal, -8).frame(maxWidth: .infinity, alignment: .leading) }
                        .padding(.horizontal, 16)
                } else {
                    hero
                    numberBlock.padding(.top, -side * 0.12)
                }
                DuoShelf(items: shelfItems, selectedID: $selectedID).padding(.top, compact ? 8 : 14)
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var hero: some View {
        CraftHouseArt(art: focus.art, dark: scheme == .dark, side: side, building: false, buildTick: 0,
                      windowsLit: focus.lit, fillStage: true) {}
            .id(focus.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            .frame(width: side, height: side)
            .frame(maxWidth: compact ? nil : .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                if v.translation.width < -40 { step(+1) } else if v.translation.width > 40 { step(-1) }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CL("\(focus.name), house \(focus.art.label), \(focus.lit ? CL("lights on") : CL("lights off"))"))
            .accessibilityAdjustableAction { step($0 == .increment ? 1 : -1) }
    }

    private func step(_ d: Int) {
        let i = shelfItems.firstIndex { $0.id == selectedID } ?? 0
        let n = shelfItems.count
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0)) {
            selectedID = shelfItems[(i + d + n) % n].id
        }
    }

    /// Each rental runs its own test, so "All rentals" names who is behind instead of pacing a summed goal.
    private func paceLine(_ f: CraftFocus, _ p: (lead: String, rest: String)) -> Text {
        if focus.isAll {
            let behind = rentals.filter { $0.focus.isBehind }
            if behind.isEmpty { return Text(CL("Every rental is on pace.")).foregroundStyle(c.positive).fontWeight(.semibold) }
            return Text(CL("\(behind.count) of \(rentals.count) behind.")).foregroundStyle(c.behind).fontWeight(.semibold)
                + Text(verbatim: " ") + Text(CL("Tap a house to see its pace.")).foregroundStyle(c.textSecondary)
        }
        return Text(p.lead).foregroundStyle(f.done ? c.positive : (f.isBehind ? c.behind : c.positive)).fontWeight(.semibold)
            + Text(verbatim: " ") + Text(p.rest).foregroundStyle(c.textSecondary)
    }

    private var numberBlock: some View {
        let f = focus.focus
        let p = f.pace
        return VStack(alignment: compact ? .leading : .center, spacing: 2) {
            Text(verbatim: "\(Int(f.logged))")
                .font(DAFont.fraunces(size: compact ? 60 : 76, opsz: 144, wght: 600)).tracking(-2)
                .foregroundStyle(c.ink).lineLimit(1)
                .contentTransition(.numericText(value: f.logged))
                .accessibilityAddTraits(.isHeader)
            Text(focus.isAll ? CL("hours across \(rentals.count) rentals") : CL("of \(Int(f.goal)) hours · \(f.name)"))
                .font(.body).foregroundStyle(c.textSecondary)
            paceLine(f, p)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .multilineTextAlignment(compact ? .leading : .center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

/// The timber shelf (round-1 B's plank render): every rental as its diorama, its name and hours under it.
/// Four items fit the 464pt pane (All rentals + 3); from 4 rentals on it scrolls sideways.
@available(iOS 26.0, *)
struct DuoShelf: View {
    let items: [DuoRental]
    @Binding var selectedID: String
    private var env = CraftEnv()
    private var da = DAEnv()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var labelHeight: CGFloat = 40
    static let model: CGFloat = 104
    static let slot: CGFloat = 108

    init(items: [DuoRental], selectedID: Binding<String>) { self.items = items; _selectedID = selectedID }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(items) { r in slot(r).id(r.id) }
                }
                .background(alignment: .top) {
                    Image("duo_shelf").resizable(resizingMode: .tile)
                        .frame(height: 12)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.22), radius: 3, y: 2)
                        .offset(y: Self.model * 0.86)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center, for: .alignment)   // centred when every rental fits
            .mask {   // soft edges once the shelf scrolls, so a clipped neighbour reads as "more", not as a cut label
                LinearGradient(stops: items.count > 4
                               ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.07),
                                  .init(color: .black, location: 0.93), .init(color: .clear, location: 1)]
                               : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
        }
    }

    private func slot(_ r: DuoRental) -> some View {
        let on = r.id == selectedID
        let c = env.c
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0)) { selectedID = r.id }
        } label: {
            VStack(spacing: 6) {
                model(r)
                    .frame(width: Self.model, height: Self.model)
                    .padding(.bottom, -Self.model * 0.06)
                VStack(spacing: 1) {
                    Text(r.name).font(.footnote.weight(.semibold)).foregroundStyle(c.ink)
                        .lineLimit(2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(CL("\(Int(r.logged)) of \(Int(r.goal))h")).font(.caption).foregroundStyle(c.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? c.chip : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? da.c.action : .clear, lineWidth: 1.5))
            }
            .frame(width: Self.slot)
        }
        .buttonStyle(DAPress())
        .accessibilityLabel(CL("\(r.name), \(Int(r.logged)) of \(Int(r.goal)) hours"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func model(_ r: DuoRental) -> some View {
        if r.isAll {
            // All rentals: three small houses grouped on one lot edge.
            ZStack {
                ForEach(Array(items.dropFirst().prefix(3).enumerated()), id: \.element.id) { i, h in
                    image(h).frame(width: Self.model * 0.62, height: Self.model * 0.62)
                        .offset(x: CGFloat(i - 1) * Self.model * 0.27, y: CGFloat(abs(i - 1)) * -Self.model * 0.04 + Self.model * 0.16)
                        .zIndex(i == 1 ? 1 : 0)
                }
            }
        } else {
            image(r)
        }
    }

    private func image(_ r: DuoRental) -> some View {
        Image(r.lit ? r.art.rawValue : (CraftHouseArt.unlitName(for: r.art) ?? r.art.rawValue))
            .resizable().interpolation(.high).scaledToFit()
            .brightness(scheme == .dark ? CraftHouseArt.nightLift(r.art) : 0)
    }
}

// MARK: - Propped up (upright 669x951, the fold across at y 463.5-487.5): house + shelf above, workstation below

@available(iOS 26.0, *)
struct DuoProppedView: View {
    @State private var selectedID = "santa"
    @State private var right: DuoRight = .list
    @State private var tab = 0
    private var half: CGFloat { (DuoGeo.propped.height - DuoGeo.hinge) / 2 }     // 463.5
    var body: some View {
        // The TabView is the root, so its bar sits at the foot of the screen: the resting bottom half.
        TabView(selection: $tab) {
            Tab(CL("Today"), systemImage: "sun.horizon", value: 0) {
                VStack(spacing: 0) {
                    DuoHousePane(rentals: DuoV2Seed.three, selectedID: $selectedID, heroSide: 220, compact: true)
                        .padding(.top, 44)
                        .frame(height: half, alignment: .top)
                        .background { CraftPage().ignoresSafeArea() }
                    Color.clear.frame(height: DuoGeo.hinge)
                    DuoWorkstation(rentals: DuoV2Seed.three, selectedID: $selectedID, right: $right, maxRows: 3)
                        .frame(maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
                .background { VStack(spacing: 0) { CraftPage(); DuoInterior() }.ignoresSafeArea() }
            }
            Tab(CL("Inbox"), systemImage: "tray", value: 1) { DuoInterior() }.badge(7)
            Tab(CL("Records"), systemImage: "book.closed", value: 2) { DuoInterior() }
            Tab(CL("Rentals"), systemImage: "house", value: 3) { DuoInterior() }
            Tab(CL("Log time"), systemImage: "plus", value: 4, role: .search) { DuoInterior() }
        }
        .modifier(DuoTint())
        .modifier(DuoNoVerticalBar())   // the Duo's vertical tab rail would sit across the fold here; keep the bottom bar
        .frame(width: DuoGeo.propped.width, height: DuoGeo.propped.height)
        .background { VStack(spacing: 0) { CraftPage(); DuoInterior() } }
    }
}

// MARK: - Shared grouped container (20pt continuous, card edge token)

struct DuoCard<Content: View>: View {
    @ViewBuilder var content: Content
    private var env = DAEnv()
    private var craft = CraftEnv()
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(env.c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

// MARK: - Snapshotter: lays the open layout out in an off-screen window and renders it with drawHierarchy

@available(iOS 26.0, *)
@MainActor
enum DuoV2Snapshotter {
    static var windows: [UIWindow] = []

    static func run() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("duo2")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mode = DuoV2Launch.mode ?? "render"
        for dark in [false, true] {
            let tag = dark ? "night" : "dusk"
            var shots: [(String, AnyView, DynamicTypeSize)] = []
            for (size, sfx) in [(DynamicTypeSize.large, ""), (.xxLarge, "-XXL")] {
                shots += [
                    ("open-3rentals\(sfx)", AnyView(DuoOpenView()), size),
                    ("open-8rentals\(sfx)", AnyView(DuoOpenView(rentals: DuoV2Seed.eight, selectedID: "bay")), size),
                    ("open-detail\(sfx)", AnyView(DuoOpenView(right: .detail("s1"))), size),
                    ("open-logtime\(sfx)", AnyView(DuoOpenView(right: .log)), size),
                ]
            }
            shots.append(("open-allrentals", AnyView(DuoOpenView(selectedID: "all")), .large))
            shots.append(("open-hinge-annotated", AnyView(DuoOpenView(annotate: true)), .large))
            for (name, view, size) in shots {
                await render(view, size: DuoGeo.open, dark: dark, typeSize: size, scene: scene,
                             to: dir.appendingPathComponent("\(name)-\(tag).png"))
            }
            await render(AnyView(DuoProppedView()), size: DuoGeo.propped, dark: dark, typeSize: .large, scene: scene,
                         to: dir.appendingPathComponent("propped-\(tag).png"), insets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
            if mode == "motion" {
                // The workstation without the door, for the clip composite (the door frames go over the left pane).
                await render(AnyView(DuoOpenView()), size: DuoGeo.open, dark: dark, typeSize: .large, scene: scene,
                             to: dir.appendingPathComponent("motion-base-\(tag).png"))
            }
        }
        NSLog("DUOV2_DONE %@", dir.path)
        try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
    }

    private static func makeWindow(_ view: AnyView, size: CGSize, dark: Bool, typeSize: DynamicTypeSize, scene: UIWindowScene,
                                   insets: EdgeInsets) -> UIWindow {
        let root = view
            .safeAreaPadding(insets)
            .environment(\.dynamicTypeSize, typeSize)
            .frame(width: size.width, height: size.height)
        let hc = UIHostingController(rootView: AnyView(root))
        hc.overrideUserInterfaceStyle = dark ? .dark : .light
        // Each pane is ~464pt, so the panes lay out compact; the system tab bar then sits in the left pane.
        hc.traitOverrides.horizontalSizeClass = .compact
        hc.traitOverrides.verticalSizeClass = .regular
        hc.safeAreaRegions = []            // the folded screen's trailing status column must not leak in
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(origin: .zero, size: size)
        w.windowLevel = .normal - 1
        w.rootViewController = hc
        w.isHidden = false
        windows.append(w)
        return w
    }

    private static func render(_ view: AnyView, size: CGSize, dark: Bool, typeSize: DynamicTypeSize, scene: UIWindowScene, to url: URL,
                               insets: EdgeInsets = EdgeInsets(top: DuoGeo.topInset, leading: 0, bottom: DuoGeo.bottomInset, trailing: 0)) async {
        let w = makeWindow(view, size: size, dark: dark, typeSize: typeSize, scene: scene, insets: insets)
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            _ = w.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        try? img.pngData()?.write(to: url)
        w.isHidden = true
    }
}
#endif
