import SwiftUI

// MARK: - LHTimeline (standard §1.28, 2.3 amendment 4)
//
// A vertical timeline: 32pt nodes joined by a 2pt line. A reached node is `action` with `onAction`
// ink and a `action` line below it; a later node is the `actionSurface` wash with `action` ink and a
// `border` line. Title `.headline` `textPrimary`, text `.subheadline` `textSecondary`. Used by the
// paywall's trial timeline (Today → reminder → renewal); reusable for year-end steps.
// Each step reads as one VoiceOver element ("Today. Full access to every rental.").

struct LHTimelineStep: Identifiable, Equatable {
    let id: Int
    let symbol: String
    let title: String
    let text: String
    var reached = false
}

struct LHTimeline: View {
    let steps: [LHTimelineStep]
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var node: CGFloat = 32

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Image(systemName: step.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(step.reached ? colors.onAction : colors.action)
                            .frame(width: node, height: node)
                            .background(step.reached ? colors.action : colors.actionSurface, in: Circle())
                            .accessibilityHidden(true)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.reached ? colors.action : colors.border)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 4)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: node)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        Text(step.text)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.top, 5)
                    .padding(.bottom, index < steps.count - 1 ? 18 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
