import SwiftUI

// MARK: - Today › care slot (2.3 step-0 seam; owner: package B, care plan)
//
// DashboardView places this under the Learn slot. Package B fills it with "This season · <rental>"
// and the 3 most timely items (frame c1), and owns its padding, navigation and paywall entry.
// Until then it draws nothing.
struct TodayCareSlot: View {
    /// The rental Today is focused on (nil with one rental, or "All").
    let rentalID: UUID?

    var body: some View {
        EmptyView()
    }
}
