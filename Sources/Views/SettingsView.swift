import SwiftUI
import PhotosUI

// MARK: - Settings
//
// Standard v2 (package H): one inset-grouped `List` on the plain canvas (no house here; the page is
// dusk only on screens that carry the hero). `LHScreenTitle` with a back to Today, an `LHSectionHeader`
// per group, `LHRow.Browse` / `.Toggle` for rows, the Pro card on `LHButton.secondary`, the
// appearance choice on `LHSegmented`. Words come from `Settings.xcstrings` through `HS`.
// The profile and account rows stay as they are: package K replaces them with Settings › iCloud &
// records and package H then deletes the old section (identity plan §4.3).

struct SettingsView: View {
    #if DEBUG
    @MainActor private static var didApplyDebugRoute = false
    #endif
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showingProfileEdit = false   // package K: opens "Your name" (YourNameSheet)
    @State private var paywall: ProPaywallRequest?
    @State private var showExport = false
    @State private var restoreStatusMessage: String?
    @State private var route: SettingsRoute?
    /// Backs the "Share anonymous usage stats" toggle. Stores whether the user opted OUT (default
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
        viewModel.userName.isEmpty ? HS.t("settings.profile.placeholder", "Your name") : viewModel.userName
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                planSection
                AutoCaptureSettingsSection(onOpenMuted: { route = .muted })
                taxSection
                recordsSection
                appSection
                privacySection
                supportSection
                // Package K: iCloud & records replaces Account, Switch profile, Sign out, Restore.
                ICloudRecordsSection(viewModel: viewModel, onOpen: { route = $0 })

                // A section footer, not a clear row: a row at the end of an inset-grouped list is
                // clipped by the section's corner mask, which cut the first glyph of each line.
                Section {
                } footer: {
                    VStack(alignment: .leading, spacing: 12) {
                        LHFootnote(HS.cpaFootnote)
                            .accessibilityIdentifier("settings.notTaxAdvice")
                        Text(HS.f("settings.version", "Dormer · %@", AppVersionInfo.display()))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("settings.version")
                    }
                    .textCase(nil)
                    .padding(.top, 4)
                }

