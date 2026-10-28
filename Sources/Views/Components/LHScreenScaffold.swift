import SwiftUI
import UIKit

// MARK: - Screen scaffolds (standard §S "Screen anatomy")
//
// The third layer of the design system: tokens → components → **screen scaffolds**. A screen never
// builds its own title, top inset, title-to-content gap or gutters; it supplies its scroll container
// (a `List` or a `ScrollView`) and calls one scaffold:
//
//   .lhTabScreen(title, subtitle:, back:, onPage:, accessory:, trailing:)  tab roots, collection roots
//   .lhDetailScreen(title, subtitle:, back:, trailing:)                    a pushed screen about one item
//   .lhSheetScreen(title, subtitle:, onClose:, background:)                task sheets; `LHSheet` too
//
// Tabs and details (Things-style, owner's pick 2026-10-27): the header sits at rest on one baseline
// and scrolls away with the content; once the title has left, a compact bar with the title in
// `.headline` (and the back and trailing actions) fades in over a material. At rest the layout is
// identical on every tab: S2 (one baseline) and S3 (one gap under the last header baseline).
// Sheets: the header is pinned (the task owns the sheet), title Fraunces 28.

/// The numbers every scaffold uses (standard §S).
enum LHScreenAnatomy {
    /// Tab roots and collection roots.
    static let titleSize: CGFloat = 34
    /// Task sheets (Fraunces' floor is 28).
    static let sheetTitleSize: CGFloat = 28
    /// The title row's top, under the safe area (tabs, details) or the grabber (sheets).
    static let headerTopInset: CGFloat = 8
    static let sheetHeaderTopInset: CGFloat = 16
    /// The title row's height: a 44pt action centres on it, so the title never moves.
    static let titleRowHeight: CGFloat = 44
    /// From the header's bottom padding edge to the first content (the scroll content's top margin).
    static let headerToContent: CGFloat = 16
    /// Height a hero screen gives up to the header (title row + accessory row) when it sizes its art
    /// from the window (§H.1 H1 is a share of the height left under the header).
    static let heroHeaderAllowance: CGFloat = 200
    /// The compact bar shows once the content has scrolled this far (the title row has left).
    static var compactThreshold: CGFloat { headerTopInset + titleRowHeight - 8 }
}

/// A back action for a pushed screen. A struct, not a bare closure, so a trailing `{ … }` after
/// `.lhTabScreen(…)` can never bind to it by accident.
struct LHBackAction {
    var label: String? = nil
    var identifier: String? = nil
    let action: () -> Void
}

// MARK: - The header

enum LHHeaderStyle: Equatable {
    /// Tab roots and collection roots: Fraunces 34/500.
    case collection
    /// A pushed screen about one item: SF `.title1.semibold` (§1.14).
    case detail
    /// Task sheets: Fraunces 28/500.
    case sheet

    var font: Font {
        switch self {
        case .collection: return LHFont.screenTitle(size: LHScreenAnatomy.titleSize)
        case .detail: return .title.weight(.semibold)
        case .sheet: return LHFont.screenTitle(size: LHScreenAnatomy.sheetTitleSize)
        }
    }

    /// The title's UIFont, for the baseline compensation (S3 is measured from the last baseline).
    var uiFont: UIFont {
        switch self {
        case .collection, .sheet:
            let size = self == .sheet ? LHScreenAnatomy.sheetTitleSize : LHScreenAnatomy.titleSize
            return UIFontMetrics(forTextStyle: .largeTitle)
                .scaledFont(for: LHFont.frauncesUIFont(size: size, weight: 500, opticalSize: size))
        case .detail:
            return UIFont.preferredFont(forTextStyle: .title1)
        }
    }
}

/// What kind of trailing action the header holds: a label action moves under the title at AX sizes
/// (a symbol stays on the title row).
private struct LHHeaderActionKindKey: PreferenceKey {
    static let defaultValue: LHHeaderAction.Kind? = nil
    static func reduce(value: inout LHHeaderAction.Kind?, nextValue: () -> LHHeaderAction.Kind?) {
        value = value ?? nextValue()
    }
}

