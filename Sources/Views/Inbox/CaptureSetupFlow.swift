import SwiftUI
import UserNotifications

// MARK: - Permissions seam

/// System calls the setup flow makes. DEBUG launches can swap in fakes so UI tests never meet a
/// system alert (see `InboxDebugSeed`).
struct CaptureSetupEnvironment {
    var requestCalendar: @MainActor () async -> CalendarAccess
    var requestNotifications: @MainActor () async -> Bool
    var makeScanner: @MainActor (AppViewModel, SuggestionStore) -> BackfillScanning

    static let live = CaptureSetupEnvironment(
        requestCalendar: {
            let source = EventKitCalendarSource()
            let access = source.accessState()
            return access == .notDetermined ? await source.requestFullAccess() : access
        },
        requestNotifications: {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            case .denied:
                return false
            default:
                return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            }
        },
        makeScanner: { app, store in
            CalendarBackfillScanner(store: store, properties: app.properties, entries: app.timeEntries)
        }
    )

    @MainActor static var current: CaptureSetupEnvironment {
        #if DEBUG
        if let fake = InboxDebugSeed.fakeSetupEnvironment() { return fake }
        #endif
        return .live
    }
}

// MARK: - Flow

/// The opt-in for auto-capture. `.whatsNew` is the one-time intro for people updating from 1.x;
/// `.onboarding` is the same choice as a new user's onboarding step. Nothing turns on without a
/// tap here: calendar suggestions and end-of-event prompts default to off.
/// Ends by starting the day-1 backfill in the background when calendar access was granted.
///
/// Standard components only (plan package D): `LHScreenTitle` (sheet), `LHRowGroup` +
/// `LHRow.Toggle`, a sample `LHRow.Action`, `LHButton`. No eyebrow, no blueprint switch style.
struct CaptureSetupFlow: View {
    enum Mode { case onboarding, whatsNew }
    enum Phase: Equatable { case priming, calendarDenied, backfill }

