import SwiftUI

// MARK: - TwoPaneLayout: one root for compact, two-pane and stacked (§1.27; plan J1/J2)
//
// Wraps the shell. In compact it shows the shell exactly as it is (the locked phone layout, details
// and Log time as sheets). In two-pane it lays the house pane on the left and the shell's tab view in
// the work pane on the right, its bar at the right pane's foot; stacked turns that on its side.
// The panes do not know which device they are on:
//   · everywhere: the two views in an `HStack` with the gap (24pt on iPad, `LayoutMode.paneGap`);
//   · the Duo (an active `.division`): its lane reads the fold and may swap the container for
//     `ArrangementView` through `TwoPaneHooks` (docs/plans/two-pane-api.md). This file has no
//     hinge, posture or door code.
// The gap is page, not a divider: nothing crosses it, and the door's light centres on it (DU2, DU10).

struct TwoPaneLayout<Work: View>: View {
    @ViewBuilder let work: () -> Work

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutBand) private var band
    @StateObject private var selection = AdaptiveSelection()
    @Environment(\.twoPaneHooks) private var hooks
    @State private var split: LayoutSplit = .compact(.zero)
    @State private var resolvedOnce = false
    /// True when the division came from the system (`reservedRegions`), not a DEBUG capture.
    @State private var systemDivision = false
    @State private var settle: Task<Void, Never>?
    /// The window's top inset: the stacked halves run to the window's edges, so the top half pads
    /// its own content below it (the numeral never sits under the status bar, AX included).
    @State private var topInset: CGFloat = 0

    init(@ViewBuilder work: @escaping () -> Work) { self.work = work }

    var body: some View {
        let readDivision = hooks.division
        let layout = ZStack {
            // The probe is the content's sibling, so a pane that ignores a safe area (stacked) can
            // never feed its own size back into the mode.
            Color.clear
                .onGeometryChange(for: GeometryProbe.self) { proxy in GeometryProbe(proxy, division: readDivision) } action: { probe in
                    update(probe)
                }
            content
        }
            .environment(\.layoutMode, split.mode)
            #if DEBUG
            .onAppear { AdaptiveDebug.onRootAppear() }
            #endif
        if let root = hooks.root {
            root(AnyView(layout), split)
        } else {
            layout
        }
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
        HousePane(split: split, topInset: split.mode == .stacked ? topInset : 0)
            .environmentObject(selection)
            .clipped()   // nothing in the house pane ever crosses the gap or fold (DU2)
    }

    private var workPane: some View {
        WorkPane {
            work().modifier(WorkPaneEnvironment(viewModel: viewModel, selection: selection, mode: split.mode,
                                                typeSize: typeSize, colorScheme: colorScheme,
                                                foldInset: split.mode == .twoPane ? split.gap.width / 2 : split.gap.height / 2,
                                                gutter: PaneMetrics.gutter(paneWidth: split.second.width, onDuo: split.isDivision),
                                                windowHeight: split.size.height))
        }
        .overlay { if let overlay = hooks.workOverlay { overlay(split) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.work")
    }

    @ViewBuilder private var twoPane: some View {
        let first = split.first, second = split.second
        Group {
            if split.isDivision, systemDivision, let arrange = hooks.arrangement {
                arrange(split, AnyView(house), AnyView(workPane))
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
            workPane.frame(height: second.height)
        }
        // The halves are measured from the window's edges (the fold sits at its division), so the
        // stack spans the whole window; each half keeps its own insets inside.
        .ignoresSafeArea(.container, edges: .vertical)
        .background { StackedWall(fold: split.gap) }
    }

    // MARK: Mode

    private func update(_ raw: GeometryProbe) {
        // Whole half-points: a size that differs only in float noise (978.9999 / 979.0001) must not
        // re-resolve the split, or the layout re-renders forever.
        let measured = CGSize(width: (raw.size.width * 2).rounded() / 2, height: (raw.size.height * 2).rounded() / 2)
        let probe = GeometryProbe(size: AdaptiveDebug.capturedSize(for: measured) ?? measured, division: raw.division)
        let inset = AdaptiveDebug.capturedTopInset(for: measured) ?? (raw.topInset * 2).rounded() / 2
        if inset != topInset { topInset = inset }
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
    /// The scene's top safe-area inset.
    var topInset: CGFloat = 0

    init(size: CGSize, division: PaneDivision?, topInset: CGFloat = 0) {
        self.size = size
        self.division = division
        self.topInset = topInset
    }

    /// - Parameter division: the Duo lane's fold reader (`TwoPaneHooks.division`); nil on iPad.
    init(_ proxy: GeometryProxy, division read: (GeometryProxy) -> PaneDivision?) {
        // The scene's size, safe areas included (the window, never the screen).
        let inset = proxy.safeAreaInsets
        topInset = inset.top
        size = CGSize(width: proxy.size.width + inset.leading + inset.trailing,
                      height: proxy.size.height + inset.top + inset.bottom)
        division = read(proxy)
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
                InteriorWall(page: false, glow: false, foldAbove: true)
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