struct LHScreenHeader<Accessory: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var style: LHHeaderStyle = .collection
    var back: LHBackAction? = nil
    /// A sheet about one item may lead its title row with its ornament (the confirm sheet's 56pt
    /// tool render, §H.5). Never on tabs.
    var leading: AnyView? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var trailingKind: LHHeaderAction.Kind?
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    /// At AX sizes a label action ("Add rental") takes its own row under the title.
    private var trailingBelow: Bool { ax && trailingKind == .label }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                if let back {
                    LHHeaderBackButton(back: back)
                        .frame(maxHeight: ax ? nil : LHScreenAnatomy.titleRowHeight)
                        .padding(.leading, -8)
                }
                if let leading { leading }
                Text(title)
                    .font(style.font)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(ax ? nil : (style == .detail ? 2 : 1))
                    .minimumScaleFactor(style == .detail ? 1 : 0.6)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !trailingBelow {
                    // S5: an action that grows with Dynamic Type never makes the row taller, so the
                    // title's baseline holds at every size below AX.
                    trailing
                        .frame(maxHeight: ax ? nil : LHScreenAnatomy.titleRowHeight)
                }
            }
            .frame(minHeight: LHScreenAnatomy.titleRowHeight)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    // One line at default; it wraps from xLarge so it is never cut (owner ruling 2026-10-27).
                    .lineLimit(typeSize >= .xLarge ? nil : 1)
                    .lhWrapsText()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            accessory
                .frame(maxWidth: .infinity, alignment: .leading)
            if trailingBelow {
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onPreferenceChange(LHHeaderActionKindKey.self) { trailingKind = $0 }
        // A container, so a screen-level `.accessibilityIdentifier("….screen")` names the header, not
        // every control in it (the back and trailing actions keep their own identifiers).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.header")
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, style == .sheet ? LHScreenAnatomy.sheetHeaderTopInset : LHScreenAnatomy.headerTopInset)
        .padding(.bottom, 8 + baselineCompensation)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// S3 is measured from the header's last baseline. A subtitle's line hangs less below its baseline
    /// than the title's, so the header adds the difference: the content starts the same distance under
    /// the last baseline whether or not there is a subtitle.
    private var baselineCompensation: CGFloat {
        guard subtitle != nil, Accessory.self == EmptyView.self, !trailingBelow else { return 0 }
        let sub = UIFont.preferredFont(forTextStyle: .subheadline)
        return max(0, abs(style.uiFont.descender) - abs(sub.descender))
    }
}

struct LHHeaderBackButton: View {
    let back: LHBackAction

    var body: some View {
        Button(action: back.action) { Image(systemName: "chevron.backward") }
            .buttonStyle(LHButton.icon)
            .accessibilityLabel(back.label ?? String(localized: "title.back", defaultValue: "Back", table: "Foundations"))
            .accessibilityIdentifier(back.identifier ?? "screen.back")
    }
}

// MARK: - Tab and detail screens (scroll-away header + compact bar)

struct LHScrollingScreenModifier<Accessory: View, Trailing: View>: ViewModifier {
    let title: String
    var subtitle: String?
    var style: LHHeaderStyle
    var back: LHBackAction?
    /// Hero screens (Today) sit on the page gradient.
    var onPage: Bool
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var trailing: Trailing

