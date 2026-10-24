import SwiftUI
import AVFoundation
import UIKit

#if DEBUG
// MARK: - Direction CRAFT, "Crafted house" (DEBUG mock, throwaway)
//
//   -LHDirection CRAFT                    turns the mock on
//   -LHHomeSeed craft|goal750             which owner (default craft: three rentals on the 100h/500h tests)
//   -LHDirFocus <n>                       start on rental n (1 = Delaney Ct, just started)
//   -LHDirDemo log|switch|confirm         scripted run for the videos (starts at 2.0s)
//   -LHCraftWindows lit|dark              force the windows state for captures (default: from the day's entries)
//
// The house is a lit Blender diorama (design/blueprint-house/scripts/craft.py): stills in
// Assets.xcassets/Craft (light/dark appearances), the build motion as HEVC-with-alpha in
// Resources/Craft. Rows, tags, the log sheet and the type come from Direction A (DirA kit).
// Windows are state: lit when hours were logged today (TodayWindowState), dark when none. Each still has an
// "<asset>-unlit" twin from the art lane; a missing twin falls back to the lit asset.
// Every string goes through CL(...) (table "DirCraft").

func CL(_ key: String.LocalizationValue) -> String { String(localized: key, table: "DirCraft") }

struct CraftLaunch {
    let seedID: String
    let demo: String?
    let focusIndex: Int
    /// DEBUG/QA: force the windows state. nil = derive from the day's entries.
    let windows: Bool?

    static let current: CraftLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard value("-LHDirection")?.uppercased() == "CRAFT" else { return nil }
        return CraftLaunch(seedID: value("-LHHomeSeed") ?? "craft",
                           demo: value("-LHDirDemo"),
                           focusIndex: Int(value("-LHDirFocus") ?? "") ?? 0,
                           windows: ["lit": true, "dark": false][value("-LHCraftWindows")?.lowercased() ?? ""])
    }()
}

// MARK: - Tokens: the page is a lit room, not paper

struct CraftColors {
    let dark: Bool
    private func pick(_ l: String, _ d: String) -> Color { Color(hex: dark ? d : l) }
    // Page: dusk-tinted neutral by day, deep navy by night; tokens live in AppColors / AdaptiveColors.
    private var a: AdaptiveColors { AdaptiveColors(colorScheme: dark ? .dark : .light) }
    var pageTop: Color { a.pageTop }
    var pageMid: Color { a.pageMid }
    var pageBottom: Color { a.pageBottom }
    /// Warm light spilling from the windows onto the lot.
    var spill: Color { a.spillPool }
    var ink: Color { pick("121B33", "F2F4FA") }
    var textSecondary: Color { pick("4A5068", "B4BCD2") }
    var action: Color { pick("1E3FA6", "8FD3FF") }
    var behind: Color { pick("9A3624", "F08A70") }
    var positive: Color { pick("0C5A30", "4ED48A") }
    var chip: Color { dark ? Color.white.opacity(0.08) : Color.white.opacity(0.65) }
    var chipBorder: Color { dark ? Color.white.opacity(0.14) : Color(hex: "C9BFA8").opacity(0.8) }
    var dot: Color { pick("8A8FA3", "5D6788") }
}

struct CraftEnv: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    var c: CraftColors { CraftColors(dark: scheme == .dark) }
}

// MARK: - Model

enum CraftArt: String {
    case started = "craft_started"     // framing, first storey (just started)
    case frame70 = "craft_frame70"     // framing, most of it
    case framing = "craft_framing"     // framing only, complete
    case half = "craft_half"           // roof on, siding about half
    case complete = "craft_complete"   // finished, lit windows at night
    var label: String {
        switch self {
        case .started: return CL("framing started")
        case .frame70: return CL("framing going up")
        case .framing: return CL("framing done")
        case .half: return CL("roof on, siding half done")
        case .complete: return CL("finished")
        }
    }
}

struct CraftFocus: Identifiable, Equatable {
    let id: String
    let name: String
    var logged: Double
    let goal: Double
    var art: CraftArt

