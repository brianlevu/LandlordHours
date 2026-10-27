import SwiftUI
import PhotosUI

// MARK: - Settings
//
// Flighty's plain inset-grouped list on the Blueprint canvas: who you are and your plan on top,
// then Auto-capture (what the app may read, and the promise that nothing counts until you
// confirm), tax setup, records, the app, data and privacy, support, and the account exits.
// docs/design/2.0-hifi-reference-spec.md §j.

struct SettingsView: View {
    #if DEBUG
    @MainActor private static var didApplyDebugRoute = false
    #endif
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var appleSignIn = AppleSignInManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showingProfileEdit = false
    @State private var paywall: ProPaywallRequest?
    @State private var showExport = false
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var profileImage: Data?
    @State private var restoreStatusMessage: String?
    @State private var restorableProfiles: [DiscoveredProfile] = []
    @State private var restoreCloudProblem = false
    @State private var restoreRetrying = false
    @State private var showRestoreSheet = false
    @State private var route: SettingsRoute?
    /// Backs the "Share anonymous usage data" toggle. Stores whether the user opted OUT (default
    /// `false`, i.e. shared/opted-in by default) directly against `Analytics.optOutKey` so this
    /// view and `Analytics` always read the same UserDefaults value.
    @AppStorage(Analytics.optOutKey) private var analyticsOptedOut = false
    #if DEBUG
    @State private var showDeveloperTools = false
    @State private var showEngagementLab = false
    #endif

    /// Presents the opt-out state as an opt-IN toggle ("Share…") while writing straight through
    /// to `Analytics.setOptOut`, so the SDK is updated the moment the user flips it.
    private var shareAnalyticsBinding: Binding<Bool> {
        Binding(
            get: { !analyticsOptedOut },
            set: { isSharing in
                analyticsOptedOut = !isSharing
                Analytics.setOptOut(analyticsOptedOut)
            }
        )
    }

