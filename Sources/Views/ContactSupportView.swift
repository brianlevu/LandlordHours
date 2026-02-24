import SwiftUI
import MessageUI

struct ContactSupportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var showingMailComposer = false
    
    let supportEmail = "brian.landlordhours@gmail.com"
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        LHIconView(icon: .info, size: 20, color: AppColors.primary)
                        Text("Get Help")
                            .font(.headline)
                            .foregroundStyle(AppColors.primary)
                    }
                    
                    Text("Have questions about REPS tracking or need help? Reach out and Brian will get back to you.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.vertical, 8)
            }
            
            Section("Subject") {
                TextField("What can we help you with?", text: $subject)
            }
            
            Section("Message") {
                TextEditor(text: $message)
                    .frame(minHeight: 150)
            }
            
            Section {
                Button {
                    showingMailComposer = true
                } label: {
                    HStack {
                        LHIconView(icon: .envelope, size: 18, color: .white)
                        Text("Send Email")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .background(subject.isEmpty || message.isEmpty ? AppColors.textTertiary : AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(subject.isEmpty || message.isEmpty)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips for better help:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 8) {
                        LHIconView(icon: .num1, size: 14, color: AppColors.primary)
                        Text("Be specific about your issue")
                    }
                    HStack(spacing: 8) {
                        LHIconView(icon: .num2, size: 14, color: AppColors.primary)
                        Text("Include screenshots if possible")
                    }
                    HStack(spacing: 8) {
                        LHIconView(icon: .num3, size: 14, color: AppColors.primary)
                        Text("Mention your iOS version")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .navigationTitle("Contact Support")
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(subject: subject, body: message, to: supportEmail)
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
