import SwiftUI
import UIKit
import GameController

#if DEBUG
// MARK: - Adaptive layout mockups (iPad, iPhone Duo, windows). DEBUG only, throwaway.
//
// Spec: ~/AgentScratch/landlordhours/2026-10-23/adaptive/spec.md (r2) and DESIGN-STANDARD §1.27.
//
//   -LHAdaptive today|inbox|records|logtime      which root opens first
//   -LHAdaptiveSidebar shown|hidden              force the .sidebarAdaptable sidebar (UIKit, capture only)
//   -LHAdaptiveFrame 669x951                     fixed-size preview window (Duo stand-in while no Duo runtime)
//   -LHAdaptiveClass compact|regular             size class inside the preview window
//   -LHAdaptiveDemo resize                       width sweep for the A→B→C hysteresis video
//   -LHAdaptiveSelect                            Inbox / Records open with the first item selected
//   -lh.probe.layout                             LHPROBE lines on stderr (§9 probe)
//
// The compact size class shows the phone prototype itself (StdProtoRoot): band A is the phone layout.

struct AdaptiveLaunch {
    enum Screen: String { case today, inbox, records, logtime }
    let screen: Screen
    let sidebar: String?
    let frame: CGSize?
    let frameClass: UserInterfaceSizeClass?
    let demo: String?
    let select: Bool

    static let current: AdaptiveLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard let raw = value("-LHAdaptive"), let screen = Screen(rawValue: raw) else { return nil }
        var frame: CGSize?
        if let f = value("-LHAdaptiveFrame") {
            let p = f.split(separator: "x").compactMap { Double($0) }
            if p.count == 2 { frame = CGSize(width: p[0], height: p[1]) }
        }
        let cls: UserInterfaceSizeClass? = value("-LHAdaptiveClass").map { $0 == "compact" ? .compact : .regular }
        return AdaptiveLaunch(screen: screen, sidebar: value("-LHAdaptiveSidebar"), frame: frame, frameClass: cls,
                              demo: value("-LHAdaptiveDemo"), select: args.contains("-LHAdaptiveSelect"))
    }()
}

enum AdaptiveProbe {
    static let on = ProcessInfo.processInfo.arguments.contains("-lh.probe.layout") || StdGeom.on
    static func log(_ line: String) {
        guard on else { return }
        let data = ("LHPROBE " + line + "\n").data(using: .utf8) ?? Data()
        FileHandle.standardError.write(data)
        // Also to the app's tmp, so runs driven by a UI test (no stderr) leave a log.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lhprobe.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }
}

// MARK: - Bands and columns (§1, the only place they are computed)

enum LayoutBand: String {
    case a = "A", b = "B", c = "C"

    /// 8pt hysteresis: A→B at 608, B→A at 592, B→C at 908, C→B at 892.
    static func resolve(previous: LayoutBand?, width w: CGFloat) -> LayoutBand {
        guard let p = previous else { return w < 600 ? .a : (w < 900 ? .b : .c) }
        switch p {
        case .a: return w >= 908 ? .c : (w >= 608 ? .b : .a)
        case .b: return w < 592 ? .a : (w >= 908 ? .c : .b)
        case .c: return w < 592 ? .a : (w < 892 ? .b : .c)
        }
    }

    var gutter: CGFloat { self == .a ? 20 : 24 }
}

enum AdaptiveColumns {
    /// Two columns iff Wc ≥ 744 (on at 752, off at 736 once decided).
    static func two(previous: Bool?, wc: CGFloat) -> Bool {
        guard let p = previous else { return wc >= 744 }
        return p ? wc >= 736 : wc >= 752
    }
    static func width(wc: CGFloat) -> CGFloat { min(600, ((wc - 24) / 2).rounded(.down)) }
}

private struct BandKey: EnvironmentKey { static let defaultValue: LayoutBand = .a }
extension EnvironmentValues {
    var layoutBand: LayoutBand {
        get { self[BandKey.self] }
        set { self[BandKey.self] = newValue }
    }
}

/// Measures its own width (the content area beside the sidebar) and hands Wc and the column
/// decision to its content. Wc = content width − 2 × 24.
struct AdaptiveContent<Content: View>: View {
    let name: String
    @ViewBuilder let content: (_ wc: CGFloat, _ two: Bool) -> Content
    @State private var width: CGFloat = 0
    @State private var two: Bool?
    @Environment(\.layoutBand) private var band

    var body: some View {
        let wc = max(0, width - 2 * band.gutter)
        // Measured on a clear base layer that takes exactly the proposed size: measuring the content
        // itself let a wider stale layout hold its own width during a live window resize (seen on
        // iPadOS 27: two 512pt columns clipped inside an 869pt window).
        // Nothing renders until the first real width: a 0pt first pass must not pick a layout.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                guard r.width > 0 else { return }
                width = r.width
                let wc = max(0, r.width - 2 * band.gutter)
                let next = AdaptiveColumns.two(previous: two, wc: wc)
                two = next
                AdaptiveProbe.log(String(format: "content=%@ minX=%.1f width=%.1f Wc=%.1f band=%@ columns=%d col=%.1f",
                                         name, r.minX, r.width, wc, band.rawValue, next ? 2 : 1,
                                         next ? AdaptiveColumns.width(wc: wc) : min(600, wc)))
            }
            .overlay {
                if let two { content(wc, two) }
            }
    }
}

// MARK: - Entry

struct AdaptiveProtoEntry: View {
    let launch: AdaptiveLaunch
    var body: some View {
        if #available(iOS 26.0, *) {
            if ProcessInfo.processInfo.arguments.contains("-LHAdaptivePlainTabs") {
                AdaptivePlainTabs()
            } else if launch.demo == "resize" {
                AdaptiveResizeDemo(launch: launch)
            } else if let size = launch.frame {
                AdaptivePreviewWindow(size: size, sizeClass: launch.frameClass ?? .regular) { AdaptiveShell(launch: launch) }
            } else {
                AdaptiveShell(launch: launch)
            }
        } else {
            Text(verbatim: "Adaptive mockups need iOS 26")
        }
    }
}