                #if DEBUG
                developerToolsSection
                #endif
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(LHMetrics.sectionGap)
            .contentMargins(.horizontal, LHMetrics.gutter, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 104, for: .scrollContent)
            .background { LHCanvas() }
            // Screen anatomy: the scaffold owns the title, the back icon and the gaps.
            .lhTabScreen(HS.t("settings.title", "Settings"), back: LHBackAction(
                label: HS.t("settings.back", "Back to Today"), identifier: "shell.backToToday") {
                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.todayIndex)
                })
            .navigationDestination(item: $route) { route in
                switch route {
                case .taxProfile: TaxProfileView()
                case .learningCenter: LearningCenterView()
                case .contactSupport: ContactSupportView()
                case .muted: MutedSuggestionsView()
                case .deleteData: DeleteAllDataView()
                case .icloud: ICloudRecordsView()
                case .earlierRecords: EarlierRecordsView()
                }
            }
            .sheet(isPresented: $showingProfileEdit) {
                YourNameSheet().environmentObject(viewModel)
            }
            .proPaywall($paywall)
            .sheet(isPresented: $showExport) {
                ExportPDFView(year: Calendar.current.component(.year, from: Date()))
            }
            .task(id: viewModel.isSignedIn) {
                #if DEBUG
                // Before the profile discovery below, which can wait on iCloud for a long time on
                // a signed-in device. `.task` re-runs when Settings reappears after a pop, so the
                // page opens once per launch.
                if !Self.didApplyDebugRoute {
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-LHOpenDeleteData") {
                        Self.didApplyDebugRoute = true
                        route = .deleteData
                    } else if args.contains("-LHOpenLearningCenterFromSettings") {
                        Self.didApplyDebugRoute = true
                        route = .learningCenter
                    } else if args.contains("-LHOpenFilingFromSettings") {
                        Self.didApplyDebugRoute = true
                        route = .taxProfile
                    } else if args.contains("-LHOpenSupportFromSettings") {
                        Self.didApplyDebugRoute = true
                        route = .contactSupport
                    } else if args.contains("-LHOpenMutedFromSettings") {
                        Self.didApplyDebugRoute = true
                        route = .muted
                    }
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

    private func header(_ title: String) -> some View {
        LHSectionHeader(title).textCase(nil)
    }

    // MARK: Profile

    private var profileSection: some View {
        Section {
            Button {
                showingProfileEdit = true
            } label: {
                HStack(spacing: 14) {
                    // Package K: no photo and no email (§2.4); the name is "Your name".
                    ProfileAvatar(name: displayName, imageData: nil, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        planBadge
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize { LHChevron() }
                }
                .padding(.horizontal, LHRow.insets.leading)
                .padding(.vertical, 8)
                .frame(minHeight: LHMetrics.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(LHButton.press)
            .longTailRow(separatorInset: LHRow.insets.leading)
            .accessibilityHint(String(localized: "Edit your name", table: "Identity"))
            .accessibilityIdentifier("settings.profile")
        }
    }

    private var planBadge: some View {
        let isPro = subscriptionManager.isPro
        return LHTag(isPro ? HS.t("settings.plan.pro", "Pro · Paid once") : HS.t("settings.plan.free", "Free plan"),
                     tone: isPro ? .positive : .neutral)
    }

    // MARK: Plan

    @ViewBuilder
    private var planSection: some View {
        if ProGate.isLocked(.settingsPro, isPro: subscriptionManager.isPro) {
            Section {
                proCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        Section {
            if ProGate.isLocked(.settingsPro, isPro: subscriptionManager.isPro) {
                LockedPreview(
                    size: .row,
                    entry: .settingsExport,
                    line: ProGate.lockLine(.settingsExport),
                    keeps: ProGate.keepsLine(.settingsExport),
                    rowInset: LHRow.insets.leading,
                    onUnlock: {
                        paywall = ProPaywallRequest(context: .export, entry: .settingsExport, onUnlocked: { showExport = true })
                    }
                ) {
                    LHRow.Browse(title: HS.t("settings.export.title", "Export the record"),
                                 meta: HS.t("settings.export.meta", "PDF and CSV for your CPA"),
                                 systemImage: "square.and.arrow.up", tint: .neutral)
                }
                .longTailRow()
            } else {
                LHRow.Browse(title: HS.t("settings.pro.active.title", "Pro is active"),
                             meta: HS.t("settings.pro.active.meta", "Paid once. Everything is unlocked."),
                             systemImage: "checkmark.seal", tint: .positive, showsChevron: false)
                    .longTailRow()
                    .accessibilityIdentifier("settings.proActive")
            }

            LHRow.Browse(
                title: subscriptionManager.isLoading
                    ? HS.t("settings.restore.loading", "Restoring purchase…")
                    : HS.t("settings.restore.title", "Restore purchase"),
                meta: subscriptionManager.isLoading ? nil : restoreStatusMessage,
                systemImage: "arrow.clockwise", tint: .neutral, showsChevron: false,
                action: {
                    Task {
                        restoreStatusMessage = nil
                        await subscriptionManager.restorePurchases()
                        // The result shows inline under the row (not a system alert, whose message
                        // text iOS draws below AA); the row stays tappable to try again.
                        restoreStatusMessage = subscriptionManager.hasPurchased
                            ? HS.t("settings.restore.done", "Your Pro purchase is back.")
                            : (subscriptionManager.restoreFailureMessage ?? subscriptionManager.purchaseError
                                ?? HS.t("settings.restore.none", "No earlier purchase found."))
                    }
                }
            )
            .disabled(subscriptionManager.isLoading)
            .longTailRow()
            .accessibilityIdentifier("settings.restorePurchase")

        } header: {
            header(HS.t("settings.section.plan", "Plan"))
        }
    }

    /// Not a lock: a plain card above the plan rows (redesign-specs §1b). Radius 20, one
    /// `LHButton.secondary`. At accessibility sizes the button drops under the text.
    private var proCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                // The product name never breaks or hyphenates: one line, scaled down if needed.
                Text(HS.t("settings.proCard.name", "Dormer\u{00A0}Pro"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subscriptionManager.proDisplayPrice.map { HS.f("settings.proCard.price", "Pay once, %@", $0) }
                     ?? HS.t("settings.proCard.payOnce", "Pay once"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Button(HS.t("settings.proCard.action", "See Pro")) {
                paywall = ProPaywallRequest(context: .settings, entry: .settingsPro)
            }
            .buttonStyle(LHButton.secondary)
            .fixedSize()
            .accessibilityIdentifier("settings.proCard")
        }
        .padding(LHMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
        .accessibilityElement(children: .contain)
        .onAppear { Analytics.lockPreviewShown(entry: .settingsPro) }
    }

    // MARK: Tax setup

    private var taxSection: some View {
        Section {
            LHRow.Browse(title: HS.t("settings.filing.title", "Filing and goal"),
                         meta: HS.t("settings.filing.meta", "Who files and your goal"),
                         systemImage: "doc.text", tint: .neutral,
                         action: { route = .taxProfile })
                .longTailRow()
                .accessibilityIdentifier("settings.taxProfile")

            LHRow.Browse(title: HS.t("settings.learn.title", "Learning center"),
                         meta: HS.t("settings.learn.meta", "The 750 hours, in plain words"),
                         systemImage: "book", tint: .neutral,
                         action: { route = .learningCenter })
                .longTailRow()
                .accessibilityIdentifier("settings.learningCenter")
        } header: {
            header(HS.t("settings.section.tax", "Tax setup"))
        }
    }

    // MARK: Records

    private var recordsSection: some View {
        Section {
            // Free users get Export as the `.row` lock under the Pro card (WP-P): one route each.
            if !ProGate.isExportLocked(isPro: subscriptionManager.isPro) {
                LHRow.Browse(title: HS.t("settings.export.title", "Export the record"),
                             meta: HS.t("settings.export.meta", "PDF and CSV for your CPA"),
                             systemImage: "square.and.arrow.up", tint: .neutral,
                             action: { showExport = true })
                    .longTailRow()
                    .accessibilityIdentifier("settings.exportReports")
            }

        } header: {
            header(HS.t("settings.section.records", "Records"))
        } footer: {
            Text(HS.t("settings.photos.footer", "Photos attached to records stay on this iPhone. They aren’t included in iCloud sync."))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("settings.photoStorageDisclosure")
        }
    }

    // MARK: App

    private var appSection: some View {
        Section {
            AppearancePreferenceRow(appearanceManager: appearanceManager)
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityIdentifier("settings.appearance")

            LHRow.Browse(title: HS.t("settings.notifications.title", "Notifications"),
                         meta: HS.t("settings.notifications.meta", "Opens iOS Settings"),
                         systemImage: "bell", tint: .neutral,
                         action: {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            .longTailRow()
        } header: {
            header(HS.t("settings.section.app", "App"))
        }
    }

    // MARK: Data and privacy

    private var privacySection: some View {
        Section {
            LHRow.Toggle(HS.t("settings.stats.title", "Share anonymous usage stats"),
                         subtitle: HS.t("settings.stats.subtitle", "Like “a record was saved”. Never your notes or rentals."),
                         isOn: shareAnalyticsBinding)
                .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                .accessibilityIdentifier("settings.analyticsOptOut")

            LHRow.Browse(title: HS.t("settings.terms.title", "Terms and privacy"),
                         systemImage: "hand.raised", tint: .neutral,
                         action: {
                if let url = URL(string: "https://www.altaiventures.co/landlord-hours/terms") {
                    UIApplication.shared.open(url)
                }
            })
            .longTailRow()
        } header: {
            // No footer: "Your records live on this iPhone and in your own iCloud" is said once, under
            // iCloud & records (package K); here it repeated word for word two sections above it.
            header(HS.t("settings.section.privacy", "Data and privacy"))
        }
    }

    // MARK: Support

    private var supportSection: some View {
        Section {
            LHRow.Browse(title: HS.t("settings.support.title", "Contact support"),
                         meta: HS.t("settings.support.meta", "Hours, the record or setup"),
                         systemImage: "envelope", tint: .neutral,
                         action: { route = .contactSupport })
                .longTailRow()
                .accessibilityIdentifier("settings.contactSupport")
        } header: {
            header(HS.t("settings.section.support", "Support"))
        }
    }

    // MARK: Helpers

    #if DEBUG
    // Developer tools are DEBUG-only and never user-facing: plain strings, not in the catalog.
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
                    LHRow.Browse(title: subscriptionManager.hasPurchased ? "Pro unlocked for this build" : "Unlock Pro for testing",
                                 systemImage: "checkmark.seal", tint: .neutral, showsChevron: false)
                }
                .buttonStyle(LHButton.press)

                Button {
                    showEngagementLab = true
                } label: {
                    LHRow.Browse(title: "Engagement Lab", meta: "Notifications, widgets, Live Activities and Siri",
                                 systemImage: "bell.badge", tint: .neutral)
                }
                .buttonStyle(LHButton.press)
                .accessibilityIdentifier("settings.engagementLab")

                ForEach(AppViewModel.MockDataScenario.allCases) { scenario in
                    Button {
                        if reduceMotion {
                            viewModel.applyMockScenario(scenario)
                        } else {
                            withAnimation(AppAnimation.smooth) { viewModel.applyMockScenario(scenario) }
                        }
                    } label: {
                        LHRow.Browse(title: scenario.title, meta: scenario.subtitle, value: "Seed",
                                     systemImage: "tray.and.arrow.down", tint: .neutral, showsChevron: false)
                    }
                    .buttonStyle(LHButton.press)
                }
            }
        }
        .listRowBackground(colors.backgroundSecondary)
    }
    #endif
}

// MARK: - List row chrome

/// A row in an inset-grouped Settings list: the row draws its own 16pt insets and 56pt floor, so the
/// list adds none. `separatorInset` is where the hairline starts (64 under a 36pt glyph tile).
private struct SettingsRowChrome: ViewModifier {
    var separatorInset: CGFloat
    var toggle: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        content
            .padding(.horizontal, toggle ? LHRow.insets.leading : 0)
            .padding(.vertical, toggle ? LHRow.insets.top : 0)
            .frame(minHeight: toggle ? LHMetrics.rowMinHeight : nil)
            .listRowInsets(EdgeInsets())
            .listRowBackground(colors.backgroundSecondary)
            .listRowSeparatorTint(colors.border)
            .alignmentGuide(.listRowSeparatorLeading) { _ in separatorInset }
    }
}

extension View {
    /// Settings list row chrome (package H). Browse rows keep the default 64pt divider inset.
    func longTailRow(separatorInset: CGFloat = LHRow.browseDividerInset, toggle: Bool = false) -> some View {
        modifier(SettingsRowChrome(separatorInset: separatorInset, toggle: toggle))
    }
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
        return letters.isEmpty || name == HS.t("settings.profile.placeholder", "Your name") ? "" : letters
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
                            .font(.title3)
                            .foregroundStyle(colors.action)
                    } else {
                        Text(initials)
                            .font(.headline)
                            .fontDesign(.rounded)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 4)
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
    case taxProfile, learningCenter, contactSupport, muted, deleteData, icloud, earlierRecords
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

    static var aiDisclosureOnDevice: String {
        HS.t("settings.capture.disclosure.device", "Calendar suggestions and the notes you type or say in Log time are read by Apple’s on-device model, on your iPhone, to fill in the form. Nothing goes to us or anyone else, and nothing is saved until you tap Log.")
    }

    static let pccSubtitle = String(localized: "settings.capture.pcc.subtitle", defaultValue: "Used only if your iPhone can\u{2019}t read a note. Apple keeps nothing, and we never see it.", table: "Foundations")

    var body: some View {
        Section {
            LHRow.Toggle(HS.t("settings.capture.calendar.title", "Calendar"),
                         subtitle: HS.t("settings.capture.calendar.subtitle", "Spot work in your events. Titles are read on your iPhone."),
                         isOn: Binding(get: { calendarOn }, set: { setCalendar($0) }))
                .disabled(isAsking)
                .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                .accessibilityIdentifier("settings.capture.calendar")

            LHRow.Toggle(HS.t("settings.capture.prompts.title", "Ask when an event ends"),
                         subtitle: calendarOn
                            ? HS.t("settings.capture.prompts.on", "At most twice a day, never after 9 pm.")
                            : HS.t("settings.capture.prompts.off", "Turn on Calendar first."),
                         isOn: Binding(get: { promptsOn }, set: { setPrompts($0) }))
                .disabled(!calendarOn || isAsking || UserScope.userId == nil)
                .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                .accessibilityIdentifier("settings.capture.prompts")

            if Self.offersPCC {
                LHRow.Toggle(HS.t("settings.capture.pcc.title", "Private Cloud Compute"),
                             subtitle: Self.pccSubtitle,
                             isOn: Binding(get: { pccOn }, set: { on in
                                pccOn = on
                                PCCSettings().isEnabled = on
                             }))
                    .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                    .accessibilityIdentifier("settings.capture.pcc")
            }

            LHRow.Browse(title: HS.t("settings.capture.muted.title", "Muted"),
                         meta: muteCount == 0
                            ? HS.t("settings.capture.muted.none", "Nothing muted")
                            : HS.f("settings.capture.muted.count", "%lld muted", muteCount),
                         systemImage: "speaker.slash", tint: .neutral,
                         action: onOpenMuted)
                .longTailRow()
                .accessibilityIdentifier("settings.capture.muted")

            if let blockedMessage {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label(blockedMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(colors.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, LHRow.insets.leading)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: LHMetrics.minTap, alignment: .leading)
                }
                .buttonStyle(LHButton.press)
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityHint(HS.t("settings.capture.blocked.hint", "Opens iOS Settings"))
                .accessibilityIdentifier("settings.capture.blocked")
            }
        } header: {
            LHSectionHeader(HS.t("settings.section.capture", "Auto-capture")).textCase(nil)
        } footer: {
            // Both sentences share one text column beside the shield.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.aiDisclosure)
                        .accessibilityIdentifier("settings.capture.aiDisclosure")
                    Text(HS.nothingCounts)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(colors.textSecondary)
            .accessibilityElement(children: .combine)
        }
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
                    ? HS.t("settings.capture.blocked.limited", "We can add to your calendar but can’t read it yet. Allow Full Access in Settings to get suggestions.")
                    : HS.t("settings.capture.blocked.off", "Calendar access is off for Dormer. Turn it on in iOS Settings.")
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
                blockedMessage = HS.t("settings.capture.blocked.notify", "Notifications are off for Dormer. Turn them on in iOS Settings.")
            }
        }
    }
}

