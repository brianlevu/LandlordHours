import SwiftUI
import UIKit

#if DEBUG
// MARK: - Duo concept A, "the door opens" (DEBUG mock, throwaway)
//
//   -LHDuoDoor open        on screen: Direction CRAFT Today (the closed Duo). Off screen: renders the OPEN layout
//                          (669×951pt, regular/regular, @3x) into Documents/duo/ as PNG, light and dark, with and
//                          without the interior art. The simulator cannot be unfolded by an agent, so the open state
//                          is forced by this argument and snapshotted from a second, off-screen window.
//
// Concept (productivity first): when the phone opens, the camera walks through the front door into a warm room. The
// room is a calm backdrop; the work sits on opaque panes over it. Left pane: To confirm. Right pane: the selected
// item, ready to confirm. The goal line rides in a plate at the top. Text never sits on the art.
// Every string goes through DD(...) (table "DuoDoor").

func DD(_ key: String.LocalizationValue) -> String { String(localized: key, table: "DuoDoor") }

struct DuoDoorLaunch {
    static let isOpen: Bool = {
        let a = ProcessInfo.processInfo.arguments
        guard let j = a.firstIndex(of: "-LHDuoDoor"), a.indices.contains(j + 1) else { return false }
        return a[j + 1].lowercased() == "open"
    }()
}

// MARK: Root: closed Today on screen, the open layout rendered off screen

struct DuoDoorRoot: View {
    var body: some View {
        DirCraftRoot(launch: CraftLaunch(seedID: "craft", demo: nil, focusIndex: 0, windows: true,
                                         firstHour: false, scrollToEnd: false))
            .task { await DuoDoorSnapshotter.run() }
    }
}

@MainActor
enum DuoDoorSnapshotter {
    static let openSize = CGSize(width: 669, height: 951)
    static var windows: [UIWindow] = []

    static func run() async {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("duo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for dark in [false, true] {
            for art in [true, false] {
                let name = "open-\(dark ? "dark" : "light")\(art ? "" : "-ui")"
                await render(DuoDoorOpenScreen(showArt: art), dark: dark, scene: scene, to: dir.appendingPathComponent(name + ".png"))
            }
        }
        print("DUODOOR snapshots in \(dir.path)")
    }

    private static func render(_ view: some View, dark: Bool, scene: UIWindowScene, to url: URL) async {
        let hc = UIHostingController(rootView: AnyView(view))
        hc.overrideUserInterfaceStyle = dark ? .dark : .light
        hc.traitOverrides.horizontalSizeClass = .regular
        hc.traitOverrides.verticalSizeClass = .regular
        hc.view.backgroundColor = .clear
        hc.safeAreaRegions = []            // the folded screen's trailing status-bar inset must not leak into the open layout
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: openSize)
        w.windowLevel = .normal - 1          // behind the on-screen app
        w.backgroundColor = .clear
        w.rootViewController = hc
        w.isHidden = false
        windows.append(w)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let f = UIGraphicsImageRendererFormat(); f.scale = 3; f.opaque = false
        let img = UIGraphicsImageRenderer(size: openSize, format: f).image { ctx in
            w.layer.render(in: ctx.cgContext)
        }
        try? img.pngData()?.write(to: url)
        w.isHidden = true
    }
}

// MARK: - The open layout

struct DuoDoorOpenScreen: View {
    var showArt = true
    @State private var selected = "s1"
    @State private var hours: Double = 2
    private var env = DAEnv()
    private var craft = CraftEnv()
    @Environment(\.colorScheme) private var scheme

    private var c: DAColors { env.c }
    private var items: [StdSuggestion] { DuoDoorSeed.items }
    private var item: StdSuggestion { items.first { $0.id == selected } ?? items[0] }

