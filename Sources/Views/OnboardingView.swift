import SwiftUI

// MARK: - Onboarding Slide Data
struct OnboardingSlide {
    let icon: LHIcon
    let title: String
    let description: String
}

// MARK: - Main Onboarding View (Tiimo-style)
struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0
    @State private var appeared = false

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            icon: .home,
            title: "Welcome to\nLandlordHours",
            description: "Your all-in-one companion for tracking rental property hours and qualifying for IRS tax benefits."
        ),
        OnboardingSlide(
            icon: .properties,
            title: "Track Every\nProperty",
            description: "Manage all your rental properties in one place and know exactly how many hours you've invested in each."
        ),
        OnboardingSlide(
            icon: .track,
            title: "Log Your\nActivities",
            description: "Record time on repairs, management, leasing, travel, and more — all IRS-qualified categories."
        ),
        OnboardingSlide(
            icon: .personTwo,
            title: "Track With\nYour Spouse",
            description: "The 50% rule requires tracking both spouses' hours. We make it simple to log for everyone."
        ),
        OnboardingSlide(
            icon: .reports,
            title: "Hit Your\n750-Hour Goal",
            description: "Visual progress, weekly summaries, and exportable reports to prove your REPS qualification."
        ),
    ]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                progressSegments
                    .padding(.top, 20)

                TabView(selection: $currentPage) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        OnboardingSlideView(slide: slide, appeared: appeared)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomActions
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                appeared = true
            }
        }
    }

    // MARK: - Progress Segments (Tiimo style)
    private var progressSegments: some View {
        HStack(spacing: 6) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule()
                    .fill(i <= currentPage ? AppColors.primary : Color(hex: "E5E7EB"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom Actions
    private var bottomActions: some View {
        VStack(spacing: 16) {
            // Primary CTA — black pill (Tiimo signature)
            Button {
                if currentPage < slides.count - 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentPage += 1
                    }
                } else {
                    showOnboarding = false
                }
            } label: {
                HStack(spacing: 8) {
                    Text(currentPage < slides.count - 1 ? "Continue" : "Get started")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(hex: "1A1A1A"))
                .clipShape(Capsule())
            }

            // Secondary action
            if currentPage == slides.count - 1 {
                Button { showOnboarding = false } label: {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(Color(hex: "9CA3AF"))
                        Text("Sign in")
                            .foregroundColor(AppColors.primary)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Button { showOnboarding = false } label: {
                    Text("Skip")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 52)
    }
}

// MARK: - Individual Slide View
struct OnboardingSlideView: View {
    let slide: OnboardingSlide
    let appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Illustration area — centered, Tiimo-style nested circles
            ZStack {
                Circle()
                    .fill(AppColors.primarySurface)
                    .frame(width: 280, height: 280)

                Circle()
                    .fill(AppColors.primary.opacity(0.12))
                    .frame(width: 200, height: 200)

                LHCircleBadge(
                    icon: slide.icon,
                    bgColor: AppColors.primary,
                    fgColor: .white,
                    size: 104,
                    iconScale: 0.48
                )
                .scaleEffect(appeared ? 1 : 0.4)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 44)

            // Title — large, bold serif, left-aligned (Tiimo editorial typography)
            Text(slide.title)
                .font(.system(size: 38, weight: .bold, design: .serif))
                .foregroundColor(Color(hex: "111827"))
                .lineSpacing(2)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
                .animation(.easeOut(duration: 0.45).delay(0.1), value: appeared)

            // Description — muted gray
            Text(slide.description)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "6B7280"))
                .lineSpacing(5)
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
                .animation(.easeOut(duration: 0.45).delay(0.18), value: appeared)

            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    OnboardingView(showOnboarding: .constant(true))
}
