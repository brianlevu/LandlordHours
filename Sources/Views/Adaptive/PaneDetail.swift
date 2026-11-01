import SwiftUI

// MARK: - PaneDetail: a detail opened in the work pane, with a back link (§1.27 "What sits where")
//
// In compact a detail is a sheet; in two-pane and stacked it pushes inside the right pane over the
// interior wall, in the same opaque card the work pane uses, with "‹ To confirm" (the back link) at
// its top. The content keeps its own pinned actions; its `dismiss()` pops back to the list, as it
// closes its sheet on the phone.

struct PaneDetail<Content: View>: View {
    /// The back link's title (the list it returns to).
    let backTitle: String
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutMode) private var mode
    @Environment(\.paneFoldInset) private var foldInset
    @Environment(\.paneGutter) private var gutter
    @Environment(\.dismiss) private var dismiss

    init(backTitle: String, @ViewBuilder content: () -> Content) {
        self.backTitle = backTitle
        self.content = content()
    }

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Label(backTitle, systemImage: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: LHMetrics.minTap)
            }
            .foregroundStyle(colors.action)
            .buttonStyle(LHButton.press)
            .keyboardShortcut(.cancelAction)
            .hoverEffect(.highlight)
            .padding(.horizontal, gutter)
            .accessibilityIdentifier("pane.back")
            content
                .clipShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? AppColors.duoNightCardEdge : colors.pageCardEdge, lineWidth: 1))
                .padding(.horizontal, gutter)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: PaneMetrics.contentCap)
        .frame(maxWidth: .infinity)
        .background {
            InteriorWall(glowCenter: mode == .stacked ? UnitPoint(x: 0.5, y: 0) : UnitPoint(x: 0, y: 0.38),
                         foldInset: foldInset, foldAbove: mode == .stacked)
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("pane.detail")
    }
}
