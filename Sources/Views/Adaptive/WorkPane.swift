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
            CompactPaneHost(content: content.modifier(NoVerticalBar()))
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

/// The one child hosting controller with the compact horizontal size class.
private struct CompactPaneHost<C: View>: UIViewControllerRepresentable {
    let content: C

    func makeUIViewController(context: Context) -> UIHostingController<C> {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.traitOverrides.horizontalSizeClass = .compact
        return host
    }

    func updateUIViewController(_ host: UIHostingController<C>, context: Context) {
        host.rootView = content
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
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, PaneMetrics.barClearance - 12)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                            .accessibilityIdentifier("pane.logTime")
                    }
                }
                .animation(reduceMotion ? AppAnimation.quick : AppAnimation.flow, value: route?.id)
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
