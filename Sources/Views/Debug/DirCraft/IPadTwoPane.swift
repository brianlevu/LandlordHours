import SwiftUI
import UIKit

#if DEBUG
// MARK: - iPad two-pane (DEBUG prototype, throwaway). Design standard §1.27 on duo-v2.
//
//   -LHIPad2P                      (with -LHDirection CRAFT -LHDirFocus 2 -LHCraftWindows lit) runs the live layout
//   -LHIPad2PRight list|detail|log   the right pane's state
//   -LHIPad2PRentals 3|8
//
// Mode is chosen from the scene width only: two-pane iff W >= 784 (hysteresis 8), else the compact one column
// (the existing DirCraft Today). Panes are (W - 24) / 2, content capped at 600 and centred. No door, no light-up:
// the right pane is lit at rest (clock.t = 1).

enum IPadTwoPaneLaunch {
    static let args = ProcessInfo.processInfo.arguments
    static func value(_ f: String) -> String? {
        guard let j = args.firstIndex(of: f), args.indices.contains(j + 1) else { return nil }
        return args[j + 1]
    }
    static var enabled: Bool { args.contains("-LHIPad2P") }
    /// Set by the renderer per frame; wins over -LHIPad2PRight.
    static var rightOverride: String?
}

enum IPadLayout {
    static let gap: CGFloat = 24
    static let minPane: CGFloat = 380
    static let contentCap: CGFloat = 600
    static func twoPane(width w: CGFloat, previous: Bool) -> Bool { previous ? w >= 776 : w >= 792 }
    static func pane(_ w: CGFloat) -> CGFloat { (w - gap) / 2 }
    static func hero(pane: CGFloat) -> CGFloat { min(max((0.626 * pane).rounded(), 290), 390) }
}

@available(iOS 26.0, *)
struct IPadTwoPaneRoot: View {
    @State private var two = false
    @State private var w: CGFloat = 0
    var body: some View {
        ZStack {
            if two { IPadTwoPaneView(width: w) }
            else if let craft = CraftLaunch.current { DirCraftRoot(launch: craft) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            w = new
            let t = IPadLayout.twoPane(width: new, previous: two)
            if t != two { two = t }
        }
        .onAppear {
            DuoTabBarInk.apply()
            if IPadTwoPaneLaunch.args.contains("-LHIPad2PRender"), !IPadSnapshotter.started { IPadSnapshotter.started = true; Task { await IPadSnapshotter.run() } }
            NSLog("IPAD2P onAppear")
            if IPadTwoPaneLaunch.args.contains("-LHIPad2PLandscape") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
                        .requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { NSLog("IPAD2P geo error: %@", "\($0)") }
                }
            }
        }
    }
}

/// Hosts SwiftUI in a controller whose horizontal size class is compact, so iPadOS draws the phone tab bar at the foot.
private struct CompactHost<C: View>: UIViewControllerRepresentable {
    let content: C
    func makeUIViewController(context: Context) -> UIHostingController<C> {
        let hc = UIHostingController(rootView: content)
        hc.view.backgroundColor = .clear
        hc.traitOverrides.horizontalSizeClass = .compact
        return hc
    }
    func updateUIViewController(_ hc: UIHostingController<C>, context: Context) { hc.rootView = content }
}

@available(iOS 26.0, *)
struct IPadTwoPaneView: View {
    let width: CGFloat
    @State private var tab = 0
    @State private var selectedID: String
    @State private var right: DuoRight
    let rentals: [DuoRental]
    private let clock = DuoDoorClock()   // t = 1: lit at rest, no door

    init(width: CGFloat) {
        self.width = width
        let eight = IPadTwoPaneLaunch.value("-LHIPad2PRentals") == "8"
        rentals = eight ? DuoV2Seed.eight : DuoV2Seed.three
        _selectedID = State(initialValue: IPadTwoPaneLaunch.value("-LHIPad2PSelect") ?? "pine")
        switch IPadTwoPaneLaunch.rightOverride ?? IPadTwoPaneLaunch.value("-LHIPad2PRight") {
        case "detail": _right = State(initialValue: .detail("s5"))
        case "log": _right = State(initialValue: .log)
        default: _right = State(initialValue: .list)
        }
    }

    private var pane: CGFloat { IPadLayout.pane(width) }
    private var cap: CGFloat { IPadLayout.contentCap }

