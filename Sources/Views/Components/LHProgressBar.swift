import SwiftUI

// MARK: - LHProgressBar and LHSegmentedProgress (standard §1.24a, 2.3 amendment 5)
//
// 4pt in cards and sheets: `actionSurface` track, `action` fill, capsule ends. `LHProgressBar` is a
// continuous share (the Learning center card, "1 of 6"); `LHSegmentedProgress` is one capsule per
// step with 6pt gaps (the lesson sheet, "card 2 of 3"), the reached ones filled. Onboarding keeps
// its 3pt bar (§1.24). Decorative: the screen states the count in text, so both are hidden from
// VoiceOver unless given a label. Changes animate with `standard`, bound to the value.

struct LHProgressBar: View {
    static let height: CGFloat = 4
    /// 0…1; non-finite and out-of-range values clamp.
    let value: Double
    var accessibilityText: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var clamped: Double { value.isFinite ? min(1, max(0, value)) : 0 }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.actionSurface)
                if clamped > 0 {
                    Capsule().fill(colors.action)
                        .frame(width: max(Self.height, proxy.size.width * clamped))
                }
            }
        }
        .frame(height: Self.height)
        .animation(AppAnimation.standard, value: clamped)
        .modifier(ProgressAccessibility(text: accessibilityText))
    }
}

struct LHSegmentedProgress: View {
    let count: Int
    /// Index of the current step (0-based); steps up to and including it are filled.
    let current: Int
    var accessibilityText: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 6) {
            ForEach(0..<max(0, count), id: \.self) { index in
                Capsule()
                    .fill(index <= current ? colors.action : colors.actionSurface)
                    .frame(height: LHProgressBar.height)
            }
        }
        .animation(AppAnimation.standard, value: current)
        .modifier(ProgressAccessibility(text: accessibilityText))
    }
}

private struct ProgressAccessibility: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text {
            content.accessibilityElement(children: .ignore).accessibilityLabel(text)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
