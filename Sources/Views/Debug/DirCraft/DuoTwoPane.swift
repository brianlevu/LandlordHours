import SwiftUI
import UIKit

#if DEBUG
// MARK: - Duo round 2, "two panes, split at the fold" (DEBUG mock, throwaway)
//
// Open, the iPhone Duo shows two separate screens, never one layout stretched across the fold:
//   left pane  "outside": the rental's lit house, its hours and pace, every rental in a short list, and the tab bar.
//   right pane "inside":  the work. To confirm, a tapped item's detail, or Log time, all in this pane, never a sheet.
// Unfolding opens the house's front door; the light from the doorway washes into the right pane as its content appears.
//
//   -LHDirection CRAFT -LHDuoV2 render   the closed app on screen (outer display); the OPEN layout (669x951pt @3x)
//                                        is laid out in a second, off-screen window and written to Documents/duo2/.
//                                        An agent cannot unfold the simulator (posture is a Device Hub GUI action).
//   -LHDirection CRAFT -LHDuoV2 motion   also writes the door clip frames (48 at 60 fps, dusk and night).
//
// Production shape (iOS 27.1 SDK, not reachable on the folded simulator):
//   ArrangementView { left } secondary: { right }.arrangementViewStyle(.split.axes(.horizontal))
//     .splitArrangementLayoutRatio(0.5) on the primary; GeometryProxy.reservedRegions(kind: .division,
//     options: .includeInactive) gives the fold's frame, and both panes keep clear of it.
//   onHingeChange { old, new in } (DeviceHingeContext.hinge?.status: .closed / .partiallyOpen / .fullyOpen) starts the door.
// The mock uses an HStack with an assumed 24pt division band in the middle (DuoGeo.hinge). Open = landscape 951x669.

enum DuoV2Launch {
    static var mode: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let j = a.firstIndex(of: "-LHDuoV2"), a.indices.contains(j + 1) else { return nil }
        return a[j + 1].lowercased()
    }
}

enum DuoGeo {
    /// Held open, the inner display is LANDSCAPE: 951x669pt, the fold running top to bottom down the middle.
    /// Each half (~464x669) matches the closed outer display (466x678), which is how the fold's axis was inferred:
    /// the device profile lists the inner framebuffer as 2007x2853 (portrait) with no fold geometry.
    static let open = CGSize(width: 951, height: 669)
    /// Propped up (tabletop): the same display upright, so the fold runs across it.
    static let propped = CGSize(width: 669, height: 951)
    /// Assumed division band (reserved rect plus margins). The real value comes from reservedRegions(kind: .division).
    static let hinge: CGFloat = 24
    static var pane: CGFloat { (open.width - hinge) / 2 }      // 463.5
    static let topInset: CGFloat = 24                           // landscape status bar (assumed)
    static let bottomInset: CGFloat = 20                        // home indicator (assumed)
}

/// Door clock: 0 = door shut, inside dark; 1 = door open, inside lit. Every door visual is a pure function of t,
/// so the clip frames and the live keyframe animation are the same thing.
@Observable final class DuoDoorClock { var t: Double = 1 }

enum DuoRight: Equatable { case list, detail(String), log, rental(String) }

struct DuoRental: Identifiable {
    let id: String
    let name: String
    let logged: Double
    let goal: Double
    let lit: Bool
    /// The seed's art for the stage (Pine Cabin is "roof on, siding half" in the locked Today seed).
    var stage: CraftArt? = nil
    var art: CraftArt { stage ?? CraftFocus.art(hours: logged, goal: goal) }
    var focus: CraftFocus { CraftFocus(id: id, name: name, logged: logged, goal: goal, art: art) }
}

enum DuoV2Seed {
    static let rentals: [DuoRental] = [
        DuoRental(id: "santa", name: "Santa Ray Ave", logged: 46, goal: 100, lit: true),
        DuoRental(id: "delaney", name: "Delaney Ct", logged: 4, goal: 100, lit: false),
        DuoRental(id: "pine", name: "Pine Cabin", logged: 262, goal: 500, lit: true, stage: .half),
    ]
    static var suggestions: [StdSuggestion] { StdSeed.make("brian").suggestions }
}

