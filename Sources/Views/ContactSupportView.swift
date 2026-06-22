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
                header
                supportForm
                tipsCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background {
            LHMobileCanvas()
        }
        .navigationTitle("Contact Support")
        .hidesAppTabBar()
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(subject: subject, body: message, to: supportEmail)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(colors.backgroundTertiary)
                .frame(width: 54, height: 54)
                .overlay {
                    LucideIcon(image: Lucide.lifeBuoy, size: 24)
                        .foregroundStyle(AppColors.charcoal)
                }

            Text("Get help")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .minimumScaleFactor(0.82)

            Text("Have questions about REPS tracking or need help? Reach out and Brian will get back to you.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var supportForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Subject")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                TextField("What can we help you with?", text: $subject)
                    .font(AppTypography.body)
                    .padding(12)
                    .background(colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Message")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                TextEditor(text: $message)
                    .font(AppTypography.body)
                    .frame(minHeight: 150)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button(action: sendSupportEmail) {
                HStack(spacing: 8) {
                    LucideIcon(image: Lucide.mail, size: 16)
                    Text("Send Email")
                }
                .font(AppTypography.button)
                .foregroundStyle(subject.isEmpty || message.isEmpty ? .white : AppColors.charcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(subject.isEmpty || message.isEmpty ? AppColors.mist : AppColors.sage)
                .clipShape(Capsule())
            }
            .disabled(subject.isEmpty || message.isEmpty)
        }
        .padding(20)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tips for better help")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            tipRow(number: "1", text: "Be specific about your issue")
            tipRow(number: "2", text: "Include screenshots if possible")
            tipRow(number: "3", text: "Mention your iOS version")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
    }

    private func sendSupportEmail() {
        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            let mailtoSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let mailtoBody = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:\(supportEmail)?subject=\(mailtoSubject)&body=\(mailtoBody)") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func tipRow(number: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.onAction)
                .frame(width: 22, height: 22)
                .background(colors.action)
                .clipShape(Circle())
            Text(text)
                .font(AppTypography.bodySmall)
                .foregroundStyle(colors.textSecondary)
        }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let subject: String
    let body: String
    let to: String

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let picker = MFMailComposeViewController()
        picker.mailComposeDelegate = context.coordinator
        picker.setSubject(subject)
        picker.setMessageBody(body, isHTML: false)
        picker.setToRecipients([to])
        return picker
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        ContactSupportView()
    }
}
