import SwiftUI

// MARK: - P28: most of the records aren't in iCloud anymore
//
// More than half of the live set absent from a complete read (R5c), or one pull deleting more than
// half of it (v4 3c): nothing is removed. The records stay visible, are not pushed, and the person
// picks. Swipe down = decide later (row P30 under Earlier records).

struct BulkAbsenceSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let hold = viewModel.identity.bulkHold
        LHSheet(String(localized: "Most of your records aren’t in iCloud anymore.", table: "Identity"), onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 12) {
                if let hold {
                    Text(String(localized: "\(IdentityCopy.hours(hold.heldHours)) of \(IdentityCopy.hours(hold.totalHours)) on this iPhone are no longer in iCloud. They may have been removed on another device, or iCloud data was reset.", table: "Identity"))
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                }
                Text(String(localized: "Nothing has been deleted here.", table: "Identity"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
            }
            .padding(.top, 4)
        } footer: {
            Button(String(localized: "Remove them from this iPhone", table: "Identity")) {
                viewModel.answerBulk(.remove)
                LHToastCenter.shared.show(.success, String(localized: "Moved to Recently removed. You can put them back.", table: "Identity"))
                dismiss()
            }
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("identity.bulk.remove")
            Button(String(localized: "Keep them on this iPhone and in iCloud", table: "Identity")) {
                viewModel.answerBulk(.keep)
                dismiss()
            }
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier("identity.bulk.keep")
        }
        .background(colors.backgroundSecondary.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("identity.bulk")
    }
}
