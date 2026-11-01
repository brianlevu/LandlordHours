import SwiftUI

// MARK: - A view-only rental (2.3, frame p5)
//
// On the free plan, every rental but the free one is view-only: the page, its house and its hours
// stay, and every hour stays in the total, but nothing new is logged there. The card says so,
// names the free rental, and offers Pro (StoreKit's price) or a switch (Settings › Free rental).

struct ViewOnlyRentalCard: View {
    let hours: Int
    let freeRentalName: String?
    let price: String?
    var onSeePro: () -> Void
    var onSwitch: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "viewOnly.title", defaultValue: "View only on the free plan", table: "Pricing"))
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text(body(freeRentalName))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("viewOnly.body")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actions }
                VStack(alignment: .leading, spacing: 4) { actions }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { shape.strokeBorder(colors.pageCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rental.viewOnly")
    }

    private func body(_ name: String?) -> String {
        if let name {
            return String(localized: "viewOnly.body", defaultValue: "You log at \(name) for free. The \(hours) hours here stay in your total.", table: "Pricing")
        }
        return String(localized: "viewOnly.bodyNoName", defaultValue: "The free plan logs at one rental. The \(hours) hours here stay in your total.", table: "Pricing")
    }

    @ViewBuilder private var actions: some View {
        Button(seeProTitle(price), action: onSeePro)
            .buttonStyle(LHButton.secondary)
            .accessibilityIdentifier("viewOnly.seePro")
        Button(String(localized: "viewOnly.switch", defaultValue: "Switch rental", table: "Pricing"), action: onSwitch)
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("viewOnly.switch")
    }
}