    // The inner display's insets, assumed (not measured: the simulator cannot unfold): status bar 32, home 20.
    private let topInset: CGFloat = 32
    private let gutter: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            if showArt { interior }
            VStack(spacing: 0) {
                goalPlate
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 12) {
                    listPane.frame(width: 280)
                    detailPane
                }
                .frame(height: 586)
                tabBar.padding(.top, 12)
            }
            .padding(.horizontal, gutter)
            .padding(.top, topInset + 8)
            .padding(.bottom, 20)
        }
        .frame(width: DuoDoorSnapshotter.openSize.width, height: DuoDoorSnapshotter.openSize.height)
        .ignoresSafeArea()
    }

    // The room: a soft, warm interior with depth of field (Blender, same rig). Calm by design: no text on it.
    private var interior: some View {
        // The render's focal band (window, pendant, bench, centred at half its height) is placed at y = 230pt, between
        // the goal plate and the panes; 1.2x; below the art the floor tone continues (the panes cover it).
        Image("duo_interior")
            .resizable()
            .frame(width: DuoDoorSnapshotter.openSize.width * 1.2, height: DuoDoorSnapshotter.openSize.height * 1.2)
            .position(x: DuoDoorSnapshotter.openSize.width / 2, y: 230)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 0.84)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: DuoDoorSnapshotter.openSize.width, height: DuoDoorSnapshotter.openSize.height)
            .background(Color(hex: scheme == .dark ? "391602" : "582802"))   // the floor's own tone, sampled from the render's bottom row
            .clipped()
            .accessibilityHidden(true)
    }

    // MARK: Goal plate: the rental, the number, the pace. Opaque, so the text never meets the art.

    private var goalPlate: some View {
        let f = DuoDoorSeed.focus
        let p = f.pace
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.name).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(c.textSecondary)
                }
                (Text(p.lead).foregroundStyle(f.isBehind ? craft.c.behind : craft.c.positive).fontWeight(.semibold)
                 + Text(verbatim: " ") + Text(p.rest).foregroundStyle(c.textSecondary))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "\(Int(f.logged))")
                    .font(DAFont.fraunces(size: 44, opsz: 144, wght: 600)).tracking(-1)
                    .foregroundStyle(c.ink)
                Text(DD("of \(Int(f.goal))h")).font(.subheadline).foregroundStyle(c.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
    }

    // MARK: Left pane: To confirm

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(DD("To confirm · \(items.count)")).font(.headline).foregroundStyle(c.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                if i > 0 { DAHairline().padding(.leading, 48) }
                row(it)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
    }

    private func row(_ it: StdSuggestion) -> some View {
        let on = it.id == selected
        return Button { selected = it.id; hours = it.hours ?? 1 } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle").font(.title3).foregroundStyle(c.textSecondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.title).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(it.when).font(.footnote).foregroundStyle(c.textSecondary)
                }
                Spacer(minLength: 4)
                Text(StdFormat.hours(it.hours ?? 0)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(c.ink)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(minHeight: 64)
            .background(on ? c.actionSurface : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(DAPress())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Right pane: the selected item, ready to confirm

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.title3.weight(.semibold)).foregroundStyle(c.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Label(DD("Calendar · \(item.when)"), systemImage: "calendar")
                    .font(.footnote).foregroundStyle(c.textSecondary)
            }
            .padding(16)
            DAHairline()
            value(DD("Rental"), "Santa Ray Ave")
            DAHairline().padding(.leading, 16)
            HStack {
                Text(DD("Kind")).font(.body).foregroundStyle(c.ink)
                Spacer()
                DATag(text: item.category?.stdLabel ?? DD("Other"),
                      ink: item.category.map { c.tagInk($0) } ?? c.textSecondary,
                      wash: item.category.map { c.tagWash($0) } ?? c.surfaceInner).fixedSize()
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
            DAHairline().padding(.leading, 16)
            value(DD("Who"), DD("You"))
            DAHairline().padding(.leading, 16)
            HStack {
                Text(DD("Hours")).font(.body).foregroundStyle(c.ink)
                Spacer()
                Text(StdFormat.hours(hours)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(c.ink)
                    .contentTransition(.numericText(value: hours))
                    .padding(.trailing, 8)
                stepper
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
            DAHairline()
            Text(DD("Adds to Santa Ray Ave's hours for 2026."))
                .font(.footnote).foregroundStyle(c.textSecondary)
                .padding(.horizontal, 16).padding(.top, 12)
            VStack(spacing: 4) {
                Button(DD("Confirm \(StdFormat.hours(hours))")) {}
                    .buttonStyle(DAPrimaryStyle())
                Button(DD("Not rental work")) {}
                    .font(.body.weight(.semibold)).foregroundStyle(c.action)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(DAPress())
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
    }

    /// LHStepper: two 44pt halves in one capsule on surfaceInner.
    private var stepper: some View {
        HStack(spacing: 0) {
            Button { hours = max(0.25, hours - 0.25) } label: { Image(systemName: "minus").frame(width: 44, height: 36) }
                .accessibilityLabel(DD("Less"))
            Rectangle().fill(c.border).frame(width: 0.5, height: 20)
            Button { hours = min(12, hours + 0.25) } label: { Image(systemName: "plus").frame(width: 44, height: 36) }
                .accessibilityLabel(DD("More"))
        }
        .font(.body.weight(.semibold)).foregroundStyle(c.ink)
        .buttonStyle(DAPress())
        .background(c.surfaceInner, in: Capsule())
    }

    private func value(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.body).foregroundStyle(c.ink)
            Spacer()
            Text(v).font(.body).foregroundStyle(c.textSecondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }

    // MARK: Tab bar (drawn here because the open pose can't be reached on the simulator; the app uses TabView)

    private var tabBar: some View {
        let tabs: [(String, String, Bool)] = [(DD("Today"), "sun.horizon", true), (DD("Inbox"), "tray", false),
                                             (DD("Records"), "book.closed", false), (DD("Rentals"), "house", false),
                                             (DD("Log time"), "plus", false)]
        return HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { t in
                VStack(spacing: 2) {
                    Image(systemName: t.1).font(.system(size: 20, weight: .medium))
                    Text(t.0).font(.caption2.weight(.semibold))
                }
                .foregroundStyle(t.2 ? c.action : c.ink)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(t.2 ? c.ink.opacity(0.08) : .clear, in: Capsule())
            }
        }
        .padding(6)
        .frame(maxWidth: 520)
        .background { Capsule().fill(c.surface).shadow(color: .black.opacity(0.18), radius: 10, y: 2) }
        .frame(maxWidth: .infinity)
    }
}

enum DuoDoorSeed {
    static let focus = CraftFocus(id: "all", name: DD("All rentals"), logged: 750, goal: 750, art: .complete)   // matches the closed frame (-LHHomeSeed goal750)
    static let items: [StdSuggestion] = [
        StdSuggestion(id: "s1", title: DD("Plumber at Santa Ray Ave"), source: .calendar, when: DD("Today 12–2"), category: .repairs, status: .none, hours: 2, rental: "santa"),
        StdSuggestion(id: "s2", title: DD("Gutter cleaning at Delaney Ct"), source: .calendar, when: DD("Today 8–10"), category: .repairs, status: .mightBeLogged, hours: 2),
        StdSuggestion(id: "s3", title: DD("Showing at Pine Cabin"), source: .calendar, when: DD("Oct 22 9–10:30"), category: .leasing, status: .notSure, hours: 1.5),
        StdSuggestion(id: "s4", title: DD("Tenant call about the lease"), source: .calendar, when: DD("Oct 21 4–4:30"), category: .leasing, status: .none, hours: 0.5),
        StdSuggestion(id: "s5", title: DD("Monthly mortgage payment"), source: .reminder, when: DD("Nov 1"), category: .bookkeeping, status: .none, hours: 0.25),
        StdSuggestion(id: "s6", title: DD("Smoke alarm check"), source: .reminder, when: DD("Oct 20"), category: .repairs, status: .none, hours: 0.5),
        StdSuggestion(id: "s7", title: DD("Insurance renewal call"), source: .calendar, when: DD("Oct 19 3–3:30"), category: .bookkeeping, status: .none, hours: 0.5),
    ]
}

// MARK: - The door: plays once when the window grows into the regular band (fold → open). Never blocks input.

/// Overlay the pre-rendered door clip for ≤ 0.8 s when the width crosses from band A to B/C. The UI underneath is laid
/// out and hit-testable from the first frame; the overlay has `allowsHitTesting(false)`. Folding plays the clip
/// reversed. Reduce Motion: a 0.2 s crossfade, no camera move. Not exercised on the simulator (no unfold).
struct DuoDoorTransition: ViewModifier {
    @State private var wide = false
    @State private var playing = false
    @State private var tick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { $0.size.width >= 608 } action: { isWide in
                guard isWide != wide else { return }
                wide = isWide
                if reduceMotion { return }      // the system resize plus a 0.2 s crossfade on the content
                playing = true; tick += 1
            }
            .overlay {
                if playing, let url = Bundle.main.url(forResource: "duo_door_\(scheme == .dark ? "dark" : "light")\(wide ? "" : "_reverse")",
                                                       withExtension: "mov") {
                    CraftVideo(url: url, tick: tick) { withAnimation(.easeOut(duration: 0.15)) { playing = false } }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: wide)
    }
}
#endif
