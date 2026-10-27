import SwiftUI
import UIKit

// MARK: - Screen scaffolds (standard "Screen anatomy", S1–S6)
//
// The third layer of the design system: tokens → components → **screen scaffolds**. A screen never
// builds its own title, top inset, title-to-content gap or gutters; it supplies its content and
// calls one scaffold:
//
//   .lhTabScreen(title, subtitle:, back:, accessory:, trailing:)   tab roots and collection roots
//   .lhSheetScreen(title, subtitle:, onClose:)                       task sheets (Log time, pickers)
//
// The scaffold owns: the title style (Fraunces 34/500 everywhere a title is a place name), the title
// position (one baseline on every tab, S2), at most one trailing action (S3), the gap from the
// header to the first content (S4), the 20pt gutter and the section rhythm of a List (S5).
//
// Two header systems implement the same API, so the owner can pick one and every screen follows:
//   .native  Option 1: the system navigation large title, set in Fraunces; trailing and accessory
//            items live in the nav bar row above the title; the title collapses inline on scroll.
//   .custom  Option 2: `LHScreenHeader`, a pinned header row: title, optional subtitle or accessory,
//            one trailing action on the title's row; fixed top inset; it never collapses.
// DEBUG: `-LHHeaderOption native|custom` picks one for captures. Release ships the picked one.

enum LHHeaderSystem: String {
    case native, custom

    static var current: LHHeaderSystem {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHHeaderOption"), args.indices.contains(i + 1),
           let v = LHHeaderSystem(rawValue: args[i + 1]) {
            return v
        }
        #endif
        return .custom
    }

    /// Option 1 sets the large title in Fraunces through the bar's appearance (proposed amendment
    /// to §1.25: the second allowed appearance line). Installed once, before the first bar draws.
    static func installNativeAppearanceIfNeeded() {
        guard current == .native, !didInstall else { return }
        didInstall = true
        let ink = UIColor { trait in
            UIColor(AdaptiveColors(colorScheme: trait.userInterfaceStyle == .dark ? .dark : .light).textPrimary)
        }
        let large = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: LHFont.frauncesUIFont(size: LHScreenAnatomy.titleSize, weight: 500, opticalSize: 34))
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        appearance.titleTextAttributes = [.foregroundColor: ink]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        scrolled.titleTextAttributes = appearance.titleTextAttributes
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
    }

    private static var didInstall = false
}

/// The numbers every scaffold uses (standard "Screen anatomy").
enum LHScreenAnatomy {
    /// One title size for tab roots, collection roots and task sheets.
    static let titleSize: CGFloat = 34
    /// Option 2: the title row's top, under the safe area (tabs) or the grabber (sheets).
    static let headerTopInset: CGFloat = 8
    static let sheetHeaderTopInset: CGFloat = 16
    /// The title row's height: a 44pt trailing action centres on it, so the title never moves.
    static let titleRowHeight: CGFloat = 44
    /// From the last line of the header (title or subtitle) to the first content.
    static let headerToContent: CGFloat = 16
    /// Height a hero screen gives up to the header (title row + accessory row) when it sizes its art
    /// from the window (§H.1 H1 is a share of the height left under the header).
    static let heroHeaderAllowance: CGFloat = 200
}

// MARK: - LHScreenHeader (Option 2, and the sheet header in both options' fallbacks)

struct LHScreenHeader<Accessory: View, Trailing: View>: View {
    enum Placement { case tab, sheet }

