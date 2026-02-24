import SwiftUI

struct TrialBannerView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var showPaywall = false

    var body: some View {
        Group {
            if subscriptionManager.isTrialActive && subscriptionManager.trialDaysRemaining <= 3 {
                // Last 3 days of trial
                trialExpiringSoonBanner
            } else if !subscriptionManager.isPro && !subscriptionManager.isTrialActive {
                // Trial expired, not purchased
                upgradeNowBanner
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(showPaywall: $showPaywall)
        }
    }

    private var trialExpiringSoonBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                LHIconView(icon: .clock, size: 16, color: AppColors.warning)

                Text("\(subscriptionManager.trialDaysRemaining) day\(subscriptionManager.trialDaysRemaining == 1 ? "" : "s") left in free trial")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.textPrimary)

                Spacer()

                Text("Upgrade")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(colors.primarySurface)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var upgradeNowBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                LHIconView(icon: .crown, size: 16, color: AppColors.primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Upgrade to Pro")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text("Unlock all features · $30 one-time")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer()

                LHIconView(icon: .chevronRight, size: 12, color: colors.textTertiary, strokeStyle: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colors.primarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

#Preview {
    VStack(spacing: 16) {
        TrialBannerView()
    }
    .padding()
}
