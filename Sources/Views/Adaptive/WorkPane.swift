import SwiftUI
import UIKit

// MARK: - WorkPane: the right (two-pane) or bottom (stacked) pane (§1.27; must-prove 12)
//
// Hosts the shell's tab view in ONE child `UIHostingController` whose
// `traitOverrides.horizontalSizeClass = .compact`, so the system itself draws its compact bottom
// bar at the pane's foot (the one allowed bridge; [grep] the only `traitOverrides.horizontalSizeClass`
// in shipping code). `.toolbarVerticalBehavior(.disabled)` (iOS 27.1) keeps the Duo from folding
// the bar into a side rail beside the fold. If must-prove 12 fails on an OS, that OS gets the
// system's own iPad bar over the right pane (`WorkPane.usesCompactBridge` false), never a custom bar.
//
// A new hosting controller does not inherit the SwiftUI environment, so the objects and values the
// shell's screens read are passed in again here (`WorkPaneEnvironment`).

struct WorkPane<Content: View>: View {
    let content: Content
    /// The bridge's handle on its hosting controller (Log time hides the tab content under it).
    @State private var bridge = PaneHostBridge()

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    /// The bridge is on for every OS this build runs on until a device run proves otherwise
    /// (must-prove 12: iPadOS 18, 26 and 27). The fallback is the system's own iPad bar.
    static var usesCompactBridge: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHPaneSystemBar") { return false }
        #endif
        return true
    }

    var body: some View {
        if Self.usesCompactBridge {
            let bridge = self.bridge
            CompactPaneHost(content: content.modifier(NoVerticalBar())
                .onPreferenceChange(PaneCoversTabKey.self) { covered in
                    MainActor.assumeIsolated { bridge.setTabContentCovered(covered) }
                },
                            bridge: bridge)
        } else {
            content.modifier(NoVerticalBar())
        }
    }
}

/// iOS 27.1: the bar stays at the foot of the resting pane, never a side rail beside the fold.
private struct NoVerticalBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) { content.toolbarVerticalBehavior(.disabled) } else { content }
    }
}

/// True while something in the pane (Log time) covers the selected tab's content.
struct PaneCoversTabKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The work pane's handle on its hosting controller. While Log time is open in the pane, the tab
/// content under it is hidden at the UIKit level, so nothing of the tab underneath (Records' list,
/// say) shows around the card, between the card and the bar, or through the bar's glass: the bar
/// floats over the pane's own wall (§1.27; gate J r2, mp12 frames). The bar itself stays.
@MainActor
final class PaneHostBridge {
    weak var host: UIViewController?
    private(set) var covered = false

    func setTabContentCovered(_ covered: Bool) {
        self.covered = covered
        apply(animated: true)
    }

    /// Hides (or shows) every tab's content view; the tab bar is the tab controller's own view
    /// and is never touched.
    func apply(animated: Bool) {
        guard let host, let tabs = Self.tabBarController(in: host) else { return }
        let alpha: CGFloat = covered ? 0 : 1
        let views = (tabs.viewControllers ?? []).compactMap(\.viewIfLoaded)
        let change = {
            for view in views {
                view.alpha = alpha
                view.accessibilityElementsHidden = self.covered
            }
        }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: change)
        } else {
            change()
        }
    }

    static func tabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let tabs = tabBarController(in: child) { return tabs }
        }
        return nil
    }
}

/// The one child hosting controller with the compact horizontal size class.
private struct CompactPaneHost<C: View>: UIViewControllerRepresentable {
    let content: C
    let bridge: PaneHostBridge

    func makeUIViewController(context: Context) -> UIHostingController<C> {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.traitOverrides.horizontalSizeClass = .compact
        bridge.host = host
        return host
    }

    func updateUIViewController(_ host: UIHostingController<C>, context: Context) {
        host.rootView = content
        bridge.host = host
        // A tab loaded while Log time was open takes the same state.
        if bridge.covered { bridge.apply(animated: false) }
    }
}

