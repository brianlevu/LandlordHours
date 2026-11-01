import SwiftUI

// MARK: - Settings › Free rental (2.3, frame p6)
//
// The free plan logs at one rental, and the person can switch it once a calendar month
// (`FreeRentalPolicy`). Before the next switch date the other rentals are locked rows that say
// when ("46h this year · switch on Nov 30"), and a tap is refused with that date. After it, a tap
// asks once, then switches (the pick syncs through iCloud, `FreeRentalSync`). Below, the Pro row.

struct FreeRentalSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var store = EntitlementStore.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var pending: FreeRentalChoice?
    @State private var refusal: String?
    @State private var paywall: ProPaywallRequest?
    @State private var switchTick = 0
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var rentals: [FreeRentalChoice] { FreeRentalChoice.all(viewModel) }
    private var freeID: UUID? { store.freeRentalID(rentals: viewModel.rentalUsages) }
    /// The next switch date, only while it is still ahead.
    private var nextSwitch: Date? {
        guard let next = store.nextFreeRentalSwitch(), next > PaywallClock.now() else { return nil }
        return next
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    LHSectionHeader(String(localized: "freeRental.section.logAt", defaultValue: "You log at", table: "Pricing"))
                        .padding(.horizontal, 4)
                    LHRowGroup {
                        ForEach(Array(rentals.enumerated()), id: \.element.id) { index, rental in
                            if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                            row(rental)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityHidden(true)
                        Text(ruleLine)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("freeRental.rule")
                    }
                    if let refusal {
                        Text(refusal)
                            .font(.subheadline)
                            .foregroundStyle(colors.caution)
                            .accessibilityIdentifier("freeRental.refused")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, -12)

                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    LHSectionHeader(String(localized: "freeRental.section.pro", defaultValue: "Pro", table: "Pricing"))
                        .padding(.horizontal, 4)
                    LHRowGroup {
                        LHRow.Browse(title: String(localized: "freeRental.pro.title", defaultValue: "Log at every rental", table: "Pricing"),
                                     meta: subscriptionManager.proDisplayPrice.map {
                                         String(localized: "freeRental.pro.meta", defaultValue: "\($0) a year, with the PDF", table: "Pricing")
                                     } ?? String(localized: "freeRental.pro.metaNoPrice", defaultValue: "Every rental, with the PDF", table: "Pricing"),
                                     systemImage: "star", wrapsMeta: true, action: {
                                         paywall = ProPaywallRequest(context: ProGate.context(for: .freeRentalSettings), entry: .freeRentalSettings)
                                     })
                            .accessibilityIdentifier("freeRental.seePro")
                    }
                }
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhDetailScreen(String(localized: "freeRental.title", defaultValue: "Free rental", table: "Pricing"),
                        subtitle: String(localized: "freeRental.subtitle", defaultValue: "The free plan logs at one rental.", table: "Pricing"),
                        back: LHBackAction(label: String(localized: "common.back", defaultValue: "Back", table: "Pricing"),
                                           identifier: "freeRental.back") { dismiss() })
        .hidesAppTabBar()
        .proPaywall($paywall)
        .sensoryFeedback(.selection, trigger: switchTick)
        .confirmationDialog(pending.map { String(localized: "freeRental.confirm.title", defaultValue: "Log at \($0.name) for free?", table: "Pricing") } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { rental in
            Button(String(localized: "freeRental.confirm.switch", defaultValue: "Switch to \(rental.name)", table: "Pricing")) { switchTo(rental) }
                .accessibilityIdentifier("freeRental.confirm")
            Button(String(localized: "freeRental.confirm.keep", defaultValue: "Keep it as it is", table: "Pricing"), role: .cancel) { pending = nil }
        } message: { _ in
            Text(String(localized: "freeRental.confirm.message", defaultValue: "You can switch once a month. Every rental’s hours stay in your total.", table: "Pricing"))
        }
        .accessibilityIdentifier("plan.freeRental")
    }

    private var ruleLine: String {
        if let next = nextSwitch {
            return String(localized: "freeRental.rule.next",
                          defaultValue: "You can switch once a month. Your next switch is on \(PricingFormat.short(next)).", table: "Pricing")
        }
        return String(localized: "freeRental.rule", defaultValue: "You can switch once a month.", table: "Pricing")
    }

    @ViewBuilder
    private func row(_ rental: FreeRentalChoice) -> some View {
        let selected = rental.id == freeID
        if selected {
            FreeRentalPickRow(rental: rental, selected: true, enabled: false)
        } else if let next = nextSwitch {
            let date = PricingFormat.short(next)
            FreeRentalPickRow(rental: rental, selected: false, enabled: false,
                              note: String(localized: "freeRental.row.locked", defaultValue: "\(rental.hoursThisYear)h this year · switch on \(date)", table: "Pricing"),
                              accessibilityHint: String(localized: "freeRental.row.lockedHint", defaultValue: "You can switch on \(date)", table: "Pricing"))
                .onTapGesture { refuse(next) }
        } else {
            FreeRentalPickRow(rental: rental, selected: false) { pending = rental }
        }
    }

    private func refuse(_ next: Date) {
        refusal = String(localized: "freeRental.refused", defaultValue: "You switched this month. You can switch again on \(PricingFormat.short(next)).", table: "Pricing")
    }

    private func switchTo(_ rental: FreeRentalChoice) {
        pending = nil
        switch store.pickFreeRental(rental.id, rentals: viewModel.rentalUsages) {
        case .allowed:
            refusal = nil
            switchTick += 1
            FreeRentalSync.shared.localPickChanged()
        case .tooSoon(let next):
            refuse(next)
        case .sameRental, .unknownRental:
            break
        }
    }
}
