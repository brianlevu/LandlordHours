import SwiftUI

// MARK: - Rental page › access slot (2.3 step-0 seam; owner: package A, pricing)
//
// PropertyDetailView places this between the hero and the body. Package A fills it with the
// view-only card on the free plan (frame p5). Until then it draws nothing.
struct RentalAccessSlot: View {
    let property: RentalProperty

    var body: some View {
        EmptyView()
    }
}