/// Fixed-size preview window: the Duo's derived point sizes inside the iPad simulator.
@available(iOS 26.0, *)
struct AdaptivePreviewWindow<Content: View>: View {
    let size: CGSize
    let sizeClass: UserInterfaceSizeClass
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            Color(white: 0.5).ignoresSafeArea()
            content
                .environment(\.horizontalSizeClass, sizeClass)
                .environment(\.verticalSizeClass, .regular)
                .frame(width: size.width, height: size.height)
                .clipped()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                    StdGeom.log(String(format: "STDGEOM window %.1f %.1f %.1f %.1f", r.minY, r.height, r.minX, r.width))
                }
        }
    }
}

// MARK: - Shell: one TabView, three forms

enum AdaptiveTab: Hashable { case today, inbox, records, rentals, rental(String), log }

@available(iOS 26.0, *)
struct AdaptiveShell: View {
    let launch: AdaptiveLaunch
    @State private var tab: AdaptiveTab
    @State private var band: LayoutBand?
    @State private var showLog: Bool
    @State private var windowControls: CGFloat = 0
    @State private var sidebarOpen = false
    @Environment(\.horizontalSizeClass) private var hsc
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.displayScale) private var scale
    @Environment(\.supportsMultipleWindows) private var multiWindow
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }
    private let seed = AdaptiveSeed.seed

    init(launch: AdaptiveLaunch) {
        self.launch = launch
        let t: AdaptiveTab
        switch launch.screen {
        case .inbox: t = .inbox
        case .records: t = .records
        default: t = .today
        }
        _tab = State(initialValue: t)
        _showLog = State(initialValue: launch.screen == .logtime)
    }

    private var stdLaunch: StdProtoLaunch {
        StdProtoLaunch(screen: launch.screen == .inbox ? .inbox : (launch.screen == .logtime ? .logtime : .today),
                       seedID: "brian", state: launch.screen == .logtime ? "filled" : "", scroll: nil, demo: nil)
    }

    var body: some View {
        Group {
            if hsc == .compact {
                // Band A / compact: the phone layout, unchanged (bottom glass bar, glass "+").
                StdProtoRoot(launch: stdLaunch)
                    // R12: in a narrow iPadOS window the window controls sit over the top-leading
                    // corner; the phone layout's in-content title moves down to clear them.
                    // safeAreaPadding does not reach into TabView's tabs, so the whole TabView moves down.
                    .padding(.top, windowControls)
                    .background(colors.background.ignoresSafeArea())
            } else {
                regular
            }
        }
        .environment(\.layoutBand, band ?? .a)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
            band = LayoutBand.resolve(previous: band, width: r.width)
            AdaptiveProbe.log(String(format: "window W=%.1f H=%.1f scale=%.0f hsc=%@ vsc=%@ band=%@ multiWindow=%@",
                                     r.width, r.height, scale, "\(hsc.map { "\($0)" } ?? "nil")", "\(vsc.map { "\($0)" } ?? "nil")",
                                     (band ?? .a).rawValue, multiWindow ? "yes" : "no"))
        }
        .background { WindowControlsReader(extra: $windowControls) }
        .background { if AdaptiveProbe.on { HingeProbe() } }
        .background {
            GeometryReader { g in
                Color.clear.onAppear {
                    let i = g.safeAreaInsets
                    AdaptiveProbe.log(String(format: "safeArea top=%.1f bottom=%.1f leading=%.1f trailing=%.1f", i.top, i.bottom, i.leading, i.trailing))
                }
            }
        }
    }

    private var regular: some View {
        TabView(selection: $tab) {
            Tab(L("Today"), systemImage: "sun.max", value: AdaptiveTab.today) { root(L("Today")) { AdaptiveToday(seed: seed, openInbox: { tab = .inbox }) } }
            Tab(L("Inbox"), systemImage: "tray", value: AdaptiveTab.inbox) { root(L("Inbox")) { AdaptiveInbox(seed: seed, selectFirst: launch.select) } }
                // No badge while the sidebar is open: the sidebar draws it in a grey we cannot set (3.2:1).
                .badge(sidebarOpen ? 0 : seed.suggestions.count)
            Tab(L("Records"), systemImage: "list.bullet.rectangle", value: AdaptiveTab.records) { root(L("Records")) { AdaptiveRecords(selectFirst: launch.select) } }
            Tab(L("Rentals"), systemImage: "house", value: AdaptiveTab.rentals) { root(L("Rentals")) { placeholder(L("All rentals")) } }
            TabSection {
                ForEach(seed.rentals.rentals) { r in
                    Tab(r.name, systemImage: "house", value: AdaptiveTab.rental(r.id)) { root(r.name) { placeholder(r.name) } }
                }
            }
            // Spec r2 used .defaultVisibility(.hidden, for: .tabBar): on iPadOS 27 the section still
            // showed as a fifth "Rentals" item in the top bar. .sidebarOnly is the modifier that holds.
            .tabPlacement(.sidebarOnly)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { AdaptiveSidebarHero(seed: seed) { tab = .today } }
        .tabViewSidebarFooter { sidebarFooter }
        .tint(colors.action)
        .background { SidebarVisibilitySetter(shown: launch.sidebar.map { $0 == "shown" }) }
        .background { SidebarVisibilityReader(shown: $sidebarOpen) }
        .sheet(isPresented: $showLog) {
            StdLogTimeSheet(seed: seed, launch: stdLaunch, onClose: { showLog = false }, onLog: { _ in showLog = false },
                            attachment: launch.screen == .logtime ? L("receipt-0423.pdf · 1 photo") : nil)
                .presentationSizing(.form)
        }
    }

    /// Every regular root: its own NavigationStack and the toolbar "+" (⌘N) in the same place.
    private func root<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showLog = true } label: { Label(L("Log time"), systemImage: "plus") }
                            .keyboardShortcut("n", modifiers: .command)
                            .help(L("Log time"))
                            .accessibilityIdentifier("toolbar.logTime")
                    }
                }
                .navigationTitle(title)
                .toolbar(removing: .title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func placeholder(_ title: String) -> some View {
        ZStack(alignment: .topLeading) {
            colors.background.ignoresSafeArea()
            StdScreenTitle(title: title, subtitle: L("Not mocked in round one")).padding(24)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Settings"), systemImage: "gearshape").font(.body).foregroundStyle(colors.textPrimary)
            if GCKeyboard.coalesced != nil {
                Text(L("⌘N Log time")).font(.footnote).foregroundStyle(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// tabViewSidebarHeader: the compact hero (house 120pt, "206 of 750", one pace line); tap opens Today.
struct AdaptiveSidebarHero: View {
    let seed: StdSeed
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let hero = seed.hero(.all)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                // AX sizes: the number alone (the sidebar is 280pt; art and pace line would fill it).
                if !typeSize.isAccessibilitySize {
                ZStack {
                    let k = HouseProgress.keyframe(for: hero.stageHours)
                    Image(decorative: k.builtImageName).resizable().interpolation(.high).scaledToFit()
                    HouseLineworkImage(name: k.linesImageName).foregroundStyle(HouseTokens.drafting)
                }
                .frame(width: 120, height: 120)
                .frame(maxWidth: .infinity)
                }
                Text(L("\(Int(hero.number)) of 750")).font(.title2.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                if let s = hero.status, !typeSize.isAccessibilitySize {
                    Text(s).font(.subheadline.weight(.semibold)).foregroundStyle(HouseTokens.cautionOnHero)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StdHeroSky(phase: .day))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(StdPressStyle())
        .accessibilityLabel(L("Today, \(Int(hero.number)) of 750 hours"))
    }
}

/// Capture hook: shows or hides the .sidebarAdaptable sidebar through UIKit (no SwiftUI binding exists).
struct SidebarVisibilitySetter: UIViewRepresentable {
    let shown: Bool?
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        guard let shown else { return }
        for delay in [0.2, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let rootVC = view.window?.rootViewController, let tbc = Self.find(rootVC) else {
                    AdaptiveProbe.log("sidebar setter: no UITabBarController")
                    return
                }
                if #available(iOS 18.0, *) {
                    tbc.sidebar.isHidden = !shown
                    AdaptiveProbe.log("sidebar hidden=\(tbc.sidebar.isHidden) mode=\(tbc.mode.rawValue)")
                }
            }
        }
    }
    static func find(_ vc: UIViewController) -> UITabBarController? {
        if let t = vc as? UITabBarController { return t }
        for c in vc.children { if let t = find(c) { return t } }
        if let p = vc.presentedViewController { return find(p) }
        return nil
    }
}

/// R12: how far the iPadOS 26+ window controls reach below the top safe area, read from UIKit's
/// corner-adapted safe-area layout region (0 when the scene is full screen or on iPhone).
struct WindowControlsReader: UIViewRepresentable {
    @Binding var extra: CGFloat
    final class Probe: UIView {
        var onChange: (CGFloat) -> Void = { _ in }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard #available(iOS 26.0, *), window != nil else { return }
            let v = layoutGuide(for: .safeArea(cornerAdaptation: .vertical)).layoutFrame
            let h = layoutGuide(for: .safeArea(cornerAdaptation: .horizontal)).layoutFrame
            // Under 8pt is corner rounding (the Duo reports 2), not window controls.
            let raw = max(0, (v.minY - safeAreaInsets.top).rounded())
            let value = raw > 8 ? raw : 0
            AdaptiveProbe.log(String(format: "windowControls extra=%.1f vGuide=(%.1f,%.1f,%.1f,%.1f) hGuide=(%.1f,%.1f,%.1f,%.1f) safe=(t%.1f l%.1f) bounds=%.1fx%.1f",
                                     value, v.minX, v.minY, v.width, v.height, h.minX, h.minY, h.width, h.height,
                                     safeAreaInsets.top, safeAreaInsets.left, bounds.width, bounds.height))
            onChange(value)
        }
    }
    func makeUIView(context: Context) -> Probe {
        let v = Probe(); v.isUserInteractionEnabled = false
        v.onChange = { value in DispatchQueue.main.async { if extra != value { extra = value } } }
        return v
    }
    func updateUIView(_ view: Probe, context: Context) { view.setNeedsLayout() }
}

/// Table on iPadOS paints the system background (#000000 dark, #FFFFFF light). This clears its
/// collection view and gives each row the card token, so the table sits on our canvas.
struct TableThemer: UIViewRepresentable {
    let canvas: UIColor
    let row: UIColor
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: UIView, context: Context) {
        for delay in [0.1, 0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let host = view.superview?.superview else { return }
                for cv in Self.collectionViews(in: host) {
                    cv.backgroundColor = canvas
                    cv.backgroundView = nil
                    for cell in cv.visibleCells {
                        var bg = UIBackgroundConfiguration.clear()
                        bg.backgroundColor = row
                        if !cell.isSelected { cell.backgroundConfiguration = bg }
                    }
                }
            }
        }
    }
    static func collectionViews(in v: UIView) -> [UICollectionView] {
        var out: [UICollectionView] = []
        if let cv = v as? UICollectionView { out.append(cv) }
        for s in v.subviews { out += collectionViews(in: s) }
        return out
    }
}