    /// Stable id for this mock rental's time entries; the aggregate "all" focus covers every rental.
    var rentalIDs: Set<UUID>? { id == "all" ? nil : [Self.rentalID(id)] }
    static func rentalID(_ id: String) -> UUID {
        let known = ["santa": "5A17A000-0000-4000-8000-000000000001",
                     "delaney": "5A17A000-0000-4000-8000-000000000002",
                     "pine": "5A17A000-0000-4000-8000-000000000003"]
        return UUID(uuidString: known[id] ?? "5A17A000-0000-4000-8000-0000000000FF")!
    }

    static let dayOfYear = 296.0   // Fri Oct 23, 2026
    static let daysLeft = 69.0
    var expected: Double { goal * Self.dayOfYear / 365 }
    var done: Bool { logged >= goal }
    var behindBy: Int { Int((expected - logged).rounded()) }
    var isBehind: Bool { !done && behindBy >= 1 }

    /// The plain pace line under the number.
    var pace: (lead: String, rest: String) {
        if done { return (CL("Done for 2026."), CL("\(Int(goal)) hours on the record.")) }
        let weekly = Int(((goal - logged) / (Self.daysLeft / 7)).rounded(.up))
        if isBehind { return (CL("Behind by \(behindBy)h."), CL("\(weekly)h a week gets you to \(Int(goal)).")) }
        return (CL("On pace."), CL("\(weekly)h a week gets you to \(Int(goal))."))
    }

    /// Hours → art. The build motion covers frame70 → framing.
    static func art(hours: Double, goal: Double) -> CraftArt {
        let f = hours / goal
        switch f {
        case ..<0.2: return .started
        case ..<0.47: return .frame70
        case ..<0.6: return .framing
        case ..<1.0: return .half
        default: return .complete
        }
    }
}

struct CraftSeed {
    var focuses: [CraftFocus]
    let suggestions: [StdSuggestion]
    /// Real `TimeEntry` values, so the windows use the same logic as the app (TodayWindowState).
    var entries: [TimeEntry]

    private static func entry(_ rental: String, hours: Double, at date: Date) -> TimeEntry {
        TimeEntry(propertyId: CraftFocus.rentalID(rental), participant: .selfParticipant, category: .repairs, hours: hours, date: date)
    }

    static func make(_ id: String) -> CraftSeed {
        let base = StdSeed.make("brian")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date()).addingTimeInterval(60)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        if id == "goal750" {
            return CraftSeed(focuses: [CraftFocus(id: "all", name: CL("All rentals"), logged: 750, goal: 750, art: .complete)],
                             suggestions: base.suggestions,
                             entries: [entry("santa", hours: 2, at: today)])
        }
        // Santa Ray logged today (lit); Delaney nothing (dark); Pine Cabin only yesterday (dark).
        return CraftSeed(focuses: [
            CraftFocus(id: "santa", name: "Santa Ray Ave", logged: 46, goal: 100, art: .frame70),
            CraftFocus(id: "delaney", name: "Delaney Ct", logged: 4, goal: 100, art: .started),
            CraftFocus(id: "pine", name: "Pine Cabin", logged: 262, goal: 500, art: .half),
        ], suggestions: base.suggestions,
           entries: [entry("santa", hours: 1.5, at: today), entry("pine", hours: 3, at: yesterday)])
    }
}

// MARK: - Root: native tab bar; "+" is the system's separate trailing tab button

