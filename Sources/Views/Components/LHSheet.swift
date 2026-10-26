import SwiftUI

// MARK: - LHSheet (standard §1.20)
//
// System `.sheet`. Header 56: title (§1.14 sheet style) left, one `.icon` close right. Gutter 20.
// The `.primary` is pinned via `safeAreaInset`, 16 inset; at most one `.tertiary` above it. No hero
// art in task sheets.
//
// Presentation (`.lhSheetPresentation(_:)`):
//   .standard  detents [.medium, .large] when content allows, drag indicator visible.
//   .focused   Log time and the confirm sheet (Brian, 2026-10-23): an opaque `.large` sheet on
//              `backgroundSecondary` with the system's push-back and dim; never glass or material.

struct LHSheet<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    var onClose: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if Footer.self != EmptyView.self {
                // Opaque, so scrolled rows never read through the pinned action (§1.20).
                VStack(spacing: 4) { footer }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                    .background(colors.backgroundSecondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel(String(localized: "sheet.close", defaultValue: "Close", table: "Foundations"))
                    .accessibilityIdentifier("sheet.close")
            }
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
        // Opaque, so scrolled content never reads through the title (§1.20).
        .frame(maxWidth: .infinity)
        .background(colors.backgroundSecondary)
    }
}

extension LHSheet where Footer == EmptyView {
    init(_ title: String, subtitle: String? = nil, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, onClose: onClose, content: content) { EmptyView() }
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
