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
//
// The house is a lit Blender diorama (design/blueprint-house/scripts/craft.py): stills in
// Assets.xcassets/Craft (light/dark appearances), the build motion as HEVC-with-alpha in
// Resources/Craft. Rows, tags, the log sheet and the type come from Direction A (DirA kit).
// Every string goes through CL(...) (table "DirCraft").

func CL(_ key: String.LocalizationValue) -> String { String(localized: key, table: "DirCraft") }

struct CraftLaunch {
    let seedID: String
    let demo: String?
    let focusIndex: Int

    static let current: CraftLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard value("-LHDirection")?.uppercased() == "CRAFT" else { return nil }
        return CraftLaunch(seedID: value("-LHHomeSeed") ?? "craft",
                           demo: value("-LHDirDemo"),
                           focusIndex: Int(value("-LHDirFocus") ?? "") ?? 0)
    }()
}

// MARK: - Tokens: the page is a lit room, not paper

struct CraftColors {
    let dark: Bool
    private func pick(_ l: String, _ d: String) -> Color { Color(hex: dark ? d : l) }
    var pageTop: Color { pick("F6F2EB", "121A3A") }
    var pageBottom: Color { pick("E9E2D6", "070B1C") }
    /// The pool of light the diorama sits in.
    var glow: Color { dark ? Color(hex: "3A4F95").opacity(0.55) : Color.white.opacity(0.9) }
    var ink: Color { pick("121B33", "F2F4FA") }
    var textSecondary: Color { pick("4A5068", "B4BCD2") }
    var action: Color { pick("1E3FA6", "8FD3FF") }
    var behind: Color { pick("A8402C", "F08A70") }
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

    static func make(_ id: String) -> CraftSeed {
        let base = StdSeed.make("brian")
        if id == "goal750" {
            return CraftSeed(focuses: [CraftFocus(id: "all", name: CL("All rentals"), logged: 750, goal: 750, art: .complete)],
                             suggestions: base.suggestions)
        }
        return CraftSeed(focuses: [
            CraftFocus(id: "santa", name: "Santa Ray Ave", logged: 46, goal: 100, art: .frame70),
            CraftFocus(id: "delaney", name: "Delaney Ct", logged: 4, goal: 100, art: .started),
            CraftFocus(id: "pine", name: "Pine Cabin", logged: 262, goal: 500, art: .half),
        ], suggestions: base.suggestions)
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

/// The lit room: a soft vertical gradient. Today adds the pool of light behind the house.
struct CraftPage: View {
    private var env = CraftEnv()
    var body: some View {
        LinearGradient(colors: [env.c.pageTop, env.c.pageBottom], startPoint: .top, endPoint: .bottom)
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
        _focusID = State(initialValue: s.focuses[min(launch.focusIndex, s.focuses.count - 1)].id)
    }

    private var c: CraftColors { env.c }
    private var focus: CraftFocus { seed.focuses.first { $0.id == focusID } ?? seed.focuses[0] }
    private var focusIndex: Int { seed.focuses.firstIndex { $0.id == focusID } ?? 0 }
    private var ax: Bool { typeSize.isAccessibilitySize }
    /// The diorama's square frame. 430pt puts the object itself at ~41% of an 874pt screen;
    /// at AX sizes it steps down so a row still shows above the tab bar.
    private var artSide: CGFloat { ax ? 200 : 430 }
    private var numeralPt: CGFloat { min(heroSize, ax ? 72 : 84) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switcher.padding(.top, 4)
                hero
                numberBlock
                    .padding(.top, ax ? 4 : -34)     // the number sits in the diorama's shadow, like a score under a gem
                confirmBlock.padding(.top, ax ? 16 : 28)
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

    // MARK: Background: page gradient + the pool of light the house sits in

    private var background: some View {
        ZStack {
            CraftPage()
            GeometryReader { g in
                // Square frame larger than the gradient's reach, so the pool of light never shows an edge.
                RadialGradient(colors: [c.glow, c.glow.opacity(0)], center: .center, startRadius: 10, endRadius: g.size.width * 0.62)
                    .frame(width: g.size.width * 1.4, height: g.size.width * 1.4)
                    .position(x: g.size.width / 2, y: g.safeAreaInsets.top + (ax ? 150 : 250))
                    .ignoresSafeArea()
            }
        }
        .accessibilityHidden(true)
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
                CraftHouseArt(art: focus.art, building: building, buildTick: buildTick) {
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
            .accessibilityLabel(CL("House, \(focus.art.label)"))
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
        withAnimation(.spring(duration: 0.3, bounce: 0)) { toast = text }
        DADemo.after(2.8) { withAnimation(.easeIn(duration: 0.2)) { toast = nil } }
        if before.art == .frame70 && next == .framing && !reduceMotion && CraftHouseArt.hasBuild(dark: scheme == .dark) {
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
    let building: Bool
    let buildTick: Int
    let onBuilt: () -> Void
    @Environment(\.colorScheme) private var scheme

    static func buildURL(dark: Bool) -> URL? {
        Bundle.main.url(forResource: dark ? "craft_build_dark" : "craft_build_light", withExtension: "mov")
    }
    static func hasBuild(dark: Bool) -> Bool { buildURL(dark: dark) != nil }

    var body: some View {
        ZStack {
            Image(art.rawValue)
                .resizable().interpolation(.high).scaledToFit()
            if building, let url = Self.buildURL(dark: scheme == .dark) {
                CraftVideo(url: url, tick: buildTick, onEnd: onBuilt)
            }
        }
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
