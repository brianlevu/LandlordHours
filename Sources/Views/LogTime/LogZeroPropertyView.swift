import SwiftUI

// MARK: - The first log: which rental? One field, then Log creates the rental and the entry together

extension LogTimeSheet {
    var rentalNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which rental is this for?")
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .leading) {
                if firstRunName.isEmpty {
                    Text("Name or address, like \u{201C}Pine Cabin\u{201D}")
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $firstRunName)
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .tint(colors.action)
                    .focused($nameFocused)
                    .submitLabel(.next)
                    .onSubmit { noteFocused = true }
                    .accessibilityLabel("Rental name")
                    .accessibilityIdentifier("log.rentalName")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.sheetCard))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(nameFocused ? colors.action : colors.sheetStroke, lineWidth: nameFocused ? 1.5 : 1))
            Text("You can add the address and type later.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
