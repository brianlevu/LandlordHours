import SwiftUI

// MARK: - The first log: which rental? One field, then Log creates the rental and the entry together

extension LogTimeSheet {
    var rentalNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lt("Which rental is this for?"))
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
            LogTextField(placeholder: isAX ? lt("Rental name") : lt("Name or address, like \u{201C}Pine Cabin\u{201D}"), text: $firstRunName,
                         focus: $nameFocused, label: lt("Rental name"), identifier: "log.rentalName",
                         submitLabel: .next, onSubmit: { noteFocused = true })
            LHFootnote(lt("You can add the address and type later."))
        }
    }
}
