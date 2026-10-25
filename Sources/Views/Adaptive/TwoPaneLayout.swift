import SwiftUI

// MARK: - TwoPaneLayout: one root for compact, two-pane and stacked (§1.27; plan J1/J2)
//
// Wraps the shell. In compact it shows the shell exactly as it is (the locked phone layout, details
// and Log time as sheets). In two-pane it lays the house pane on the left and the shell's tab view in
// the work pane on the right, its bar at the right pane's foot; stacked turns that on its side.
// The panes do not know which device they are on:
//   · the Duo (an active `.division`, iOS 27.1): `ArrangementView { house } secondary: { work }`
//     with `.split` along the fold (which side the primary renders on is must-prove 15);
//   · everywhere else: the same two views in an `HStack` with the 24pt gap.
// The gap is page, not a divider: nothing crosses it, and the door's light centres on it (DU2, DU10).

struct TwoPaneLayout<Work: View>: View {
    @ViewBuilder let work: () -> Work

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutBand) private var band
    @StateObject private var selection = AdaptiveSelection()
    @StateObject private var clock = DoorClock()
    @State private var split: LayoutSplit = .compact(.zero)
    @State private var resolvedOnce = false
    /// True when the division came from the system (`reservedRegions`), not a DEBUG capture.
    @State private var systemDivision = false
    @State private var settle: Task<Void, Never>?

    init(@ViewBuilder work: @escaping () -> Work) { self.work = work }

    var body: some View {
        content
            .background {
                Color.clear
                    .onGeometryChange(for: GeometryProbe.self) { proxy in GeometryProbe(proxy) } action: { probe in
                        update(probe)
                    }
            }
            .environment(\.layoutMode, split.mode)
            .duoUnfold(clock, isEnabled: split.isDivision)
            .simultaneousGesture(TapGesture().onEnded { clock.finish() }, including: clock.t < 1 ? .all : .none)
            #if DEBUG
            .onAppear { AdaptiveDebug.onRootAppear() }
            #endif
    }

    @ViewBuilder private var content: some View {
        switch split.mode {
        case .compact:
            if horizontalSizeClass == .regular {
                // A compact iPad window (Split View, Stage Manager under 800 × 645) is still regular
                // width, where the system would float its iPad bar at the top. The bar is the same
                // bottom bar in every mode (§1.27), so the shell goes through the same bridge.
                WorkPane {
                    work().modifier(WorkPaneEnvironment(viewModel: viewModel, selection: selection, mode: .compact,
                                                        typeSize: typeSize, colorScheme: colorScheme,
                                                        context: .sheet, band: band))
                }
                .ignoresSafeArea(.container, edges: .vertical)
            } else {
                work()
                    .environment(\.paneContext, .sheet)
                    .environmentObject(selection)
            }
        case .twoPane, .stacked:
            split.mode == .twoPane ? AnyView(twoPane) : AnyView(stacked)
        }
    }

    // MARK: Two-pane

    private var house: some View {
        HousePane(split: split, showsDoor: split.isDivision, clock: clock)
            .environmentObject(selection)
    }

    private var workPane: some View {
        WorkPane {
            work().modifier(WorkPaneEnvironment(viewModel: viewModel, selection: selection, mode: split.mode,
                                                typeSize: typeSize, colorScheme: colorScheme,
                                                foldInset: split.mode == .twoPane ? split.gap.width / 2 : 0))
        }
        .overlay { if split.isDivision { InsideLight(clock: clock) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.work")
    }

    @ViewBuilder private var twoPane: some View {
        let first = split.first, second = split.second
        Group {
            if #available(iOS 27.1, *), split.isDivision, systemDivision {
                ArrangementView {
                    house
                } secondary: {
                    workPane
                }
                .arrangementViewStyle(.split.axes(.horizontal))
                .splitArrangementLayoutRatio(0.5)
            } else {
                HStack(spacing: 0) {
                    house.frame(width: first.width)
                    // The gap: page, not a divider. Nothing crosses it.
                    Color.clear.frame(width: split.gap.width).accessibilityHidden(true)
                    // The work pane runs to the window's top and bottom edges, so its hosted bar
                    // takes the home indicator's inset like a phone's (UIKit safe areas inside).
                    workPane.frame(width: second.width).ignoresSafeArea(.container, edges: .vertical)
                }
            }
        }
        .background {
            // One page under both panes, so the two walls meet with no seam (DU9).
            HStack(spacing: 0) {
                LHPage()
                    .overlay { FoldWash() }
                    .frame(width: first.width + split.gap.width / 2)
                InteriorWall(glowCenter: UnitPoint(x: 0, y: 0.38))
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Stacked (the Duo propped)

    @ViewBuilder private var stacked: some View {
        let first = split.first, second = split.second
        VStack(spacing: 0) {
            house.frame(height: first.height)
            Color.clear.frame(height: split.gap.height).accessibilityHidden(true)
            workPane.frame(height: second.height).ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background { StackedWall(fold: split.gap) }
    }

    // MARK: Mode

    private func update(_ probe: GeometryProbe) {
        systemDivision = probe.division != nil
        let division = probe.division ?? AdaptiveDebug.capturedDivision(for: probe.size)
        if !resolvedOnce {
            // Scene connect and launch: no history.
            resolvedOnce = true
            apply(LayoutMode.resolve(previous: nil, size: probe.size, division: division, live: false))
            return
        }
        // A size change: resolve with hysteresis while it is live, then once more with no history
        // after 0.3 s of stillness (the mode never depends on the path taken).
        apply(LayoutMode.resolve(previous: split.mode, size: probe.size, division: division, live: true))
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(LayoutMode.settleDelay))
            guard !Task.isCancelled else { return }
            apply(LayoutMode.resolve(previous: nil, size: probe.size, division: division, live: false))
        }
    }

    private func apply(_ new: LayoutSplit) {
        guard new != split else { return }
        split = new
    }
}

/// What the root measures: the scene's size (safe areas included) and the active division.
struct GeometryProbe: Equatable {
    let size: CGSize
    let division: PaneDivision?

    init(size: CGSize, division: PaneDivision?) {
        self.size = size
        self.division = division
    }

    init(_ proxy: GeometryProxy) {
        // The scene's size, safe areas included (the window, never the screen).
        let inset = proxy.safeAreaInsets
        size = CGSize(width: proxy.size.width + inset.leading + inset.trailing,
                      height: proxy.size.height + inset.top + inset.bottom)
        if #available(iOS 27.1, *) {
            let regions = proxy.reservedRegions(kind: .division).filter(\.isActive)
            if let region = regions.first {
                let f = region.frame, m = region.margins
                division = PaneDivision(rect: CGRect(x: f.minX - m.leading, y: f.minY - m.top,
                                                     width: f.width + m.leading + m.trailing,
                                                     height: f.height + m.top + m.bottom))
            } else {
                division = nil
            }
        } else {
            division = nil
        }
    }
}

/// The propped wall: one page down the whole display, the room in the lower half, and one door glow
/// straddling the fold (one object, so both sides carry the same wall; DU9).
private struct StackedWall: View {
    let fold: CGRect
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { g in
            let h = max(g.size.height, 1)
            let mid = fold.midY
            let dark = colorScheme == .dark
            ZStack(alignment: .top) {
                LHPage()
                InteriorWall(page: false, glow: false)
                    .frame(height: max(0, h - mid))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                RadialGradient(colors: [DoorArt.glow(dark: dark), .clear], center: UnitPoint(x: 0.5, y: mid / h),
                               startRadius: 0, endRadius: 260)
                    .blendMode(dark ? .plusLighter : .screen)
                    .mask {
                        LinearGradient(stops: dark
                                       ? [.init(color: .black.opacity(0.12), location: 0), .init(color: .black.opacity(0.12), location: max(0, (mid - 14) / h)),
                                          .init(color: .black, location: max(0, (mid - 6) / h)), .init(color: .black, location: min(1, (mid + 6) / h)),
                                          .init(color: .black.opacity(0.12), location: min(1, (mid + 14) / h)), .init(color: .black.opacity(0.12), location: 1)]
                                       : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .compositingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
