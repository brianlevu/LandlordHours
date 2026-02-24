import SwiftUI

struct PaywallView: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Binding var showPaywall: Bool
    var onDismiss: (() -> Void)?

    // Hero animation
    @State private var heroScale: CGFloat = 0.5
    @State private var heroOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    // Features stagger
    @State private var featureOffsets: [CGFloat] = Array(repeating: 32, count: 5)
    @State private var featureOpacities: [Double] = Array(repeating: 0, count: 5)
    // Bottom section
    @State private var bottomOffset: CGFloat = 40
    @State private var bottomOpacity: Double = 0

    private let proFeatures: [(icon: LHIcon, title: String, desc: String, color: String)] = [
        (.sparkles,   "AI Smart Entry",       "Describe your work, AI does the rest",   "7C6FF7"),
        (.camera,     "Photo Evidence",        "Attach photos to every time entry",       "EF4444"),
        (.icloud,     "iCloud Backup",         "Your records, safe and synced forever",   "60A5FA"),
        (.doc,        "Audit-Ready Reports",   "Clean PDF exports for tax filing",        "34D399"),
        (.properties, "Unlimited Properties",  "Track every rental you own",              "FBBF24"),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.top, 56)
                        .padding(.bottom, 32)

                    featuresSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                    freeNotice
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)

                    pricingAndCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                }
            }

            // Close button
            Button {
                showPaywall = false
                onDismiss?()
            } label: {
                ZStack {
                    Circle()
                        .fill(colors.backgroundTertiary)
                        .frame(width: 32, height: 32)
                    LHIconView(icon: .close, size: 12, color: colors.textSecondary)
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .onAppear { animateIn() }
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer pulse ring
                Circle()
                    .fill(AppColors.primary.opacity(0.07))
                    .frame(width: 148, height: 148)
                    .scaleEffect(pulseScale)

                // Inner lavender circle
                Circle()
                    .fill(colors.primarySurface)
                    .frame(width: 112, height: 112)

                LHIconView(icon: .crown, size: 48, color: AppColors.primary)
            }
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            VStack(spacing: 8) {
                Text("Go Pro")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(colors.textPrimary)

                Text("Track every hour.\nKeep every deduction.")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(heroOpacity)
        }
    }

    // MARK: - Features
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionPill(icon: .sparkles, label: "WHAT'S INCLUDED")
                .padding(.bottom, 4)

            ForEach(Array(proFeatures.enumerated()), id: \.offset) { index, feature in
                featureRow(feature, index: index)
            }
        }
    }

    private func featureRow(_ feature: (icon: LHIcon, title: String, desc: String, color: String), index: Int) -> some View {
        HStack(spacing: 14) {
            LHIconBadge(icon: feature.icon, bgColor: Color(hex: feature.color), fgColor: .white, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(feature.desc)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            LHIconView(icon: .checkmark, size: 18, color: AppColors.success)
        }
        .padding(14)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 8, x: 0, y: 2)
        .offset(y: featureOffsets[index])
        .opacity(featureOpacities[index])
    }

    // MARK: - Free Notice
    private var freeNotice: some View {
        HStack(spacing: 10) {
            LHIconView(icon: .info, size: 14, color: colors.textTertiary)
            Text("Free plan: 1 property · 20 entries/month · basic reports")
                .font(.system(size: 13))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .offset(y: bottomOffset)
        .opacity(bottomOpacity)
    }

    // MARK: - Pricing + CTA
    private var pricingAndCTA: some View {
        VStack(spacing: 16) {
            // Price display
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("$30")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("one-time")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(colors.textSecondary)
                        Text("yours forever ✓")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.success)
                    }
                }
                Text("Less than one hour of billable time")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.bottom, 4)

            // Trial note
            if subscriptionManager.isTrialActive {
                HStack(spacing: 6) {
                    LHIconView(icon: .clock, size: 12, color: AppColors.warning)
                    Text("\(subscriptionManager.trialDaysRemaining) day\(subscriptionManager.trialDaysRemaining == 1 ? "" : "s") left in free trial")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.warning.opacity(0.1))
                .clipShape(Capsule())
            }

            // CTA Button
            if subscriptionManager.isLoading {
                ProgressView("Processing...")
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            } else if subscriptionManager.hasPurchased {
                Button {
                    showPaywall = false
                    onDismiss?()
                } label: {
                    HStack(spacing: 8) {
                        LHIconView(icon: .checkmark, size: 20, color: .white)
                        Text("You're Pro! Tap to continue")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AppColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            } else {
                Button {
                    Task { await subscriptionManager.purchasePro() }
                } label: {
                    Group {
                        if let product = subscriptionManager.proProduct {
                            Text("Unlock Pro · \(product.displayPrice)")
                        } else {
                            Text("Unlock Pro · $30")
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .disabled(subscriptionManager.products.isEmpty)
            }

            // Error message
            if let error = subscriptionManager.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Dismiss link
            Button {
                showPaywall = false
                onDismiss?()
            } label: {
                Text(subscriptionManager.hasPurchased ? "Close" : "Maybe Later")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .offset(y: bottomOffset)
        .opacity(bottomOpacity)
    }

    // MARK: - Helpers
    private func sectionPill(icon: LHIcon, label: String) -> some View {
        HStack(spacing: 5) {
            LHIconView(icon: icon, size: 11, color: colors.textSecondary)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
        }
        .foregroundStyle(colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.backgroundTertiary)
        .clipShape(Capsule())
    }

    // MARK: - Animations
    private func animateIn() {
        // Hero bounces in
        withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.05)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }
        // Continuous pulse on outer ring
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.8)) {
            pulseScale = 1.1
        }
        // Features stagger in
        for i in 0..<proFeatures.count {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.35 + Double(i) * 0.08)) {
                featureOffsets[i] = 0
                featureOpacities[i] = 1.0
            }
        }
        // Bottom section slides up
        withAnimation(.easeOut(duration: 0.45).delay(0.75)) {
            bottomOffset = 0
            bottomOpacity = 1.0
        }
    }
}

#Preview {
    PaywallView(showPaywall: .constant(true))
}