struct DirCraftRoot: View {
    let launch: CraftLaunch
    @State private var tab = 0
    @State private var lastTab = 0
    @State private var showLog = false
    @State private var logged: Double? = nil
    @State private var logSerial = 0
    private var env = DAEnv()

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                TabView(selection: $tab) {
                    Tab(CL("Today"), systemImage: "sun.horizon", value: 0) {
                        CraftTodayScreen(launch: launch, logSerial: logSerial, logged: logged, openLog: { showLog = true })
                    }
                    Tab(CL("Inbox"), systemImage: "tray", value: 1) { CraftPage() }.badge(7)
                    Tab(CL("Records"), systemImage: "book.closed", value: 2) { CraftPage() }
                    Tab(CL("Rentals"), systemImage: "house", value: 3) { CraftPage() }
                    // The search role is meant to give this tab its own glass circle beside the bar. On iOS 27
                    // it renders inline as the bar's last item; either way the "+" lives with the tab bar and
                    // never floats over the rows. Selecting it opens Log time and keeps the current tab.
                    Tab(CL("Log time"), systemImage: "plus", value: 4, role: .search) { CraftPage() }
                }
            } else {
                CraftTodayScreen(launch: launch, logSerial: logSerial, logged: logged, openLog: { showLog = true })
            }
        }
        .tint(CraftColors(dark: false).action)
        .modifier(CraftTint())
        .onChange(of: tab) { old, new in
            if new == 4 { tab = old; showLog = true } else { lastTab = new }
        }
        .sheet(isPresented: $showLog) {
            DALogTimeSheet(demo: nil, onLog: { hours, _ in
                logged = hours
                logSerial += 1
                showLog = false
            }, onClose: { showLog = false })
            .presentationDetents([.large])
            .presentationBackground(env.c.sheet)
        }
        .onAppear {
            if launch.demo == "log" {
                DADemo.after(1.6) { showLog = true }
                DADemo.after(3.6) { logged = 1.5; logSerial += 1; showLog = false }   // the sheet's 1h 30m
            }
        }
    }
}

/// Action tint per appearance (blueprint by day, drafting cyan by night).
private struct CraftTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(CraftColors(dark: scheme == .dark).action) }
}

