import SwiftUI

/// The Inbox tab: detected work waiting for a yes or no. Nothing here counts until confirmed.
/// docs/design/2.0-hifi-reference-spec.md §b, ported to the Blueprint brand (blueprint-r6 frames).
struct InboxView: View {
    @ObservedObject var model: InboxViewModel
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSetup = false
    @State private var logTick = 0
    @State private var dismissTick = 0
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if model.visible.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background { LHMobileCanvas() }
            .navigationBarHidden(true)
        }
        .sheet(item: $model.sheetSuggestion) { suggestion in
            SuggestionConfirmSheet(suggestion: suggestion, model: model)
        }
        .sheet(isPresented: $showSetup, onDismiss: { model.reload() }) {
            CaptureSetupFlow(mode: .whatsNew, environment: .current) { _ in
                showSetup = false
            }
            .environmentObject(viewModel)
        }
        .sensoryFeedback(.success, trigger: logTick)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
        .onAppear { model.reload() }
        .onDisappear { model.commitPending() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.commitPending() }
            if phase == .active { model.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in
            if model.pendingAction == nil { model.reload() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.screen")
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                titleRow
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if model.backfillCount > 0 {
                    backfillBanner
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { suggestion in
                        row(suggestion)
                    }
                } header: {
                    Text(section.group.title)
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.3)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.list")
    }

    private var titleRow: some View {
        Text("Inbox")
            .lhDisplayFont(.largeTitle)
            .foregroundStyle(colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ suggestion: Suggestion) -> some View {
        let propertyName = model.propertyName(for: suggestion)
        let badges = model.badges(for: suggestion)
        let quick = model.canQuickLog(suggestion)
        return Button {
            model.sheetSuggestion = suggestion
        } label: {
            SuggestionRowView(suggestion: suggestion, propertyName: propertyName, badges: badges)
        }
        .buttonStyle(.plain)
        .listRowBackground(colors.backgroundSecondary)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 74 }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                swipeLog(suggestion)
            } label: {
                Label(quick ? "Log" : "Review", systemImage: quick ? "checkmark" : "square.and.pencil")
            }
            .tint(Color(hex: AppColors.Hex.positive))
            .accessibilityIdentifier("inbox.swipe.log")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                dismiss(suggestion)
            } label: {
                Label("Not work", systemImage: "xmark")
            }
            .tint(Color(hex: AppColors.Hex.textSecondary))
            .accessibilityIdentifier("inbox.swipe.dismiss")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SuggestionRowView.accessibilityLabel(for: suggestion, propertyName: propertyName, badges: badges, now: Date()))
        .accessibilityHint("Opens the details to confirm")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: quick ? "Log \(InboxFormat.hours(suggestion.proposedHours ?? 0))" : "Review and log") {
            swipeLog(suggestion)
        }
        .accessibilityAction(named: "Not landlord work") { dismiss(suggestion) }
        .accessibilityIdentifier("inbox.row.\(suggestion.sourceKey)")
    }

    private func swipeLog(_ suggestion: Suggestion) {
        if model.swipeLog(suggestion) == .logged {
            logTick += 1
            UIAccessibility.post(notification: .announcement, argument: "Logged. Undo is available.")
        }
    }

    private func dismiss(_ suggestion: Suggestion) {
        model.dismiss(suggestion)
        dismissTick += 1
        UIAccessibility.post(notification: .announcement, argument: "Marked not landlord work. Undo is available.")
    }

    // MARK: Banner

    private var backfillBanner: some View {
        let count = model.backfillCount
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                CategoryToolTile(category: .repairs, size: 44)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -12, y: 10)
                CategoryToolTile(category: .leasing, size: 44)
                    .rotationEffect(.degrees(6))
                    .offset(x: 14, y: -10)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(count == 1 ? "1 thing from the last 90 days" : "\(count) things from the last 90 days")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OnBlueprint.primary)
                Text("Confirm the ones that were work and they go up on the house.")
                    .font(.subheadline)
                    .foregroundStyle(OnBlueprint.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(InboxBlueprintPaper())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.backfillBanner")
    }

    // MARK: Empty

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                VStack(spacing: 12) {
                    InboxEmptyArt()
                        .padding(.bottom, 8)
                    Text("Nothing waiting")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(model.store != nil && viewModel.calendarSuggestionsEnabled
                         ? "We'll put work here when your calendar looks like rental work. Nothing counts until you say so."
                         : "Turn on calendar suggestions and we'll put likely rental work here for you to confirm.")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !viewModel.calendarSuggestionsEnabled {
                        Button("Find rental work in my calendar") { showSetup = true }
                            .buttonStyle(InboxPrimaryButtonStyle())
                            .padding(.top, 12)
                            .accessibilityIdentifier("inbox.empty.setup")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 72)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 96)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.empty")
    }
}

/// "Logged 2h · Undo". Shown by the shell just above the floating tab bar (the tab bar draws
/// over tab content, so the toast can't live inside the Inbox's own safe area).
struct InboxUndoToast: View {
    let action: InboxPendingAction
    var onUndo: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.isLog ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(action.isLog ? colors.positive : colors.textSecondary)
                .accessibilityHidden(true)
            Text(action.message(defaultHours: nil))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.action)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("inbox.undo")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 52)
        .background(
            Capsule()
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 16, y: 4)
        )
        .overlay(Capsule().strokeBorder(colors.border.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.toast")
    }
}

extension InboxPendingAction {
    var isLog: Bool {
        if case .log = self { return true }
        return false
    }
}