    @State private var scrolled: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var compact: Bool { scrolled > LHScreenAnatomy.compactThreshold }

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, LHScreenAnatomy.headerToContent - 8, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .toolbar(.hidden, for: .navigationBar)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in
                scrolled = value
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // The header moves with the content (it is in the safe-area inset, the content scrolls
                // under it), so it reads as part of the page and leaves with it.
                LHScreenHeader(title: title, subtitle: subtitle, style: style, back: back,
                               accessory: { accessory }, trailing: { trailing })
                    .offset(y: -max(0, scrolled))
                    .opacity(compact ? 0 : 1)
                    .allowsHitTesting(!compact)
                    .accessibilityHidden(compact)
            }
            .overlay(alignment: .top) {
                if compact {
                    compactBar
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : AppAnimation.quick, value: compact)
    }

    /// The compact bar: back, the title in `.headline`, the trailing action, on the bar material
    /// (glass on iOS 26+), with a hairline under it.
    private var compactBar: some View {
        HStack(spacing: 8) {
            if let back { LHHeaderBackButton(back: back) } else { Color.clear.frame(width: LHMetrics.minTap, height: 1) }
            Text(title)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.compactTitle")
            ZStack { Color.clear.frame(width: LHMetrics.minTap, height: 1); trailing }
                .frame(maxHeight: LHScreenAnatomy.titleRowHeight)
        }
        .padding(.horizontal, LHMetrics.gutter - 8)
        .frame(height: LHScreenAnatomy.titleRowHeight)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle().fill(.bar)
                .overlay(alignment: .bottom) { colors.border.frame(height: LHMetrics.hairline) }
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Every tab root and collection root. The screen supplies its scroll container (a `List` or a
    /// `ScrollView`) with no title row, no top padding and no `.toolbar(.hidden…)` of its own.
    func lhTabScreen<Accessory: View, Trailing: View>(
        _ title: String, subtitle: String? = nil, back: LHBackAction? = nil, onPage: Bool = false,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(LHScrollingScreenModifier(title: title, subtitle: subtitle, style: .collection, back: back,
                                           onPage: onPage, accessory: accessory, trailing: trailing))
    }

    /// A pushed screen about one item (a rental, a record): the same rhythm, SF `.title1.semibold`.
    func lhDetailScreen<Accessory: View, Trailing: View>(
        _ title: String, subtitle: String? = nil, back: LHBackAction? = nil, onPage: Bool = false,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(LHScrollingScreenModifier(title: title, subtitle: subtitle, style: .detail, back: back,
                                           onPage: onPage, accessory: accessory, trailing: trailing))
    }
}

// MARK: - Sheets

/// The one sheet header: Fraunces 28, close at the trailing edge of the title row.
struct LHSheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var style: LHHeaderStyle = .sheet
    var leading: AnyView? = nil
    var onClose: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        LHScreenHeader(title: title, subtitle: subtitle, style: style, leading: leading, accessory: { EmptyView() }) {
            HStack(spacing: 8) {
                trailing
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(LHButton.icon)
                        .accessibilityLabel(String(localized: "sheet.close", defaultValue: "Close", table: "Foundations"))
                        .accessibilityIdentifier("sheet.close")
                }
            }
        }
    }
}

extension LHSheetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, style: LHHeaderStyle = .sheet, leading: AnyView? = nil,
         onClose: (() -> Void)?) {
        self.init(title: title, subtitle: subtitle, style: style, leading: leading, onClose: onClose, trailing: { EmptyView() })
    }
}

struct LHSheetScreenModifier: ViewModifier {
    let title: String
    var subtitle: String?
    var style: LHHeaderStyle
    var leading: AnyView?
    var onClose: (() -> Void)?
    var background: Color

    @State private var scrolled: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let ax = typeSize.isAccessibilitySize
        content
            .contentMargins(.top, LHScreenAnatomy.headerToContent - 8, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in
                scrolled = value
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // Pinned and opaque below AX: scrolled rows never read through the title (§1.20). At AX
                // the wrapped title would hold half the sheet, so it leaves with the content (§1.20 AX).
                LHSheetHeader(title: title, subtitle: subtitle, style: style, leading: leading, onClose: onClose)
                    .background(background)
                    .offset(y: ax ? -max(0, scrolled) : 0)
            }
    }
}

extension View {
    /// Sheets: the screen supplies a scroll container with no header. `style` is `.sheet` (Fraunces 28)
    /// for a task sheet (Log time, pickers) and `.detail` (SF `.title1.semibold`) for a sheet about one
    /// item (the confirm sheet, whose `leading` is its 56pt tool render).
    func lhSheetScreen(_ title: String, subtitle: String? = nil, style: LHHeaderStyle = .sheet,
                       leading: AnyView? = nil, onClose: (() -> Void)? = nil, background: Color) -> some View {
        modifier(LHSheetScreenModifier(title: title, subtitle: subtitle, style: style, leading: leading,
                                       onClose: onClose, background: background))
    }
}

// MARK: - The one header action (S5)

/// The single action a header may carry: `LHButton.icon` for a symbol, `LHButton.tertiary` for a
/// short label. A label action moves under the title at AX sizes. Never a "+": the create action is
/// the fifth tab (§1.25).
struct LHHeaderAction: View {
    enum Kind: Equatable { case symbol, label }
    private enum Content { case symbol(String), label(String) }

    private let content: Content
    let accessibilityLabel: String
    var identifier: String? = nil
    let action: () -> Void

    init(symbol: String, label: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.content = .symbol(symbol)
        self.accessibilityLabel = label
        self.identifier = identifier
        self.action = action
    }

    init(title: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.content = .label(title)
        self.accessibilityLabel = title
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        switch content {
        case .symbol(let name):
            Button(action: action) { Image(systemName: name) }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier ?? "")
                .preference(key: LHHeaderActionKindKey.self, value: .symbol)
        case .label(let title):
            Button(title, action: action)
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier(identifier ?? "")
                .preference(key: LHHeaderActionKindKey.self, value: .label)
        }
    }
}

