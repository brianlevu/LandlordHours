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
    /// Room the floating tab bar takes at the foot of a pane (bar ~62pt + its float gap + a little air).
    static let barClearance: CGFloat = 84
}

enum DuoRight: Equatable { case list, detail(String), log }

/// Door clock: 0 = door shut and the workstation dark; 1 = door open, workstation lit. Every door visual is a pure
/// function of t, so the clip frames and the live animation (keyframes on onHingeChange) are the same thing.
@Observable final class DuoDoorClock { var t: Double = 1 }

func duoEase(_ x: Double, _ a: Double, _ b: Double) -> Double {
    let u = min(max((x - a) / (b - a), 0), 1)
    return 1 - pow(1 - u, 3)
}

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
        DuoRental(id: "pine", name: "Pine Cabin", logged: 262, goal: 500, lit: true, stage: .half),
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
    var clock: DuoDoorClock

    init(rentals: [DuoRental] = DuoV2Seed.three, selectedID: String = "pine", right: DuoRight = .list, annotate: Bool = false,
         clock: DuoDoorClock = DuoDoorClock()) {
        self.rentals = rentals; _selectedID = State(initialValue: selectedID); _right = State(initialValue: right)
        self.annotate = annotate; self.clock = clock
    }

    var body: some View {
        HStack(spacing: 0) {
            DuoHousePane(rentals: rentals, selectedID: $selectedID, clock: clock).frame(width: DuoGeo.pane)
            Color.clear.frame(width: DuoGeo.hinge)        // the division region: no text, no art crosses it
            workstationTabs.frame(width: DuoGeo.pane)
                .overlay { DuoInsideLight(clock: clock).allowsHitTesting(false) }
        }
        .background {
            HStack(spacing: 0) {
                CraftPage()
                    .overlay { DuoFoldWash() }
                    .frame(width: DuoGeo.pane + DuoGeo.hinge / 2)
                DuoInterior()
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

    /// The system TabView, laid out at the right pane's compact width, so its bar sits at the foot of the workstation:
    /// the tabs switch the work, and "+" (Log time) sits beside the list it adds to.
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
        .modifier(DuoNoVerticalBar())   // in the trailing pane the system otherwise collapses the bar into a side rail
    }
}

/// iOS 27.1: opt out of the Duo's vertical toolbar so the tab bar stays at the foot of the resting half.
private struct DuoNoVerticalBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) { content.toolbarVerticalBehavior(.disabled) } else { content }
    }
}

/// The house's ink on the native tab bar: unselected items in textPrimary (#121B33 / #F2F4FA) instead of stock black.
enum DuoTabBarInk {
    static func apply() {
        UITabBar.appearance().unselectedItemTintColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0xF2/255, green: 0xF4/255, blue: 0xFA/255, alpha: 0.85)
            : UIColor(red: 0x12/255, green: 0x1B/255, blue: 0x33/255, alpha: 1) }
    }
}

private struct DuoTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(CraftColors(dark: scheme == .dark).action) }
}

/// The workstation lights from the fold outward as the door opens: a warm-dark scrim whose edge travels left to right.
struct DuoInsideLight: View {
    var clock: DuoDoorClock
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let r = duoEase(clock.t, 0.12, 0.76)
        if r < 1 {
            Color(hex: scheme == .dark ? "05081A" : "2A1A0A").opacity(scheme == .dark ? 0.78 : 0.70)
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .clear, location: max(0, r * 1.3 - 0.3)),
                                           .init(color: .black, location: min(1, r * 1.3))],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .ignoresSafeArea()
        }
    }
}

/// The door's light leaking back across the fold onto the house pane: the same colour and strength as the inside
/// wall at the fold line (so the two walls meet without a seam), fading within ~150pt.
struct DuoFoldWash: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        RadialGradient(colors: [Color(hex: dark ? "FFC877" : "FFE6C2").opacity(dark ? 0.09 : 0.55), .clear],
                       center: UnitPoint(x: 1, y: 0.38), startRadius: 0, endRadius: 150)
            .blendMode(dark ? .plusLighter : .screen)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// The inside wall. The same page gradient as the house pane, so the fold has no seam; round-1 A's room shows through
