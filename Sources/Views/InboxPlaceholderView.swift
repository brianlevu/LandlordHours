import SwiftUI

/// The Inbox tab before WP3: an honest empty state. Suggestions (calendar, trips, receipts) are
/// not built yet, so this says they are coming and offers the manual path that works today.
struct InboxPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    Text("Inbox")
                        .lhDisplayFont(.largeTitle)
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "tray")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(colors.action)
                            .frame(width: 72, height: 72)
                            .background(colors.actionSurface)
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                        Text("SUGGESTIONS · COMING SOON")
                            .font(AppTypography.drafting)
                            .tracking(1.3)
                            .foregroundStyle(colors.draftingInk)

                        Text("Suggestions are coming")
                            .font(AppTypography.title2)
                            .foregroundStyle(colors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Soon LandlordHours will spot work in your calendar, trips and receipts and put it here for you to confirm. For now, log hours with the + button.")
                            .font(AppTypography.bodyLarge)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            NotificationCenter.default.post(name: .switchToTab, object: ShellTab.logTimeIndex)
                        } label: {
                            Text("Log time")
                                .font(AppTypography.buttonLarge)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .frame(minHeight: 44)
                                .background(colors.action)
                                .foregroundStyle(colors.onAction)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.lhPressable)
                        .padding(.top, AppSpacing.xs)
                        .accessibilityIdentifier("inbox.placeholder.logTime")
                    }
                    .padding(.vertical, AppSpacing.xxl)
                    .padding(.horizontal, AppSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("inbox.placeholder")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(colors.background)
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    InboxPlaceholderView()
}
