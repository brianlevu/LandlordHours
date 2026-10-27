import SwiftUI

// MARK: - Delete all data (v2)
//
// A pushed page that says exactly what goes, then a destructive-outline capsule the person holds
// for 1.5s. Letting go snaps back in 200ms. VoiceOver gets a custom action that asks with a standard
// alert, the one place the app uses `.alert` for an irreversible act (standard §1.21: a title of six
// words or fewer, verbs for buttons, the destructive role set). Cancel is always on screen.
// Deletion runs through `AppViewModel.deleteAccountAndData` (App Review 5.1.1(v)); the iCloud-off
// question is the second alert, and a failure shows as a line on the page, not an "OK" alert.
// Afterwards the app is signed out, so the root shows Welcome. Package K changes the two call
// sites (`isAppleProfile`, `deleteAccountAndData`); the page does not change.

struct DeleteAllDataView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var signInManager = AppleSignInManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static let holdDuration: Double = 1.5

    @State private var showExport = false
    @State private var showVoiceOverConfirm = false
    @State private var showICloudOffPrompt = false
    @State private var isDeleting = HoldToDeleteButton.debugShowsDeleting
    @State private var deleteError: String? = Self.debugFailure

    private var isAppleProfile: Bool { signInManager.loginType == .apple }

    private var photoCount: Int {
        viewModel.timeEntries.reduce(0) { $0 + $1.attachments.filter { $0.mimeType.hasPrefix("image") }.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LongTailHeader(
                    title: isAppleProfile
                        ? HS.t("delete.title.account", "Delete account and data")
                        : HS.t("delete.title", "Delete all data"),
                    style: .detail,
                    back: (label: HS.t("common.back", "Back"), identifier: "delete.back", action: { dismiss() })
                )

                Text(HS.t("delete.subtitle", "This removes everything from this iPhone and iCloud:"))
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)

                LHRowGroup {
                    item("house", propertiesText)
                    LHDivider(leadingInset: LHRow.browseDividerInset)
                    item("list.bullet.rectangle", entriesText)
                    LHDivider(leadingInset: LHRow.browseDividerInset)
                    item("photo", photosText)
                    LHDivider(leadingInset: LHRow.browseDividerInset)
                    item("target", HS.t("delete.item.goal", "Your goal and filing details"))
                    if isAppleProfile {
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        item("person.crop.circle", HS.t("delete.item.account", "Your account"))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("delete.items")

                Text(HS.t("delete.undone", "This can’t be undone."))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)

                if subscriptionManager.isPro {
                    Button { showExport = true } label: {
                        Label(HS.t("delete.export", "Export a copy first"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(LHButton.secondary)
                    .disabled(isDeleting)
                    .accessibilityIdentifier("delete.export")
                }

                if let deleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(colors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("delete.error")
                }

                VStack(spacing: 4) {
                    HoldToDeleteButton(isDeleting: isDeleting, onComplete: { runDelete(allowLocalOnly: false) }) {
                        showVoiceOverConfirm = true
                    }
                    .padding(.bottom, 4)
                    if !isDeleting {
                        Text(HS.t("delete.hold.hint", "Hold for a moment to confirm."))
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Button(HS.t("delete.cancel", "Cancel")) { dismiss() }
                        .buttonStyle(LHButton.tertiary)
                        .accessibilityIdentifier("delete.cancel")
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .accessibilityIdentifier("delete.screen")
        .sheet(isPresented: $showExport) {
            ExportPDFView(year: Calendar.current.component(.year, from: Date()))
        }
        .alert(HS.t("delete.alert.title", "Delete everything?"), isPresented: $showVoiceOverConfirm) {
            Button(HS.t("delete.alert.keep", "Keep"), role: .cancel) { }
            Button(HS.t("delete.alert.delete", "Delete"), role: .destructive) { runDelete(allowLocalOnly: false) }
        } message: {
            Text(HS.t("delete.alert.message", "This removes everything from this iPhone and iCloud. This can’t be undone."))
        }
        .alert(HS.t("delete.icloud.title", "iCloud is off"), isPresented: $showICloudOffPrompt) {
            Button(HS.t("delete.alert.keep", "Keep"), role: .cancel) { }
            Button(HS.t("delete.icloud.delete", "Delete from this iPhone"), role: .destructive) { runDelete(allowLocalOnly: true) }
        } message: {
            Text(HS.t("delete.icloud.message", "Copies saved in iCloud can’t be removed right now. Delete from this iPhone anyway, or turn on iCloud and try again."))
        }
    }

    // MARK: Counted items (one key per plural form so each reads right in every language)

    private var propertiesText: String {
        let n = viewModel.properties.count
        if n == 0 { return HS.t("delete.rentals.zero", "No rentals") }
        if n == 1 { return HS.t("delete.rentals.one", "1 rental") }
        return HS.f("delete.rentals.many", "%lld rentals", n)
    }

    private var entriesText: String {
        let n = viewModel.timeEntries.count
        if n == 0 { return HS.t("delete.records.zero", "No records") }
        if n == 1 { return HS.t("delete.records.one", "1 record") }
        return HS.f("delete.records.many", "%lld records", n)
    }

    private var photosText: String {
        let n = photoCount
        if n == 0 { return HS.t("delete.photos.zero", "No receipt photos") }
        if n == 1 { return HS.t("delete.photos.one", "1 receipt photo") }
        return HS.f("delete.photos.many", "%lld receipt photos", n)
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        LHRow.Browse(title: text, systemImage: symbol, tint: .neutral, showsChevron: false)
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
        deleteError = nil
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
            if isDeleting { Text(HS.t("delete.hold.deleting", "Deleting…")) } else { Text(HS.t("delete.hold.label", "Hold to delete everything")) }
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
        .accessibilityLabel(Text(HS.t("delete.hold.a11y", "Delete everything")))
        .accessibilityHint(Text(HS.t("delete.hold.hint", "Hold for a moment to confirm.")))
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
