import SwiftUI
import UIKit

// MARK: - Settings › iCloud & records (hosted by H's SettingsView)
//
// Replaces Account, Switch profile, Sign out and Restore (§1.6). One grouped container of
// `LHRow.Browse` rows: the iCloud status (P7 / P8 / P9, restricted), Sync now or Turn on iCloud,
// Earlier records (count and "1 waiting for your answer"; also when the iCloud search failed),
// Your name, Advanced, Delete all data (P20). Footer: where records live.

struct ICloudRecordsSection: View {
    /// Opens one of Settings' pushed screens (Settings owns the one destination, §1.25): plain
    /// button rows with the shared `LHChevron`, never a List `NavigationLink` and its grey chevron.
    var onOpen: (SettingsRoute) -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var sync: CloudKitSyncService
    @ObservedObject private var identity: IdentityCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    init(viewModel: AppViewModel, onOpen: @escaping (SettingsRoute) -> Void) {
        self.onOpen = onOpen
        _sync = ObservedObject(wrappedValue: viewModel.syncService)
        _identity = ObservedObject(wrappedValue: viewModel.identity)
    }

    /// A `List` section (the system draws the grouped card and the hairlines).
    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Section {
            ICloudStatusRow(showsChevron: true) { onOpen(.icloud) }
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("settings.icloud.status")
            if identity.status == .off || identity.status == .restricted {
                LHRow.Browse(title: String(localized: "Turn on iCloud for Dormer", table: "Identity"),
                             meta: String(localized: "Opens iPhone Settings", table: "Identity"), systemImage: "gearshape", tint: .neutral) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("settings.icloud.turnOn")
            } else {
                LHRow.Browse(title: String(localized: "Sync now", table: "Identity"), meta: syncMeta,
                             systemImage: "arrow.triangle.2.circlepath", tint: .action, showsChevron: false) {
                    viewModel.syncNow()
                }
                .disabled(identity.status == .syncing)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("settings.syncNow")
            }
            if identity.earlierCount > 0 || identity.searchFailed || identity.bulkHold != nil {
                LHRow.Browse(title: String(localized: "Earlier records", table: "Identity"), meta: earlierMeta,
                             value: identity.earlierCount > 0 && !typeSize.isAccessibilitySize ? "\(identity.earlierCount)" : nil,
                             systemImage: "clock.arrow.circlepath",
                             tint: identity.waitingCount > 0 || identity.searchFailed ? .caution : .neutral,
                             action: { onOpen(.earlierRecords) })
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("settings.earlierRecords")
            }
            YourNameRow()
                .listRowInsets(EdgeInsets())
            LHRow.Browse(title: String(localized: "Delete all data", table: "Identity"),
                         meta: deleteMeta, systemImage: "trash", tint: .caution, action: { onOpen(.deleteData) })
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("settings.deleteData")
        } header: {
            LHSectionHeader(String(localized: "iCloud & records", table: "Identity"))
                .textCase(nil)
                .accessibilityIdentifier("settings.icloudRecords")
        } footer: {
            Text(IdentityCopy.footer)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .listRowBackground(colors.backgroundSecondary)
        .onAppear { identity.refresh(sync: sync) }
        .onChange(of: sync.isSyncing) { _, _ in identity.updateStatus(sync) }
        .onChange(of: sync.accountState) { _, _ in identity.updateStatus(sync) }
        .onChange(of: sync.lastSyncDate) { _, _ in identity.updateStatus(sync) }
    }

    private var syncMeta: String {
        if identity.status == .syncing { return String(localized: "Syncing…", table: "Identity") }
        return String(localized: "Send and get the latest", table: "Identity")
    }

    private var earlierMeta: String {
        if identity.searchFailed { return String(localized: "Couldn’t search iCloud", table: "Identity") }
        let waiting = identity.waitingCount
        if waiting == 1 { return String(localized: "1 waiting for your answer", table: "Identity") }
        if waiting > 1 { return String(localized: "\(waiting) waiting for your answer", table: "Identity") }
        return String(localized: "Nothing waiting", table: "Identity")
    }

    private var deleteMeta: String {
        identity.status == .off
            ? String(localized: "Everything on this iPhone", table: "Identity")
            : String(localized: "This iPhone and your iCloud", table: "Identity")
    }
}

