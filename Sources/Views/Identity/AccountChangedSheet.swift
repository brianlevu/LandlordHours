import SwiftUI

// MARK: - P13: this iPhone is signed in to a different iCloud account
//
// Detected by comparing the iCloud user record stored at the first cloud read. Sync pauses until
// the person picks. "Keep them with this iCloud" pushes into the new account (after reading it and
// asking about any second set there); "Use this iCloud's records instead" moves this iPhone's set
// to Earlier records (nothing deleted); "Decide later" keeps sync paused with a Today card.

struct AccountChangedSheet: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var working = false

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LHSheet(String(localized: "A different iCloud", table: "Identity"), onClose: { later() }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "This iPhone is now signed in to a different iCloud account.", table: "Identity"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                Text(String(localized: "Your \(IdentityCopy.hours(viewModel.timeEntries.reduce(0) { $0 + $1.hours })) at \(IdentityCopy.rentals(viewModel.properties.count)) are still on this iPhone. What should happen to them?", table: "Identity"))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                VStack(alignment: .leading, spacing: 0) {
                    Button(String(localized: "Use this iCloud’s records instead", table: "Identity")) { choose(.useThisICloud) }
                        .buttonStyle(LHButton.tertiary)
                        .disabled(working)
                        .accessibilityIdentifier("identity.account.useThis")
                    Button(String(localized: "Decide later", table: "Identity")) { later() }
                        .buttonStyle(LHButton.tertiary)
                        .accessibilityIdentifier("identity.account.later")
                }
            }
            .padding(.top, 4)
        } footer: {
            Button(String(localized: "Keep them with this iCloud", table: "Identity")) { choose(.keepWithThisICloud) }
                .buttonStyle(LHButton.primary)
                .disabled(working)
                .accessibilityIdentifier("identity.account.keep")
        }
        .background(colors.backgroundSecondary.ignoresSafeArea())
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.62), .large])
        .interactiveDismissDisabled(working)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("identity.accountChanged")
    }

    private func later() {
        viewModel.identity.deferAccountChanged()
        dismiss()
    }

    private func choose(_ answer: AccountChangedAnswer) {
        working = true
        Task {
            await viewModel.answerAccountChanged(answer)
            working = false
            dismiss()
        }
    }
}

// MARK: - P31: the records were deleted from iCloud on another device
//
// The zone is gone and this device synced before: sync stops and asks. It never recreates the
// zone on its own, so "Delete all data" on one device isn't undone by another (review fix 1).

struct ZoneGoneSheet: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var working = false
    @State private var confirmDelete = false

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LHSheet(String(localized: "Records deleted in iCloud", table: "Identity")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Your records were deleted from iCloud on another device.", table: "Identity"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                Text(String(localized: "Keep this iPhone’s copy and put it back in iCloud, or delete it here too?", table: "Identity"))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                Button(String(localized: "Delete here too", table: "Identity"), role: .destructive) { confirmDelete = true }
                    .buttonStyle(LHButton.destructiveTertiary)
                    .disabled(working)
                    .accessibilityIdentifier("identity.zoneGone.delete")
            }
            .padding(.top, 4)
        } footer: {
            Button(String(localized: "Keep and put back in iCloud", table: "Identity")) {
                working = true
                Task {
                    await viewModel.answerZoneGone(.keepAndRestore)
                    working = false
                    dismiss()
                }
            }
            .buttonStyle(LHButton.primary)
            .disabled(working)
            .accessibilityIdentifier("identity.zoneGone.keep")
        }
        .background(colors.backgroundSecondary.ignoresSafeArea())
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.62), .large])
        .interactiveDismissDisabled(true)
        .alert(String(localized: "Delete from this iPhone?", table: "Identity"), isPresented: $confirmDelete) {
            Button(String(localized: "Delete", table: "Identity"), role: .destructive) {
                Task {
                    await viewModel.answerZoneGone(.deleteHere)
                    dismiss()
                }
            }
            Button(String(localized: "Keep", table: "Identity"), role: .cancel) {}
        } message: {
            Text(String(localized: "Every record on this iPhone goes. This can’t be undone.", table: "Identity"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("identity.zoneGone")
    }
}
