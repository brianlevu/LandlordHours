import SwiftUI

// MARK: - Restore sheet (welcome screen + Settings)
//
// Sandbox `S2Restore` (spec §5, frames restore / restore-confirm): a sheet with a glass close,
// the plain promise, and one card of earlier profiles, each with an initial seal. From Settings a
// tap asks "Open these records?" first; from Welcome it opens straight away. Nothing is merged or
// deleted either way.

struct ProfileRestoreSheet: View {
    enum Context {
        case welcome
        case settings
    }

    let profiles: [DiscoveredProfile]
    let context: Context
    /// iCloud could not be searched: say so, with a way to try again.
    var cloudProblem = false
    var isRetrying = false
    var onRetry: (() -> Void)?
    let onRestore: (DiscoveredProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingSwitch: DiscoveredProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if context == .welcome { Text("Your earlier records") } else { Text("Your other records") }
                    }
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel(Text("Close"))
                    .accessibilityIdentifier("restore.close")
                }

                Group {
                    if context == .welcome {
                        Text("Records from before, on this iPhone or in iCloud. Pick one to open it. Nothing is merged or deleted.")
                    } else {
                        Text("Other records on this iPhone or in iCloud. Yours stay put, and you can switch back any time.")
                    }
                }
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if cloudProblem {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Couldn’t reach iCloud. Check you’re signed in to iCloud and try again.")
                            .font(.body)
                            .foregroundStyle(colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("restore.cloudError")
                        if let onRetry {
                            Button(action: onRetry) {
                                Text(isRetrying ? "Trying again…" : "Try again")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColors.onAction)
                                    .padding(.horizontal, 20)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(colors.action))
                            }
                            .buttonStyle(.lhPressable)
                            .disabled(isRetrying)
                            .accessibilityIdentifier("restore.tryAgain")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppCornerRadius.medium).fill(colors.cautionSurface))
                }

                if profiles.isEmpty && !cloudProblem {
                    Text("We didn’t find any earlier records.")
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("restore.empty")
                }

                if !profiles.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        Button {
                            if context == .settings {
                                pendingSwitch = profile
                            } else {
                                onRestore(profile)
                            }
                        } label: {
                            ProfileCandidateRow(profile: profile, palette: Self.palette(at: index))
                        }
                        .buttonStyle(.lhPressable)
                        .accessibilityIdentifier("restore.profile.\(profile.id)")
                        if index < profiles.count - 1 { PropertyInsetDivider(leading: 68) }
                    }
                }
                .propertyCard()
                }

                if profiles.contains(where: \.isICloudOnly) {
                    Text("Photos weren’t saved to iCloud, so records restored from iCloud come back without them. Hours, properties and settings come back in full.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("restore.photosNote")
                }
            }
            .padding(20)
        }
        .background(colors.background.ignoresSafeArea())
        .presentationBackground(colors.background)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize || profiles.count > 3 ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("restore.sheet")
        .alert("Open these records?", isPresented: Binding(
            get: { pendingSwitch != nil },
            set: { if !$0 { pendingSwitch = nil } }
        ), presenting: pendingSwitch) { profile in
            Button("Cancel", role: .cancel) { pendingSwitch = nil }
            Button("Open") {
                pendingSwitch = nil
                onRestore(profile)
            }
        } message: { profile in
            Text("You’ll see the records for \(profile.displayLabel). Your own records stay put, and you can switch back from Settings.")
        }
    }

    /// Seals cycle through the identity palette that isn't blueprint (blueprint is the action).
    static func palette(at index: Int) -> SealPalette {
        let cycle: [SealPalette] = [.slate, .brass, .timber, .terracotta]
        return cycle[index % cycle.count]
    }
}

private struct ProfileCandidateRow: View {
    let profile: DiscoveredProfile
    let palette: SealPalette

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            PropertySeal(monogram: initial, palette: palette, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                // An email sits on its own line and loses its middle if it is too long; words
                // wrap at word boundaries. Nothing breaks mid-word.
                Text(verbatim: profile.displayLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(profile.displayLabel.contains("@") ? 1 : 3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                countsLine
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if profile.isICloudOnly {
                    Text("In iCloud")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var initial: String {
        let letter = profile.displayLabel.first { $0.isLetter || $0.isNumber }
        return letter.map { String($0).uppercased() } ?? "?"
    }

    private var entries: String {
        profile.entryCount == 1 ? String(localized: "1 entry") : String(localized: "\(profile.entryCount) entries")
    }

    private var propertiesPart: String {
        profile.propertyCount == 1 ? String(localized: "1 property") : String(localized: "\(profile.propertyCount) properties")
    }

    private var lastDate: String? {
        guard let last = profile.lastEntryDate else { return nil }
        let sameYear = Calendar.current.isDate(last, equalTo: Date(), toGranularity: .year)
        return sameYear
            ? last.formatted(.dateTime.month(.abbreviated).day())
            : last.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// One localized format per shape, so translators can reorder the parts.
    private var countsLine: Text {
        switch (profile.propertyCount > 0, lastDate) {
        case (true, let date?): return Text("\(entries) · \(propertiesPart) · last \(date)")
        case (true, nil): return Text("\(entries) · \(propertiesPart)")
        case (false, let date?): return Text("\(entries) · last \(date)")
        case (false, nil): return Text(verbatim: entries)
        }
    }
}

// MARK: - Settings › Account (switch profile / sign out / delete)

struct SettingsAccountSection: View {
    /// Pushes the hold-to-delete page (`DeleteAllDataView`), which owns the deletion and its alerts.
    var onDeleteData: () -> Void = {}

    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var signInManager = AppleSignInManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showSwitchConfirm = false

    private var isAppleProfile: Bool { signInManager.loginType == .apple }

    var body: some View {
        Section {
            if isAppleProfile {
                Button {
                    viewModel.signOut()
                } label: {
                    SettingRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out")
                }
                .buttonStyle(.plain)
                .longTailRow()
                .accessibilityIdentifier("settings.signOut")
            } else {
                Button {
                    showSwitchConfirm = true
                } label: {
                    SettingRow(symbol: "arrow.left.arrow.right", title: "Switch profile", subtitle: "Open other data or start fresh")
                }
                .buttonStyle(.plain)
                .longTailRow()
                .accessibilityIdentifier("settings.switchProfile")
                .sheet(isPresented: $showSwitchConfirm) {
                    ProfileSwitchConfirmSheet(
                        title: "Switch profile?",
                        message: "Your records stay on this iPhone. Open them again anytime with Restore earlier records.",
                        onConfirm: {
                            showSwitchConfirm = false
                            viewModel.signOut()
                        },
                        onCancel: { showSwitchConfirm = false }
                    )
                }
            }

            Button {
                onDeleteData()
            } label: {
                SettingRow(
                    symbol: "trash",
                    title: isAppleProfile ? "Delete account and data" : "Delete all data",
                    subtitle: isAppleProfile
                        ? "Remove this account and everything in it"
                        : "Remove everything in this profile",
                    showsChevron: true,
                    isDestructive: true
                )
            }
            .buttonStyle(.plain)
            .longTailRow()
            .accessibilityIdentifier("settings.deleteData")
        } header: {
            BPSectionHeader(title: "Account")
        }
        .listRowBackground(colors.backgroundSecondary)
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
                .buttonStyle(LHButton.primary)
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