/// The status row (P7 / P8 / P9 / restricted). Tapping opens Settings › iCloud & records › details.
struct ICloudStatusRow: View {
    var showsChevron = true
    var onTap: () -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let status = viewModel.identity.status
        // At accessibility sizes a trailing value squeezes the text column to a few points and
        // interleaves with the wrapped meta (gate K 1.1 B1), so the value leads the meta line instead.
        let ax = typeSize.isAccessibilitySize
        let metaLine = ax ? String(localized: "\(value(status)). \(meta(status))", table: "Identity") : meta(status)
        LHRow.Browse(title: String(localized: "iCloud", table: "Identity"), meta: metaLine, value: ax ? nil : value(status),
                     systemImage: glyph(status), tint: tint(status), showsChevron: showsChevron, action: showsChevron ? onTap : nil)
            .accessibilityIdentifier("settings.icloud.status")
    }

    private func value(_ s: ICloudRecordsStatus) -> String {
        switch s {
        case .on, .syncing: return String(localized: "On", table: "Identity")
        case .off, .restricted: return String(localized: "Off", table: "Identity")
        case .problem: return String(localized: "Couldn’t sync", table: "Identity")
        }
    }

    private func meta(_ s: ICloudRecordsStatus) -> String {
        switch s {
        case .on(let date): return IdentityCopy.lastSynced(date)
        case .syncing: return String(localized: "Syncing…", table: "Identity")
        case .off: return String(localized: "Only on this iPhone", table: "Identity")
        case .restricted: return String(localized: "Can’t be used for sync", table: "Identity")
        case .problem: return String(localized: "Safe on this iPhone", table: "Identity")
        }
    }

    private func glyph(_ s: ICloudRecordsStatus) -> String {
        switch s {
        case .on, .syncing: return "icloud"
        case .off, .restricted: return "icloud.slash"
        case .problem: return "exclamationmark.icloud"
        }
    }

    private func tint(_ s: ICloudRecordsStatus) -> LHRowGlyph.Tint {
        switch s {
        case .on, .syncing: return .action
        case .off, .restricted: return .neutral
        case .problem: return .caution
        }
    }
}

/// Settings › iCloud & records › iCloud: the status in full, the error with Try again (P9),
/// and Advanced (export the migration backup, "N records couldn't be read", setup answers kept).
struct ICloudRecordsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let identity = viewModel.identity
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LHRowGroup {
                    ICloudStatusRow(showsChevron: false) {}
                    if case .problem(let text, let last) = identity.status {
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(colors.textPrimary)
                                .accessibilityIdentifier("icloud.problem")
                            Text(String(localized: "Last synced: \(last.map { IdentityCopy.shortDate($0) } ?? String(localized: "never", table: "Identity")).", table: "Identity"))
                                .font(.subheadline)
                                .foregroundStyle(colors.textSecondary)
                            Button(String(localized: "Try again", table: "Identity")) { viewModel.syncNow() }
                                .buttonStyle(LHButton.secondary)
                                .accessibilityIdentifier("icloud.tryAgain")
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    LHSectionHeader(String(localized: "Advanced", table: "Identity"))
                    LHRowGroup {
                        if let url = identity.backupURL {
                            ShareLink(item: url) {
                                LHRow.Browse(title: String(localized: "Export the update backup", table: "Identity"),
                                             meta: String(localized: "What this iPhone held before", table: "Identity"),
                                             systemImage: "square.and.arrow.up", tint: .neutral, showsChevron: false) {}
                            }
                            .accessibilityIdentifier("icloud.exportBackup")
                            LHDivider(leadingInset: LHRow.browseDividerInset)
                        }
                        // "Kept and tried again" only when something couldn't be read: under "Every record
                        // could be read" it contradicted the title (the problem state shows this row too).
                        LHRow.Browse(title: unreadTitle(identity.unparsedCount),
                                     meta: identity.unparsedCount > 0
                                        ? String(localized: "They’re kept and will be tried again.", table: "Identity")
                                        : nil,
                                     systemImage: "doc.questionmark", tint: .neutral, showsChevron: false)
                            .accessibilityIdentifier("icloud.unparsed")
                        if let kept = identity.discardedSettings {
                            LHDivider(leadingInset: LHRow.browseDividerInset)
                            LHRow.Browse(title: String(localized: "Setup answers not used", table: "Identity"),
                                         meta: String(localized: "From \(IdentityCopy.shortDate(kept.at)). Your earlier settings were kept.", table: "Identity"),
                                         systemImage: "slider.horizontal.3", tint: .neutral, showsChevron: false)
                                .accessibilityIdentifier("icloud.discardedSettings")
                        }
                    }
                }
                Text(IdentityCopy.footer)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
        }
        .background(colors.background)
        .lhTabScreen(String(localized: "iCloud", table: "Identity"), back: LHBackAction(identifier: "icloud.back") { dismiss() })
        .hidesAppTabBar()
        .onAppear { identity.refresh(sync: viewModel.syncService) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("icloud.detail")
    }

    private func unreadTitle(_ n: Int) -> String {
        switch n {
        case 0: return String(localized: "Every record in iCloud could be read", table: "Identity")
        case 1: return String(localized: "1 record in iCloud couldn’t be read", table: "Identity")
        default: return String(localized: "\(n) records in iCloud couldn’t be read", table: "Identity")
        }
    }
}