/// §9 probe: UIKit's hinge (iOS 27.1+; SwiftUI has no onHingeChange). Logs status and angle.
struct HingeProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            let i = UIHingeInteraction { _, update in
                if let h = update.hinge {
                    AdaptiveProbe.log(String(format: "hinge status=%ld angle=%.1f", h.status.rawValue, h.angle))
                } else {
                    AdaptiveProbe.log("hinge none")
                }
            }
            v.addInteraction(i)
        } else {
            AdaptiveProbe.log("hinge api unavailable (< iOS 27.1)")
        }
        return v
    }
    func updateUIView(_ view: UIView, context: Context) {
        let s = view.window?.windowScene
        AdaptiveProbe.log(String(format: "screen bounds=%.0fx%.0f nativeScale=%.1f scene=%.0fx%.0f",
                                 s?.screen.bounds.width ?? 0, s?.screen.bounds.height ?? 0, s?.screen.nativeScale ?? 0,
                                 s?.coordinateSpace.bounds.width ?? 0, s?.coordinateSpace.bounds.height ?? 0))
    }
}

extension View {
    /// Table rows meet D1: a 56pt row (the cell grows the system's 44pt row to the list row height).
    func tableRow() -> some View { frame(minHeight: 48) }
}

/// Probe for the closed Duo: the plainest native TabView (four tabs, no .search slot, no glass "+"),
/// to tell the system's own placement from ours. -LHAdaptivePlainTabs.
struct AdaptivePlainTabs: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            TabView {
                Tab("Today", systemImage: "sun.max") { Text(verbatim: "Plain TabView probe") }
                Tab("Inbox", systemImage: "tray") { Color.clear }
                Tab("Records", systemImage: "list.bullet.rectangle") { Color.clear }
                Tab("Rentals", systemImage: "house") { Color.clear }
            }
        }
    }
}