    let title: String
    var subtitle: String? = nil
    var placement: Placement = .tab
    var back: (() -> Void)? = nil
    var backLabel: String? = nil
    var backIdentifier: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                if let back {
                    Button(action: back) { Image(systemName: "chevron.backward") }
                        .buttonStyle(LHButton.icon)
                        .frame(maxHeight: ax ? nil : LHScreenAnatomy.titleRowHeight)
                        .padding(.leading, -8)
                        .accessibilityLabel(backLabel ?? String(localized: "title.back", defaultValue: "Back", table: "Foundations"))
                        .accessibilityIdentifier(backIdentifier ?? "screen.back")
                }
                Text(title)
                    .font(LHFont.screenTitle(size: LHScreenAnatomy.titleSize))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(ax ? nil : 1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // S2: an action that grows with Dynamic Type never makes the row taller, so the
                // title's baseline holds at every size below AX.
                trailing
                    .frame(maxHeight: ax ? nil : LHScreenAnatomy.titleRowHeight)
            }
            .frame(minHeight: LHScreenAnatomy.titleRowHeight)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(ax ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            accessory
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, placement == .tab ? LHScreenAnatomy.headerTopInset : LHScreenAnatomy.sheetHeaderTopInset)
        .padding(.bottom, 8 + baselineCompensation)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// S4 is measured from the header's last baseline. A subtitle's line hangs less below its baseline
    /// than the 34pt title's, so the header adds the difference and the content starts at the same
    /// distance under the last baseline whether or not there is a subtitle.
    private var baselineCompensation: CGFloat {
        guard subtitle != nil, Accessory.self == EmptyView.self else { return 0 }
        let title = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: LHFont.frauncesUIFont(size: LHScreenAnatomy.titleSize, weight: 500, opticalSize: 34))
        let sub = UIFont.preferredFont(forTextStyle: .subheadline)
        return max(0, abs(title.descender) - abs(sub.descender))
    }
}

// MARK: - Tab screen

struct LHTabScreenModifier<Accessory: View, Trailing: View>: ViewModifier {
    let title: String
    var subtitle: String?
    var back: (() -> Void)?
    var backLabel: String?
    var backIdentifier: String?
    /// Hero screens (Today) sit on the page gradient: the pinned header stays clear.
    var onPage: Bool
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, subtitle: String?, back: (() -> Void)?, backLabel: String?, backIdentifier: String?, onPage: Bool,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.backLabel = backLabel
        self.backIdentifier = backIdentifier
        self.onPage = onPage
        self.accessory = accessory()
        self.trailing = trailing()
        LHHeaderSystem.installNativeAppearanceIfNeeded()
    }

    func body(content: Content) -> some View {
        switch LHHeaderSystem.current {
        case .native: native(content)
        case .custom: custom(content)
        }
    }

    @ViewBuilder private func native(_ content: Content) -> some View {
        content
            .contentMargins(.top, LHScreenAnatomy.headerToContent, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .modifier(LHNavigationSubtitle(subtitle: subtitle))
            .navigationBarBackButtonHidden(back != nil)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if let back {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: back) { Image(systemName: "chevron.backward") }
                            .accessibilityLabel(backLabel ?? String(localized: "title.back", defaultValue: "Back", table: "Foundations"))
                            .accessibilityIdentifier(backIdentifier ?? "screen.back")
                    }
                }
                if Accessory.self != EmptyView.self {
                    ToolbarItem(placement: .topBarLeading) { accessory }
                }
                if Trailing.self != EmptyView.self {
                    ToolbarItem(placement: .topBarTrailing) { trailing }
                }
            }
    }

    @ViewBuilder private func custom(_ content: Content) -> some View {
        let header = LHScreenHeader(title: title, subtitle: subtitle, placement: .tab, back: back,
                                    backLabel: backLabel, backIdentifier: backIdentifier,
                                    accessory: { accessory }, trailing: { trailing })
        let base = content
            .contentMargins(.top, LHScreenAnatomy.headerToContent - 8, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, 0)
            .toolbar(.hidden, for: .navigationBar)
        if #available(iOS 26, *) {
            base.safeAreaBar(edge: .top, spacing: 0) { header }
        } else {
            base.safeAreaInset(edge: .top, spacing: 0) {
                header.background(onPage ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar))
            }
        }
    }
}