/// The objects and values the shell's screens read, re-injected inside the work pane's host.
struct WorkPaneEnvironment: ViewModifier {
    let viewModel: AppViewModel
    let selection: AdaptiveSelection
    let mode: LayoutMode
    let typeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    /// `.pane` in two-pane and stacked; `.sheet` when a compact iPad window hosts the whole shell.
    var context: PaneContext = .pane
    /// Each pane is phone-width (band A, §1.27 AD16); a compact window keeps its own band.
    var band: LayoutBand = .a
    /// Half the gap (two-pane), so the pane's wall lines up with the fold (DU9).
    var foldInset: CGFloat = 0
    /// The gutter inside the pane (16 on the Duo and under 440, else 24).
    var gutter: CGFloat = 16
    /// The window's height (two-pane and stacked), so the pane knows where the bar floats.
    var windowHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environmentObject(viewModel)
            .environmentObject(selection)
            .environmentObject(CategoryManager.shared)
            .environmentObject(GoalManager.shared)
            .environmentObject(AppearanceManager.shared)
            .environment(\.paneContext, context)
            .environment(\.layoutMode, mode)
            .environment(\.layoutBand, band)
            .environment(\.paneFoldInset, foldInset)
            .environment(\.paneGutter, gutter)
            .environment(\.paneWindowHeight, windowHeight)
            .environment(\.paneLogRental, context == .pane ? selection.selectedRentalID : nil)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.colorScheme, colorScheme)
    }
}

// MARK: - Log time: a sheet in compact, in the pane in two-pane and stacked (§1.27 create action)

/// `LogTimeSheet` as a `.large` sheet in compact; in a pane, its content in the right pane over the
/// interior wall, above the bar. "Log time" stays the fifth tab in every mode.
struct PaneAwareLogTime<Sheet: View>: ViewModifier {
    @Binding var route: LogSheetRoute?
    let background: Color
    @ViewBuilder let sheet: (LogSheetRoute) -> Sheet

    @Environment(\.paneContext) private var paneContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutMode) private var mode
    @Environment(\.paneFoldInset) private var foldInset
    @Environment(\.paneGutter) private var gutter

    /// How far the interior wall behind Log time reaches below the card: to the bar's top edge
    /// (measured 23–24pt on iPadOS 26.5 and 27.0, iPad Air 13"), so the tab underneath (Records'
    /// list, say) never shows between the card and the bar. The bar itself stays uncovered.
    static var backdropReach: CGFloat { 22 }

    func body(content: Content) -> some View {
        switch paneContext {
        case .sheet:
            content.sheet(item: $route) { route in
                sheet(route)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(background)
            }
        case .pane:
            content
                .overlay {
                    if let current = route {
                        // The pane's own wall behind the card: the tab underneath is covered, not
                        // framed (it showed around a Log time opened over Records).
                        InteriorWall(glowCenter: mode == .stacked ? UnitPoint(x: 0.5, y: 0) : UnitPoint(x: 0, y: 0.38),
                                     foldInset: foldInset, foldAbove: mode == .stacked)
                            .padding(.bottom, PaneMetrics.barClearance - 12 - Self.backdropReach)
                            .ignoresSafeArea(edges: [.top, .horizontal])
                            .contentShape(Rectangle())
                            .transition(.opacity)
                            .accessibilityHidden(true)
                        sheet(current)
                            .background(background)
                            .clipShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                                .strokeBorder(colorScheme == .dark ? AppColors.duoNightCardEdge
                                                                   : AdaptiveColors(colorScheme: colorScheme).pageCardEdge, lineWidth: 1))
                            .padding(.horizontal, gutter)
                            .padding(.top, 8)
                            .padding(.bottom, PaneMetrics.barClearance - 12)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                            .accessibilityIdentifier("pane.logTime")
                    }
                }
                .animation(reduceMotion ? AppAnimation.quick : AppAnimation.flow, value: route?.id)
                // The tab underneath is hidden while the card is up (`PaneHostBridge`).
                .preference(key: PaneCoversTabKey.self, value: route != nil)
        }
    }
}

extension View {
    /// Log time where the mode puts it: a sheet in compact, the right pane otherwise.
    func paneAwareLogTime<Sheet: View>(route: Binding<LogSheetRoute?>, background: Color,
                                       @ViewBuilder sheet: @escaping (LogSheetRoute) -> Sheet) -> some View {
        modifier(PaneAwareLogTime(route: route, background: background, sheet: sheet))
    }
}