/// The mute rules the user set from the Inbox ("stop suggesting things like this").
struct MutedSuggestionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var rules: [CaptureMuteRule] = []

    var body: some View {
        List {
            Section {
                LongTailHeader(
                    title: HS.t("muted.title", "Muted"),
                    back: (label: HS.t("common.back", "Back"), identifier: "muted.back", action: { dismiss() })
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if rules.isEmpty {
                Section {
                    LHEmptyState(
                        systemImage: "speaker.slash",
                        tone: .action,
                        headline: HS.t("muted.empty.headline", "Nothing muted"),
                        message: HS.t("muted.empty.message", "Muted things show up here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(rules) { rule in
                        LHRow.Browse(
                            title: rule.match == .titleContains
                                ? HS.f("muted.rule.title", "Titles with “%@”", rule.value)
                                : HS.t("muted.rule.calendar", "Events from one calendar"),
                            meta: HS.f("muted.rule.date", "Muted %@", rule.createdAt.formatted(.dateTime.month(.abbreviated).day().year())),
                            systemImage: rule.match == .titleContains ? "text.magnifyingglass" : "calendar",
                            tint: .neutral, showsChevron: false
                        )
                        .longTailRow()
                        .swipeActions {
                            Button(HS.t("muted.unmute", "Unmute"), role: .destructive) { remove(rule) }
                        }
                        .accessibilityAction(named: HS.t("muted.unmute", "Unmute")) { remove(rule) }
                    }
                } footer: {
                    Text(HS.t("muted.footer", "Swipe left to unmute. Muted things are never suggested again until you unmute them."))
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
            .contentMargins(.horizontal, LHMetrics.gutter, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background { LHCanvas() }
        .toolbar(.hidden, for: .navigationBar)
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

/// Auto / Light / Dark on `LHSegmented`. The choice is the state, so there is no "Saved" line.
private struct AppearancePreferenceRow: View {
    @ObservedObject var appearanceManager: AppearanceManager

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var options: [LHSegmented<AppAppearancePreference>.Option] {
        [.init(.system, HS.t("settings.appearance.auto", "Auto")),
         .init(.light, HS.t("settings.appearance.light", "Light")),
         .init(.dark, HS.t("settings.appearance.dark", "Dark"))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HS.t("settings.appearance.title", "Appearance"))
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                Text(HS.t("settings.appearance.subtitle", "Follow your iPhone or pick a theme"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
            }
            LHSegmented(options, selection: Binding(
                get: { appearanceManager.preference },
                set: { appearanceManager.preference = $0 }
            ), accessibilityLabel: HS.t("settings.appearance.title", "Appearance"))
        }
        .padding(.horizontal, LHRow.insets.leading)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Filing and goal

/// "Tax profile" in 2.0. The few facts that decide which hours count toward the goal: who files,
/// the goal, the year, the other-work hours behind the more-than-half test, the 100-hour question.
struct TaxProfileView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
        case .none: return HS.t("filing.hundred.unanswered", "Not answered")
        case .some(true): return HS.t("filing.hundred.noOne", "No one did more")
        case .some(false): return HS.t("filing.hundred.someone", "Someone did more")
        }
    }

    var body: some View {
        List {
            Section {
                LongTailHeader(
                    title: HS.t("filing.title", "Filing and goal"),
                    subtitle: HS.t("filing.subtitle", "The few facts that decide which hours count."),
                    back: (label: HS.t("common.back", "Back"), identifier: "filing.back", action: { dismiss() })
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Menu {
                    Picker(HS.t("filing.status", "Filing status"), selection: $taxProfile.filingStatus) {
                        ForEach(FilingStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                } label: {
                    valueRow(HS.t("filing.status", "Filing status"), value: taxProfile.filingStatus.rawValue)
                }
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityIdentifier("taxProfile.filingStatus")

                LHRow.Toggle(HS.t("filing.spouse.title", "Spouse hours"),
                             subtitle: HS.t("filing.spouse.subtitle", "Track your spouse’s hours too. For the 750, one of you has to get there alone."),
                             isOn: $taxProfile.spouseTracking)
                    .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                    .accessibilityIdentifier("taxProfile.spouseTracking")
            } header: {
                header(HS.t("filing.section.you", "You"))
            }

            Section {
                // The same four goals as onboarding (2.0 adds the 500-hour test).
                Menu {
                    Picker(HS.t("filing.goal", "Goal"), selection: Binding(
                        get: { goalManager.goalChoice },
                        set: { goalManager.setGoalChoice($0) }
                    )) {
                        ForEach(GoalChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } label: {
                    valueRow(HS.t("filing.goal", "Goal"), value: goalManager.goalChoice.title)
                }
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityIdentifier("taxProfile.goal")

                Menu {
                    Picker(HS.t("filing.year", "Tax year"), selection: $taxProfile.taxYear) {
                        ForEach(2024...2030, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } label: {
                    valueRow(HS.t("filing.year", "Tax year"), value: String(taxProfile.taxYear))
                }
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityIdentifier("taxProfile.year")

                LHRow.Toggle(HS.t("filing.group.title", "Group your rentals"),
                             subtitle: HS.t("filing.group.subtitle", "Count all your rentals together."),
                             isOn: $taxProfile.groupingElection)
                    .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                    .accessibilityIdentifier("taxProfile.grouping")
            } header: {
                header(HS.t("filing.section.goal", "Goal"))
            } footer: {
                // Line 3 of the standard's worst-lines table: the plain sentence, then the CPA's name for it.
                Text(HS.t("filing.group.footer", "Your CPA may call this a grouping election."))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }

            Section {
                Button {
                    workHoursText = taxProfile.nonREWorkHours > 0 ? String(Int(taxProfile.nonREWorkHours)) : ""
                    showWorkHoursInput = true
                } label: {
                    LongTailValueRow(label: HS.t("filing.other.title", "Other work hours"),
                                     value: taxProfile.nonREWorkHours > 0
                                        ? HS.f("filing.other.hours", "%lldh", Int(taxProfile.nonREWorkHours))
                                        : HS.t("filing.other.unset", "Not set"),
                                     accessory: .disclosure)
                }
                .buttonStyle(LHButton.press)
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityIdentifier("taxProfile.otherWorkHours")
            } header: {
                header(HS.t("filing.section.half", "More than half"))
            } footer: {
                Text(HS.t("filing.half.footer", "For the 750, your rental hours have to be more than half of all the hours you worked this year. Add W-2 or other job hours here."))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }

            Section {
                Button { showParticipationConfirmation = true } label: {
                    LongTailValueRow(label: HS.t("filing.hundred.title", "Did anyone else do more?"),
                                     value: participationAnswerLabel, accessory: .disclosure)
                }
                .buttonStyle(LHButton.press)
                    .longTailRow(separatorInset: LHRow.insets.leading)
                    .accessibilityIdentifier("taxProfile.hundred")
            } header: {
                header(HS.t("filing.section.hundred", "The 100-hour test"))
            } footer: {
                Text(HS.t("filing.hundred.footer", "It needs more than 100 hours, and no one else, like a manager or contractor, putting in more than you."))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
            }

            Section {
                if viewModel.properties.isEmpty {
                    Text(HS.t("filing.rentals.empty", "No rentals yet"))
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, LHRow.insets.leading)
                        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
                        .longTailRow(separatorInset: LHRow.insets.leading)
                } else {
                    ForEach(viewModel.properties) { property in
                        LHRow.Browse(
                            title: property.name,
                            meta: property.shortAddress.isEmpty ? nil : property.shortAddress,
                            value: property.propertyType.rawValue,
                            systemImage: "house", tint: .neutral, showsChevron: false
                        )
                        .longTailRow()
                    }
                }
                Button {
                    showAddProperty = true
                } label: {
                    Label(HS.t("filing.rentals.add", "Add a rental"), systemImage: "plus")
                        .font(.body)
                        .foregroundStyle(colors.action)
                        .padding(.horizontal, LHRow.insets.leading)
                        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LHButton.press)
                .longTailRow(separatorInset: LHRow.insets.leading)
                .accessibilityIdentifier("taxProfile.addRental")
            } header: {
                header(HS.t("filing.section.rentals", "Your rentals"), count: viewModel.properties.count)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
            .contentMargins(.horizontal, LHMetrics.gutter, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background { LHCanvas() }
        .toolbar(.hidden, for: .navigationBar)
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

    private func header(_ title: String, count: Int? = nil) -> some View {
        LHSectionHeader(title, count: count).textCase(nil)
    }

    /// A label and its value as a `Menu` label.
    private func valueRow(_ label: String, value: String) -> some View {
        LongTailValueRow(label: label, value: value, accessory: .menu)
    }

    private var workHoursSheet: some View {
        LHSheet(HS.t("filing.other.title", "Other work hours"), onClose: { showWorkHoursInput = false }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(HS.t("filing.other.sheet", "Hours you worked outside real estate this year, like a W-2 job."))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LHField(HS.t("filing.other.field", "Hours"), text: $workHoursText,
                        accessibilityLabel: HS.t("filing.other.title", "Other work hours"),
                        identifier: "taxProfile.otherWorkHours.field")
                    .keyboardType(.numberPad)
            }
        } footer: {
            Button(HS.t("common.save", "Save")) {
                if let hours = Double(workHoursText) {
                    taxProfile.nonREWorkHours = hours
                }
                showWorkHoursInput = false
            }
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier("taxProfile.otherWorkHours.save")
        }
        .lhSheetPresentation()
    }

    private var addPropertySheet: some View {
        LHSheet(HS.t("filing.add.title", "Add a rental"), onClose: { showAddProperty = false }) {
            VStack(alignment: .leading, spacing: 16) {
                if typeSize.isAccessibilitySize {
                    // Two long labels do not fit one capsule track at AX sizes: stack them.
                    VStack(spacing: 8) {
                        ForEach([PropertyType.ltr, PropertyType.str], id: \.self) { kind in
                            Button { newPropertyType = kind } label: {
                                HStack {
                                    Text(kind.fullName)
                                        .font(.body)
                                        .foregroundStyle(colors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if newPropertyType == kind {
                                        Image(systemName: "checkmark").foregroundStyle(colors.action)
                                    }
                                }
                                .padding(LHRow.insets)
                                .frame(minHeight: LHMetrics.minTap)
                                .background(newPropertyType == kind ? colors.primarySurface : colors.backgroundTertiary,
                                            in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(newPropertyType == kind ? .isSelected : [])
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(HS.t("filing.add.type", "Type"))
                } else {
                    LHSegmented(
                        [.init(PropertyType.ltr, PropertyType.ltr.fullName), .init(PropertyType.str, PropertyType.str.fullName)],
                        selection: $newPropertyType,
                        accessibilityLabel: HS.t("filing.add.type", "Type")
                    )
                }
                LHField(HS.t("filing.add.name", "Rental name"), text: $newPropertyName)
                LHField(HS.t("filing.add.address", "Address"), text: $newPropertyAddress)
            }
        } footer: {
            Button(HS.t("filing.add.action", "Add rental")) {
                guard !newPropertyName.isEmpty else { return }
                viewModel.addProperty(name: newPropertyName, address: newPropertyAddress, type: newPropertyType)
                newPropertyName = ""
                newPropertyAddress = ""
                newPropertyType = .ltr
                showAddProperty = false
            }
            .buttonStyle(LHButton.primary)
            .disabled(newPropertyName.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("taxProfile.addRental.save")
        }
        .lhSheetPresentation()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppViewModel())
        .environmentObject(CategoryManager.shared)
}