    let mode: Mode
    let environment: CaptureSetupEnvironment
    /// Skip the choice and run the 90-day look-back (calendar already on, e.g. after a cancel).
    var startAtBackfill = false
    /// `true` when the user should land on the Inbox.
    var onFinish: (_ openInbox: Bool) -> Void

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var phase: Phase = .priming
    // Both start OFF: turning on capture is an explicit choice, never a default.
    @State private var findInCalendar = false
    @State private var askWhenVisitEnds = false
    @State private var isWorking = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Group {
            switch phase {
            case .priming:
                priming
            case .calendarDenied:
                calendarDenied
            case .backfill:
                // WP-L: the look-back runs in the background. Start it and go straight to the
                // Inbox, where suggestions stream in under a compact progress header.
                Color.clear.onAppear {
                    guard let store = AppModelHost.shared.suggestionStore else {
                        onFinish(false)
                        return
                    }
                    BackfillJob.shared.start(environment.makeScanner(viewModel, store))
                    NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
                    onFinish(true)
                }
            }
        }
        .onAppear {
            if startAtBackfill { phase = .backfill }
            #if DEBUG
            if InboxDebugSeed.has("-LHCaptureSetupOn") { findInCalendar = true; askWhenVisitEnds = true }
            if InboxDebugSeed.value(after: "-LHCaptureSetupPhase") == "denied" { phase = .calendarDenied }
            #endif
        }
        .presentationDragIndicator(.visible)
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : AppAnimation.smooth, value: phase)
        .background(colors.background.ignoresSafeArea())
    }

    // MARK: Priming

    private var priming: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    LHScreenTitle(
                        mode == .whatsNew
                            ? String(localized: "capture.title.whatsNew", defaultValue: "We can notice your rental work", table: "Inbox")
                            : String(localized: "capture.title.onboarding", defaultValue: "Let us notice your rental work", table: "Inbox"),
                        style: .sheet
                    )
                    .accessibilityIdentifier("capture.priming.title")
                    Text(String(localized: "capture.body", defaultValue: "We look for things like a plumber visit or a showing in your calendar, then ask you. Nothing counts until you confirm it.", table: "Inbox"))
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switches

                preview

                CapturePrivacyFooter()
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, mode == .whatsNew ? 24 : 12)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { primingFooter }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(mode == .whatsNew ? "capture.whatsNew" : "capture.onboarding")
    }

    private var primingFooter: some View {
        VStack(spacing: 4) {
            Button {
                Task { await continueTapped() }
            } label: {
                if isWorking {
                    ProgressView().tint(colors.onAction)
                } else {
                    Text(String(localized: "capture.turnOn", defaultValue: "Turn on", table: "Inbox"))
                }
            }
            .buttonStyle(LHButton.primary)
            .disabled(isWorking || !findInCalendar)
            .accessibilityIdentifier("capture.priming.continue")
            Button(String(localized: "capture.notNow", defaultValue: "Not now", table: "Inbox")) { notNow() }
                .buttonStyle(LHButton.tertiary)
                .disabled(isWorking)
                .accessibilityIdentifier("capture.priming.notNow")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            colors.background
                .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: LHMetrics.hairline) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var switches: some View {
        LHRowGroup {
            LHRow.Toggle(
                String(localized: "capture.toggle.calendar", defaultValue: "Find rental work in my calendar", table: "Inbox"),
                subtitle: String(localized: "capture.toggle.calendar.detail", defaultValue: "Looks back 90 days, then watches new events.", table: "Inbox"),
                isOn: $findInCalendar.animation(reduceMotion ? nil : AppAnimation.quick)
            )
            .padding(LHRow.insets)
            .accessibilityIdentifier("capture.toggle.calendar")

            LHDivider(leadingInset: 16)

            LHRow.Toggle(
                String(localized: "capture.toggle.prompts", defaultValue: "Ask me when a visit ends", table: "Inbox"),
                subtitle: findInCalendar
                    ? String(localized: "capture.toggle.prompts.detail", defaultValue: "One short note after a visit. Two a day at most, never at night.", table: "Inbox")
                    : String(localized: "capture.toggle.prompts.off", defaultValue: "Needs calendar suggestions.", table: "Inbox"),
                isOn: $askWhenVisitEnds
            )
            .disabled(!findInCalendar)
            .padding(LHRow.insets)
            .accessibilityIdentifier("capture.toggle.eventPrompts")
        }
        .onChange(of: findInCalendar) { _, on in
            if !on { askWhenVisitEnds = false }
        }
    }

    /// One suggestion row and one notification, so people see what they are agreeing to.
    private var preview: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(String(localized: "capture.preview.title", defaultValue: "What you’ll see", table: "Inbox"))
            LHRowGroup {
                SuggestionRowView(
                    suggestion: Self.sampleSuggestion,
                    propertyName: Self.samplePropertyName,
                    badges: SuggestionBadges(notSure: false, mightAlreadyBeLogged: false, needsHours: false),
                    quick: true,
                    now: Self.sampleNow
                )
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "capture.preview.a11y", defaultValue: "Example suggestion: 2 hours, Plumber at Pine Cabin, from your calendar", table: "Inbox"))

            if askWhenVisitEnds {
                notificationPreview
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            LHCompactLogo(size: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "capture.notification.title", defaultValue: "Plumber visit just ended", table: "Inbox"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(String(localized: "capture.notification.body", defaultValue: "Log 2h at Pine Cabin?", table: "Inbox"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer(minLength: 0)
            Text(String(localized: "capture.notification.now", defaultValue: "now", table: "Inbox"))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(LHMetrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 12, y: 4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "capture.notification.a11y", defaultValue: "Example notification: Plumber visit just ended. Log 2 hours at Pine Cabin?", table: "Inbox"))
        .accessibilityIdentifier("capture.notificationPreview")
    }

    static let samplePropertyName = "Pine Cabin"

    static let sampleNow: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 16; c.hour = 12
        return Calendar.current.date(from: c) ?? Date()
    }()

    static let sampleSuggestion: Suggestion = {
        let start = Calendar.current.date(byAdding: .hour, value: -51, to: sampleNow) ?? sampleNow
        return Suggestion(
            sourceKey: "sample",
            kind: .calendar,
            detectedAt: start,
            start: start,
            end: start.addingTimeInterval(7200),
            title: "Plumber",
            proposedCategory: .repairs,
            proposedHours: 2,
            hoursBasis: .scheduled,
            confidence: 0.9
        )
    }()

    // MARK: Actions

    private func continueTapped() async {
        guard findInCalendar else {
            CaptureOptIn.recordChoice(calendar: false, eventPrompts: false)
            onFinish(false)
            return
        }
        isWorking = true
        defer { isWorking = false }
        let access = await environment.requestCalendar()
        let granted = access == .fullAccess
        var prompts = false
        if granted, askWhenVisitEnds {
            prompts = await environment.requestNotifications()
        }
        CaptureOptIn.recordChoice(calendar: granted, eventPrompts: prompts)
        viewModel.objectWillChange.send()
        // WP4: rebuild end-of-event prompts now that the answer changed.
        Task { await CaptureNotificationRefresher.shared.refresh(reason: "capture-opt-in") }
        guard granted else {
            phase = .calendarDenied
            return
        }
        if CaptureOptIn.backfillCompleted() {
            onFinish(true)
        } else {
            phase = .backfill
        }
    }

    private func notNow() {
        CaptureOptIn.recordChoice(calendar: false, eventPrompts: false)
        // WP4: clear any prompts already scheduled for this profile.
        Task { await CaptureNotificationRefresher.shared.refresh(reason: "capture-opt-out") }
        onFinish(false)
    }

    // MARK: Denied

    private var deniedActions: some View {
        VStack(spacing: 4) {
            Button(String(localized: "capture.denied.settings", defaultValue: "Open Settings", table: "Inbox")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier("capture.denied.settings")
            Button(String(localized: "capture.denied.continue", defaultValue: "Continue without it", table: "Inbox")) { onFinish(false) }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("capture.denied.continue")
        }
    }

    private var calendarDenied: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LHScreenTitle(String(localized: "capture.denied.title", defaultValue: "Calendar access is off", table: "Inbox"), style: .sheet)
                Text(String(localized: "capture.denied.body", defaultValue: "To find rental work, we need Full Access to your calendar. You can turn it on in Settings any time. Logging by hand works either way.", table: "Inbox"))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Accessibility sizes: the two actions are taller than the copy, so they scroll
                // with it instead of pinning over it.
                if dynamicTypeSize.isAccessibilitySize { deniedActions.padding(.top, 8) }
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                deniedActions
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(colors.background)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.denied")
    }
}

/// Onboarding → shell hand-off: land on the Inbox after the backfill intro.
enum CaptureSetupHandoff {
    @MainActor static var openInboxAfterOnboarding = false
}