/// Sidebar text we cannot restyle: iPadOS 27's SwiftUI sidebar ignores UITabSidebarItem content
/// configurations (tried through a forwarding delegate: update(item:) runs, nothing changes), so its
/// badge and section-header grey stay at 3.1–3.3:1. The fix is structural: no section header, and
/// no badge while the sidebar is open (the top bar's red badge is fine). This proxy only reports
/// sidebar visibility; every other delegate call goes to SwiftUI's own coordinator.
@available(iOS 18.0, *)
struct SidebarVisibilityReader: UIViewRepresentable {
    @Binding var shown: Bool
    final class Coordinator: NSObject, UITabBarController.Sidebar.Delegate {
        weak var inner: UITabBarController.Sidebar.Delegate?
        var onChange: (Bool) -> Void = { _ in }
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (inner?.responds(to: aSelector) ?? false)
        }
        override func forwardingTarget(for aSelector: Selector!) -> Any? { inner }
        func tabBarController(_ tabBarController: UITabBarController, sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar,
                              animator: any UITabBarController.Sidebar.Animating) {
            inner?.tabBarController?(tabBarController, sidebarVisibilityWillChange: sidebar, animator: animator)
            let hidden = sidebar.isHidden
            DispatchQueue.main.async { self.onChange(!hidden) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: UIView, context: Context) {
        let c = context.coordinator
        c.onChange = { v in if shown != v { shown = v } }
        for delay in [0.1, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let root = view.window?.rootViewController, let tbc = SidebarVisibilitySetter.find(root) else { return }
                if tbc.sidebar.delegate !== c { c.inner = tbc.sidebar.delegate; tbc.sidebar.delegate = c }
                let open = !tbc.sidebar.isHidden && tbc.traitCollection.horizontalSizeClass == .regular
                if shown != open { shown = open }
            }
        }
    }
}

// MARK: - Today (§3.1): two columns when Wc ≥ 744; else the phone order in one column ≤ 600

@available(iOS 26.0, *)
struct AdaptiveToday: View {
    let seed: StdSeed
    var openInbox: () -> Void = {}
    @State private var focus: HomeProtoFocus = .all
    @State private var confirmed: Set<String> = []
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutBand) private var band
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        AdaptiveContent(name: "today") { wc, two in
            // Band B is one column even when Wc ≥ 744 (spec band table and device table; §1 R1 alone would split).
            if two && band == .c && !typeSize.isAccessibilitySize {
                twoColumns(col: AdaptiveColumns.width(wc: wc))
            } else {
                // One column, phone order, capped at 600 and centred (R1). The phone screen itself.
                StdTodayScreen(seed: seed, launch: StdProtoLaunch(screen: .today, seedID: "brian", state: "", scroll: nil, demo: nil),
                               openInbox: openInbox)
                    .contentMargins(.horizontal, band.gutter, for: .scrollContent)
                    .frame(maxWidth: min(600, wc) + 2 * band.gutter)
                    .stdMeasure("column.single")
                    .frame(maxWidth: .infinity)
                    .background(colors.background.ignoresSafeArea())
            }
        }
        .background(colors.background.ignoresSafeArea())
    }

    private var likely: [StdSuggestion] { seed.suggestions.filter { $0.isLikely && !confirmed.contains($0.id) } }

    private func twoColumns(col: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // Left: the house and the pace. Its own scroll.
            List {
                Section {} header: {
                    VStack(alignment: .leading, spacing: 0) {
                        StdScreenTitle(title: L("Today"), subtitle: L("Fri, Oct 23")).padding(.bottom, 16)
                        StdHeroCard(seed: seed, focus: $focus).stdMeasure("hero")
                        StdSectionHeader(title: L("Pace")).padding(.top, 24).padding(.bottom, 8)
                        let tiles = seed.paceTiles(focus)
                        let layout = col >= 440 ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
                        layout {
                            ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                                StdStatTile(value: t.0, label: t.1, glyph: t.2).stdMeasure("stat.\(i)")
                            }
                        }
                        StdCPAFootnote().padding(.top, 16)
                    }
                    .textCase(nil)
                    .stdHeaderInsets()
                }
            }
            .modifier(AdaptiveListStyle())
            .frame(width: col)
            .stdMeasure("column.left")

            // Right: the work. To confirm (own List, swipes) then This week.
            List {
                confirmSection
                weekSection
            }
            .modifier(AdaptiveListStyle())
            .frame(width: col)
            .stdMeasure("column.right")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var confirmSection: some View {
        Section {
            ForEach(Array(stdDayGroups(seed.suggestions).enumerated()), id: \.element.name) { gi, g in
                StdDayHeader(title: g.name).stdDayRow(first: gi == 0, colors: colors)
                ForEach(g.items) { item in
                    AdaptiveActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirmed.insert(item.id) }
                }
            }
            if likely.count >= 2 {
                Button(StdCanon.confirmLikely(likely.count)) { likely.forEach { confirmed.insert($0.id) } }
                    .buttonStyle(StdButtonStyle(.tertiary))
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(colors.backgroundSecondary)
                    .stdMeasure("foot")
            }
        } header: {
            // Aligns with the left column's title baseline band: the header starts under the title row.
            StdSectionHeader(title: L("To confirm"), count: seed.suggestions.count, trailing: L("Review all"), onTrailing: openInbox)
                .padding(.top, 70)
                .textCase(nil)
                .stdHeaderInsets()
        }
    }

    private var weekSection: some View {
        Section {
            ForEach(seed.week) { e in
                StdBrowseRow(title: e.title, meta: L("\(e.rental) · \(e.category.stdLabel)"), value: StdFormat.hours(e.hours)) {
                    CategoryToolTile(category: e.category, size: 36)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(colors.backgroundSecondary)
                .hoverEffect(.highlight)
                .contextMenu { recordMenu }
            }
        } header: {
            StdSectionHeader(title: L("This week"), trailing: L("Records")).textCase(nil).stdHeaderInsets()
        }
    }

    @ViewBuilder private var recordMenu: some View {
        Button(L("Open"), systemImage: "arrow.up.right") {}
        Button(L("Edit"), systemImage: "pencil") {}
        Button(L("Duplicate"), systemImage: "plus.square.on.square") {}
        Button(L("Delete"), systemImage: "trash", role: .destructive) {}
    }
}

