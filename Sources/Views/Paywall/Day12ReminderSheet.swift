import SwiftUI
import StoreKit

// MARK: - The day-12 reminder (2.3, frame p3)
//
// Two days before a trial renews, once per trial and only while it will renew
// (`EntitlementStore.shouldShowDay12Reminder()`). The primary is "Keep Pro" (it closes the sheet
// and marks it shown); "Cancel in Settings" opens Apple's Manage subscriptions sheet. The billed
// amount is StoreKit's price and the largest price text; the renewal terms are spelled out.
// Not a nudge: it ignores the nudge switches.

struct Day12ReminderSheet: View {
    let renewal: Date
    let price: String?
    let freeRentalName: String?
    /// Called once the person answered (Keep Pro, close or swipe): mark it shown.
    var onAnswered: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showManage = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var daysLeft: Int {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: PaywallClock.now()),
                                                   to: Calendar.current.startOfDay(for: renewal)).day ?? TrialSchedule.reminderLeadDays
        return max(1, days)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let price {
                    PaywallPriceRow(display: PriceDisplay(billed: price, trialDays: nil), colors: colors,
                                    trailing: String(localized: "day12.price.from",
                                                     defaultValue: "a year, from \(PricingFormat.short(renewal))", table: "Pricing"))
                        .accessibilityLabel(String(localized: "day12.price.a11y",
                                                   defaultValue: "\(price) a year, from \(PricingFormat.short(renewal))", table: "Pricing"))
                }
                Text(String(localized: "day12.body", defaultValue: "Pro renews on its own. To stop it, cancel in Settings at least a day before.", table: "Pricing"))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 6)
                    .accessibilityIdentifier("day12.terms")

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "day12.ifCancel", defaultValue: "If you cancel", table: "Pricing"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    line("checkmark", String(localized: "day12.keeps.hours", defaultValue: "Every hour you logged stays.", table: "Pricing"))
                    line("checkmark", freeRentalName.map {
                        String(localized: "day12.keeps.rental", defaultValue: "You keep logging at \($0), free.", table: "Pricing")
                    } ?? String(localized: "day12.keeps.oneRental", defaultValue: "You keep logging at one rental, free.", table: "Pricing"))
                    line("minus", String(localized: "day12.needsPro", defaultValue: "Other rentals and the PDF need Pro.", table: "Pricing"))
                }
                .padding(LHMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .padding(.top, 20)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .lhSheetScreen(String(localized: "day12.title", defaultValue: "Your trial ends in \(daysLeft) days", table: "Pricing"),
                       onClose: { answer() }, background: colors.backgroundSecondary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button(String(localized: "day12.keep", defaultValue: "Keep Pro", table: "Pricing")) { answer() }
                    .buttonStyle(LHButton.primary)
                    .accessibilityIdentifier("day12.keep")
                Button(String(localized: "day12.cancel", defaultValue: "Cancel in Settings", table: "Pricing")) { showManage = true }
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("day12.cancel")
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .background { LHFootFade(color: colors.backgroundSecondary) }
        }
        .background(colors.backgroundSecondary)
        .presentationBackground(colors.backgroundSecondary)
        .manageSubscriptionsSheet(isPresented: $showManage)
        .onDisappear { onAnswered() }
        .accessibilityIdentifier("trial.day12")
    }

    private func answer() {
        onAnswered()
        dismiss()
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(symbol == "checkmark" ? colors.positive : colors.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(colors.textPrimary)
        }
    }
}
