import SwiftUI

// MARK: - Pick your free rental (2.3, frame p4)
//
// Shown when Pro ends (a trial that lapsed, a subscription that ended) and the person has two or
// more rentals and no pick (`EntitlementStore.needsFreeRentalPick`). The most-used rental is
// selected first. There is no close button: "Log at <name>" saves the pick (it starts the month
// before the next switch), and a swipe-down keeps the most-used rental without using up the pick
// (`keepDefaultFreeRental`). Every rental's hours stay in the total either way.

/// One rental as the free-rental screens show it.
struct FreeRentalChoice: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// Whole hours this calendar year (what the rental page shows).
    let hoursThisYear: Int

    @MainActor
    static func all(_ viewModel: AppViewModel, now: Date = Date(), calendar: Calendar = .current) -> [FreeRentalChoice] {
        let year = calendar.component(.year, from: now)
        var hours: [UUID: Double] = [:]
        for entry in viewModel.timeEntries where calendar.component(.year, from: entry.date) == year {
            hours[entry.propertyId, default: 0] += entry.hours
        }
        return viewModel.properties.map {
            FreeRentalChoice(id: $0.id, name: $0.name, hoursThisYear: Int(max(0, hours[$0.id] ?? 0).rounded(.down)))
        }
    }
}

/// A rental row with the Settings-style selection (§1.24): a trailing `checkmark` in `action`.
/// A locked row (Settings, before the monthly switch) keeps full-contrast ink and isn't a button.
struct FreeRentalPickRow: View {
    let rental: FreeRentalChoice
    let selected: Bool
    var enabled = true
    /// Replaces the hours line on a locked row ("46h this year · switch on Nov 30").
    var note: String? = nil
    var accessibilityHint: String? = nil
    var action: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    static func keptLine(_ hours: Int) -> String {
        String(localized: "freeRental.row.kept", defaultValue: "\(hours)h this year · kept in your total", table: "Pricing")
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        if enabled {
            Button(action: action) { face(colors) }
                .buttonStyle(LHButton.press)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("freeRental.row.\(rental.name)")
        } else {
            face(colors)
                .accessibilityElement(children: .combine)
                .accessibilityHint(accessibilityHint ?? "")
                .accessibilityIdentifier("freeRental.row.\(rental.name)")
        }
    }

    private func face(_ colors: AdaptiveColors) -> some View {
        HStack(spacing: 12) {
            LHRowGlyph(systemImage: "house", tint: selected ? .action : .neutral)
            VStack(alignment: .leading, spacing: 2) {
                Text(rental.name).font(.body).foregroundStyle(colors.textPrimary)
                Text(note ?? Self.keptLine(rental.hoursThisYear))
                    .font(.subheadline).foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                    .accessibilityHidden(true)
            }
        }
        .padding(LHRow.insets)
        .frame(minHeight: LHMetrics.rowMinHeight)
        .contentShape(Rectangle())
    }
}

struct PickFreeRentalSheet: View {
    /// Why the sheet shows: a trial that ended, a paid plan that ended, or neither known.
    enum Reason: String { case trialEnded, proEnded, unknown }

    let reason: Reason
    var onSeePro: () -> Void

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var store = EntitlementStore.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: UUID?
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var rentals: [FreeRentalChoice] { FreeRentalChoice.all(viewModel) }
    private var current: UUID? { selected ?? store.freeRentalID(rentals: viewModel.rentalUsages) }
    private var currentName: String { rentals.first { $0.id == current }?.name ?? "" }

    private var lead: String {
        switch reason {
        case .trialEnded:
            return String(localized: "pickFree.lead.trial", defaultValue: "Your trial has ended. You can keep logging at one rental for free. Every rental’s hours stay in your total.", table: "Pricing")
        case .proEnded:
            return String(localized: "pickFree.lead.pro", defaultValue: "Your Pro plan has ended. You can keep logging at one rental for free. Every rental’s hours stay in your total.", table: "Pricing")
        case .unknown:
            return String(localized: "pickFree.lead.free", defaultValue: "The free plan logs at one rental. Every rental’s hours stay in your total.", table: "Pricing")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(lead)
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                LHRowGroup {
                    ForEach(Array(rentals.enumerated()), id: \.element.id) { index, rental in
                        if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                        FreeRentalPickRow(rental: rental, selected: current == rental.id) { selected = rental.id }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                        .strokeBorder(colors.border, lineWidth: 1)
                }
                .padding(.top, 20)
                LHFootnote(String(localized: "pickFree.footnote", defaultValue: "You can switch once a month in Settings.", table: "Pricing"))
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .lhSheetScreen(String(localized: "pickFree.title", defaultValue: "Pick your free rental", table: "Pricing"), background: colors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button(String(localized: "pickFree.cta", defaultValue: "Log at \(currentName)", table: "Pricing")) { confirm() }
                    .buttonStyle(LHButton.primary)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("pickFree.confirm")
                Button(seeProTitle(subscriptionManager.proDisplayPrice), action: onSeePro)
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("pickFree.seePro")
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .background { LHFootFade(color: colors.background) }
        }
        .background(colors.background)
        .presentationBackground(colors.background)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityIdentifier("plan.pickFree")
    }

    private func confirm() {
        if let id = current {
            if store.pickFreeRental(id, rentals: viewModel.rentalUsages) == .allowed {
                FreeRentalSync.shared.localPickChanged()
            }
        }
        dismiss()
    }
}

/// "See Pro · $49.99 a year" with StoreKit's price; "See Pro" before it loads.
func seeProTitle(_ price: String?) -> String {
    if let price {
        return String(localized: "seePro.price", defaultValue: "See Pro · \(price) a year", table: "Pricing")
    }
    return String(localized: "seePro", defaultValue: "See Pro", table: "Pricing")
}
