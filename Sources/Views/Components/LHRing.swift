import SwiftUI

// MARK: - LHRing and LHBarRow (standard §1.12)
//
// Ring (Reports): 18pt stroke, 260pt, track `actionSurface`, fill `action`; pace states use
// `positive` / `caution`; no gradients outside the hero. Bars: 8pt, radius 4, label `.subheadline`
// left, value tabular right. Animate on value change only (`ringProgress`), never on appear.
// `accessibilityValue` carries the number and the target ("206 of 750 hours").

struct LHRing<Center: View>: View {
    enum Tone: Equatable { case action, positive, caution }

    /// 0…1 (clamped).
    let progress: Double
    var tone: Tone = .action
    var diameter: CGFloat = 260
    var lineWidth: CGFloat = 18
    var accessibilityValue: String
    @ViewBuilder var center: Center

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(progress: Double, tone: Tone = .action, diameter: CGFloat = 260, lineWidth: CGFloat = 18,
         accessibilityValue: String, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.tone = tone
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.accessibilityValue = accessibilityValue
        self.center = center()
    }

    static func clamped(_ progress: Double) -> Double { progress.isFinite ? min(max(progress, 0), 1) : 0 }

    private var fill: Color {
        switch tone {
        case .action: return colors.action
        case .positive: return colors.positive
        case .caution: return colors.caution
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(colors.actionSurface, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Self.clamped(progress))
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.ringProgress, value: progress)
            center
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(accessibilityValue)
    }
}

struct LHBarRow: View {
    let label: String
    let value: String
    /// 0…1 of the widest bar in the set.
    let fraction: Double

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline).foregroundStyle(colors.textPrimary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.actionSurface)
                    Capsule()
                        .fill(colors.chartBarFill)
                        .frame(width: proxy.size.width * LHRing<EmptyView>.clamped(fraction))
                        .animation(AppAnimation.ringProgress, value: fraction)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension AdaptiveColors {
    var chartBarFill: Color { action }
}