/// The phone List styling, shared by every adaptive column.
struct AdaptiveListStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
    }
}

/// LHRow.Action with the regular-width additions: hover, context menu, Space / ⌫ on focus.
struct AdaptiveActionRow: View {
    let item: StdSuggestion
    let confirmed: Bool
    var selected = false
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        StdActionRow(item: item, confirmed: confirmed, onConfirm: onConfirm, showDay: false)
            .stdMeasure("row.\(item.id)")
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(selected ? colors.actionSurface : colors.backgroundSecondary)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 34 }
            .hoverEffect(.highlight)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(action: onConfirm) { Label(StdCanon.confirm, systemImage: "checkmark") }.tint(colors.positive)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {} label: { Label(StdCanon.notRentalWork, systemImage: "xmark") }.tint(colors.textSecondary)
            }
            .contextMenu {
                if let h = item.hours, item.canQuickLog {
                    Button(L("Confirm \(StdFormat.hours(h))"), systemImage: "checkmark", action: onConfirm)
                }
                Button(L("Change hours…"), systemImage: "clock") {}
                Button(StdCanon.notRentalWork, systemImage: "xmark") {}
                Button(L("Open"), systemImage: "arrow.up.right") {}
            }
            .onKeyPress(.space) { onConfirm(); return .handled }
    }
}

// MARK: - Inbox (§3.2): list + confirm detail in C with Wc ≥ 744; pushes otherwise

@available(iOS 26.0, *)
struct AdaptiveInbox: View {
    let seed: StdSeed
    @State private var selection: String?
    @State private var confirmed: Set<String> = []
    @State private var visibility: NavigationSplitViewVisibility = .all
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutBand) private var band
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(seed: StdSeed, selectFirst: Bool) {
        self.seed = seed
        _selection = State(initialValue: selectFirst ? stdDayGroups(seed.suggestions).first?.items.first?.id : nil)
    }

    var body: some View {
        AdaptiveContent(name: "inbox") { wc, two in
            if band == .c && two {
                // NavigationSplitView with the system's own column widths (list 320 on iPadOS 27;
                // navigationSplitViewColumnWidth does not widen it, so we no longer ask).
                NavigationSplitView(columnVisibility: $visibility) {
                    list(width: nil, gutter: 16)
                        .toolbar(removing: .sidebarToggle)
                        .stdMeasure("column.list")
                } detail: {
                    detail.stdMeasure("column.detail")
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                list(width: min(600, wc))
                    .frame(maxWidth: .infinity)
                    .navigationDestination(item: $selection) { id in
                        if let item = seed.suggestions.first(where: { $0.id == id }) { AdaptiveConfirmDetail(item: item, seed: seed) }
                    }
            }
        }
        .background(colors.background.ignoresSafeArea())
    }

    @ViewBuilder private var detail: some View {
        if let id = selection, let item = seed.suggestions.first(where: { $0.id == id }) {
            AdaptiveConfirmDetail(item: item, seed: seed)
        } else {
            ContentUnavailableView(L("Pick something to confirm"), systemImage: "tray")
                .background(colors.background.ignoresSafeArea())
        }
    }

    private var likely: [StdSuggestion] { seed.suggestions.filter { $0.isLikely && !confirmed.contains($0.id) } }

    /// `gutter`: 16 inside the 320pt split column (system list margin), the band gutter elsewhere.
    private func list(width: CGFloat?, gutter: CGFloat? = nil) -> some View {
        List {
            Section {
                ForEach(Array(stdDayGroups(seed.suggestions).enumerated()), id: \.element.name) { gi, g in
                    StdDayHeader(title: g.name).stdDayRow(first: gi == 0, colors: colors)
                    ForEach(g.items) { item in
                        AdaptiveActionRow(item: item, confirmed: confirmed.contains(item.id), selected: selection == item.id) {
                            confirmed.insert(item.id)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selection = item.id }
                    }
                }
                if likely.count >= 2 {
                    Button(StdCanon.confirmLikely(likely.count)) {}
                        .buttonStyle(StdButtonStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(colors.backgroundSecondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 16) {
                    StdScreenTitle(title: L("Inbox"), subtitle: L("\(seed.suggestions.count) to confirm"))
                    AdaptiveQuestionCard(rental: seed.rentals.rentals.first?.name ?? "")
                }
                .padding(.bottom, 8)
                .textCase(nil)
                .stdHeaderInsets()
            } footer: {
                Text(StdCanon.nothingCounts).font(.footnote).foregroundStyle(colors.textSecondary)
            }
        }
        // Gutter before the shared style: the innermost contentMargins wins.
        .contentMargins(.horizontal, gutter ?? band.gutter, for: .scrollContent)
        .modifier(AdaptiveListStyle())
        .frame(maxWidth: width.map { $0 + 2 * band.gutter })
    }
}

struct AdaptiveQuestionCard: View {
    let rental: String
    @ViewBuilder private var chips: some View {
        StdChip(text: L("Cleaner"), selected: picked == 0, fill: true) { picked = 0 }
        StdChip(text: L("Me"), selected: picked == 1, fill: true) { picked = 1 }
        StdChip(text: L("Not sure"), selected: picked == 2, fill: true) { picked = 2 }
    }
    @State private var picked: Int?
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(L("From your calendar")) } icon: { Image(systemName: "calendar") }
                .font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                .foregroundStyle(colors.draftingInk)
            Text(L("Who does more of the work at \(rental)?")).font(.headline).foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // Three equal chips; in the 320pt split column they stack rather than truncate.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }.fixedSize()
                VStack(spacing: 8) { chips }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
    }
}