/// The page at dusk: a gentle vertical gradient that darkens behind the hero and lifts again for the rows.
struct CraftPage: View {
    private var env = CraftEnv()
    var body: some View {
        LinearGradient(stops: [.init(color: env.c.pageTop, location: 0),
                               .init(color: env.c.pageMid, location: 0.32),
                               .init(color: env.c.pageBottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Today

struct CraftTodayScreen: View {
    let launch: CraftLaunch
    let logSerial: Int
    let logged: Double?
    let openLog: () -> Void

    @State private var seed: CraftSeed
    @State private var entries: [TimeEntry]
    /// Focus ids whose lights wait for the timber drop to finish before fading on.
    @State private var windowsHeld: Set<String> = []
    @State private var focusID: String
    @State private var slideEdge: Edge = .trailing
    @State private var confirmed: Set<String> = []
    @State private var removed: Set<String> = []
    @State private var toast: String? = nil
    @State private var successTick = 0
    @State private var knock = 0
    @State private var buildTick = 0
    @State private var building = false

    private var env = CraftEnv()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 84

    init(launch: CraftLaunch, logSerial: Int, logged: Double?, openLog: @escaping () -> Void) {
        self.launch = launch; self.logSerial = logSerial; self.logged = logged; self.openLog = openLog
        let s = CraftSeed.make(launch.seedID)
        _seed = State(initialValue: s)
        _entries = State(initialValue: s.entries)
        _focusID = State(initialValue: s.focuses[min(launch.focusIndex, s.focuses.count - 1)].id)
    }

    private var c: CraftColors { env.c }
    private var focus: CraftFocus { seed.focuses.first { $0.id == focusID } ?? seed.focuses[0] }
    private var focusIndex: Int { seed.focuses.firstIndex { $0.id == focusID } ?? 0 }
    private var ax: Bool { typeSize.isAccessibilitySize }
    /// Hours logged today on the selected rental (all rentals for the aggregate focus), or the QA override.
    private func lightsOn(_ f: CraftFocus) -> Bool {
        launch.windows ?? TodayWindowState.loggedToday(entries: entries, rentalIDs: f.rentalIDs)
    }
    private var windowsLit: Bool { lightsOn(focus) && !windowsHeld.contains(focus.id) }
    /// The diorama's square frame: 390pt at every size, 44.6% of an 874pt screen (was 49%). At AX sizes it holds
    /// so the house stays tall and the page scrolls beneath it.
    private var artSide: CGFloat { 390 }
    private var numeralPt: CGFloat { min(heroSize, ax ? 72 : 84) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if ax { switcher.padding(.top, 4) }
                hero
                    .padding(.top, ax ? 0 : 10)     // headroom so the rental chip clears the roof ridge at "finished"
                    .overlay(alignment: .top) { if !ax { switcher.padding(.top, 4) } }   // in the diorama's headroom
                numberBlock
                    .padding(.top, ax ? 8 : -44)     // the number sits in the diorama's shadow, like a score under a gem
                confirmBlock.padding(.top, ax ? 16 : 8)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background { background }
        .overlay(alignment: .top) { toastView }   // in the open air above the house, never over the rows
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: knock)
        .sensoryFeedback(.selection, trigger: focusID)
        .onChange(of: logSerial) { _, _ in
            guard let logged else { return }
            add(logged, toast: CL("\(StdFormat.hours(logged)) on the books. \(focus.name)."))
        }
        .onAppear(perform: runDemo)
    }

    // MARK: Background: the dusk page gradient

    private var background: some View {
        CraftPage()   // the warm spill pool is drawn under the lot, inside CraftHouseArt, so it follows the house
    }

    // MARK: Rental switcher: one quiet menu, page dots under the house, swipe on the house

    private var switcher: some View {
        Menu {
            Picker(CL("Rental"), selection: Binding(get: { focusID }, set: { select($0) })) {
                ForEach(seed.focuses) { f in Text(f.name).tag(f.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(focus.name).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
                    .contentTransition(.opacity)
                if seed.focuses.count > 1 {
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(c.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(c.chip, in: Capsule())
            .overlay(Capsule().strokeBorder(c.chipBorder, lineWidth: 0.5))
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .disabled(seed.focuses.count < 2)
        .accessibilityLabel(CL("Rental: \(focus.name)"))
        .accessibilityHint(CL("Switches the rental"))
    }

    // MARK: The hero object

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                CraftHouseArt(art: focus.art, dark: scheme == .dark, side: artSide, building: building, buildTick: buildTick,
                              windowsLit: windowsLit) {
                    finishBuild()
                }
                .id(focus.id)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: slideEdge).combined(with: .opacity),
                    removal: .move(edge: slideEdge == .trailing ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(width: artSide, height: artSide)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                if v.translation.width < -40 { step(+1) } else if v.translation.width > 40 { step(-1) }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CL("House, \(focus.art.label), \(windowsLit ? CL("lights on") : CL("lights off"))"))
            .accessibilityAdjustableAction { dir in step(dir == .increment ? 1 : -1) }
            if seed.focuses.count > 1 && !ax {
                dots.padding(.top, -48)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(Array(seed.focuses.enumerated()), id: \.element.id) { i, _ in
                Circle().fill(i == focusIndex ? c.ink : c.dot.opacity(0.5)).frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The number, tied to the object

    private var numberBlock: some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(Int(focus.logged.rounded(.down)))")
                .font(DAFont.fraunces(size: numeralPt, opsz: 144, wght: 600))
                .tracking(-2)
                .foregroundStyle(c.ink)
                .contentTransition(.numericText(value: focus.logged))
                .animation(reduceMotion ? nil : .spring(duration: 0.40, bounce: 0), value: focus.logged)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(CL("of \(Int(focus.goal)) hours"))
                .font(.body).foregroundStyle(c.textSecondary)
            paceLine.padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    private var paceLine: some View {
        let p = focus.pace
        let leadInk = focus.done ? c.positive : (focus.isBehind ? c.behind : c.positive)
        return (Text(p.lead).foregroundStyle(leadInk).fontWeight(.semibold) + Text(verbatim: " ") + Text(p.rest).foregroundStyle(c.textSecondary))
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    // MARK: Below the hero: quiet

    private var todayItems: [StdSuggestion] { seed.suggestions.filter { !removed.contains($0.id) } }
    private var rows: [StdSuggestion] { Array(todayItems.filter { $0.group == L("Today") }.prefix(2)) }

    private var confirmBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CL("To confirm · \(todayItems.count)"))
                .font(.headline).foregroundStyle(c.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            DASection {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { DAHairline().padding(.leading, 50) }
                    DAActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                DAHairline()
                Button(CL("See all \(todayItems.count)")) {}
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(c.action)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(DAPress())
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(c.positive)
                Text(toast).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .modifier(CraftGlassCapsule())
            .padding(.horizontal, 20).padding(.top, 48)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func select(_ id: String) {
        guard id != focusID else { return }
        let to = seed.focuses.firstIndex { $0.id == id } ?? 0
        slideEdge = to > focusIndex ? .trailing : .leading
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0)) { focusID = id }
    }

    private func step(_ d: Int) {
        let n = seed.focuses.count
        guard n > 1 else { return }
        let i = (focusIndex + d + n) % n
        select(seed.focuses[i].id)
    }

    private func confirm(_ item: StdSuggestion) {
        guard !confirmed.contains(item.id) else { return }
        withAnimation(.easeOut(duration: 0.15)) { _ = confirmed.insert(item.id) }
        successTick += 1
        DADemo.after(0.45) {
            withAnimation(.spring(duration: 0.25, bounce: 0)) { _ = removed.insert(item.id) }
            add(item.hours ?? 0, toast: CL("\(StdFormat.hours(item.hours)) on the books. \(focus.name)."))
        }
    }

    /// Hours land on the focused rental. If the art advances, the build motion plays first and the
    /// number rolls as the last timber lands (the wood knock); otherwise the number rolls at once.
    private func add(_ hours: Double, toast text: String) {
        guard let i = seed.focuses.firstIndex(where: { $0.id == focusID }) else { return }
        let before = seed.focuses[i]
        let after = before.logged + hours
        let next = CraftFocus.art(hours: after, goal: before.goal)
        // The first hour of the day lights the windows, but only once the timber has landed.
        let firstOfDay = !lightsOn(before)
        entries.append(TimeEntry(propertyId: CraftFocus.rentalID(before.id == "all" ? "santa" : before.id),
                                 participant: .selfParticipant, category: .repairs, hours: hours))
        let willBuild = !reduceMotion && CraftHouseArt.buildClip(from: before.art, to: next, dark: scheme == .dark) != nil
        if firstOfDay && launch.windows == nil {
            windowsHeld.insert(before.id)
            if !willBuild { DADemo.after(0.30) { windowsHeld.remove(before.id) } }   // after the art settles
        }
        withAnimation(.spring(duration: 0.3, bounce: 0)) { toast = text }
        DADemo.after(2.8) { withAnimation(.easeIn(duration: 0.2)) { toast = nil } }
        if willBuild {
            building = true
            buildTick += 1
            pendingArt = (i, next, after)
        } else {
            withAnimation(.spring(duration: 0.40, bounce: 0)) {
                seed.focuses[i].logged = after
                seed.focuses[i].art = next
            }
            knock += 1
        }
    }

    @State private var pendingArt: (Int, CraftArt, Double)? = nil

    private func finishBuild() {
        guard let (i, art, hours) = pendingArt else { building = false; return }
        seed.focuses[i].art = art
        withAnimation(.spring(duration: 0.40, bounce: 0)) { seed.focuses[i].logged = hours }
        knock += 1
        pendingArt = nil
        windowsHeld.remove(seed.focuses[i].id)   // the drop is done: lights fade on
        DADemo.after(0.05) { building = false }
    }

    private func runDemo() {
        switch launch.demo {
        case "switch":
            DADemo.after(2.0) { select("delaney") }
            DADemo.after(4.2) { select("pine") }
            DADemo.after(6.4) { select("santa") }
        case "confirm":
            DADemo.after(2.0) { if let first = rows.first(where: { $0.isLikely }) { confirm(first) } }
        default: break
        }
    }
}

private struct CraftGlassCapsule: ViewModifier {
    private var env = CraftEnv()
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - The diorama: still art, plus the build motion (HEVC with alpha) on a stage advance

struct CraftHouseArt: View {
    let art: CraftArt
    let dark: Bool
    let side: CGFloat
    let building: Bool
    let buildTick: Int
    /// Lit windows (hours logged today). Drives the crossfade between the asset and its "-unlit" twin.
    var windowsLit: Bool = true
    let onBuilt: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hook for the art lane: a build sequence for a stage advance (alpha clip), or nil to use the
    /// default stage change (0.25s fade with a small scale settle). Add cases here as clips arrive.
    static func buildClip(from: CraftArt, to: CraftArt, dark: Bool) -> URL? {
        switch (from, to) {
        case (.frame70, .framing): return buildURL(dark: dark)
        default: return nil
        }
    }

    static func buildURL(dark: Bool) -> URL? {
        Bundle.main.url(forResource: dark ? "craft_build_dark" : "craft_build_light", withExtension: "mov")
    }
    static func hasBuild(dark: Bool) -> Bool { buildURL(dark: dark) != nil }

    /// The art lane names the dark-window render "<asset>-unlit". nil when it has not landed (use the lit asset).
    static func unlitName(for art: CraftArt) -> String? {
        let name = art.rawValue + "-unlit"
        return UIImage(named: name) == nil ? nil : name
    }

    /// 0.4s warm-up; a plain linear fade under Reduce Motion.
    private var windowsFade: Animation { reduceMotion ? .linear(duration: 0.4) : .easeInOut(duration: 0.4) }

    private var spill: Color { CraftColors(dark: scheme == .dark).spill }

    /// The dark-window render underneath, the lit render fading in over it. No twin yet: lit only.
    @ViewBuilder private var stills: some View {
        let lit = Image(art.rawValue).resizable().interpolation(.high).scaledToFit()
        if let unlit = Self.unlitName(for: art) {
            ZStack {
                Image(unlit).resizable().interpolation(.high).scaledToFit()
                lit.opacity(windowsLit ? 1 : 0).animation(windowsFade, value: windowsLit)
            }
        } else {
            lit
        }
    }

    var body: some View {
        ZStack {
            // Contact shadow under the block, drawn here so the page always has weight under the object
            // (the baked render shadow is faint on a light page).
            // Spill pool: warm light from the windows on the lot. Fades with the windows.
            Circle()
                .fill(RadialGradient(colors: [spill, spill.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.48))
                .frame(width: side * 0.96, height: side * 0.96)
                .scaleEffect(y: 0.34)
                .offset(y: side * 0.345)
                .opacity(windowsLit ? 1 : 0.2)
                .animation(windowsFade, value: windowsLit)
                .accessibilityHidden(true)
            Ellipse()
                .fill(Color.black.opacity(dark ? 0.55 : 0.30))
                .frame(width: side * 0.80, height: side * 0.07)
                .blur(radius: side * 0.035)
                .offset(y: side * 0.355)
            stills
                .id(art)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity))
            if building, let url = Self.buildURL(dark: scheme == .dark) {
                CraftVideo(url: url, tick: buildTick, onEnd: onBuilt)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.25), value: art)
    }
}

/// AVPlayerLayer keeps the HEVC alpha channel: the clip composites straight onto the page.
struct CraftVideo: UIViewRepresentable {
    let url: URL
    let tick: Int
    let onEnd: () -> Void

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var observer: NSObjectProtocol?
        var tick = -1
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        guard v.tick != tick else { return }
        v.tick = tick
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        v.playerLayer.player = player
        if let o = v.observer { NotificationCenter.default.removeObserver(o) }
        v.observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            onEnd()
        }
        player.play()
    }

    static func dismantleUIView(_ v: PlayerView, coordinator: ()) {
        if let o = v.observer { NotificationCenter.default.removeObserver(o) }
        v.playerLayer.player?.pause()
    }
}
#endif