/// desaturated (dusty, low-chroma) and only away from the door; the door's light pools at the fold side.
struct DuoInterior: View {
    /// Where the door's light comes from, in this view's unit space (the fold edge).
    var glowCenter = UnitPoint(x: 0, y: 0.38)
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        GeometryReader { g in
            ZStack {
                CraftPage()
                // By day the room shows through, dusty; at night it is the navy page with one warm pool (the door).
                if !dark {
                Image("duo_interior").resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                    .saturation(dark ? 0.15 : 0.45)
                    .blendMode(dark ? .multiply : .multiply)
                    .opacity(dark ? 0.55 : 0.42)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.18),
                                                 .init(color: .black, location: 0.85)], startPoint: .leading, endPoint: .trailing))
                }
                // doorGlow: the light from the open door, brightest at the fold, fading outward.
                RadialGradient(colors: [Color(hex: dark ? "FFC877" : "FFE6C2").opacity(dark ? 0.09 : 0.55), .clear],
                               center: glowCenter, startRadius: 0, endRadius: 370)
                    .blendMode(dark ? .plusLighter : .screen)
            }
        }
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

    init(rentals: [DuoRental], selectedID: Binding<String>, right: Binding<DuoRight>, maxRows: Int? = nil,
         glowCenter: UnitPoint = UnitPoint(x: -DuoGeo.hinge / 2 / DuoGeo.pane, y: 0.38)) {
        self.rentals = rentals; _selectedID = selectedID; _right = right; self.maxRows = maxRows; self.glowCenter = glowCenter
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

    var glowCenter: UnitPoint
    var body: some View {
        ZStack { DuoInterior(glowCenter: glowCenter); content }
    }

    @ViewBuilder private var content: some View {
        switch right {
        case .list: list
        case .detail(let id): detail(all.first { $0.id == id } ?? all[0])
        case .log:
            DALogTimeSheet(demo: nil, showsEyebrow: false, rental: selected?.name ?? DuoV2Seed.three[0].name, onLog: { _, _ in right = .list }, onClose: { right = .list })
                .background(c.sheet)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        }
    }

    private var list: some View {
        ScrollView {
            DuoCard {
                HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CL("To confirm")).font(.headline).foregroundStyle(c.ink)
                        .accessibilityAddTraits(.isHeader)
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
                    } else {
                        Text(CL("Every rental")).font(.subheadline).foregroundStyle(c.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                // Round-1 A's summary-bar figure: the number set large on the right of a slim bar.
                Text(verbatim: "\(items.count - confirmed.count)")
                    .font(DAFont.fraunces(size: 44, opsz: 144, wght: 600)).tracking(-1)
                    .foregroundStyle(c.ink).monospacedDigit()
                    .contentTransition(.numericText(value: Double(items.count - confirmed.count)))
                    .accessibilityLabel(CL("\(items.count - confirmed.count) to confirm"))
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
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
            .padding(.horizontal, 16).padding(.top, 8)
            if let s = selected { loggedToday(s).padding(.horizontal, 16).padding(.top, 10) }
        }
        .contentMargins(.bottom, DuoGeo.barClearance, for: .scrollContent)   // at rest the last card ends above the bar
        .scrollIndicators(.hidden)
    }

    /// The honest fill for a filtered list: what is already on the record today at this rental.
    private func loggedToday(_ r: DuoRental) -> some View {
        let entries: [(String, String, Double)] = r.lit
            ? [(CL("Fixed the porch step"), CL("Repairs · 8–9:30"), 1.5), (CL("Picked up paint for the trim"), CL("Repairs · 11–11:30"), 0.5)]
            : []
        return DuoCard {
            HStack(alignment: .firstTextBaseline) {
                Text(CL("On the record today")).font(.headline).foregroundStyle(c.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                if !entries.isEmpty {
                    Text(StdFormat.hours(entries.reduce(0) { $0 + $1.2 })).font(.headline).monospacedDigit().foregroundStyle(c.ink)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            if entries.isEmpty {
                // Zero logged: one honest line, no figure, no button. The card keeps its place so the page doesn't jump.
                DAHairline().padding(.leading, 16)
                Text(CL("Nothing logged yet today."))
                    .font(.subheadline).foregroundStyle(c.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 14)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                DAHairline().padding(.leading, 16)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.0).font(.body.weight(.semibold)).foregroundStyle(c.ink).fixedSize(horizontal: false, vertical: true)
                        Text(e.1).font(.footnote).foregroundStyle(c.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(StdFormat.hours(e.2)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(c.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 52)
            }
        }
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
    var clock: DuoDoorClock
    private var env = CraftEnv()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rentals: [DuoRental], selectedID: Binding<String>, heroSide: CGFloat = 290, compact: Bool = false, clock: DuoDoorClock) {
        self.rentals = rentals; _selectedID = selectedID; self.heroSide = heroSide; self.compact = compact; self.clock = clock
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
        ZStack {
            CraftHouseArt(art: focus.art, dark: scheme == .dark, side: side, building: false, buildTick: 0,
                          windowsLit: focus.lit, fillStage: true) {}
            DuoFrontDoor(art: focus.art, side: side, clock: clock)
        }
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
    @ScaledMetric(relativeTo: .footnote) private var slotW: CGFloat = 108   // wide enough that labels wrap at word breaks
    @Environment(\.dynamicTypeSize) private var typeSize
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
            .mask {   // edges once the shelf scrolls: steep, so a label is either readable (>= 4.5:1) or cut, never mid-fade
                GeometryReader { g in
                    let w = max(g.size.width, 1)
                    LinearGradient(stops: (items.count > 4 || typeSize.isAccessibilitySize)
                                   ? [.init(color: .clear, location: 0), .init(color: .clear, location: 9 / w),
                                      .init(color: .black.opacity(0.8), location: 13 / w), .init(color: .black, location: 36 / w),
                                      .init(color: .black, location: 1 - 36 / w), .init(color: .black.opacity(0.8), location: 1 - 13 / w),
                                      .init(color: .clear, location: 1 - 9 / w), .init(color: .clear, location: 1)]
                                   : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
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
                    Text(status(r)).font(.caption).foregroundStyle(c.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? c.chip : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? c.chipBorder : .clear, lineWidth: 0.8))
                .shadow(color: .black.opacity(on ? 0.10 : 0), radius: 4, y: 1)
            }
            .frame(width: max(Self.slot, slotW))
        }
        .buttonStyle(DAPress())
        .accessibilityLabel(CL("\(r.name), \(status(r))"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "46 of 100h" per rental. "All rentals" never sums goals from different tests: it says how many are behind.
    private func status(_ r: DuoRental) -> String {
        guard r.isAll else { return CL("\(Int(r.logged)) of \(Int(r.goal))h") }
        let rentals = items.filter { !$0.isAll }
        let behind = rentals.filter { $0.focus.isBehind }.count
        return behind == 0 ? CL("All on pace") : CL("\(behind) of \(rentals.count) behind")
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

/// The front door, swung open by the clock. The leaf is the still's own door pixels, hinged on its left jamb, with warm
/// light in the doorway and on the step. Measured on craft_half (1206px still): x 627-676, y 567-712.
struct DuoFrontDoor: View {
    let art: CraftArt
    let side: CGFloat
    var clock: DuoDoorClock
    @Environment(\.colorScheme) private var scheme
    private static let doorPx = CGRect(x: 627, y: 567, width: 49, height: 145)
    private var door: CGRect {
        let k = side / 1206
        return CGRect(x: Self.doorPx.minX * k, y: Self.doorPx.minY * k, width: Self.doorPx.width * k, height: Self.doorPx.height * k)
    }
    var body: some View {
        if art == .half {
            let open = duoEase(clock.t, 0.0, 0.42)
            let glow = duoEase(clock.t, 0.05, 0.5)
            let dark = scheme == .dark
            let warm = Color(hex: dark ? "FFC877" : "F2B872")
            ZStack(alignment: .topLeading) {
                // The hall behind the door. At night it is the brightest thing on the house; at dusk it is a dim
                // interior with a soft lamp glow, never brighter than the daylit facade.
                Rectangle()
                    .fill(dark
                          ? AnyShapeStyle(LinearGradient(colors: [warm, warm.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(LinearGradient(colors: [Color(hex: "2A1C12"), Color(hex: "4A3220")], startPoint: .top, endPoint: .bottom)))
                    .overlay {
                        if !dark {
                            RadialGradient(colors: [warm.opacity(0.75), .clear], center: UnitPoint(x: 0.65, y: 0.45),
                                           startRadius: 0, endRadius: door.height * 0.55)
                        }
                    }
                    .frame(width: door.width, height: door.height).offset(x: door.minX, y: door.minY)
                    .opacity(glow)
                // Spill on the step and path: a smooth radial falloff (no edge), brightest at the threshold, pushed
                // forward and to the viewer's left by the leaf's swing (a shear that grows with the door angle).
                let spill = door.width * 3.4
                RadialGradient(stops: [.init(color: warm.opacity(dark ? 0.62 : 0.42), location: 0),
                                       .init(color: warm.opacity(dark ? 0.40 : 0.27), location: 0.22),
                                       .init(color: warm.opacity(dark ? 0.19 : 0.13), location: 0.48),
                                       .init(color: warm.opacity(dark ? 0.06 : 0.03), location: 0.76),
                                       .init(color: warm.opacity(0), location: 1)],
                               center: .center, startRadius: 0, endRadius: spill / 2)
                    .frame(width: spill, height: spill * 0.62)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: 0.45 * open, d: 1, tx: 0, ty: 0))
                    .rotationEffect(.degrees(16 * open))
                    .offset(x: door.midX - spill / 2 + door.width * (0.5 + 0.9 * open), y: door.maxY - spill * 0.62 / 2 + door.width * 0.5)
                    .blendMode(dark ? .plusLighter : .screen)
                    .opacity(glow)
                    .allowsHitTesting(false)
                // The leaf: the still's own door pixels, swung on its left hinge in perspective (a sheared quad that
                // narrows and turns away), darkening as it turns out of the light.
                Image(art.rawValue).resizable().interpolation(.high)
                    .frame(width: side, height: side)
                    .brightness(dark ? CraftHouseArt.nightLift(art) : 0)
                    .mask(alignment: .topLeading) {
                        Rectangle().frame(width: door.width, height: door.height).offset(x: door.minX, y: door.minY)
                    }
                    .brightness(-0.12 * open)
                    .rotation3DEffect(.degrees(-78 * open), axis: (x: 0, y: 1, z: 0),
                                      anchor: UnitPoint(x: door.minX / side, y: (door.midY) / side), perspective: 2.2)
                    .shadow(color: .black.opacity(0.35 * open), radius: 1.5, x: 1, y: 0)
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Propped up (upright 669x951, the fold across at y 463.5-487.5): house + shelf above, workstation below

@available(iOS 26.0, *)
struct DuoProppedView: View {
    @State private var selectedID = "pine"
    @State private var right: DuoRight = .list
    @State private var tab = 0
    private var half: CGFloat { (DuoGeo.propped.height - DuoGeo.hinge) / 2 }     // 463.5
    var body: some View {
        // The TabView is the root, so its bar sits at the foot of the screen: the resting bottom half.
        TabView(selection: $tab) {
            Tab(CL("Today"), systemImage: "sun.horizon", value: 0) {
                VStack(spacing: 0) {
                    DuoHousePane(rentals: DuoV2Seed.three, selectedID: $selectedID, heroSide: 220, compact: true, clock: DuoDoorClock())
                        .padding(.top, 44)
                        .frame(height: half, alignment: .top)
                        .background { CraftPage().ignoresSafeArea() }
                    Color.clear.frame(height: DuoGeo.hinge)
                    DuoWorkstation(rentals: DuoV2Seed.three, selectedID: $selectedID, right: $right, maxRows: 1,
                                   glowCenter: UnitPoint(x: 0.5, y: -0.05))
                        .frame(maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
                .background { VStack(spacing: 0) { CraftPage(); DuoInterior(glowCenter: UnitPoint(x: 0.5, y: 0)) }.ignoresSafeArea() }
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
    @Environment(\.colorScheme) private var scheme
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    /// Light: pageCardEdge. Night: duoNightCardEdge #3A4778 (new, Duo only): 2.06:1 on the night room #0B1230, inside
    /// the H.4 card-edge band (1.9-2.2); the shared dark edge #2A3560 measures 1.55 there.
    private var edge: Color { scheme == .dark ? Color(hex: "3A4778") : craft.c.cardEdge }
    /// Night: a slightly brighter edge on the fold side only, where the card crosses the warm pool (2.0:1 there).
    private var edgeStyle: AnyShapeStyle {
        scheme == .dark
            ? AnyShapeStyle(LinearGradient(stops: [.init(color: Color(hex: "424F84"), location: 0), .init(color: edge, location: 0.55)],
                                           startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(edge)
    }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(env.c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(edgeStyle, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

// MARK: - Snapshotter: lays the open layout out in an off-screen window and renders it with drawHierarchy

@available(iOS 26.0, *)
@MainActor
enum DuoV2Snapshotter {
    static var windows: [UIWindow] = []

    static func run() async {
        DuoTabBarInk.apply()
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
                    ("open-detail\(sfx)", AnyView(DuoOpenView(right: .detail("s5"))), size),
                    ("open-logtime\(sfx)", AnyView(DuoOpenView(right: .log)), size),
                ]
            }
            shots += [
                ("open-3rentals-AX3", AnyView(DuoOpenView()), .accessibility3),
                ("open-zerologged", AnyView(DuoOpenView(rentals: DuoV2Seed.eight, selectedID: "oak")), .large),
            ]
            shots.append(("open-allrentals", AnyView(DuoOpenView(selectedID: "all")), .large))
            shots.append(("open-hinge-annotated", AnyView(DuoOpenView(annotate: true)), .large))
            for (name, view, size) in shots {
                await render(view, size: DuoGeo.open, dark: dark, typeSize: size, scene: scene,
                             to: dir.appendingPathComponent("\(name)-\(tag).png"))
            }
            await render(AnyView(DuoProppedView()), size: DuoGeo.propped, dark: dark, typeSize: .large, scene: scene,
                         to: dir.appendingPathComponent("propped-\(tag).png"), insets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
            if mode == "motion" {
                let clock = DuoDoorClock(); clock.t = 0
                let w = makeWindow(AnyView(DuoOpenView(clock: clock)), size: DuoGeo.open, dark: dark, typeSize: .large, scene: scene,
                                   insets: EdgeInsets(top: DuoGeo.topInset, leading: 0, bottom: DuoGeo.bottomInset, trailing: 0))
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let mdir = dir.appendingPathComponent("motion-\(tag)")
                try? FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)
                for i in 0..<48 {
                    clock.t = Double(i) / 47
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    snap(w, size: DuoGeo.open, to: mdir.appendingPathComponent(String(format: "f_%03d.png", i)))
                }
                w.isHidden = true
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
        snap(w, size: size, to: url)
        w.isHidden = true
    }

    private static func snap(_ w: UIWindow, size: CGSize, to url: URL) {
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            _ = w.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        try? img.pngData()?.write(to: url)
    }
}
#endif
