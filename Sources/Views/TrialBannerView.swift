import SwiftUI
import LucideIcons

struct TrialBannerView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var showPaywall = false

    var body: some View {
        Group {
            if !subscriptionManager.isPro {
                upgradeNowBanner
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(showPaywall: $showPaywall)
        }
    }

    private var upgradeNowBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                LucideIcon(image: Lucide.crown, size: 16)
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Unlock Pro features")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(colors.textPrimary)
                    Text(upgradeSubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer()

                LucideIcon(image: Lucide.chevronRight, size: 12)
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colors.primarySurface)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var upgradeSubtitle: String {
        if let product = subscriptionManager.proProduct {
            return "Lifetime access \(product.displayPrice)"
        }
        return "Check App Store availability"
    }
}

#Preview {
    VStack(spacing: 16) {
        TrialBannerView()
    }
    .padding()
}