private func ease(_ x: Double, _ a: Double, _ b: Double) -> Double {
    let u = min(max((x - a) / (b - a), 0), 1)
    return 1 - pow(1 - u, 3)          // ease-out cubic
}

// MARK: - The open layout

@available(iOS 26.0, *)
struct DuoOpenView: View {
    @State var tab: Int
    @State var right: DuoRight
    @State var focusID: String
    var clock: DuoDoorClock
    /// Snapshot hook: draw the division band (annotation copy only).
    var annotate = false

    @State private var confirmed: Set<String> = []
    private var env = DAEnv()
    private var craft = CraftEnv()
    @Environment(\.colorScheme) private var scheme

    init(tab: Int = 0, right: DuoRight = .list, focusID: String = "pine", clock: DuoDoorClock, annotate: Bool = false) {
        _tab = State(initialValue: tab); _right = State(initialValue: right); _focusID = State(initialValue: focusID)
        self.clock = clock; self.annotate = annotate
    }

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: DuoGeo.pane)
            Color.clear.frame(width: DuoGeo.hinge)        // the division region: no text, no art crosses it
            DuoInsidePane(tab: tab, right: $right, focusID: $focusID, clock: clock)
                .frame(width: DuoGeo.pane)
        }
        .background {
            HStack(spacing: 0) {
                CraftPage().frame(width: DuoGeo.pane + DuoGeo.hinge / 2)
                DuoInsideBackground(clock: clock)
            }
            .ignoresSafeArea()
        }
        .overlay {
            if annotate {
                Rectangle().fill(Color.pink.opacity(0.28))
                    .overlay(Rectangle().strokeBorder(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: DuoGeo.hinge)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: tab) { old, new in
            if new == 4 { tab = old; right = .log }
            else if new == 3 { right = .rental(focusID) }
            else if old == 3 || right == .log { right = .list }
        }
    }

    /// Left pane: the real system TabView, laid out at the pane's compact width, so the bar lives in this pane.
    private var left: some View {
        TabView(selection: $tab) {
            Tab(CL("Today"), systemImage: "sun.horizon", value: 0) {
                DuoOutsideToday(focusID: $focusID, clock: clock)
            }
            Tab(CL("Inbox"), systemImage: "tray", value: 1) { DuoPlaceholder(title: CL("Inbox")) }.badge(7)
            Tab(CL("Records"), systemImage: "book.closed", value: 2) { DuoPlaceholder(title: CL("Records")) }
            Tab(CL("Rentals"), systemImage: "house", value: 3) {
                DuoOutsideRentals(focusID: $focusID, onPick: { right = .rental($0) })
            }
            Tab(CL("Log time"), systemImage: "plus", value: 4, role: .search) { CraftPage() }
        }
        .modifier(DuoTint())
    }
}

private struct DuoTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(CraftColors(dark: scheme == .dark).action) }
}

private struct DuoPlaceholder: View {
    let title: String
    var body: some View { CraftPage() }
}

// MARK: - Left pane, Today: the house, the number, every rental

struct DuoOutsideToday: View {
    @Binding var focusID: String
    var clock: DuoDoorClock
    private var env = CraftEnv()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(focusID: Binding<String>, clock: DuoDoorClock) { _focusID = focusID; self.clock = clock }