/// The confirm sheet's content, rendered as the Inbox detail. One .primary (Confirm), pinned.
struct AdaptiveConfirmDetail: View {
    let item: StdSuggestion
    let seed: StdSeed
    @State private var hours: Double
    @State private var who = 0
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(item: StdSuggestion, seed: StdSeed) {
        self.item = item
        self.seed = seed
        _hours = State(initialValue: item.hours ?? 1)
    }

    private var rentalName: String? { item.rental.flatMap { seed.rentals.rental($0)?.name } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("Rental · \(item.when)")).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                    .foregroundStyle(colors.draftingInk)
                HStack(alignment: .center, spacing: 14) {
                    CategoryToolTile(category: item.category, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.source == .calendar ? L("Calendar · Fri, Oct 23") : L("Reminder · Fri, Oct 23"))
                            .font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                }
                VStack(spacing: 0) {
                    value(L("Rental"), rentalName)
                    divider
                    value(L("Kind of work"), item.category?.stdLabel)
                    divider
                    HStack {
                        Text(L("How long")).font(.body).foregroundStyle(colors.textPrimary)
                        Spacer(minLength: 8)
                        StdStepper(hours: $hours)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 59)
                    divider
                    HStack {
                        Text(L("Who")).font(.body).foregroundStyle(colors.textPrimary)
                        Spacer(minLength: 12)
                        StdSegmented(options: [L("Me"), L("Spouse")], selection: $who).frame(maxWidth: 200)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 59)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Note (optional)")).font(.subheadline).foregroundStyle(colors.textSecondary)
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border, lineWidth: 1))
                        .frame(height: 88)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(L("Confirm \(StdFormat.hours(hours))")) {}
                    .buttonStyle(StdButtonStyle(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .stdMeasure("detail.primary")
                Button(StdCanon.notRentalWork) {}.buttonStyle(StdButtonStyle(.tertiary))
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var divider: some View { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 16) }

    private func value(_ label: String, _ v: String?) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.body).foregroundStyle(colors.textPrimary)
            Spacer(minLength: 12)
            Text(v ?? L("Not picked")).font(.body).foregroundStyle(v == nil ? colors.caution : colors.textSecondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(colors.textTertiary)
        }
        .padding(.horizontal, 16).frame(minHeight: 59)
    }
}

// MARK: - Records (§3.7): Table + inspector when Wc ≥ 720 and text ≤ XXL; the row list otherwise

struct AdaptiveRecord: Identifiable, Hashable {
    let id: Int
    let sortDate: Int
    let day: String
    let title: String
    let rental: String
    let category: ActivityCategory
    let who: String
    let hours: Double
    let source: String   // calendar | reminder | manual

    var sourceGlyph: String {
        switch source {
        case "calendar": return "calendar"
        case "reminder": return "checklist"
        default: return "square.and.pencil"
        }
    }
}

