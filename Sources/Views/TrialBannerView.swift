import SwiftUI
import LucideIcons

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
                LucideIcon(image: Lucide.clock, size: 16)
                    .foregroundStyle(AppColors.honey)

                Text("\(subscriptionManager.trialDaysRemaining) day\(subscriptionManager.trialDaysRemaining == 1 ? "" : "s") left in free trial")
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.textPrimary)

                Spacer()

                Text("Upgrade")
                    .font(AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(colors.primarySurface)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.honeyWash)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    private var upgradeNowBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 10) {
                LucideIcon(image: Lucide.crown, size: 16)
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Upgrade to Pro")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(colors.textPrimary)
                    Text("Unlock all features \u{00B7} $30 one-time")
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
}

#Preview {
    VStack(spacing: 16) {
        TrialBannerView()
    }
    .padding()
}
