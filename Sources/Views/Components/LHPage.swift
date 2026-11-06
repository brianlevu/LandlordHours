import SwiftUI

// MARK: - LHPage: the dusk / night page (standard §H.4)
//
// The page under a hero is a vertical gradient, never flat, never a drawn grid:
//   pageTop at 0 · pageMid at 0.32 (behind the hero) · pageBottom at 1.0
//   light (dusk) #EAE3D7 → #D8CFC0 → #E8E0D3 · dark (night) #0B1230 → #0B1230 → #080C1D
// Only on the hero screens: Today, the rental page, Welcome, the Inbox empty state, the milestone.
// Every other screen keeps the plain `background` canvas (`LHCanvas`).
//
// Inks on the light page: only textPrimary, textSecondary, action, behind and positiveOnPage clear
// 4.5:1 there; every other intent ink appears only inside a card on the page.

struct LHPage: View {
    @Environment(\.colorScheme) private var colorScheme

    static let midLocation: CGFloat = 0.32

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LinearGradient(stops: [.init(color: colors.pageTop, location: 0),
                               .init(color: colors.pageMid, location: Self.midLocation),
                               .init(color: colors.pageBottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The plain canvas for lists and forms (`#EEF2FA` / `#0B1230`).
struct LHCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AdaptiveColors(colorScheme: colorScheme).background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The rental `Menu` chip on the page (§H.8): capsule 36, `.subheadline.semibold` ink and a
/// `chevron.down`, white 0.65 fill with a #C9BFA8 0.8 hairline (night: white 0.08 / 0.14). The
/// toast replaces it while a top toast shows (`LHToastChipSlot`, package 0).
struct LHHeroChip: View {
    let title: String
    var showsChevron = true

    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, showsChevron: Bool = true) {
        self.title = title
        self.showsChevron = showsChevron
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(colors.heroChipFill, in: Capsule())
        .overlay(Capsule().strokeBorder(colors.heroChipHairline, lineWidth: 0.5))
        .frame(minHeight: LHMetrics.minTap)
        .contentShape(Capsule())
    }
}

/// Page dots under the house (§H.8): 6pt, 7 gap; the current dot `textPrimary`, the rest `heroDot`
/// at 0.5. Shown only with more than one rental.
struct LHPageDots: View {
    let count: Int
    let current: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 7) {
            ForEach(0..<max(count, 0), id: \.self) { i in
                Circle()
                    .fill(i == current ? colors.textPrimary : colors.heroDot.opacity(0.5))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(AppAnimation.quick, value: current)
        .accessibilityHidden(true)
    }
}