@available(iOS 26.0, *)
struct AdaptiveRecords: View {
    @State private var selection: AdaptiveRecord.ID?
    @State private var sort = [KeyPathComparator(\AdaptiveRecord.sortDate, order: .reverse)]
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutBand) private var band
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(selectFirst: Bool) {
        _selection = State(initialValue: selectFirst ? AdaptiveSeed.records.max(by: { $0.sortDate < $1.sortDate })?.id : nil)
    }

    private var rows: [AdaptiveRecord] { AdaptiveSeed.records.sorted(using: sort) }
    private var total: String { StdFormat.hours(AdaptiveSeed.records.reduce(0) { $0 + $1.hours }) }

    var body: some View {
        AdaptiveContent(name: "records") { wc, _ in
            if band == .c && wc >= 720 && typeSize <= .xxLarge {
                // The inspector (280 on iPadOS 27) only opens beside a table that keeps ≥ 720.
                table(inspectorFits: wc - 280 >= 720)
            } else {
                rowList(width: min(600, wc))
            }
        }
        .background(colors.background.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Menu(L("Year 2026")) { Button(L("2026")) {}; Button(L("2025")) {} }
                Menu(L("Rental")) { Button(L("All rentals")) {}; Button("Santa Ray Ave") {}; Button("Delaney Ct") {} }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {} label: { Label(L("Export"), systemImage: "square.and.arrow.up") }.help(L("Export"))
            }
        }
    }

    private var header: some View {
        StdScreenTitle(title: L("Records"), subtitle: L("\(total) in 2026 · \(AdaptiveSeed.records.count) records"))
    }

    private func table(inspectorFits: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.horizontal, band.gutter)
            Table(rows, selection: $selection, sortOrder: $sort) {
                TableColumn(L("Date"), value: \.sortDate) { r in Text(r.day).monospacedDigit().foregroundStyle(colors.textSecondary).tableRow() }
                    .width(min: 64, ideal: 72, max: 90)
                TableColumn(L("What")) { r in
                    HStack(spacing: 10) {
                        CategoryToolTile(category: r.category, size: 28)
                        Text(r.title).lineLimit(1).foregroundStyle(colors.textPrimary)
                    }
                    .tableRow()
                }
                .width(min: 240)
                TableColumn(L("Rental"), value: \.rental) { r in Text(r.rental).foregroundStyle(colors.textSecondary).tableRow() }.width(min: 110, ideal: 130)
                TableColumn(L("Kind")) { r in
                    StdTag(text: r.category.stdLabel, ink: colors.categoryTagInk(r.category), wash: colors.categoryTagWash(r.category))
                }
                .width(min: 90, ideal: 110)
                TableColumn(L("Who"), value: \.who) { r in Text(r.who).foregroundStyle(colors.textSecondary).tableRow() }.width(min: 64, ideal: 72)
                TableColumn(L("Hours"), value: \.hours) { r in
                    Text(StdFormat.hours(r.hours)).fontDesign(.rounded).monospacedDigit().foregroundStyle(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .trailing).tableRow()
                }
                .width(min: 72, ideal: 80)
                TableColumn("") { r in Image(systemName: r.sourceGlyph).foregroundStyle(colors.textSecondary).accessibilityLabel(r.source) }
                    .width(28)
            }
            .contextMenu(forSelectionType: AdaptiveRecord.ID.self) { _ in
                Button(L("Open"), systemImage: "arrow.up.right") {}
                Button(L("Edit"), systemImage: "pencil") {}
                Button(L("Duplicate"), systemImage: "plus.square.on.square") {}
                Button(L("Delete"), systemImage: "trash", role: .destructive) {}
            }
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .background { TableThemer(canvas: UIColor(colors.background), row: UIColor(colors.backgroundSecondary)) }
            .stdMeasure("table")
        }
        .padding(.top, 8)
        // The inspector's container paints the system background above the table without this.
        .background(colors.background.ignoresSafeArea())
        .searchable(text: $query, placement: .toolbar, prompt: L("Search records"))
        .inspector(isPresented: Binding(get: { inspectorFits && selection != nil }, set: { if !$0 { selection = nil } })) {
            if let id = selection, let r = AdaptiveSeed.records.first(where: { $0.id == id }) {
                AdaptiveRecordInspector(record: r).inspectorColumnWidth(min: 280, ideal: 320, max: 360).stdMeasure("inspector")
            }
        }
        // Too narrow for table + inspector (Duo landscape): the record opens as a form sheet instead.
        .sheet(isPresented: Binding(get: { !inspectorFits && selection != nil }, set: { if !$0 { selection = nil } })) {
            if let id = selection, let r = AdaptiveSeed.records.first(where: { $0.id == id }) {
                AdaptiveRecordInspector(record: r).presentationSizing(.form)
            }
        }
    }

    /// Fallback: the r8 row list (LHRow.Browse) in one column ≤ 600, grouped by month.
    private func rowList(width: CGFloat) -> some View {
        List {
            Section {
                ForEach(rows) { r in
                    NavigationLink(value: r) {
                        StdBrowseRow(title: r.title, meta: L("\(r.day) · \(r.rental) · \(r.category.stdLabel)"),
                                     value: StdFormat.hours(r.hours), chevron: false) {
                            CategoryToolTile(category: r.category, size: 36)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(colors.backgroundSecondary)
                    .hoverEffect(.highlight)
                }
            } header: {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            StdChip(text: L("All rentals"), selected: true)
                            StdChip(text: "Santa Ray Ave")
                            StdChip(text: "Delaney Ct")
                            StdChip(text: "Yeandle Ave")
                        }
                    }
                    StdSectionHeader(title: L("October"))
                }
                .textCase(nil)
                .stdHeaderInsets()
            }
        }
        // Gutter before the shared style: the innermost contentMargins wins.
        .contentMargins(.horizontal, band.gutter, for: .scrollContent)
        .modifier(AdaptiveListStyle())
        .frame(maxWidth: width + 2 * band.gutter)
        .frame(maxWidth: .infinity)
        .navigationDestination(for: AdaptiveRecord.self) { r in
            ScrollView { AdaptiveRecordInspector(record: r).frame(maxWidth: 560) }.frame(maxWidth: .infinity)
                .background(colors.background.ignoresSafeArea())
        }
        .stdMeasure("column.single")
    }
}

struct AdaptiveRecordInspector: View {
    let record: AdaptiveRecord
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    CategoryToolTile(category: record.category, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title).font(.headline).foregroundStyle(colors.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text(L("\(record.day) · \(record.rental)")).font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                }
                VStack(spacing: 0) {
                    row(L("Hours"), StdFormat.hours(record.hours))
                    row(L("Kind of work"), record.category.stdLabel)
                    row(L("Who"), record.who)
                    row(L("From"), record.source == "calendar" ? L("Calendar") : record.source == "reminder" ? L("Reminder") : L("Logged by hand"))
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
                StdSectionHeader(title: L("Attachments"))
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundTertiary)
                    .overlay(Label(L("receipt-1022.pdf"), systemImage: "doc.richtext").font(.footnote).lineLimit(1)
                        .foregroundStyle(colors.textSecondary).padding(.horizontal, 8))
                    .frame(width: 180, height: 96)
                HStack(spacing: 12) {
                    Button(L("Edit")) {}.buttonStyle(StdButtonStyle(.secondary))
                    Button(L("Delete")) {}.buttonStyle(StdButtonStyle(.tertiary, destructive: true))
                }
            }
            .padding(20)
        }
        .background(colors.background)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body).foregroundStyle(colors.textPrimary)
            Spacer(minLength: 8)
            Text(value).font(.body).foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
    }
}