    private var c: CraftColors { env.c }
    private var rentals: [DuoRental] { DuoV2Seed.rentals }
    private var focus: DuoRental { rentals.first { $0.id == focusID } ?? rentals[0] }
    private var side: CGFloat { typeSize.isAccessibilitySize ? 200 : 268 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    DuoHouse(art: focus.art, lit: focus.lit, side: side, clock: clock)
                        .id(focus.id)
                    numberBlock.frame(maxWidth: .infinity)
                }
                .padding(.leading, 4).padding(.trailing, 12)
                rentalList.padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background { CraftPage() }
    }

    private var numberBlock: some View {
        let f = focus.focus
        let p = f.pace
        return VStack(alignment: .leading, spacing: 2) {
            Text(f.name).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
            Text(verbatim: "\(Int(f.logged))")
                .font(DAFont.fraunces(size: 72, opsz: 144, wght: 600)).tracking(-2)
                .foregroundStyle(c.ink).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Text(CL("of \(Int(f.goal)) hours")).font(.subheadline).foregroundStyle(c.textSecondary)
            (Text(p.lead).foregroundStyle(f.isBehind ? c.behind : c.positive).fontWeight(.semibold)
             + Text(verbatim: " ") + Text(p.rest).foregroundStyle(c.textSecondary))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Every rental, one tap each. 56pt rows; the selected one carries the action tint.
    private var rentalList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(CL("Your rentals")).font(.headline).foregroundStyle(c.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(CL("\(Int(rentals.reduce(0) { $0 + $1.logged }))h in all"))
                    .font(.footnote).foregroundStyle(c.textSecondary).monospacedDigit()
            }
            .padding(.horizontal, 4)
            DuoCard {
                ForEach(Array(rentals.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { DAHairline().padding(.leading, 60) }
                    DuoRentalRow(rental: r, selected: r.id == focusID, compact: true) {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0)) { focusID = r.id }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct DuoRentalRow: View {
    let rental: DuoRental
    let selected: Bool
    var compact = false
    let onTap: () -> Void
    private var env = CraftEnv()
    private var da = DAEnv()
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var thumb: CGFloat = 40

    init(rental: DuoRental, selected: Bool, compact: Bool = false, onTap: @escaping () -> Void) {
        self.rental = rental; self.selected = selected; self.compact = compact; self.onTap = onTap
    }

    var body: some View {
        let c = env.c
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(rental.lit ? rental.art.rawValue : (CraftHouseArt.unlitName(for: rental.art) ?? rental.art.rawValue))
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: min(thumb, 56), height: min(thumb, 56))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rental.name).font(.body.weight(.semibold)).foregroundStyle(c.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CL("\(Int(rental.logged)) of \(Int(rental.goal))h · \(rental.lit ? CL("worked on today") : CL("not today"))"))
                        .font(.footnote).foregroundStyle(c.textSecondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(da.c.action)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(selected ? da.c.actionSurface : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(DAPress())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Left pane, Rentals: the list of houses (outside)

struct DuoOutsideRentals: View {
    @Binding var focusID: String
    let onPick: (String) -> Void
    private var env = CraftEnv()
    init(focusID: Binding<String>, onPick: @escaping (String) -> Void) { _focusID = focusID; self.onPick = onPick }
    var body: some View {
        let c = env.c
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(CL("Rentals")).font(DAFont.fraunces(size: 34, opsz: 72, wght: 600)).foregroundStyle(c.ink)
                    .accessibilityAddTraits(.isHeader).padding(.horizontal, 4).padding(.top, 8)
                Text(CL("\(DuoV2Seed.rentals.count) rentals · \(DuoV2Seed.rentals.filter(\.lit).count) worked on today"))
                    .font(.subheadline).foregroundStyle(c.textSecondary).padding(.horizontal, 4).padding(.bottom, 8)
                DuoCard {
                    ForEach(Array(DuoV2Seed.rentals.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { DAHairline().padding(.leading, 60) }
                        DuoRentalRow(rental: r, selected: r.id == focusID) { focusID = r.id; onPick(r.id) }
                    }
                    DAHairline()
                    Button {} label: {
                        Label(CL("Add a rental"), systemImage: "plus").font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .foregroundStyle(c.action).buttonStyle(DAPress())
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .background { CraftPage() }
    }
}

// MARK: - The house with a front door that opens (the door is SwiftUI over the still; half and complete stages)

struct DuoHouse: View {
    let art: CraftArt
    let lit: Bool
    let side: CGFloat
    var clock: DuoDoorClock
    @Environment(\.colorScheme) private var scheme

    /// The door leaf in the 1206px still (measured on craft_half: x 627-676, y 567-712, hinge on the left).
    private static let doorPx = CGRect(x: 627, y: 567, width: 49, height: 145)
    private var hasDoor: Bool { art == .half }
    private var door: CGRect {
        let k = side / 1206
        return CGRect(x: Self.doorPx.minX * k, y: Self.doorPx.minY * k, width: Self.doorPx.width * k, height: Self.doorPx.height * k)
    }
    private var open: Double { ease(clock.t, 0.0, 0.42) }          // the leaf swings in 0-0.34s
    private var glow: Double { ease(clock.t, 0.05, 0.5) }
    private var warm: Color { Color(hex: scheme == .dark ? "FFC877" : "FFD9A0") }

    var body: some View {
        ZStack {
            CraftHouseArt(art: art, dark: scheme == .dark, side: side, building: false, buildTick: 0,
                          windowsLit: lit, fillStage: true) {}
            if hasDoor {
                ZStack(alignment: .topLeading) {
                    // The lit hall behind the door.
                    Rectangle()
                        .fill(LinearGradient(colors: [warm, warm.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .frame(width: door.width, height: door.height)
                        .offset(x: door.minX, y: door.minY)
                        .opacity(glow)
                    // Light falling out of the doorway onto the step and the path.
                    Ellipse()
                        .fill(RadialGradient(colors: [warm.opacity(0.85), warm.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: door.width * 1.6))
                        .frame(width: door.width * 3.2, height: door.width * 1.3)
                        .offset(x: door.minX - door.width * 0.6, y: door.maxY - door.width * 0.45)
                        .blendMode(scheme == .dark ? .plusLighter : .screen)
                        .opacity(glow * 0.9)
                    // The leaf: the still's own door pixels, swung on the left jamb.
                    Image(art.rawValue).resizable().interpolation(.high)
                        .frame(width: side, height: side)
                        .brightness(scheme == .dark ? CraftHouseArt.nightLift(art) : 0)
                        .mask(alignment: .topLeading) {
                            Rectangle().frame(width: door.width, height: door.height).offset(x: door.minX, y: door.minY)
                        }
                        .brightness(-0.18 * open)
                        .scaleEffect(x: 1 - 0.78 * open, y: 1, anchor: UnitPoint(x: door.minX / side, y: 0.5))
                }
                .frame(width: side, height: side, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CL("House, \(art.label), front door open"))
    }
}

// MARK: - Right pane: inside

struct DuoInsideBackground: View {
    var clock: DuoDoorClock
    private var da = DAEnv()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let lit = ease(clock.t, 0.12, 0.85)
        ZStack {
            da.c.canvas
            // Lamplight from the door side: a warm pool at the top of the pane, nearest the fold.
            RadialGradient(colors: [Color(hex: scheme == .dark ? "3A3150" : "F6E7C8").opacity(0.9), .clear],
                           center: UnitPoint(x: 0, y: 0.18), startRadius: 0, endRadius: 420)
            // Before the door opens the room is dark; the dark lifts from the fold outward.
            Color(hex: scheme == .dark ? "05081A" : "2E2010").opacity((scheme == .dark ? 0.6 : 0.5) * (1 - lit))
        }
    }
}

struct DuoInsidePane: View {
    let tab: Int
    @Binding var right: DuoRight
    @Binding var focusID: String
    var clock: DuoDoorClock

    private var env = DAEnv()
    private var craft = CraftEnv()
    @State private var confirmed: Set<String> = []
    @State private var hours: Double = 2
    @Environment(\.dynamicTypeSize) private var typeSize

    init(tab: Int, right: Binding<DuoRight>, focusID: Binding<String>, clock: DuoDoorClock) {
        self.tab = tab; _right = right; _focusID = focusID; self.clock = clock
    }

    private var c: DAColors { env.c }
    private var items: [StdSuggestion] { DuoV2Seed.suggestions }

    /// The content enters with the light: from the fold side outward (a soft mask edge), then settles.
    private var reveal: Double { ease(clock.t, 0.15, 0.95) }

    var body: some View {
        content
            .mask {
                GeometryReader { g in
                    let w = g.size.width
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: max(0, reveal * 1.25 - 0.25)),
                                           .init(color: .clear, location: min(1, reveal * 1.25))],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: w)
                }
            }
            .offset(x: (1 - reveal) * -10)
    }

    @ViewBuilder private var content: some View {
        switch right {
        case .list: list
        case .detail(let id): detail(items.first { $0.id == id } ?? items[0])
        case .log:
            DALogTimeSheet(demo: nil, showsEyebrow: false, onLog: { _, _ in right = .list }, onClose: { right = .list })
                .background(c.sheet)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
                .padding(.top, 8)
        case .rental(let id): DuoRentalDetail(rental: DuoV2Seed.rentals.first { $0.id == id } ?? DuoV2Seed.rentals[0], clock: clock)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(CL("To confirm")).font(DAFont.fraunces(size: 34, opsz: 72, wght: 600)).foregroundStyle(c.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(verbatim: "\(items.count - confirmed.count)").font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(c.textSecondary)
            }
            Text(CL("Tap the circle to confirm. Tap the item to check it first."))
                .font(.footnote).foregroundStyle(c.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.top, 8)
                DuoCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { DAHairline().padding(.leading, 50) }
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
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func detail(_ item: StdSuggestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { right = .list } label: {
                    Label(CL("To confirm"), systemImage: "chevron.left").font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(c.action).buttonStyle(DAPress())
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.title2.weight(.semibold)).foregroundStyle(c.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(CL("Calendar · \(item.when)"), systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(c.textSecondary)
                }
                .padding(.horizontal, 4)
                DuoCard {
                    valueRow(CL("Rental"), item.rental == "santa" ? "Santa Ray Ave" : CL("Choose"))
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
                }
                Text(CL("Adds \(StdFormat.hours(hours)) to Santa Ray Ave for 2026."))
                    .font(.footnote).foregroundStyle(c.textSecondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 4) {
                    Button(CL("Confirm \(StdFormat.hours(hours))")) { right = .list }.buttonStyle(DAPrimaryStyle())
                    Button(CL("Not rental work")) { right = .list }
                        .font(.body.weight(.semibold)).foregroundStyle(c.action)
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(DAPress())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
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
            Text(v).font(.body).foregroundStyle(c.textSecondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}

// MARK: - Right pane, Rentals: one rental, inside

struct DuoRentalDetail: View {
    let rental: DuoRental
    var clock: DuoDoorClock
    private var env = DAEnv()
    private var craft = CraftEnv()
    init(rental: DuoRental, clock: DuoDoorClock) { self.rental = rental; self.clock = clock }
    var body: some View {
        let c = env.c
        let f = rental.focus
        let p = f.pace
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rental.name).font(DAFont.fraunces(size: 34, opsz: 72, wght: 600)).foregroundStyle(c.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 4).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(Int(f.logged))").font(DAFont.fraunces(size: 56, opsz: 144, wght: 600)).tracking(-1.5)
                        .foregroundStyle(c.ink)
                    Text(CL("of \(Int(f.goal)) hours")).font(.body).foregroundStyle(c.textSecondary)
                }
                .padding(.horizontal, 4)
                (Text(p.lead).foregroundStyle(f.isBehind ? craft.c.behind : craft.c.positive).fontWeight(.semibold)
                 + Text(verbatim: " ") + Text(p.rest).foregroundStyle(c.textSecondary))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                Text(CL("Recent")).font(.headline).foregroundStyle(c.ink).padding(.horizontal, 4).padding(.top, 8)
                DuoCard {
                    entry(CL("Repairs"), CL("Fixed the porch step"), CL("Today"), 1.5)
                    DAHairline().padding(.leading, 16)
                    entry(CL("Management"), CL("Turnover clean"), CL("Yesterday"), 3)
                    DAHairline().padding(.leading, 16)
                    entry(CL("Leasing"), CL("Showing for the upstairs unit"), CL("Oct 19"), 1)
                }
                Text(CL("Details")).font(.headline).foregroundStyle(c.ink).padding(.horizontal, 4).padding(.top, 8)
                DuoCard {
                    detailRow(CL("Goal"), CL("\(Int(f.goal)) hours in 2026"))
                    DAHairline().padding(.leading, 16)
                    detailRow(CL("Type"), CL("Long-term"))
                    DAHairline().padding(.leading, 16)
                    detailRow(CL("Who works here"), CL("You"))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func entry(_ kind: String, _ what: String, _ when: String, _ h: Double) -> some View {
        let c = env.c
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(what).font(.body.weight(.semibold)).foregroundStyle(c.ink).fixedSize(horizontal: false, vertical: true)
                Text(CL("\(when) · \(kind)")).font(.footnote).foregroundStyle(c.textSecondary)
            }
            Spacer(minLength: 4)
            Text(StdFormat.hours(h)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(c.ink).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 56)
    }

    private func detailRow(_ k: String, _ v: String) -> some View {
        let c = env.c
        return HStack {
            Text(k).font(.body).foregroundStyle(c.ink)
            Spacer()
            Text(v).font(.body).foregroundStyle(c.textSecondary).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}

// MARK: - Propped up (tabletop): upright 669x951, the fold runs across at y 463.5-487.5

struct DuoProppedView: View {
    var clock: DuoDoorClock
    private var env = DAEnv()
    private var craft = CraftEnv()
    init(clock: DuoDoorClock) { self.clock = clock }
    private var half: CGFloat { (DuoGeo.propped.height - DuoGeo.hinge) / 2 }     // 463.5 per half
    var body: some View {
        let c = env.c
        let r = DuoV2Seed.rentals[2]
        let f = r.focus
        let p = f.pace
        VStack(spacing: 0) {
            // Upper half, upright and readable from across the room: the house, its hours and pace.
            VStack(spacing: 0) {
                DuoHouse(art: r.art, lit: r.lit, side: 300, clock: clock)
                VStack(spacing: 2) {
                    Text(verbatim: "\(Int(f.logged))").font(DAFont.fraunces(size: 64, opsz: 144, wght: 600)).tracking(-2)
                        .foregroundStyle(craft.c.ink)
                    Text(CL("of \(Int(f.goal)) hours · \(r.name)")).font(.subheadline).foregroundStyle(craft.c.textSecondary)
                    (Text(p.lead).foregroundStyle(craft.c.behind).fontWeight(.semibold) + Text(verbatim: " ")
                     + Text(p.rest).foregroundStyle(craft.c.textSecondary)).font(.subheadline)
                }
                .multilineTextAlignment(.center)
                .padding(.top, -36)
            }
            .padding(.top, 36)
            .frame(maxWidth: .infinity)
            .frame(height: half, alignment: .top)
            .background { CraftPage() }
            Color.clear.frame(height: DuoGeo.hinge)
            // Lower half, resting on the table, within reach: log time in one tap, and the next items to confirm.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Array([CL("30m"), CL("1h"), CL("2h")].enumerated()), id: \.offset) { i, s in
                        Text(s).font(.body.weight(.semibold)).foregroundStyle(i == 1 ? c.onAction : c.ink)
                            .frame(minWidth: 64, minHeight: 44)
                            .background(i == 1 ? c.action : c.surfaceInner, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    Button(CL("Log 1h")) {}.buttonStyle(DAPrimaryStyle()).frame(width: 200)
                }
                Text(CL("To confirm · \(DuoV2Seed.suggestions.count)")).font(.headline).foregroundStyle(c.ink).padding(.top, 4)
                DuoCard {
                    ForEach(Array(DuoV2Seed.suggestions.prefix(3).enumerated()), id: \.element.id) { i, item in
                        if i > 0 { DAHairline().padding(.leading, 50) }
                        DAActionRow(item: item, confirmed: false) {}.padding(.horizontal, 16).padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 20)
            .frame(height: half, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(c.canvas)
        }
        .frame(width: DuoGeo.propped.width, height: DuoGeo.propped.height)
        .background { VStack(spacing: 0) { CraftPage(); c.canvas } }
    }
}

/// Diagnostic: what the system TabView does at the full open width with regular traits (where its bar lands).
@available(iOS 26.0, *)
struct DuoSystemBarProbe: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            Tab(CL("Today"), systemImage: "sun.horizon", value: 0) { CraftPage() }
            Tab(CL("Inbox"), systemImage: "tray", value: 1) { CraftPage() }.badge(7)
            Tab(CL("Records"), systemImage: "book.closed", value: 2) { CraftPage() }
            Tab(CL("Rentals"), systemImage: "house", value: 3) { CraftPage() }
            Tab(CL("Log time"), systemImage: "plus", value: 4, role: .search) { CraftPage() }
        }
        .overlay {
            Rectangle().fill(Color.pink.opacity(0.28)).frame(width: DuoGeo.hinge).ignoresSafeArea().allowsHitTesting(false)
        }
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
            let full = DuoDoorClock()
            let shots: [(String, AnyView, DynamicTypeSize)] = [
                ("open-today", AnyView(DuoOpenView(clock: full)), .large),
                ("open-today-selected", AnyView(DuoOpenView(right: .detail("s1"), clock: full)), .large),
                ("open-logtime", AnyView(DuoOpenView(right: .log, clock: full)), .large),
                ("open-rentals", AnyView(DuoOpenView(tab: 3, right: .rental("pine"), clock: full)), .large),
                ("open-today-XXL", AnyView(DuoOpenView(clock: full)), .xxLarge),
                ("open-today-selected-XXL", AnyView(DuoOpenView(right: .detail("s1"), clock: full)), .xxLarge),
                ("open-logtime-XXL", AnyView(DuoOpenView(right: .log, clock: full)), .xxLarge),
                ("open-rentals-XXL", AnyView(DuoOpenView(tab: 3, right: .rental("pine"), clock: full)), .xxLarge),
                ("open-today-hinge-annotated", AnyView(DuoOpenView(clock: full, annotate: true)), .large),
            ]
            for (name, view, size) in shots {
                await render(view, size: DuoGeo.open, dark: dark, typeSize: size, scene: scene,
                             to: dir.appendingPathComponent("\(name)-\(tag).png"))
            }
            if !dark {
                await render(AnyView(DuoProppedView(clock: full)), size: DuoGeo.propped, dark: dark, typeSize: .large, scene: scene,
                             to: dir.appendingPathComponent("propped-\(tag).png"), insets: EdgeInsets(top: 44, leading: 0, bottom: 20, trailing: 0))
                await render(AnyView(DuoSystemBarProbe()), size: DuoGeo.open, dark: dark, typeSize: .large, scene: scene,
                             to: dir.appendingPathComponent("probe-system-tabbar-regular-\(tag).png"), regular: true)
            }
            if mode == "motion" {
                let clock = DuoDoorClock()
                clock.t = 0
                let w = makeWindow(AnyView(DuoOpenView(clock: clock)), size: DuoGeo.open, dark: dark, typeSize: .large, scene: scene)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let mdir = dir.appendingPathComponent("motion-\(tag)")
                try? FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)
                for i in 0..<48 {
                    clock.t = Double(i) / 47
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    write(w, size: DuoGeo.open, to: mdir.appendingPathComponent(String(format: "f_%03d.png", i)))
                }
                w.isHidden = true
            }
        }
        NSLog("DUOV2_DONE %@", dir.path)
        try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
    }

    private static func makeWindow(_ view: AnyView, size: CGSize, dark: Bool, typeSize: DynamicTypeSize, scene: UIWindowScene,
                                   insets: EdgeInsets = EdgeInsets(top: DuoGeo.topInset, leading: 0, bottom: DuoGeo.bottomInset, trailing: 0),
                                   regular: Bool = false) -> UIWindow {
        let root = view
            .safeAreaPadding(insets)
            .environment(\.dynamicTypeSize, typeSize)
            .frame(width: size.width, height: size.height)
        let hc = UIHostingController(rootView: AnyView(root))
        hc.overrideUserInterfaceStyle = dark ? .dark : .light
        // Each pane is ~322pt, so the panes lay out compact; the system tab bar then sits in the left pane.
        hc.traitOverrides.horizontalSizeClass = regular ? .regular : .compact
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

    private static func write(_ w: UIWindow, size: CGSize, to url: URL) {
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            _ = w.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        try? img.pngData()?.write(to: url)
    }

    private static func render(_ view: AnyView, size: CGSize, dark: Bool, typeSize: DynamicTypeSize, scene: UIWindowScene, to url: URL,
                               insets: EdgeInsets = EdgeInsets(top: DuoGeo.topInset, leading: 0, bottom: DuoGeo.bottomInset, trailing: 0),
                               regular: Bool = false) async {
        let w = makeWindow(view, size: size, dark: dark, typeSize: typeSize, scene: scene, insets: insets, regular: regular)
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        write(w, size: size, to: url)
        w.isHidden = true
    }
}
#endif
