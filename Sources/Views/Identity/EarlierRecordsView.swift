import SwiftUI

// MARK: - Earlier records: the safety net (P14–P19, P26, P30)
//
// Everything the merge could not place on its own: a held set waiting for an answer, a set kept
// aside, records removed elsewhere or inferred
// (Put back), records waiting on the bulk answer. Rows carry no buttons (§1.1): the row opens a
// dialog with its actions. A failed iCloud search is shown here, never hidden (diagnosis §7.1).

struct EarlierRecordsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var acting: ArchivedGroup?
    @State private var deleting: ArchivedGroup?
    @State private var answering: ArchivedGroup?
    @State private var showBulk = false
    @State private var showRemoved = false

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let identity = viewModel.identity
        List {
            Section {
            } header: {
                Text(String(localized: "Records from an earlier version, another device or another sign-in. Add them to yours, or delete them. Nothing changes until you choose.", table: "Identity"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .textCase(nil)
            }
            if identity.searchFailed {
                Section {
                    LHRow.Browse(title: String(localized: "Couldn’t search iCloud", table: "Identity"),
                                 meta: String(localized: "Earlier records in iCloud may be missing here.", table: "Identity"),
                                 value: String(localized: "Try again", table: "Identity"), systemImage: "exclamationmark.icloud", tint: .caution) {
                        viewModel.syncNow()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(colors.backgroundSecondary)
                    .accessibilityIdentifier("earlier.searchFailed")
                }
            }
            if let hold = identity.bulkHold {
                Section {
                    LHRow.Browse(title: String(localized: "\(IdentityCopy.hours(hold.heldHours)) waiting for your answer about iCloud", table: "Identity"),
                                 meta: String(localized: "Answer now", table: "Identity"), systemImage: "exclamationmark.icloud", tint: .caution) {
                        showBulk = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(colors.backgroundSecondary)
                    .accessibilityIdentifier("earlier.bulk")
                }
            }
            let groups = identity.archivedGroups
            if !groups.isEmpty || !identity.settingsOnlyGroups.isEmpty {
                Section {
                    ForEach(groups) { group in
                        groupRow(group)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(colors.backgroundSecondary)
                    }
                    ForEach(identity.settingsOnlyGroups) { group in
                        LHRow.Browse(title: String(localized: "Settings only, no hours", table: "Identity"),
                                     meta: IdentityCopy.groupSource(group.source), systemImage: "slider.horizontal.3", tint: .neutral,
                                     showsChevron: false)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(colors.backgroundSecondary)
                            .accessibilityIdentifier("earlier.settingsOnly")
                    }
                }
            }
            if !identity.removed.isEmpty {
                Section {
                    LHRow.Browse(title: String(localized: "Recently removed", table: "Identity"), meta: removedMeta,
                                 value: "\(identity.removed.count)", systemImage: "arrow.uturn.backward", tint: .neutral) {
                        showRemoved = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(colors.backgroundSecondary)
                    .accessibilityIdentifier("earlier.recentlyRemoved")
                }
            }
            if groups.isEmpty && identity.removed.isEmpty && identity.bulkHold == nil && !identity.searchFailed {
                Section {
                    LHEmptyState(systemImage: "checkmark.icloud", headline: String(localized: "Nothing waiting", table: "Identity"),
                                 message: String(localized: "Everything you tracked is in one place.", table: "Identity"))
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle(String(localized: "Earlier records", table: "Identity"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(acting.map(dialogTitle) ?? "", isPresented: Binding(get: { acting != nil }, set: { if !$0 { acting = nil } }),
                            titleVisibility: .visible, presenting: acting) { group in
            actions(for: group)
        }
        .alert(String(localized: "Delete these records?", table: "Identity"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { group in
            Button(String(localized: "Delete", table: "Identity"), role: .destructive) {
                Task { await viewModel.identity.deleteGroup(group.id) }
            }
            Button(String(localized: "Keep", table: "Identity"), role: .cancel) {}
        } message: { _ in
            Text(String(localized: "They go from iCloud and this iPhone. This can’t be undone.", table: "Identity"))
        }
        .sheet(item: $answering) { group in
            MergeQuestionSheet(group: group).environmentObject(viewModel)
        }
        .sheet(isPresented: $showBulk) { BulkAbsenceSheet().environmentObject(viewModel) }
        .navigationDestination(isPresented: $showRemoved) { RecentlyRemovedView() }
        .onAppear { viewModel.identity.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("earlier.list")
    }

    private var removedMeta: String {
        let hours = viewModel.identity.removed.reduce(0) { $0 + $1.hours }
        return String(localized: "\(IdentityCopy.hours(hours)) you can put back", table: "Identity")
    }

    private func groupRow(_ group: ArchivedGroup) -> some View {
        let summary = IdentityCopy.groupSummary(hours: group.hours, rentals: group.properties.count, last: group.lastEntryDate)
        let meta: String
        let glyph: String
        switch group.status {
        case .pending:
            meta = String(localized: "Waiting for your answer", table: "Identity")
            glyph = "questionmark.circle"
        case .notNeeded:
            meta = String(localized: "\(IdentityCopy.groupSource(group.source)) · Only custom categories", table: "Identity")
            glyph = "tag"
        default:
            meta = String(localized: "\(IdentityCopy.groupSource(group.source)) · Kept aside", table: "Identity")
            glyph = "tray"
        }
        return LHRow.Browse(title: summary, meta: meta, systemImage: glyph, tint: group.status == .pending ? .caution : .neutral) {
            if group.status == .pending { viewModel.identity.questionDeferred = true; answering = group } else { acting = group }
        }
        .accessibilityIdentifier("earlier.group.\(group.status.rawValue)")
    }

    private func dialogTitle(_ group: ArchivedGroup) -> String {
        IdentityCopy.groupSummary(hours: group.hours, rentals: group.properties.count, last: group.lastEntryDate)
    }

    @ViewBuilder private func actions(for group: ArchivedGroup) -> some View {
        switch group.status {
        default:
            Button(String(localized: "Add to my records", table: "Identity")) {
                // This page asks; the app-level host stays quiet so one sheet shows, after the
                // dialog has finished closing.
                viewModel.identity.questionDeferred = true
                viewModel.identity.reconsider(group: group.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    answering = viewModel.identity.earlier.group(group.id)
                }
            }
            Button(String(localized: "Delete", table: "Identity"), role: .destructive) { deleting = group }
        }
        Button(String(localized: "Cancel", table: "Identity"), role: .cancel) {}
    }
}

/// P18: removed records, newest first. A row opens "Put back"; removals the app inferred stay
/// until you act, deletes made on another device stay 30 days.
struct RecentlyRemovedView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: RemovedRecord?

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let removed = RemovedRecord.newestFirst(viewModel.identity.removed)
        List {
            Section {
                ForEach(removed) { item in
                    LHRow.Browse(title: title(item), meta: meta(item), value: item.entry.map { LHFormat.hours($0.hours) },
                                 systemImage: item.property != nil ? "house" : "clock", tint: .neutral, showsChevron: false) {
                        selected = item
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(colors.backgroundSecondary)
                }
            } footer: {
                if removed.count > 1 {
                    Button(String(localized: "Put back all", table: "Identity")) {
                        viewModel.putBack(Set(removed.map(\.name)))
                    }
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("removed.putBackAll")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle(String(localized: "Recently removed", table: "Identity"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(selected.map(title) ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
                            titleVisibility: .visible, presenting: selected) { item in
            Button(String(localized: "Put back", table: "Identity")) { viewModel.putBack([item.name]) }
            Button(String(localized: "Cancel", table: "Identity"), role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("removed.list")
    }

    private func title(_ item: RemovedRecord) -> String {
        if let property = item.property { return property.name }
        if let entry = item.entry {
            let rental = viewModel.properties.first { $0.id == entry.propertyId }?.name ?? String(localized: "No rental", table: "Identity")
            return String(localized: "\(rental) · \(IdentityCopy.shortDate(entry.date))", table: "Identity")
        }
        return item.category?.name ?? item.name
    }

    private func meta(_ item: RemovedRecord) -> String {
        switch item.reason {
        case .deletedElsewhere:
            return item.keepUntil.map { String(localized: "Removed on another device. Kept until \(IdentityCopy.shortDate($0)).", table: "Identity") }
                ?? String(localized: "Removed on another device.", table: "Identity")
        case .deletedHere:
            return item.keepUntil.map { String(localized: "Deleted on this iPhone. Kept until \(IdentityCopy.shortDate($0)).", table: "Identity") }
                ?? String(localized: "Deleted on this iPhone.", table: "Identity")
        case .inferredAbsent, .bulkRemoved:
            return String(localized: "Not in iCloud anymore. Kept until you choose.", table: "Identity")
        case .replacedByNewer:
            return item.keepUntil.map { String(localized: "Changed on another device after you edited it here. Your version is kept until \(IdentityCopy.shortDate($0)).", table: "Identity") }
                ?? String(localized: "Changed on another device after you edited it here.", table: "Identity")
        }
    }
}
