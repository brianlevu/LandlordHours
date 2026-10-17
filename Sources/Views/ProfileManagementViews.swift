import SwiftUI
import LucideIcons

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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context == .welcome ? "Restore earlier data" : "Restore other data")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text(context == .welcome
                             ? "Pick a profile to open its records. Nothing is merged or deleted."
                             : "Open another profile's records. Your current data stays on this iPhone, and you can switch back anytime.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(profiles) { profile in
                        Button {
                            if context == .settings {
                                pendingSwitch = profile
                            } else {
                                onRestore(profile)
                            }
                        } label: {
                            ProfileCandidateCard(profile: profile)
                        }
                        .buttonStyle(.lhPressable)
                        .accessibilityIdentifier("restore.profile.\(profile.id)")
                    }

                    if profiles.contains(where: \.isICloudOnly) {
                        HStack(alignment: .top, spacing: 8) {
                            LucideIcon(image: Lucide.info, size: 14)
                                .foregroundStyle(colors.informational)
                                .padding(.top, 2)
                            Text("Photos weren't saved to iCloud, so profiles restored from iCloud come back without them. Hours, properties and settings come back in full.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("restore.photosNote")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
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

private struct ProfileCandidateCard: View {
    let profile: DiscoveredProfile

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            LucideIcon(image: Lucide.userRound, size: 20)
                .foregroundStyle(colors.action)
                .frame(width: 42, height: 42)
                .background(colors.actionSurface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(countsLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .monospacedDigit()
                Text(sourceLine)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.informationalText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(colors.informationalSurface)
                    .clipShape(Capsule())
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            LucideIcon(image: Lucide.chevronRight, size: 14)
                .foregroundStyle(colors.textTertiary)
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .strokeBorder(colors.border.opacity(colorScheme == .dark ? 0.42 : 0.28), lineWidth: 1)
        }
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
        case (true, true): return "On this iPhone + iCloud"
        case (true, false): return "On this iPhone"
        default: return "In iCloud"
        }
    }
}

// MARK: - Settings › Account › Restore other data

/// Visible whenever discovery finds an inactive earlier profile — for local and
/// Apple-ID profiles alike. Picking one switches to it (no merge in 1.1).
struct SettingsProfileRestoreRow: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var profiles: [DiscoveredProfile] = []
    @State private var showSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if !profiles.isEmpty {
                Divider().background(colors.border.opacity(0.35))

                Button {
                    showSheet = true
                } label: {
                    SettingRow(
                        icon: Lucide.history,
                        iconColor: AppColors.action,
                        iconWash: colors.actionSurface,
                        title: "Restore other data",
                        subtitle: profiles.count == 1
                            ? "1 earlier profile on this iPhone or in iCloud"
                            : "\(profiles.count) earlier profiles on this iPhone or in iCloud"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.restoreOtherData")
            }
        }
        .task(id: viewModel.isSignedIn) {
            profiles = await viewModel.discoverRestorableProfiles()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-LHOpenRestoreSheet"), !profiles.isEmpty {
                showSheet = true
            }
            #endif
        }
        .sheet(isPresented: $showSheet) {
            ProfileRestoreSheet(profiles: profiles, context: .settings) { profile in
                showSheet = false
                viewModel.switchToProfile(profile)
                Task { profiles = await viewModel.discoverRestorableProfiles() }
            }
        }
    }
}

// MARK: - Settings › Support & Legal › Switch profile / Sign out / Delete

struct SettingsProfileExitRows: View {
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
        VStack(spacing: 0) {
            Divider().background(colors.border.opacity(0.35))

            if isAppleProfile {
                Button {
                    viewModel.signOut()
                } label: {
                    SettingRow(
                        icon: Lucide.logOut,
                        iconColor: AppColors.coral,
                        iconWash: colors.destructiveSurface,
                        title: "Sign Out",
                        showChevron: false,
                        isDanger: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.signOut")
            } else {
                Button {
                    showSwitchConfirm = true
                } label: {
                    SettingRow(
                        icon: Lucide.arrowLeftRight,
                        iconColor: AppColors.action,
                        iconWash: colors.actionSurface,
                        title: "Switch Profile",
                        subtitle: "Open other data or start fresh",
                        showChevron: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.switchProfile")
            }

            Divider().background(colors.border.opacity(0.35))

            Button {
                showDeleteConfirm = true
            } label: {
                SettingRow(
                    icon: Lucide.trash2,
                    iconColor: AppColors.coral,
                    iconWash: colors.destructiveSurface,
                    title: isDeleting ? "Deleting..." : deleteTitle,
                    subtitle: isAppleProfile
                        ? "Permanently remove this account and records"
                        : "Permanently remove this profile's records",
                    showChevron: false,
                    isDanger: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityIdentifier("settings.deleteData")
        }
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
/// dark mode), so the switch confirmation is a small sheet with a violet primary button.
struct ProfileSwitchConfirmSheet: View {
    let title: String
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 14) {
            LucideIcon(image: Lucide.arrowLeftRight, size: 22)
                .foregroundStyle(colors.actionText)
                .frame(width: 48, height: 48)
                .background(colors.actionSurface)
                .clipShape(Circle())
                .padding(.top, 22)

            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onConfirm) {
                Text("Switch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(colors.action)
                    .foregroundStyle(colors.onAction)
                    .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
            .padding(.top, 6)
            .accessibilityIdentifier("switchConfirm.switch")

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("switchConfirm.cancel")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .presentationBackground(colors.backgroundSecondary)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }
}
