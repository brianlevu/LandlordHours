import SwiftUI

// MARK: - Delete all data (2.0)
//
// Sandbox `S2DeleteAll` (spec §5, frames delete-hold / delete-hold-mid): a pushed page that says
// exactly what goes, then a destructive-outline capsule the person holds for 1.5s. Letting go
// snaps back in 200ms. VoiceOver gets a custom action that asks with a standard alert. Cancel is
// always on screen. Deletion runs through `AppViewModel.deleteAllData` (App Review
// 5.1.1(v)); its iCloud-off and failure alerts are kept as the error states. Afterwards the app
// is a new install (package K: the whole iCloud zone goes), so the root shows Welcome.

struct DeleteAllDataView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static let holdDuration: Double = 1.5

    @State private var showExport = false
    @State private var showVoiceOverConfirm = false
    @State private var showICloudOffPrompt = false
    @State private var isDeleting = HoldToDeleteButton.debugShowsDeleting
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 24
    @State private var deleteError: String? = Self.debugFailure

    /// Package K: there is no account any more (Sign in with Apple is removed in 2.2).
    private var isAppleProfile: Bool { false }

    private var photoCount: Int {
        viewModel.timeEntries.reduce(0) { $0 + $1.attachments.filter { $0.mimeType.hasPrefix("image") }.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("This removes everything from this iPhone and iCloud:")
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    item("house") { propertiesText }
                    PropertyInsetDivider(leading: 28 + iconColumn)
                    item("list.bullet.rectangle") { entriesText }
                    PropertyInsetDivider(leading: 28 + iconColumn)
                    item("photo") { photosText }
                    PropertyInsetDivider(leading: 28 + iconColumn)
                    item("target") { Text("Your goal and tax details") }
                    if isAppleProfile {
                        PropertyInsetDivider(leading: 28 + iconColumn)
                        item("person.crop.circle") { Text("Your account") }
                    }
                }
                .propertyCard()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("delete.items")

                Text(String(localized: "Delete on your other devices too, or they will offer to put the records back.", table: "Identity"))
                    .font(.subheadline).foregroundStyle(colors.textSecondary)
                Text("This can’t be undone.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)

                if subscriptionManager.isPro {
                    Button { showExport = true } label: {
                        Label("Export a copy first", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PropertyTintedButtonStyle())
                    .disabled(isDeleting)
                    .accessibilityIdentifier("delete.export")
                }

                HoldToDeleteButton(isDeleting: isDeleting, onComplete: { runDelete(allowLocalOnly: false) }) {
                    showVoiceOverConfirm = true
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text("Hold for a moment to confirm.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.action)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.lhPressable)
                    .accessibilityIdentifier("delete.cancel")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(colors.background.ignoresSafeArea())
        // Solid canvas bar: scrolled content (the blueprint hero) never meets the clock.
        .toolbarBackground(colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(isAppleProfile ? "Delete account and data" : "Delete all data")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .accessibilityIdentifier("delete.screen")
        .sheet(isPresented: $showExport) {
            ExportPDFView(year: Calendar.current.component(.year, from: Date()))
        }
        .alert("Delete everything?", isPresented: $showVoiceOverConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { runDelete(allowLocalOnly: false) }
        } message: {
            Text("This removes everything from this iPhone and iCloud. This can’t be undone.")
        }
        .alert("iCloud is off", isPresented: $showICloudOffPrompt) {
            Button("Cancel", role: .cancel) { }
            Button("Delete from this iPhone", role: .destructive) { runDelete(allowLocalOnly: true) }
        } message: {
            Text("Copies saved in iCloud can’t be removed right now. Delete from this iPhone anyway, or turn on iCloud and try again.")
        }
        .alert("Couldn’t delete", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: Counted items (Text literals so each plural reads right and goes through the catalog)

    @ViewBuilder private var propertiesText: some View {
        let n = viewModel.properties.count
        if n == 0 { Text("No properties") } else if n == 1 { Text("1 property") } else { Text("\(n) properties") }
    }

    @ViewBuilder private var entriesText: some View {
        let n = viewModel.timeEntries.count
        if n == 0 { Text("No entries") } else if n == 1 { Text("1 entry") } else { Text("\(n) entries") }
    }

    @ViewBuilder private var photosText: some View {
        let n = photoCount
        if n == 0 { Text("No receipt photos") } else if n == 1 { Text("1 receipt photo") } else { Text("\(n) receipt photos") }
    }

    private func item<Label: View>(_ symbol: String, @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            label()
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// DEBUG: `-LHDeleteFailurePreview` opens on the honest failure (iCloud lost mid-delete) for
    /// the visual gate. Nothing is deleted.
    private static var debugFailure: String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHDeleteFailurePreview") {
            return CloudKitSyncService.AccountDeleteICloudUnreachableError().localizedDescription
        }
        #endif
        return nil
    }

    private func runDelete(allowLocalOnly: Bool) {
        guard !isDeleting else { return }
        Task {
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await viewModel.deleteAllData(allowLocalOnly: allowLocalOnly)
            } catch AppViewModel.ProfileDeletionError.iCloudUnavailable {
                showICloudOffPrompt = true
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }
}

// MARK: - Hold to delete

/// 52pt destructive-outline capsule. Holding fills it left to right over 1.5s (linear) with a
/// rigid haptic at the start and the end; letting go early snaps back over 200ms.
struct HoldToDeleteButton: View {
    let isDeleting: Bool
    let onComplete: () -> Void
    let onAccessibilityConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = Self.frozenProgress
    @State private var holding = false
    @State private var completed = false
    @State private var startTick = 0
    @State private var doneTick = 0
    @State private var pendingFinish: DispatchWorkItem?

    init(isDeleting: Bool, onComplete: @escaping () -> Void, onAccessibilityConfirm: @escaping () -> Void) {
        self.isDeleting = isDeleting
        self.onComplete = onComplete
        self.onAccessibilityConfirm = onAccessibilityConfirm
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let label = Group {
            if isDeleting { Text("Deleting…") } else { Text("Hold to delete everything") }
        }
        .font(.body.weight(.semibold))
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)

        ZStack {
            Capsule().fill(colors.backgroundSecondary)
            label.foregroundStyle(colors.destructive)
            // The fill is a mask over a filled copy, so the words never move while it grows.
            ZStack {
                Capsule().fill(colors.destructive)
                label.foregroundStyle(colors.onAction)
            }
            .mask(alignment: .leading) {
                GeometryReader { g in Rectangle().frame(width: g.size.width * progress) }
            }
        }
        .overlay(Capsule().strokeBorder(colors.destructive, lineWidth: 1.5))
        .frame(minHeight: 52)
        .fixedSize(horizontal: false, vertical: true)
        .scaleEffect(holding && !reduceMotion ? 0.98 : 1)
        .contentShape(Capsule())
        // No dimming while deleting: the label must keep AA on the full fill.
        .onLongPressGesture(minimumDuration: DeleteAllDataView.holdDuration, maximumDistance: 40) {
            finishHold()
        } onPressingChanged: { pressing in
            guard !isDeleting else { return }
            withAnimation(AppAnimation.feedback) { holding = pressing }
            pendingFinish?.cancel()
            if pressing {
                completed = false
                startTick += 1
                withAnimation(.linear(duration: DeleteAllDataView.holdDuration)) { progress = 1 }
                // The fill and the deletion share one clock: finish when the fill does, even if
                // the gesture's own completion arrives late or not at all.
                let work = DispatchWorkItem { finishHold() }
                pendingFinish = work
                DispatchQueue.main.asyncAfter(deadline: .now() + DeleteAllDataView.holdDuration, execute: work)
            } else {
                // The perform closure lands just after the press ends: wait a beat before
                // snapping back so a finished hold stays full.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if !completed { withAnimation(.easeOut(duration: 0.2)) { progress = 0 } }
                }
            }
        }
        .onChange(of: isDeleting) { _, deleting in
            if !deleting {
                completed = false
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: startTick)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: doneTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Delete everything"))
        .accessibilityHint(Text("Hold for a moment to confirm."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAccessibilityConfirm() }
        .accessibilityIdentifier("delete.hold")
    }

    private func finishHold() {
        guard !isDeleting, !completed else { return }
        pendingFinish?.cancel()
        pendingFinish = nil
        completed = true
        doneTick += 1
        progress = 1
        onComplete()
    }

    /// DEBUG: a finished hold (`-LHDeleteHoldPreview 1`) shows the page as it is right after the
    /// hold completes: full fill, "Deleting…". Nothing is deleted.
    static var debugShowsDeleting: Bool { frozenProgress >= 1 }

    /// DEBUG: a still mid-hold frame for the visual gate (`-LHDeleteHoldPreview 0.55`).
    static var frozenProgress: CGFloat {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHDeleteHoldPreview"), args.indices.contains(i + 1),
           let v = Double(args[i + 1]) { return CGFloat(min(1, max(0, v))) }
        #endif
        return 0
    }
}
