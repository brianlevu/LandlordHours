import SwiftUI

#if DEBUG
// MARK: - 2.3 foundation component gallery (DEBUG capture boards, compiled out of Release)
//
//   -LHSurfaceBoard components23-a|components23-b -LHColorScheme light|dark [-LHTypeSize xxl]
//
// The new LH* components from the approved 2.3 hi-fi designs (~/AgentScratch/landlordhours/
// 2026-11-02/2.3-hifi), each in the context of the frame it must match:
//   a: LHTimeline (p1 paywall), LHRow.DoneTile in browse rows (c2 care plan), LHFootFade (p1 foot).
//   b: LHProgressBar (l5 Learning center card), LHSegmentedProgress (l2 lesson sheet header),
//      LHCardLines (l2 "Usually counts / Usually doesn't").
// Sample text only; the price is a sample of StoreKit's displayPrice, never app copy.

enum Components23Sample {
    static let displayPrice = "$49.99"
    static let now = Date(timeIntervalSince1970: 1_793_000_000)
}

struct Components23BoardA: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var steps: [LHTimelineStep] {
        let s = TrialSchedule.preview(from: Components23Sample.now)
        func short(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
        return [
            LHTimelineStep(id: 0, symbol: "lock.open", title: "Today",
                           text: "Pro is on: every rental, your PDF, care plans and lessons.", reached: true),
            LHTimelineStep(id: 1, symbol: "bell", title: "In 12 days · \(short(s.reminder))",
                           text: "We remind you that the trial ends in 2 days."),
            LHTimelineStep(id: 2, symbol: "calendar", title: "In 14 days · \(short(s.renewal))",
                           text: "Pro renews at \(Components23Sample.displayPrice) a year. Cancel at least a day before and you pay nothing."),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("How your trial works")
                    .font(LHFont.screenTitle(size: 28))
                    .foregroundStyle(colors.textPrimary)
                    .padding(.top, 16)
                LHTimeline(steps: steps)
                    .padding(.top, 20)
                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    LHSectionHeader("Fall")
                        .padding(.horizontal, 4)
                    LHRowGroup(onPage: true) {
                        LHRow.Browse(title: "Clear the gutters", meta: "Logged 1h · Oct 4", action: {}) { LHRow.DoneTile() }
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        LHRow.Browse(title: "Service the furnace", meta: "Before the first frost", action: {}) {
                            LHRowGlyph(systemImage: "flame", tint: .informational)
                        }
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        LHRow.Browse(title: "What counts toward the 750", meta: "Read", action: {}) { LHRow.DoneTile() }
                    }
                }
                .padding(.top, LHMetrics.sectionGap)
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button("Start free trial") {}
                    .buttonStyle(LHButton.primary)
                Text("Cancel any time in Settings, at least a day before it renews.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background { LHFootFade(color: colors.pageBottom) }
        }
        .background { LHPage() }
        .accessibilityIdentifier("components23.a")
    }
}

struct Components23BoardB: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                // l5: the Learning center progress card.
                VStack(alignment: .leading, spacing: 2) {
                    Text("1 of 6")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                    Text("lessons read · about 2 minutes each")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                    LHProgressBar(value: 1.0 / 6.0)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LHMetrics.cardPadding)
                .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))

                // l2: the lesson sheet header and the first card's lists.
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What counts toward the 750")
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        Text("Card 1 of 3")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                    }
                    LHSegmentedProgress(count: 3, current: 0)
                }
                VStack(alignment: .leading, spacing: 16) {
                    list("Usually counts", [
                        LHCardLine(id: 0, symbol: "checkmark", tint: .positive, text: "Repairs and upkeep you do"),
                        LHCardLine(id: 1, symbol: "checkmark", tint: .positive, text: "Showings, leases and tenant calls"),
                        LHCardLine(id: 2, symbol: "checkmark", tint: .positive, text: "Hiring and managing contractors"),
                    ])
                    list("Usually doesn’t", [
                        LHCardLine(id: 0, symbol: "xmark", text: "Reading statements as an investor"),
                        LHCardLine(id: 1, symbol: "xmark", text: "Learning about real estate in general"),
                        LHCardLine(id: 2, symbol: "xmark", text: "Hours a manager puts in for you"),
                    ])
                }
                LHFootnote(String(localized: "learn.notAdvice"))
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .accessibilityIdentifier("components23.b")
    }

    private func list(_ title: String, _ lines: [LHCardLine]) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            Text(title)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, 4)
            LHCardLines(lines: lines)
        }
    }
}
#endif