private struct LHNavigationSubtitle: ViewModifier {
    let subtitle: String?
    func body(content: Content) -> some View {
        if let subtitle, #available(iOS 26, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

/// A back action for a pushed collection root. A struct, not a bare closure, so a trailing
/// `{ … }` after `.lhTabScreen(…)` can never bind to it by accident.
struct LHBackAction {
    var label: String? = nil
    var identifier: String? = nil
    let action: () -> Void
}

extension View {
    /// Every tab root and collection root. The screen supplies its scroll container (a `List` or a
    /// `ScrollView`) with no title row, no top padding and no `.toolbar(.hidden…)` of its own.
    func lhTabScreen<Accessory: View, Trailing: View>(
        _ title: String, subtitle: String? = nil, back: LHBackAction? = nil, onPage: Bool = false,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(LHTabScreenModifier(title: title, subtitle: subtitle, back: back?.action, backLabel: back?.label,
                                     backIdentifier: back?.identifier, onPage: onPage,
                                     accessory: accessory, trailing: trailing))
    }
}

// MARK: - Sheet header (task sheets)

/// The one sheet header: the same title face and size as the tabs, close at the trailing edge of the
/// title row. `.native` hosts it in a navigation bar (large title); `.custom` pins `LHScreenHeader`.
struct LHSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)?

    var body: some View {
        LHScreenHeader(title: title, subtitle: subtitle, placement: .sheet, accessory: { EmptyView() }) {
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel(String(localized: "sheet.close", defaultValue: "Close", table: "Foundations"))
                    .accessibilityIdentifier("sheet.close")
            }
        }
    }
}

struct LHSheetScreenModifier: ViewModifier {
    let title: String
    var subtitle: String?
    var onClose: (() -> Void)?
    var background: Color

    init(title: String, subtitle: String?, onClose: (() -> Void)?, background: Color) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.background = background
        LHHeaderSystem.installNativeAppearanceIfNeeded()
    }

    func body(content: Content) -> some View {
        switch LHHeaderSystem.current {
        case .native:
            NavigationStack {
                content
                    .contentMargins(.top, LHScreenAnatomy.headerToContent, for: .scrollContent)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.large)
                    .modifier(LHNavigationSubtitle(subtitle: subtitle))
                    .toolbar {
                        if let onClose {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(action: onClose) { Image(systemName: "xmark") }
                                    .accessibilityLabel(String(localized: "sheet.close", defaultValue: "Close", table: "Foundations"))
                                    .accessibilityIdentifier("sheet.close")
                            }
                        }
                    }
                    .background(background.ignoresSafeArea())
            }
        case .custom:
            content
                .contentMargins(.top, LHScreenAnatomy.headerToContent - 8, for: .scrollContent)
                .safeAreaInset(edge: .top, spacing: 0) {
                    LHSheetHeader(title: title, subtitle: subtitle, onClose: onClose)
                        .background(background)
                }
        }
    }
}

extension View {
    /// Task sheets (Log time, pickers): the screen supplies a scroll container with no header.
    func lhSheetScreen(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil,
                       background: Color) -> some View {
        modifier(LHSheetScreenModifier(title: title, subtitle: subtitle, onClose: onClose, background: background))
    }
}

// MARK: - The one header action (S3)

/// The single action a header may carry (the trailing slot), or the accessory's control. It draws
/// itself per header system: in the system bar (`.native`) it is a plain button and the bar gives
/// it the glass capsule; on the custom title row it is `LHButton.icon` (a symbol) or
/// `LHButton.tertiary` (a short label). Never a "+": the create action is the fifth tab (§1.25).
struct LHHeaderAction: View {
    enum Content { case symbol(String), label(String) }

    let content: Content
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
        let button = Button(action: action) {
            switch content {
            case .symbol(let name): Image(systemName: name)
            case .label(let title): Text(title)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? "")
        switch (LHHeaderSystem.current, content) {
        case (.native, _): button
        case (.custom, .symbol): button.buttonStyle(LHButton.icon)
        case (.custom, .label): button.buttonStyle(LHButton.tertiary)
        }
    }
}
