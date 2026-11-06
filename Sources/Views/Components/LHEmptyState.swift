import SwiftUI

// MARK: - LHEmptyState (standard §1.18)
//
// In a container: SF Symbol 28 in `positive` / `action` → `.headline` → `.subheadline`
// `textSecondary` ≤ 2 lines → optional `.secondary`. Padding 20, total ≤ 160. Motion
// `emptyStateEntrance`: glyph, headline and body fade and rise 8pt, 40 ms apart (≤ 0.30 s; fade only
// under Reduce Motion), bound to the empty state replacing the list.
//
// Full screen (the Inbox with nothing, §H.5): `LHEmptyState.Page`, the diorama of the first rental
// (unlit when nothing was logged today) on the dusk/night page, frame ≤ 240pt and ≤ 28% of the
// viewport, one headline, one line, one `.primary`.

struct LHEmptyState: View {
    enum Tone: Equatable { case positive, action }

    let systemImage: String
    var tone: Tone = .positive
    let headline: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var shown = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var glyph: CGFloat = 28
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(systemImage: String, tone: Tone = .positive, headline: String, message: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.tone = tone
        self.headline = headline
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(.title))
                .imageScale(.medium)
                .frame(height: glyph)
                .foregroundStyle(tone == .positive ? colors.positive : colors.action)
                .modifier(Entrance(shown: shown, index: 0, reduceMotion: reduceMotion))
                .accessibilityHidden(true)
            Text(headline)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
                .modifier(Entrance(shown: shown, index: 1, reduceMotion: reduceMotion))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .modifier(Entrance(shown: shown, index: 2, reduceMotion: reduceMotion))
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(LHButton.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .accessibilityElement(children: .contain)
        // emptyStateEntrance: bound to the state that shows it (one of the two allowed appear motions).
        .onAppear { shown = true }
    }

    struct Entrance: ViewModifier {
        let shown: Bool
        let index: Int
        let reduceMotion: Bool
        func body(content: Content) -> some View {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 8)
                .animation(AppAnimation.reveal.delay(Double(index) * 0.04), value: shown)
        }
    }
}

extension LHEmptyState {
    /// The full-screen empty state on the page: the diorama ≤ 240pt (≤ 28% of the viewport), one
    /// headline, one line, one `.primary`.
    struct Page: View {
        let stage: CraftStage
        let windowsLit: Bool
        let headline: String
        let message: String
        let actionTitle: String
        let action: () -> Void

        @State private var height: CGFloat = 0
        @Environment(\.colorScheme) private var colorScheme
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

        static func side(viewportHeight: CGFloat) -> CGFloat {
            guard viewportHeight > 0 else { return CraftHeroSize.minimumDioramaSide }
            return max(CraftHeroSize.minimumDioramaSide, min(240, (0.28 * viewportHeight).rounded(.down)))
        }

        var body: some View {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                CraftHouseView(stage: stage, windowsLit: windowsLit, side: Self.side(viewportHeight: height))
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .lhColumnGutter()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Button(actionTitle, action: action)
                    .buttonStyle(LHButton.primary)
                    .lhColumnGutter()
                    .padding(.bottom, 16)
            }
            .background { LHPage() }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
    }
}
