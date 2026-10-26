import SwiftUI
import MessageUI

/// Contact support: one form on the plain page, one pinned `LHButton.primary`, and what helps us
/// answer fast. Standard v2 (package H): `LHScreenTitle`, `LHField`, no list chrome.
struct ContactSupportView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var showingMailComposer = false

    let supportEmail = "brian.landlordhours@gmail.com"

    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LongTailHeader(
                    title: HS.t("support.title", "Get help"),
                    subtitle: HS.t("support.subtitle", "Write to Brian. You’ll hear back by email."),
                    style: .detail,
                    back: (label: HS.t("common.back", "Back"), identifier: "support.back", action: { dismiss() })
                )

                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    LHSectionHeader(HS.t("support.section", "Your message"))
                    VStack(spacing: 12) {
                        LHField(HS.t("support.subject", "Subject"), text: $subject,
                                accessibilityLabel: HS.t("support.subject", "Subject"), identifier: "support.subject")
                        LHField(HS.t("support.message.placeholder", "What happened, and what did you expect?"), text: $message,
                                multiline: true, accessibilityLabel: HS.t("support.message", "Message"), identifier: "support.message")
                    }
                    Text(HS.t("support.hint", "It helps to include what you tapped, a screenshot, and your iOS version."))
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .padding(.top, 4)
                }

                // At accessibility sizes the button is too tall to pin: it ends the content.
                if typeSize.isAccessibilitySize { sendButton }
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { LHCanvas() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typeSize.isAccessibilitySize {
                sendButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                    .background(colors.background)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(subject: subject, body: message, to: supportEmail)
        }
        .accessibilityIdentifier("support.screen")
    }

    private var sendButton: some View {
        Button {
            sendSupportEmail()
        } label: {
            Label(HS.t("support.send", "Send email"), systemImage: "paperplane")
        }
        .buttonStyle(LHButton.primary)
        .disabled(!canSend)
        .accessibilityIdentifier("support.send")
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
