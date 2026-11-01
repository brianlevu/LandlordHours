import SwiftUI

// MARK: - Today › Learn slot (2.3 step-0 seam; owner: package C, learning)
//
// DashboardView places this under To confirm and above the care slot (NOTES: the Learn card sits
// under To confirm). Package C fills it with the milestone card (frame l1) and owns its own
// padding, presentation and paywall entry. Until then it draws nothing.
struct TodayLearnSlot: View {
    /// The rental Today is focused on (nil with one rental, or "All").
    let rentalID: UUID?

    var body: some View {
        EmptyView()
    }
}
