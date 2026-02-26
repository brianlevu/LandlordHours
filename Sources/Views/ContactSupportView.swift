import SwiftUI
import MessageUI
import LucideIcons

struct ContactSupportView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var showingMailComposer = false

    let supportEmail = "brian.landlordhours@gmail.com"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        JellyBadge(systemName: "life-buoy", color: AppColors.primary, wash: colors.primarySurface, size: 36)
                        Text("Get Help")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                    }

                    Text("Have questions about REPS tracking or need help? Reach out and Brian will get back to you.")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)

                // Form card
                VStack(alignment: .leading, spacing: 16) {
                    // Subject
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SUBJECT")
                            .font(AppTypography.label)
                            .tracking(1.5)
                            .foregroundStyle(colors.textSecondary)
                        TextField("What can we help you with?", text: $subject)
                            .font(AppTypography.body)
                            .padding(12)
                            .background(colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    }

                    // Message
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MESSAGE")
                            .font(AppTypography.label)
                            .tracking(1.5)
                            .foregroundStyle(colors.textSecondary)
                        TextEditor(text: $message)
                            .font(AppTypography.body)
                            .frame(minHeight: 150)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    }

                    // Send button
                    Button {
                        showingMailComposer = true
                    } label: {
                        HStack(spacing: 8) {
                            LucideIcon(image: Lucide.mail, size: 16)
                            Text("Send Email")
                        }
                        .font(AppTypography.button)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(subject.isEmpty || message.isEmpty ? AppColors.mist : AppColors.primary)
                        .clipShape(Capsule())
                    }
                    .disabled(subject.isEmpty || message.isEmpty)
                }
                .padding(20)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)

                // Tips card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tips for better help:")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(colors.textPrimary)

                    tipRow(number: "1", text: "Be specific about your issue")
                    tipRow(number: "2", text: "Include screenshots if possible")
                    tipRow(number: "3", text: "Mention your iOS version")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(colors.background)
        .navigationTitle("Contact Support")
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(subject: subject, body: message, to: supportEmail)
        }
    }

    private func tipRow(number: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppColors.primary)
                .clipShape(Circle())
            Text(text)
                .font(AppTypography.bodySmall)
                .foregroundStyle(colors.textSecondary)
        }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let to: String

    func makeUIViewController(context: Context) -> UIViewController {
        let picker = MFMailComposeViewController()
        picker.setSubject(subject)
        picker.setMessageBody(body, isHTML: false)
        picker.setToRecipients([to])
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ContactSupportView()
    }
}
