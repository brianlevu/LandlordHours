import SwiftUI

// MARK: - Rental page › access slot (2.3; owner: package A, pricing)
//
// PropertyDetailView places this between the hero and the body. On the free plan, a rental that
// isn't the free one shows the view-only card (frame p5). Pro, the trial, founding buyers and the
// free rental itself draw nothing.
struct RentalAccessSlot: View {
    let property: RentalProperty

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var store = EntitlementStore.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSwitch = false

    var body: some View {
        // Read the plan so a change redraws the slot.
        let _ = store.plan
        if viewModel.rentalAccess(property.id) == .viewOnly {
            ViewOnlyRentalCard(hours: hoursThisYear, freeRentalName: viewModel.freeRentalName,
                               price: subscriptionManager.proDisplayPrice,
                               // The shell's paywall, not a local cover: the card (and any cover it
                               // held) goes away the moment the trial starts, and the trial-start
                               // moment must stay on screen.
                               onSeePro: { ProPaywallPresenter.shared.present(entry: .viewOnlyRental) },
                               onSwitch: { showSwitch = true })
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, LHMetrics.sectionGap)
                .navigationDestination(isPresented: $showSwitch) { FreeRentalSettingsView() }
                .onAppear { Analytics.lockPreviewShown(entry: .viewOnlyRental) }
        }
    }

    private var hoursThisYear: Int {
        FreeRentalChoice.all(viewModel).first { $0.id == property.id }?.hoursThisYear ?? 0
    }
}
