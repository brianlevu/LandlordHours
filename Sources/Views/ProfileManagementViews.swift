import SwiftUI

// MARK: - Restore sheet (welcome screen + Settings)

/// Lists earlier profiles found on this device or in iCloud. Picking one opens it;
/// nothing is merged or deleted.
struct ProfileRestoreSheet: View {
    enum Context {
        case welcome
        case settings
    }

    let profiles: [DiscoveredProfile]
    let context: Context
    let onRestore: (DiscoveredProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var pendingSwitch: DiscoveredProfile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context == .welcome ? "Restore earlier data" : "Restore other data")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(context == .welcome
                             ? "Pick a profile to open its records. Nothing is merged or deleted."
                             : "Open another profile's records. Your current data stays on this iPhone, and you can switch back anytime.")
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }

                Section {
                    ForEach(profiles) { profile in
                        Button {
                            if context == .settings {
                                pendingSwitch = profile
                            } else {
                                onRestore(profile)
                            }
                        } label: {
                            ProfileCandidateRow(profile: profile)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("restore.profile.\(profile.id)")
                    }
                } footer: {
                    if profiles.contains(where: \.isICloudOnly) {
                        Label("Photos weren't saved to iCloud, so profiles restored from iCloud come back without them. Hours, properties and settings come back in full.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("restore.photosNote")
                    }
                }
                .listRowBackground(colors.backgroundSecondary)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.action)
                }
            }
            .sheet(item: $pendingSwitch) { profile in
                ProfileSwitchConfirmSheet(
                    title: "Switch to this profile?",
                    message: "Your current data stays on this iPhone. You can come back to it from Restore other data.",
                    onConfirm: {
                        pendingSwitch = nil
                        onRestore(profile)
                    },
                    onCancel: { pendingSwitch = nil }
                )
            }
        }
    }
}

private struct ProfileCandidateRow: View {
    let profile: DiscoveredProfile

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 26))
                .foregroundStyle(colors.textSecondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(countsLine)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .monospacedDigit()
                Label(sourceLine, systemImage: profile.sources.contains(.iCloud) ? "icloud" : "iphone")
                    .font(.footnote)
                    .foregroundStyle(colors.informational)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var countsLine: String {
        var parts: [String] = []
        parts.append(profile.entryCount == 1 ? "1 entry" : "\(profile.entryCount) entries")
        if profile.propertyCount > 0 {
            parts.append(profile.propertyCount == 1 ? "1 property" : "\(profile.propertyCount) properties")
        }
        if let last = profile.lastEntryDate {
            parts.append("last \(last.formatted(.dateTime.month(.abbreviated).day().year()))")
        }
        return parts.joined(separator: " · ")
    }

    private var sourceLine: String {
        switch (profile.sources.contains(.device), profile.sources.contains(.iCloud)) {
        case (true, true): return "On this iPhone and in iCloud"
        case (true, false): return "On this iPhone"
        default: return "In iCloud"
        }
    }
}

// MARK: - Settings › Account (switch profile / sign out / delete)

struct SettingsAccountSection: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var signInManager = AppleSignInManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showSwitchConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showICloudOffPrompt = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var isAppleProfile: Bool { signInManager.loginType == .apple }
    private var deleteTitle: String { isAppleProfile ? "Delete Account and Data" : "Delete All Data" }

    var body: some View {
        Section {
            if isAppleProfile {
                Button {
                    viewModel.signOut()
                } label: {
                    SettingRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign Out")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.signOut")
            } else {
                Button {
                    showSwitchConfirm = true
                } label: {
                    SettingRow(symbol: "arrow.left.arrow.right", title: "Switch Profile", subtitle: "Open other data or start fresh")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.switchProfile")
                .sheet(isPresented: $showSwitchConfirm) {
                    ProfileSwitchConfirmSheet(
                        title: "Switch profile?",
                        message: "Your data stays on this iPhone. Open it again anytime with Restore earlier data.",
                        onConfirm: {
                            showSwitchConfirm = false
                            viewModel.signOut()
                        },
                        onCancel: { showSwitchConfirm = false }
                    )
                }
            }

            Button {
                showDeleteConfirm = true
            } label: {
                SettingRow(
                    symbol: "trash",
                    title: isDeleting ? "Deleting…" : deleteTitle,
                    subtitle: isAppleProfile
                        ? "Permanently remove this account and its records"
                        : "Permanently remove this profile's records",
                    isDestructive: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityIdentifier("settings.deleteData")
            .alert("\(deleteTitle)?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { runDelete(allowLocalOnly: false) }
            } message: {
                Text("This permanently deletes this profile's properties, time entries, photos, categories, goals and tax profile from this iPhone and from iCloud. This cannot be undone.")
            }
            .alert("iCloud is off", isPresented: $showICloudOffPrompt) {
                Button("Cancel", role: .cancel) { }
                Button("Delete from This iPhone", role: .destructive) { runDelete(allowLocalOnly: true) }
            } message: {
                Text("Copies saved in iCloud can't be removed right now. Delete from this iPhone anyway, or turn on iCloud and try again.")
            }
            .alert("Couldn't Delete", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        } header: {
            BPSectionHeader(title: "Account")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    private func runDelete(allowLocalOnly: Bool) {
        Task {
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await viewModel.deleteAccountAndData(allowLocalOnly: allowLocalOnly)
            } catch AppViewModel.ProfileDeletionError.iCloudUnavailable {
                showICloudOffPrompt = true
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }
}

// MARK: - Switch confirmation (custom so the primary action uses the action tokens)

/// A system alert tints its default button with system blue under white text (2.50:1 in
/// dark mode), so the switch confirmation is a small sheet with the brand's primary button.
struct ProfileSwitchConfirmSheet: View {
    let title: String
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.action)
                .frame(width: 52, height: 52)
                .background(Circle().fill(colors.actionSurface))
                .padding(.top, 22)
                .accessibilityHidden(true)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Switch", action: onConfirm)
                .buttonStyle(InboxPrimaryButtonStyle())
                .padding(.top, 6)
                .accessibilityIdentifier("switchConfirm.switch")

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("switchConfirm.cancel")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .presentationBackground(colors.backgroundSecondary)
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
    }
}