    private var displayName: String {
        appleSignIn.fullName ?? (viewModel.userName.isEmpty ? "Your name" : viewModel.userName)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        BPBackToTodayButton()
                        BPScreenTitle(text: "Settings")
                    }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                profileSection
                planSection
                AutoCaptureSettingsSection(onOpenMuted: { route = .muted })
                taxSection
                recordsSection
                appSection
                privacySection
                supportSection
                SettingsAccountSection(onDeleteData: { route = .deleteData })

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        NotTaxAdviceNote()
                        Text("LandlordHours · \(AppVersionInfo.display())")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("settings.version")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                #if DEBUG
                if AdminAccess.isCurrentUserAdmin {
                    developerToolsSection
                }
                #endif
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 104, for: .scrollContent)
            .contentMargins(.horizontal, LHMetrics.gutter, for: .scrollContent)
            .background { LHMobileCanvas() }
            .navigationBarHidden(true)
            .navigationDestination(item: $route) { route in
                switch route {
                case .taxProfile: TaxProfileView()
                case .learningCenter: LearningCenterView()
                case .contactSupport: ContactSupportView()
                case .muted: MutedSuggestionsView()
                case .deleteData: DeleteAllDataView()
                }
            }
            .sheet(isPresented: $showingProfileEdit) {
                ProfileEditView(userName: $userName, userEmail: $userEmail, profileImage: $profileImage)
            }
            .proPaywall($paywall)
            .sheet(isPresented: $showExport) {
                ExportPDFView(year: Calendar.current.component(.year, from: Date()))
            }
            .sheet(isPresented: $showRestoreSheet) {
                ProfileRestoreSheet(
                    profiles: restorableProfiles, context: .settings,
                    cloudProblem: restoreCloudProblem, isRetrying: restoreRetrying,
                    onRetry: {
                        Task {
                            restoreRetrying = true
                            let found = await viewModel.discoverRestorable()
                            restorableProfiles = found.profiles
                            restoreCloudProblem = found.cloudProblem
                            restoreRetrying = false
                        }
                    }
                ) { profile in
                    showRestoreSheet = false
                    viewModel.switchToProfile(profile)
                    Task { restorableProfiles = await viewModel.discoverRestorableProfiles() }
                }
            }
            .task(id: viewModel.isSignedIn) {
                #if DEBUG
                // Before the profile discovery below, which can wait on iCloud for a long time on
                // a signed-in device. `.task` re-runs when Settings reappears after a pop, so the
                // page opens once per launch.
                if !Self.didApplyDebugRoute {
                    if ProcessInfo.processInfo.arguments.contains("-LHOpenDeleteData") {
                        Self.didApplyDebugRoute = true
                        route = .deleteData
                    } else if ProcessInfo.processInfo.arguments.contains("-LHOpenLearningCenterFromSettings") {
                        Self.didApplyDebugRoute = true
                        route = .learningCenter
                    }
                }
                #endif
                let found = await viewModel.discoverRestorable()
                restorableProfiles = found.profiles
                restoreCloudProblem = found.cloudProblem
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-LHOpenRestoreSheet"), !restorableProfiles.isEmpty {
                    showRestoreSheet = true
                }
                #endif
            }
            #if DEBUG
            .navigationDestination(isPresented: $showEngagementLab) {
                EngagementLabView()
            }
            .onAppear {
                guard ProcessInfo.processInfo.arguments.contains("-LHOpenEngagementLab") else { return }
                DispatchQueue.main.async {
                    showEngagementLab = true
                }
            }
            #endif
        }
        .accessibilityIdentifier("settings.screen")
    }

    // MARK: Profile

    private var profileSection: some View {
        Section {
            Button {
                userName = appleSignIn.fullName ?? viewModel.userName
                userEmail = appleSignIn.email ?? ""
                profileImage = appleSignIn.profileImageData
                showingProfileEdit = true
            } label: {
                HStack(spacing: 14) {
                    ProfileAvatar(name: displayName, imageData: profileImage ?? appleSignIn.profileImageData, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        if let email = appleSignIn.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(colors.textSecondary)
                                // Never cut at AX: the whole address wraps (owner ruling 2026-10-27).
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .truncationMode(.middle)
                        }
                        planBadge
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize { LHChevron() }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your name, email and photo")
            .accessibilityIdentifier("settings.profile")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    private var planBadge: some View {
        let isPro = subscriptionManager.isPro
        return Text(isPro ? "Pro · Paid once" : "Free plan")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isPro ? colors.positive : colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(isPro ? colors.positiveSurface : colors.backgroundTertiary))
    }

    // MARK: Plan

    private var planSection: some View {
        Section {
            if ProGate.isLocked(.settingsPro, isPro: subscriptionManager.isPro) {
                proCard
                LockedPreview(
                    size: .row,
                    entry: .settingsExport,
                    line: ProGate.lockLine(.settingsExport),
                    keeps: ProGate.keepsLine(.settingsExport),
                    rowInset: 0,
                    onUnlock: {
                        paywall = ProPaywallRequest(context: .export, entry: .settingsExport, onUnlocked: { showExport = true })
                    }
                ) {
                    SettingRow(symbol: "square.and.arrow.up", title: "Export reports", subtitle: "PDF and CSV for your accountant", showsChevron: true)
                        .padding(.vertical, 8)
                }
            } else {
                SettingRow(
                    symbol: "checkmark.seal",
                    title: "Pro is active",
                    subtitle: "Paid once. Exports and every rental are unlocked."
                )
                .accessibilityIdentifier("settings.proActive")
            }

            Button {
                Task {
                    restoreStatusMessage = nil
                    await subscriptionManager.restorePurchases()
                    restoreStatusMessage = subscriptionManager.hasPurchased
                        ? String(localized: "Your Pro purchase has been restored.")
                        : (subscriptionManager.restoreFailureMessage ?? subscriptionManager.purchaseError ?? String(localized: "No previous purchase was found."))
                }
            } label: {
                // The result shows inline under the row (not a system alert, whose message text
                // iOS draws below AA); the row stays tappable to try again.
                SettingRow(
                    symbol: "arrow.clockwise",
                    title: subscriptionManager.isLoading ? "Restoring purchase…" : "Restore purchase",
                    subtitle: subscriptionManager.isLoading ? nil : restoreStatusMessage
                )
            }
            .buttonStyle(.plain)
            .disabled(subscriptionManager.isLoading)
            .accessibilityIdentifier("settings.restorePurchase")

            if !restorableProfiles.isEmpty {
                Button {
                    showRestoreSheet = true
                } label: {
                    SettingRow(
                        symbol: "clock.arrow.circlepath",
                        title: "Restore other data",
                        subtitle: restorableProfiles.count == 1
                            ? "1 earlier profile on this iPhone or in iCloud"
                            : "\(restorableProfiles.count) earlier profiles on this iPhone or in iCloud",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.restoreOtherData")
            }
        } header: {
            BPSectionHeader(title: "Plan")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    /// Not a lock: a plain card at the top of the plan section (redesign-specs §1b).
    private var proCard: some View {
        // At accessibility sizes the button drops under the text so "See Pro" never truncates.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Image(systemName: "house.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(InboxBlueprintPaper(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // The product name never breaks or hyphenates: one line, scaled down if needed.
                Text("LandlordHours\u{00A0}Pro")
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Group {
                    if let price = subscriptionManager.proDisplayPrice {
                        Text("Pay once, \(price)")
                    } else {
                        Text("Pay once")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Button("See Pro") {
                paywall = ProPaywallRequest(context: .settings, entry: .settingsPro)
            }
            .buttonStyle(ProTintedButtonStyle())
            .fixedSize()
            .accessibilityIdentifier("settings.proCard")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .onAppear { Analytics.lockPreviewShown(entry: .settingsPro) }
    }

    // MARK: Tax setup

    private var taxSection: some View {
        Section {
            Button {
                route = .taxProfile
            } label: {
                SettingRow(symbol: "doc.text", title: "Tax profile", subtitle: "Filing, goal, spouse hours, the 50% rule", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.taxProfile")

            Button {
                route = .learningCenter
            } label: {
                SettingRow(symbol: "book", title: "Learning center", subtitle: "REPS, rentals and records, in plain words", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.learningCenter")
        } header: {
            BPSectionHeader(title: "Tax setup")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    // MARK: Records

    private var recordsSection: some View {
        Section {
            // Free users get Export as the `.row` lock under the Pro card (WP-P): one route each.
            if !ProGate.isExportLocked(isPro: subscriptionManager.isPro) {
                Button {
                    showExport = true
                } label: {
                    SettingRow(symbol: "square.and.arrow.up", title: "Export reports", subtitle: "PDF and CSV for your accountant", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.exportReports")
            }

            Button {
                viewModel.syncNow()
            } label: {
                SettingRow(
                    symbol: syncNeedsAttention ? "exclamationmark.icloud" : "icloud",
                    title: "Sync now",
                    subtitle: syncSubtitle ?? "Back up your records to iCloud"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.syncNow")
        } header: {
            BPSectionHeader(title: "Records")
        } footer: {
            Text("Photos attached to records stay on this iPhone. They aren’t included in iCloud sync.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("settings.photoStorageDisclosure")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    // MARK: App

    private var appSection: some View {
        Section {
            AppearancePreferenceRow(appearanceManager: appearanceManager)
                .accessibilityIdentifier("settings.appearance")

            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                SettingRow(symbol: "bell", title: "Notification permission", subtitle: "Opens iOS Settings", showsChevron: true)
            }
            .buttonStyle(.plain)
        } header: {
            BPSectionHeader(title: "App")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    // MARK: Data and privacy

    private var privacySection: some View {
        Section {
            SettingToggleRow(
                symbol: "chart.bar.xaxis",
                title: "Share anonymous usage data",
                subtitle: "Signals like \u{201C}a record was saved\u{201D}. Never your notes, properties or personal data.",
                isOn: shareAnalyticsBinding
            )
            .accessibilityIdentifier("settings.analyticsOptOut")

            Button {
                if let url = URL(string: "https://www.altaiventures.co/landlord-hours/terms") {
                    UIApplication.shared.open(url)
                }
            } label: {
                SettingRow(symbol: "hand.raised", title: "Terms and privacy", showsChevron: true)
            }
            .buttonStyle(.plain)
        } header: {
            BPSectionHeader(title: "Data and privacy")
        } footer: {
            Text("Your records live on this iPhone and in your own iCloud. We never see them.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("settings.analyticsOptOutCaption")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    // MARK: Support

    private var supportSection: some View {
        Section {
            Button {
                route = .contactSupport
            } label: {
                SettingRow(symbol: "envelope", title: "Contact support", subtitle: "Questions about tracking, exports or setup", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.contactSupport")
        } header: {
            BPSectionHeader(title: "Support")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    // MARK: Helpers

    private var syncNeedsAttention: Bool {
        !viewModel.syncService.isSyncing && !viewModel.syncService.isRunningInitialSync
            && (!viewModel.syncService.accountAvailable || viewModel.syncService.syncError != nil)
    }

    private var syncSubtitle: String? {
        if viewModel.syncService.isSyncing || viewModel.syncService.isRunningInitialSync { return "Syncing…" }
        if !viewModel.syncService.accountAvailable { return "iCloud sync is off. Your records are safe on this iPhone." }
        if viewModel.syncService.syncError != nil { return "Couldn’t sync just now. Your records are safe on this iPhone." }
        if let date = viewModel.syncService.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last sync: \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        return nil
    }

    #if DEBUG
    private var developerToolsSection: some View {
        Section {
            Button {
                if reduceMotion { showDeveloperTools.toggle() } else { withAnimation(AppAnimation.smooth) { showDeveloperTools.toggle() } }
            } label: {
                SettingRow(symbol: "hammer", title: "Developer tools", subtitle: "Mock data and debug-only Pro controls", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showDeveloperTools ? "Expanded" : "Collapsed")
            if showDeveloperTools {
                Button {
                    subscriptionManager.unlockPro()
                } label: {
                    SettingRow(symbol: "checkmark.seal", title: subscriptionManager.hasPurchased ? "Pro unlocked for this build" : "Unlock Pro for testing")
                }
                .buttonStyle(.plain)

                Button {
                    showEngagementLab = true
                } label: {
                    SettingRow(symbol: "bell.badge", title: "Engagement Lab", subtitle: "Notifications, widgets, Live Activities and Siri", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.engagementLab")

                ForEach(AppViewModel.MockDataScenario.allCases) { scenario in
                    Button {
                        if reduceMotion {
                            viewModel.applyMockScenario(scenario)
                        } else {
                            withAnimation(AppAnimation.smooth) { viewModel.applyMockScenario(scenario) }
                        }
                    } label: {
                        SettingRow(symbol: "tray.and.arrow.down", title: scenario.title, subtitle: scenario.subtitle, value: "Seed", valueColor: colors.action)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listRowBackground(colors.backgroundSecondary)
    }
    #endif
}

// MARK: - Avatar

struct ProfileAvatar: View {
    let name: String
    let imageData: Data?
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var colorScheme

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty || name == "Your name" ? "" : letters
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(colors.actionSurface)
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(colors.action)
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.action)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Auto-capture

/// What the app may read and when it may ask. Both switches start off; turning the calendar on
/// asks for access, turning prompts on asks for notification permission. Mutes live one level in.
/// Settings' pushed screens. Buttons + one destination (not NavigationLinks in the List), so
/// each row is a plain button for VoiceOver and UI tests, with its own chevron.
enum SettingsRoute: Hashable {
    case taxProfile, learningCenter, contactSupport, muted, deleteData
}

private struct AutoCaptureSettingsSection: View {
    var onOpenMuted: () -> Void = {}
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var calendarOn = CaptureOptIn.calendarSuggestionsEnabled()
    @State private var promptsOn = EventPromptsConsent.isEnabled()
    @State private var muteCount = 0
    @State private var blockedMessage: String?
    @State private var isAsking = false

    @State private var pccOn = PCCSettings().isEnabled

    /// Must stay true to the code: calendar titles only ever reach the on-device model
    /// (ClassifierChain); a Log time note goes to the on-device model first and to Private
    /// Cloud Compute only when the phone's model can't answer and the toggle below is on
    /// (NoteReaderChain + PCCGate). Nothing is saved until the user taps Log.
    /// PCC is offered (toggle + disclosure) only on iOS 27 in a build that carries the PCC
    /// entitlement (PCCEntitlement). Otherwise notes never leave the phone, and the copy says so.
    static var offersPCC: Bool {
        guard #available(iOS 27.0, *) else { return false }
        #if DEBUG
        // Captures of the entitled variant only; the gate itself never reads this.
        if ProcessInfo.processInfo.arguments.contains("-LHShowPCCSetting") { return true }
        #endif
        return PCCEntitlement.isConfigured
    }

    static var aiDisclosure: String { offersPCC ? aiDisclosureWithPCC : aiDisclosureOnDevice }

    static let aiDisclosureWithPCC = String(localized: "settings.capture.aiDisclosure.pcc", defaultValue: "Apple\u{2019}s on-device model reads your calendar suggestions and Log time notes. If it can\u{2019}t, Private Cloud Compute may read a note instead (turn that off above). Apple keeps nothing, and we never see it.", table: "Foundations")

    static let aiDisclosureOnDevice = "Calendar suggestions and the notes you type or say in Log time are read by Apple\u{2019}s on-device model, on your iPhone, to fill in the form. Nothing goes to us or anyone else, and nothing is saved until you tap Log."

    static let pccSubtitle = String(localized: "settings.capture.pcc.subtitle", defaultValue: "Used only if your iPhone can\u{2019}t read a note. Apple keeps nothing, and we never see it.", table: "Foundations")

    var body: some View {
        Section {
            SettingToggleRow(
                symbol: "calendar",
                title: "Calendar",
                subtitle: "Suggest work from your events. Titles are read on your iPhone.",
                isOn: Binding(get: { calendarOn }, set: { setCalendar($0) })
            )
            .disabled(isAsking)
            .accessibilityIdentifier("settings.capture.calendar")

            SettingToggleRow(
                symbol: "bell.badge",
                title: "Ask when an event ends",
                subtitle: calendarOn ? "At most twice a day, never after 9 pm." : "Turn on Calendar first.",
                isOn: Binding(get: { promptsOn }, set: { setPrompts($0) })
            )
            .disabled(!calendarOn || isAsking || UserScope.userId == nil)
            .accessibilityIdentifier("settings.capture.prompts")

            if Self.offersPCC {
                SettingToggleRow(
                    symbol: "lock.icloud",
                    title: "Private Cloud Compute",
                    subtitle: Self.pccSubtitle,
                    isOn: Binding(get: { pccOn }, set: { on in
                        pccOn = on
                        PCCSettings().isEnabled = on
                    })
                )
                .accessibilityIdentifier("settings.capture.pcc")
            }

            Button(action: onOpenMuted) {
                SettingRow(
                    symbol: "speaker.slash",
                    title: "Muted",
                    subtitle: "Things you asked us to stop suggesting",
                    value: muteCount == 0 ? "None" : "\(muteCount)",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.capture.muted")

            if let blockedMessage {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label(blockedMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens iOS Settings")
                .accessibilityIdentifier("settings.capture.blocked")
            }
        } header: {
            BPSectionHeader(title: "Auto-capture")
        } footer: {
            // Both sentences share one text column beside the shield, so the second one no
            // longer starts back under the glyph.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(colors.draftingInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.aiDisclosure)
                        .accessibilityIdentifier("settings.capture.aiDisclosure")
                    Text("Nothing goes in your record until you confirm it.")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(colors.textSecondary)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(colors.backgroundSecondary)
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func reload() {
        calendarOn = CaptureOptIn.calendarSuggestionsEnabled()
        promptsOn = EventPromptsConsent.isEnabled()
        pccOn = PCCSettings().isEnabled
        muteCount = AppModelHost.shared.suggestionStore?.muteRules.count ?? 0
    }

    private func setCalendar(_ on: Bool) {
        blockedMessage = nil
        if !on {
            calendarOn = false
            CaptureOptIn.setCalendarSuggestionsEnabled(false)
            if promptsOn { setPrompts(false) }
            return
        }
        isAsking = true
        Task { @MainActor in
            defer { isAsking = false }
            let access = await CaptureSetupEnvironment.current.requestCalendar()
            if access == .fullAccess {
                CaptureOptIn.setCalendarSuggestionsEnabled(true)
                calendarOn = true
                NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
            } else {
                calendarOn = false
                blockedMessage = access == .limited
                    ? "LandlordHours can only add events. Allow Full Access in iOS Settings to get suggestions."
                    : "Calendar access is off for LandlordHours. Turn it on in iOS Settings."
            }
        }
    }

    private func setPrompts(_ on: Bool) {
        blockedMessage = nil
        if !on {
            promptsOn = false
            viewModel.eventPromptsEnabled = false
            return
        }
        isAsking = true
        Task { @MainActor in
            defer { isAsking = false }
            let allowed = await CaptureSetupEnvironment.current.requestNotifications()
            if allowed {
                viewModel.eventPromptsEnabled = true
                // Show what was actually stored (nothing is saved without an active profile).
                promptsOn = viewModel.eventPromptsEnabled
            } else {
                promptsOn = false
                blockedMessage = "Notifications are off for LandlordHours. Turn them on in iOS Settings."
            }
        }
    }
}

/// The mute rules the user set from the Inbox ("stop suggesting things like this").
struct MutedSuggestionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var rules: [CaptureMuteRule] = []

    var body: some View {
        List {
            if rules.isEmpty {
                Section {
                    BPEmptyState(
                        symbol: "speaker.slash",
                        title: "Nothing muted",
                        message: "When you tell the Inbox to stop suggesting something, it shows up here."
                    )
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(rules) { rule in
                        SettingRow(
                            symbol: rule.match == .titleContains ? "text.magnifyingglass" : "calendar",
                            title: rule.match == .titleContains ? "Titles with \u{201C}\(rule.value)\u{201D}" : "Events from one calendar",
                            subtitle: "Muted \(rule.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))"
                        )
                        .swipeActions {
                            Button("Unmute", role: .destructive) { remove(rule) }
                        }
                        .accessibilityAction(named: "Unmute") { remove(rule) }
                    }
                } footer: {
                    Text("Swipe left to unmute. Muted things are never suggested again until you unmute them.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
                .listRowBackground(colors.backgroundSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle("Muted")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .onAppear { rules = AppModelHost.shared.suggestionStore?.muteRules ?? [] }
        .accessibilityIdentifier("settings.muted.screen")
    }

    private func remove(_ rule: CaptureMuteRule) {
        AppModelHost.shared.suggestionStore?.removeMuteRule(id: rule.id)
        rules = AppModelHost.shared.suggestionStore?.muteRules ?? []
        NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
    }
}

// MARK: - Appearance

private struct AppearancePreferenceRow: View {
    @ObservedObject var appearanceManager: AppearanceManager

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedTick = 0
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance", subtitle: "Follow your iPhone or pick a theme")
            HStack(spacing: 8) {
                ForEach(AppAppearancePreference.allCases) { preference in
                    appearanceButton(preference)
                }
            }
            Label(appearanceManager.preference.confirmationText, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .labelStyle(SavedLabelStyle(tint: colors.positive))
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: savedTick)
    }

    private func appearanceButton(_ preference: AppAppearancePreference) -> some View {
        let isSelected = appearanceManager.preference == preference
        return Button {
            guard appearanceManager.preference != preference else { return }
            if reduceMotion {
                appearanceManager.preference = preference
            } else {
                withAnimation(AppAnimation.quick) { appearanceManager.preference = preference }
            }
            savedTick += 1
        } label: {
            Label(preference.displayName, systemImage: symbol(for: preference))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? colors.onAction : colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(isSelected ? colors.action : colors.backgroundTertiary))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : colors.border, lineWidth: 1))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("\(preference.displayName) appearance")
        .accessibilityHint(preference.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbol(for preference: AppAppearancePreference) -> String {
        switch preference {
        case .system: return "iphone"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

private struct SavedLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

// MARK: - Not tax advice

/// Plain disclaimer at the foot of Settings. The PDF export carries its own version.
struct NotTaxAdviceNote: View {
    static let text = "LandlordHours keeps your records. It doesn’t give tax advice. Ask a tax professional what your hours mean for you."

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(Self.text)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.notTaxAdvice")
    }
}

// MARK: - Tax Profile View

struct TaxProfileView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showWorkHoursInput = false
    @State private var showParticipationConfirmation = false
    @State private var showAddProperty = false
    @State private var workHoursText = ""
    @State private var newPropertyName = ""
    @State private var newPropertyAddress = ""
    @State private var newPropertyType: PropertyType = .ltr

    private var participationAnswerLabel: String {
        switch taxProfile.noOneParticipatedMore(forYear: taxProfile.taxYear) {
        case .none: return "Not answered"
        case .some(true): return "No one did more"
        case .some(false): return "Someone did more"
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tax profile")
                        .lhDisplayFont(.largeTitle)
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("The few facts that decide which hours count.")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }

            Section {
                Picker(selection: $taxProfile.filingStatus) {
                    ForEach(FilingStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                } label: {
                    SettingRow(symbol: "person.text.rectangle", title: "Filing status")
                }
                .tint(colors.action)

                SettingToggleRow(
                    symbol: "person.2",
                    title: "Spouse hours",
                    subtitle: "Track your spouse’s hours too. They count together for material participation, never for your 750.",
                    isOn: $taxProfile.spouseTracking
                )
                .accessibilityIdentifier("taxProfile.spouseTracking")
            } header: {
                BPSectionHeader(title: "You")
            }
            .listRowBackground(colors.backgroundSecondary)

            Section {
                // The same four goals as onboarding (2.0 adds material participation at 500h).
                Picker(selection: Binding(
                    get: { goalManager.goalChoice },
                    set: { goalManager.setGoalChoice($0) }
                )) {
                    ForEach(GoalChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                } label: {
                    SettingRow(symbol: "flag", title: "Goal")
                }
                .tint(colors.action)

                Picker(selection: $taxProfile.taxYear) {
                    ForEach(2024...2030, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                } label: {
                    SettingRow(symbol: "calendar", title: "Tax year")
                }
                .tint(colors.action)

                SettingToggleRow(
                    symbol: "square.stack.3d.up",
                    title: "Grouping election",
                    subtitle: "Treat all your rentals as one activity for material participation.",
                    isOn: $taxProfile.groupingElection
                )
            } header: {
                BPSectionHeader(title: "Goal")
            }
            .listRowBackground(colors.backgroundSecondary)

            Section {
                Button {
                    workHoursText = taxProfile.nonREWorkHours > 0 ? String(Int(taxProfile.nonREWorkHours)) : ""
                    showWorkHoursInput = true
                } label: {
                    SettingRow(
                        symbol: "briefcase",
                        title: "Other work hours",
                        subtitle: "W-2 or other job hours this year",
                        value: taxProfile.nonREWorkHours > 0 ? "\(Int(taxProfile.nonREWorkHours))h" : "Not set",
                        valueColor: taxProfile.nonREWorkHours > 0 ? nil : colors.caution,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("taxProfile.otherWorkHours")
            } header: {
                BPSectionHeader(title: "50% rule")
            } footer: {
                Text("For REPS, your real estate hours must be more than half of all the hours you worked this year.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }
            .listRowBackground(colors.backgroundSecondary)

            Section {
                Button {
                    showParticipationConfirmation = true
                } label: {
                    SettingRow(symbol: "checkmark.circle", title: "100-hour test", subtitle: "Did anyone else do more?", value: participationAnswerLabel, showsChevron: true)
                }
                .buttonStyle(.plain)
            } header: {
                BPSectionHeader(title: "Material participation")
            } footer: {
                Text("Test 3 needs more than 100 hours and no one else, like a manager or contractor, putting in more time than you.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }
            .listRowBackground(colors.backgroundSecondary)

            Section {
                if viewModel.properties.isEmpty {
                    Text("No properties yet")
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                } else {
                    ForEach(viewModel.properties) { property in
                        HStack(spacing: 14) {
                            Image(systemName: "house")
                                .font(.system(size: 19))
                                .foregroundStyle(colors.textSecondary)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(property.name)
                                    .font(.body)
                                    .foregroundStyle(colors.textPrimary)
                                if !property.shortAddress.isEmpty {
                                    Text(property.shortAddress)
                                        .font(.subheadline)
                                        .foregroundStyle(colors.textSecondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(property.propertyType.rawValue)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(colors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
                Button {
                    showAddProperty = true
                } label: {
                    Label("Add property", systemImage: "plus")
                        .foregroundStyle(colors.action)
                        .frame(minHeight: 36)
                }
            } header: {
                BPSectionHeader(title: "Properties")
            }
            .listRowBackground(colors.backgroundSecondary)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .sheet(isPresented: $showWorkHoursInput) { workHoursSheet }
        .sheet(isPresented: $showAddProperty) { addPropertySheet }
        .sheet(isPresented: $showParticipationConfirmation) {
            ParticipationConfirmationSheet(
                year: taxProfile.taxYear,
                currentAnswer: taxProfile.noOneParticipatedMore(forYear: taxProfile.taxYear)
            ) { answer in
                taxProfile.setNoOneParticipatedMore(answer, forYear: taxProfile.taxYear)
            }
        }
        .accessibilityIdentifier("taxProfile.screen")
    }

    private var workHoursSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Hours you worked outside real estate this year, like a W-2 job.")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Hours", text: $workHoursText)
                    .keyboardType(.numberPad)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.backgroundSecondary))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.border, lineWidth: 1))
                    .accessibilityLabel("Other work hours")

                Button("Save") {
                    if let hours = Double(workHoursText) {
                        taxProfile.nonREWorkHours = hours
                    }
                    showWorkHoursInput = false
                }
                .buttonStyle(InboxPrimaryButtonStyle())
            }
            .padding(24)
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("Other work hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showWorkHoursInput = false }
                        .foregroundStyle(colors.action)
                }
            }
        }
        .presentationDetents([.height(360), .large])
    }

    private var addPropertySheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $newPropertyType) {
                        ForEach([PropertyType.ltr, PropertyType.str], id: \.self) { type in
                            Text(type.fullName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField("Property name", text: $newPropertyName)
                    TextField("Address", text: $newPropertyAddress)
                }
                .listRowBackground(colors.backgroundSecondary)
                Section {
                    Button("Add property") {
                        guard !newPropertyName.isEmpty else { return }
                        viewModel.addProperty(name: newPropertyName, address: newPropertyAddress, type: newPropertyType)
                        newPropertyName = ""
                        newPropertyAddress = ""
                        newPropertyType = .ltr
                        showAddProperty = false
                    }
                    .buttonStyle(InboxPrimaryButtonStyle())
                    .disabled(newPropertyName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("Add property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddProperty = false }
                        .foregroundStyle(colors.action)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Profile Edit View

struct ProfileEditView: View {
    @Binding var userName: String
    @Binding var userEmail: String
    @Binding var profileImage: Data?
    @StateObject private var appleSignIn = AppleSignInManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatar(name: userName.isEmpty ? "Your name" : userName, imageData: profileImage ?? appleSignIn.profileImageData, size: 96)
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Change photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.action)
                        }
                        .onChange(of: selectedPhotoItem) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    profileImage = data
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Your name", text: $userName)
                        .textContentType(.name)
                    TextField("your@email.com", text: $userEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                } header: {
                    BPSectionHeader(title: "Name and email")
                } footer: {
                    Text("Shown on your export so your accountant knows whose record it is.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
                .listRowBackground(colors.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.action)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        AppleSignInManager.shared.updateProfile(
                            name: userName.isEmpty ? nil : userName,
                            email: userEmail.isEmpty ? nil : userEmail,
                            imageData: profileImage
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.action)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppViewModel())
        .environmentObject(CategoryManager.shared)
}
