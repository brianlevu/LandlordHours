import SwiftUI

// MARK: - The trial-start moment (2.3, frame p2)
//
// Shown in place of the paywall once Apple's free trial starts. The house's windows light once
// (`windowsOn`, played by `CraftHouseView` when `windowsLit` turns true; linear under Reduce
// Motion) with one `.success` haptic. The words give the real dates: open until the renewal, the
// reminder two days before, then the yearly price unless the person cancels.

struct TrialStartView: View {
    let renewal: Date
    let price: String?
    var onAddRentals: () -> Void
    var onMakePDF: () -> Void
    var onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lit = false
    @State private var played = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static func body(renewal: Date, price: String?) -> String {
        let end = PricingFormat.short(renewal)
        let remind = PricingFormat.short(TrialSchedule.reminderDate(renewal: renewal))
        if let price {
            return String(localized: "trialStart.body",
                          defaultValue: "Everything in Pro is open until \(end). We’ll remind you on \(remind). Then \(price) a year unless you cancel.",
                          table: "Pricing")
        }
        return String(localized: "trialStart.bodyNoPrice",
                      defaultValue: "Everything in Pro is open until \(end). We’ll remind you on \(remind). Then it renews each year unless you cancel.",
                      table: "Pricing")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CraftHouseView(stage: .half, windowsLit: lit, side: typeSize.isAccessibilitySize ? 160 : 248, fillsStage: false)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                    .padding(.top, 8)
                Text(String(localized: "trialStart.title", defaultValue: "Your trial is on.", table: "Pricing"))
                    .font(LHFont.screenTitle(size: 34))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("trial.title")
                Text(Self.body(renewal: renewal, price: price))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("paywall.success")

                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    Text(String(localized: "trialStart.tryFirst", defaultValue: "Try these first", table: "Pricing"))
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    LHRowGroup(onPage: true) {
                        LHRow.Browse(title: String(localized: "trialStart.rentals.title", defaultValue: "Add your other rentals", table: "Pricing"),
                                     meta: String(localized: "trialStart.rentals.meta", defaultValue: "Each gets its own care plan", table: "Pricing"),
                                     systemImage: "house", action: onAddRentals)
                            .accessibilityIdentifier("trial.addRentals")
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        LHRow.Browse(title: String(localized: "trialStart.pdf.title", defaultValue: "Make your first PDF", table: "Pricing"),
                                     meta: String(localized: "trialStart.pdf.meta", defaultValue: "The record your CPA gets", table: "Pricing"),
                                     systemImage: "doc.text", action: onMakePDF)
                            .accessibilityIdentifier("trial.makePDF")
                    }
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: LHMetrics.readingColumn)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(String(localized: "trialStart.done", defaultValue: "Done", table: "Pricing"), action: onDone)
                .buttonStyle(LHButton.primary)
                .frame(maxWidth: LHMetrics.readingColumn)
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background { LHFootFade(color: colors.pageBottom) }
                .accessibilityIdentifier("paywall.continue")
        }
        .background { LHPage() }
        .sensoryFeedback(.success, trigger: lit) { _, new in new }
        .task {
            // Once per presentation: the windows light after the page settles.
            guard !played else { return }
            played = true
            try? await Task.sleep(for: .milliseconds(350))
            lit = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trial.start")
    }
}
