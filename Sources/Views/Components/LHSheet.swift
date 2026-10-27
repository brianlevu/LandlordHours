import SwiftUI

// MARK: - LHSheet (standard §1.20)
//
// System `.sheet`. Header 56: title (§1.14 sheet style) left, one `.icon` close right. Gutter 20.
// The `.primary` is pinned via `safeAreaInset`, 16 inset, on an opaque bar; at most one `.tertiary`
// above it. No hero art in task sheets.
//
// AX policy (owner ruling 2026-10-27): at accessibility sizes ONLY the primary is pinned (opaque
// footer, 24pt fade above it); secondary and tertiary choices scroll with the body, after the
// content. Use `LHSheet(_:content:primary:secondary:)`. Titles wrap, never truncate, at AX.
//
// Presentation (`.lhSheetPresentation(_:)`):
//   .standard  detents [.medium, .large] when content allows, drag indicator visible.
//   .focused   Log time and the confirm sheet (Brian, 2026-10-23): an opaque `.large` sheet on
//              `backgroundSecondary` with the system's push-back and dim; never glass or material.

struct LHSheet<Content: View, Footer: View, Secondary: View>: View {
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)? = nil
    @ViewBuilder var content: Content
    /// The primary action: always pinned, on an opaque bar.
    @ViewBuilder var footer: Footer
    /// Secondary and tertiary choices. Pinned above the primary below AX; at AX they scroll with the
    /// body, after the content (owner ruling 2026-10-27: at AX only the primary stays pinned).
    @ViewBuilder var secondary: Secondary

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var hasPrimary: Bool { Footer.self != EmptyView.self }
    private var hasSecondary: Bool { Secondary.self != EmptyView.self }

    /// The pinned bar's fade at AX: content dissolves into the opaque footer over this height.
    static var footerFadeHeight: CGFloat { 24 }

    /// `footer` holds every action and is pinned whole (no secondary slot). Prefer the
    /// `primary:`/`secondary:` form, which applies the AX policy.
    init(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer,
         @ViewBuilder secondary: () -> Secondary) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
        self.secondary = secondary()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // At AX the wrapped title can fill half the screen, so it scrolls with the body and
                // only the close button stays pinned (below).
                if ax { titleBlock }
                content
                if ax && hasSecondary {
                    VStack(spacing: 8) { secondary }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { if ax { axCloseBar } else { header } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasPrimary || (hasSecondary && !ax) {
                // Opaque, so scrolled rows never read through the pinned action (§1.20).
                VStack(spacing: 4) {
                    if !ax { secondary }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(colors.backgroundSecondary)
                .overlay(alignment: .top) {
                    if ax {
                        LinearGradient(colors: [colors.backgroundSecondary.opacity(0), colors.backgroundSecondary],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.footerFadeHeight)
                            .offset(y: -Self.footerFadeHeight)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            // A sheet title wraps to the lines it needs; it is never cut (§1.14, owner ruling 2026-10-27).
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(ax ? nil : 2)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(ax ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var closeButton: some View {
        if let onClose {
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel(String(localized: "sheet.close", defaultValue: "Close", table: "Foundations"))
                .accessibilityIdentifier("sheet.close")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            titleBlock
            closeButton
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
        // Opaque, so scrolled content never reads through the title (§1.20).
        .frame(maxWidth: .infinity)
        .background(colors.backgroundSecondary)
    }

    /// AX: a slim opaque bar holding only the close button; the title scrolls with the body.
    @ViewBuilder private var axCloseBar: some View {
        if onClose != nil {
            HStack { Spacer(minLength: 0); closeButton }
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .background(colors.backgroundSecondary)
        }
    }
}

extension LHSheet where Secondary == EmptyView {
    /// Every action in `footer`, pinned whole at every size (use `primary:`/`secondary:` for the AX policy).
    init(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(title, subtitle: subtitle, onClose: onClose, content: content, footer: footer) { EmptyView() }
    }
}

extension LHSheet where Footer == EmptyView, Secondary == EmptyView {
    init(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, onClose: onClose, content: content) { EmptyView() }
    }
}

extension LHSheet {
    /// The AX-aware form: `primary` is pinned at every size; `secondary` (the secondary and tertiary
    /// choices) pins above it below AX and scrolls with the body at AX.
    init(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder primary: () -> Footer,
         @ViewBuilder secondary: () -> Secondary) {
        self.init(title, subtitle: subtitle, onClose: onClose, content: content, footer: primary, secondary: secondary)
    }
}

enum LHSheetPresentation: Equatable {
    case standard
    case focused
}

private struct LHSheetPresentationModifier: ViewModifier {
    let kind: LHSheetPresentation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        switch kind {
        case .standard:
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AdaptiveColors(colorScheme: colorScheme).backgroundSecondary)
        case .focused:
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AdaptiveColors(colorScheme: colorScheme).backgroundSecondary)
        }
    }
}

extension View {
    /// Applies the §1.20 sheet presentation to a sheet's root view.
    func lhSheetPresentation(_ kind: LHSheetPresentation = .standard) -> some View {
        modifier(LHSheetPresentationModifier(kind: kind))
    }
}