// MARK: - Resize demo: a window swept 1376 → 540 → 1376 in 8pt steps, so the hysteresis shows

@available(iOS 26.0, *)
struct AdaptiveResizeDemo: View {
    let launch: AdaptiveLaunch
    @State private var width: CGFloat = 1376
    @State private var shownBand: LayoutBand?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Color(white: 0.35).ignoresSafeArea()
                AdaptiveShell(launch: launch)
                    .environment(\.horizontalSizeClass, width < 600 ? .compact : .regular)
                    .frame(width: width, height: g.size.height - 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .offset(y: 56)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                        shownBand = LayoutBand.resolve(previous: shownBand, width: w)
                    }
                Text(verbatim: String(format: "Window W %.0f pt · band %@", width, (shownBand ?? .c).rawValue))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.top, 12)
            }
        }
        .task {
            func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            await pause(2.0)
            let down = stride(from: 1376.0, through: 540.0, by: -8.0)
            let up = stride(from: 540.0, through: 1376.0, by: 8.0)
            for w in down { width = w; await pause(w > 880 && w < 920 || w > 580 && w < 620 ? 0.35 : 0.06) }
            await pause(1.5)
            for w in up { width = w; await pause(w > 880 && w < 920 || w > 580 && w < 620 ? 0.35 : 0.06) }
        }
    }
}

// MARK: - Seed: Brian's rentals, ten To confirm items (R6 needs ≥ 8 on 13"), 24 records

enum AdaptiveSeed {
    static let seed: StdSeed = {
        let base = StdSeed.make("brian")
        let extra = [
            StdSuggestion(id: "s8", title: L("Lockbox code change at Yeandle Ave"), source: .reminder, when: L("Oct 20 3–3:30"), category: .management, status: .none, hours: 0.5, rental: "yeandle"),
            StdSuggestion(id: "s9", title: L("Pest control visit at Santa Ray Ave"), source: .calendar, when: L("Oct 21 9–10"), category: .repairs, status: .none, hours: 1, rental: "santa"),
            StdSuggestion(id: "s10", title: L("Insurance renewal call"), source: .calendar, when: L("Oct 21 2–2:30"), category: .insurance, status: .notSure, hours: 0.5),
        ]
        return StdSeed(id: base.id, rentals: base.rentals, suggestions: base.suggestions + extra, week: base.week)
    }()

    static let records: [AdaptiveRecord] = {
        let raw: [(String, String, String, ActivityCategory, String, Double, String)] = [
            ("Oct 22", "Smoke alarm batteries", "Santa Ray Ave", .repairs, "Me", 0.75, "manual"),
            ("Oct 20", "Paid the mortgage", "Delaney Ct", .bookkeeping, "Me", 0.25, "reminder"),
            ("Oct 19", "Showing", "Delaney Ct", .leasing, "Me", 1.5, "calendar"),
            ("Oct 19", "Tenant text about parking", "Delaney Ct", .management, "Spouse", 0.25, "manual"),
            ("Oct 17", "Turnover clean", "Santa Ray Ave", .management, "Me", 1.5, "calendar"),
            ("Oct 16", "Rent reminder texts", "Yeandle Ave", .management, "Me", 0.25, "reminder"),
            ("Oct 15", "Water heater quote", "Yeandle Ave", .repairs, "Me", 1, "calendar"),
            ("Oct 14", "Lease renewal draft", "Delaney Ct", .legal, "Spouse", 2, "manual"),
            ("Oct 12", "Hardware store run", "Santa Ray Ave", .repairs, "Me", 1, "manual"),
            ("Oct 11", "Gutter cleaning", "Delaney Ct", .repairs, "Me", 2, "calendar"),
            ("Oct 10", "Insurance policy review", "Yeandle Ave", .insurance, "Me", 0.5, "calendar"),
            ("Oct 9", "Guest check-in", "Santa Ray Ave", .management, "Spouse", 0.5, "calendar"),
            ("Oct 8", "Bookkeeping catch-up", "Delaney Ct", .bookkeeping, "Me", 1.5, "manual"),
            ("Oct 6", "Paint touch-ups", "Yeandle Ave", .renovations, "Me", 3, "manual"),
            ("Oct 5", "Showing", "Yeandle Ave", .leasing, "Me", 1, "calendar"),
            ("Oct 3", "Plumber visit", "Santa Ray Ave", .repairs, "Me", 2, "calendar"),
            ("Oct 2", "Property tax payment", "Delaney Ct", .bookkeeping, "Spouse", 0.25, "reminder"),
            ("Oct 1", "Paid the mortgage", "Santa Ray Ave", .bookkeeping, "Me", 0.25, "reminder"),
            ("Sep 29", "Turnover clean", "Santa Ray Ave", .management, "Me", 1.5, "calendar"),
            ("Sep 27", "Yard work", "Yeandle Ave", .repairs, "Me", 2.5, "manual"),
            ("Sep 25", "Tenant screening calls", "Delaney Ct", .leasing, "Me", 1, "calendar"),
            ("Sep 23", "Appliance delivery", "Yeandle Ave", .renovations, "Spouse", 1.5, "calendar"),
            ("Sep 21", "HOA meeting", "Delaney Ct", .management, "Me", 1, "calendar"),
            ("Sep 19", "Lockbox install", "Santa Ray Ave", .repairs, "Me", 0.5, "manual"),
        ]
        return raw.enumerated().map { i, r in
            AdaptiveRecord(id: i, sortDate: 1000 - i, day: r.0, title: r.1, rental: r.2, category: r.3, who: r.4, hours: r.5, source: r.6)
        }
    }()
}
#endif
