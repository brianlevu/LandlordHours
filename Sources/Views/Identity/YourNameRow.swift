import SwiftUI

// MARK: - Your name (P23), optional, shown on reports as "Prepared for"
//
// Stored on the device and in the synced `TaxProfile.displayName` (§2.4), so a new phone's CPA
// export still says who it is for.

struct YourNameRow: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showName = false

    var body: some View {
        LHRow.Browse(title: String(localized: "Your name", table: "Identity"),
                     meta: String(localized: "On your reports", table: "Identity"),
                     value: viewModel.userName.isEmpty ? String(localized: "Optional", table: "Identity") : viewModel.userName,
                     systemImage: "person.text.rectangle", tint: .neutral) { showName = true }
            .accessibilityIdentifier("settings.yourName")
            .sheet(isPresented: $showName) { YourNameSheet().environmentObject(viewModel) }
    }
}

struct YourNameSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LHSheet(String(localized: "Your name", table: "Identity"), onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(String(localized: "Optional", table: "Identity"), text: $name)
                    .font(.body)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .frame(minHeight: LHMetrics.rowMinHeight)
                    .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                    .accessibilityIdentifier("yourName.field")
                Text(String(localized: "Shown on your reports as “Prepared for”.", table: "Identity"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.top, 4)
        } footer: {
            Button(String(localized: "Save", table: "Identity")) {
                viewModel.setDisplayName(name)
                dismiss()
            }
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier("yourName.save")
        }
        .background(colors.backgroundSecondary.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear {
            name = viewModel.userName
            focused = true
        }
    }
}
