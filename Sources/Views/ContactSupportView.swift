import SwiftUI
import MessageUI

/// Contact support: a plain grouped form, one action, and what helps us answer fast.
struct ContactSupportView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
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
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get help")
                        .lhDisplayFont(.largeTitle)
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Questions about tracking, exports or setup? Write to Brian, who builds LandlordHours. You'll hear back by email.")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }

            Section {
                TextField("Subject", text: $subject)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("support.subject")
                TextField("What happened, and what did you expect?", text: $message, axis: .vertical)
                    .lineLimit(5...12)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("support.message")
            } header: {
                BPSectionHeader(title: "Your message")
            }
            .listRowBackground(colors.backgroundSecondary)

            Section {
                Button(action: sendSupportEmail) {
                    Label("Send email", systemImage: "paperplane")
                }
                .buttonStyle(InboxPrimaryButtonStyle())
                .disabled(!canSend)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("support.send")
            } footer: {
                Text("It helps to include what you tapped, a screenshot, and your iOS version.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(subject: subject, body: message, to: supportEmail)
        }
        .accessibilityIdentifier("support.screen")
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