    var body: some View {
        HStack(spacing: 0) {
            DuoHousePane(rentals: rentals, selectedID: $selectedID, heroSide: IPadLayout.hero(pane: pane), clock: clock)
                .frame(maxWidth: cap)
                .frame(width: pane)
            Color.clear.frame(width: IPadLayout.gap)
            CompactHost(content: workTabs).frame(width: pane)
        }
        .background {
            HStack(spacing: 0) {
                CraftPage().overlay { DuoFoldWash() }.frame(width: pane + IPadLayout.gap / 2)
                DuoInterior(glowCenter: UnitPoint(x: -IPadLayout.gap / 2 / pane, y: 0.38))
            }
            .ignoresSafeArea()
        }
        .onChange(of: tab) { old, new in if new == 4 { tab = old; right = .log } }
    }

    private var workTabs: some View {
        TabView(selection: $tab) {
            Tab(CL("Today"), systemImage: "sun.horizon", value: 0) { work }
            Tab(CL("Inbox"), systemImage: "tray", value: 1) { DuoInterior(glowCenter: UnitPoint(x: -IPadLayout.gap / 2 / pane, y: 0.38)) }.badge(7)
            Tab(CL("Records"), systemImage: "book.closed", value: 2) { DuoInterior() }
            Tab(CL("Rentals"), systemImage: "house", value: 3) { DuoInterior() }
            Tab(CL("Log time"), systemImage: "plus", value: 4, role: .search) { DuoInterior() }
        }
        .modifier(IPadTint())
        .modifier(IPadTabBarOnly())
    }

    private var work: some View {
        DuoWorkstation(rentals: rentals, selectedID: $selectedID, right: $right,
                       glowCenter: UnitPoint(x: -IPadLayout.gap / 2 / pane, y: 0.38))
            .padding(.horizontal, max(0, (pane - cap) / 2))
            .background { DuoInterior(glowCenter: UnitPoint(x: -IPadLayout.gap / 2 / pane, y: 0.38)) }
    }
}

private struct IPadTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(CraftColors(dark: scheme == .dark).action) }
}

private struct IPadTabBarOnly: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.tabViewStyle(.tabBarOnly) } else { content }
    }
}

// MARK: - Off-screen renderer: the live view in a UIWindow of an exact iPad window size, drawHierarchy @2x

@available(iOS 26.0, *)
@MainActor
enum IPadSnapshotter {
    static var windows: [UIWindow] = []
    static var started = false
    /// The 13" Air (M4) screen is 1024x1366; the others are real iPadOS window widths.
    static let sizes: [(String, CGSize)] = [
        ("landscape-1366x1024", CGSize(width: 1366, height: 1024)),
        ("portrait-1024x1366", CGSize(width: 1024, height: 1366)),
        ("splithalf-678x1024", CGSize(width: 678, height: 1024)),
        ("split-438x1024", CGSize(width: 438, height: 1024)),
        ("w792-792x1024", CGSize(width: 792, height: 1024)),
        ("w775-775x1024", CGSize(width: 775, height: 1024)),
    ]
    static func run() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ipad2p")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for dark in [false, true] {
            let tag = dark ? "night" : "dusk"
            for (name, size) in sizes {
                for right in ["list", "detail"] where right == "list" || name.hasPrefix("landscape") || name.hasPrefix("portrait") {
                    IPadTwoPaneLaunch.rightOverride = right
                    let root = IPadTwoPaneRoot()
                        .safeAreaPadding(EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))
                        .environment(\.dynamicTypeSize, .large)
                        .frame(width: size.width, height: size.height)
                    let hc = UIHostingController(rootView: AnyView(root))
                    hc.overrideUserInterfaceStyle = dark ? .dark : .light
                    hc.safeAreaRegions = []
                    let w = UIWindow(windowScene: scene)
                    w.frame = CGRect(origin: .zero, size: size)
                    w.windowLevel = .normal - 1
                    w.rootViewController = hc
                    w.isHidden = false
                    windows.append(w)
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    let f = UIGraphicsImageRendererFormat(); f.scale = 2; f.opaque = true
                    let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
                        _ = w.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                    }
                    try? img.pngData()?.write(to: dir.appendingPathComponent("\(name)-\(right)-\(tag).png"))
                    w.isHidden = true
                }
            }
        }
        try? "done".write(to: dir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
    }
}
#endif
