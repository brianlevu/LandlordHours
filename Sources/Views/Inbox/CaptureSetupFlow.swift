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
        .onAppear { if startAtBackfill { phase = .backfill } }
        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : AppAnimation.smooth, value: phase)
        .background(colors.background.ignoresSafeArea())
    }

    // MARK: Priming

    private var priming: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if mode == .whatsNew {
                        Text("New in 2.0")
                            .font(AppTypography.drafting)
                            .tracking(1.3)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.draftingInk)
                            .padding(.bottom, 10)
                    }
                    Text(mode == .whatsNew ? "LandlordHours can notice your rental work" : "Let LandlordHours notice your rental work")
                        .font(.title.weight(.bold))
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("capture.priming.title")
                    Text("We look for things like a plumber visit or a showing in your calendar, then ask you. Nothing counts until you confirm it.")
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    switches
                        .padding(.top, 24)

                    preview
                        .padding(.top, 28)

                    CapturePrivacyFooter()
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, mode == .whatsNew ? 32 : 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button {
                    Task { await continueTapped() }
                } label: {
                    if isWorking {
                        ProgressView().tint(colors.onAction)
                    } else {
                        Text("Turn on")
                    }
                }
                .buttonStyle(InboxPrimaryButtonStyle())
                .disabled(isWorking || !findInCalendar)
                .accessibilityIdentifier("capture.priming.continue")
                Button("Not now") { notNow() }
                    .font(.body)
                    .foregroundStyle(colors.action)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(isWorking)
                    .accessibilityIdentifier("capture.priming.notNow")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                colors.background
                    .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(mode == .whatsNew ? "capture.whatsNew" : "capture.onboarding")
    }

    private var switches: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $findInCalendar.animation(reduceMotion ? nil : AppAnimation.quick)) {
                switchLabel(
                    symbol: "calendar",
                    title: "Find rental work in my calendar",
                    detail: "Looks back 90 days, then watches new events."
                )
            }
            .toggleStyle(InboxSwitchStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("capture.toggle.calendar")

            Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 56)

            Toggle(isOn: $askWhenVisitEnds) {
                switchLabel(
                    symbol: "bell.badge",
                    title: "Ask me when a visit ends",
                    detail: findInCalendar
                        ? "One short note after the event so you can log it with a tap. At most two a day, never at night."
                        : "Needs calendar suggestions."
                )
            }
            .toggleStyle(InboxSwitchStyle())
            .disabled(!findInCalendar)
            .opacity(findInCalendar ? 1 : 0.55)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("capture.toggle.eventPrompts")
        }
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: findInCalendar) { _, on in
            if !on { askWhenVisitEnds = false }
        }
    }

    private func switchLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(colors.action)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One suggestion row and one notification, so people see what they are agreeing to.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you’ll see")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(colors.textSecondary)
            SuggestionRowView(
                suggestion: Self.sampleSuggestion,
                propertyName: "Pine Cabin",
                badges: SuggestionBadges(notSure: false, mightAlreadyBeLogged: false, needsHours: false),
                now: Self.sampleNow
            )
            .padding(.horizontal, 12)
            .fixedSize(horizontal: false, vertical: true)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Example suggestion: 2 hours, Plumber at Pine Cabin, from your calendar")

            if askWhenVisitEnds {
                notificationPreview
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 10) {
            LHCompactLogo(size: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plumber visit just ended")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("Log 2h at Pine Cabin?")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer(minLength: 0)
            Text("now")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 12, y: 4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example notification: Plumber visit just ended. Log 2 hours at Pine Cabin?")
        .accessibilityIdentifier("capture.notificationPreview")
    }

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

    private var calendarDenied: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar access is off")
                .font(.title.weight(.bold))
                .foregroundStyle(colors.textPrimary)
            Text("To find rental work, LandlordHours needs Full Access to your calendar. You can turn it on in Settings any time. Logging by hand works either way.")
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(InboxPrimaryButtonStyle())
            Button("Continue without it") { onFinish(false) }
                .font(.body)
                .foregroundStyle(colors.action)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("capture.denied.continue")
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.denied")
    }
}

/// Onboarding → shell hand-off: land on the Inbox after the backfill intro.
enum CaptureSetupHandoff {
    @MainActor static var openInboxAfterOnboarding = false
}
