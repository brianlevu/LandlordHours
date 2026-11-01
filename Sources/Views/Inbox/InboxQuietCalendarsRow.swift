import SwiftUI

// MARK: - Settings › Auto-capture › Calendars (2.3 package F)
//
// Which calendars the Inbox looks at. A browse row in `AutoCaptureSettingsSection` (package A's
// seam line) opens a sheet of toggles, one per calendar, grouped by account (as the Calendar app's
// own calendar list is). Turning a calendar off takes its pending items out of the Inbox (not a
// dismissal: turning it back on brings them back on the next scan) and the detector stops reading
// it (`CalendarDetector.scannedCalendarIds`). The choice is per profile, on this device only.
//
// The same file holds the Inbox's one-time prompt (`InboxQuietCalendarPrompt`): once a calendar has
// three "Not rental work" answers and no confirms, the Inbox asks once whether to stop checking it.

struct InboxQuietCalendarsRow: View {
    @State private var showSheet = false
    @State private var summary = InboxQuietCalendarsRow.Summary(total: 0, checked: 0)
    @Environment(\.scenePhase) private var scenePhase

    struct Summary: Equatable {
        var total: Int
        var checked: Int
    }

    var body: some View {
        Group {
            // Without calendar access there is nothing to list; the Calendar toggle above says why.
            if summary.total > 0 {
                LHRow.Browse(title: InboxQuietText.rowTitle,
                             meta: InboxQuietText.rowMeta(checked: summary.checked, total: summary.total),
                             systemImage: "calendar", tint: .neutral,
                             action: { showSheet = true })
                    .longTailRow()
                    .accessibilityHint(InboxQuietText.rowHint)
                    .accessibilityIdentifier("settings.capture.calendars")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in reload() }
        .sheet(isPresented: $showSheet, onDismiss: reload) {
            InboxQuietCalendarsSheet { showSheet = false }
        }
    }

    private func reload() {
        guard CaptureOptIn.calendarSuggestionsEnabled() else {
            summary = Summary(total: 0, checked: 0)
            return
        }
        let all = InboxQuietCalendars.list()
        let off = InboxQuietCalendars.excluded()
        summary = Summary(total: all.count, checked: all.filter { !off.contains($0.id) }.count)
    }
}

// MARK: - The sheet

struct InboxQuietCalendarsSheet: View {
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var calendars: [CalendarInfo] = []
    @State private var off: Set<String> = []
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    /// Accounts in the order the calendars came (already sorted by account, then title).
    private var accounts: [String] {
        var seen = Set<String>()
        return calendars.map(\.account).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            Section {
                Text(InboxQuietText.sheetIntro)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // On the section headers' 16pt line, inside the row (a 0 inset clipped the first glyph).
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("calendars.intro")
            }
            ForEach(accounts, id: \.self) { account in
                Section {
                    ForEach(calendars.filter { $0.account == account }) { calendar in
                        LHRow.Toggle(calendar.title,
                                     subtitle: calendar.isWork ? InboxQuietText.workSubtitle : nil,
                                     isOn: Binding(get: { !off.contains(calendar.id) },
                                                   set: { set(calendar.id, checked: $0) }))
                            .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
                            .accessibilityIdentifier("calendars.toggle.\(calendar.id)")
                    }
                } header: {
                    LHSectionHeader(account.isEmpty ? InboxQuietText.otherAccount : account).textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
        .scrollContentBackground(.hidden)
        .lhListGutter()
        .lhSheetScreen(InboxQuietText.rowTitle, onClose: onClose, background: colors.background)
        .background(colors.background)
        .lhSheetPresentation()
        .onAppear {
            calendars = InboxQuietCalendars.list()
            off = InboxQuietCalendars.excluded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendars.sheet")
    }

    private func set(_ id: String, checked: Bool) {
        if checked { off.remove(id) } else { off.insert(id) }
        InboxQuietCalendars.apply(checked: checked, calendarId: id)
    }
}

// MARK: - The one-time prompt in the Inbox

/// "Stop checking “Work”?" A question with two answers, so a card (§1.1), never a row: it sits above
/// the To confirm card. Shown once per calendar (3+ "Not rental work", no confirms), answered once.
struct InboxQuietCalendarPrompt: View {
    let calendar: CalendarInfo
    let dismissals: Int
    var onStop: () -> Void
    var onKeep: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(InboxQuietText.promptTitle(calendar.title))
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("inbox.quiet.prompt.title")
            Text(InboxQuietText.promptBody(dismissals))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            let buttons = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            buttons {
                Button(InboxQuietText.promptStop, action: onStop)
                    .buttonStyle(LHButton.secondary)
                    .accessibilityIdentifier("inbox.quiet.prompt.stop")
                Button(InboxQuietText.promptKeep, action: onKeep)
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("inbox.quiet.prompt.keep")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.quiet.prompt")
    }
}

// MARK: - Calendar list and the choice

extension InboxQuietCalendars {
    /// The device's event calendars (EventKit), or the DEBUG stand-ins for frames and UI tests.
    @MainActor static func list() -> [CalendarInfo] {
        #if DEBUG
        if let fake = debugCalendars { return fake }
        #endif
        return EventKitCalendarSource().calendars()
    }

    /// Turns one calendar on or off for this profile. Off: its pending items leave the Inbox now.
    @MainActor static func apply(checked: Bool, calendarId: String) {
        setChecked(checked, calendarId: calendarId)
        if !checked { AppModelHost.shared.suggestionStore?.removePending(inCalendars: [calendarId]) }
        NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
    }

    #if DEBUG
    /// `-LHInboxQuietCalendars`: two stand-in calendars (a work account and iCloud) instead of
    /// EventKit, so Settings › Calendars and the Inbox prompt can be captured without calendar data.
    /// The work one is the Inbox seed's calendar ("debug-calendar").
    @MainActor static var debugCalendars: [CalendarInfo]? {
        guard ProcessInfo.processInfo.arguments.contains("-LHInboxQuietCalendars") else { return nil }
        return [
            CalendarInfo(id: "debug-home", title: "Home", account: "iCloud", color: nil, isWork: false),
            CalendarInfo(id: "debug-rentals", title: "Rentals", account: "iCloud", color: nil, isWork: false),
            CalendarInfo(id: "debug-calendar", title: "Work", account: "sam@example-corp.com", color: nil, isWork: true),
        ]
    }
    #endif
}

// MARK: - Strings (table InboxQuiet)

enum InboxQuietText {
    static var rowTitle: String { String(localized: "quiet.calendars.title", defaultValue: "Calendars", table: "InboxQuiet") }

    static func rowMeta(checked: Int, total: Int) -> String {
        checked == total
            ? String(localized: "quiet.calendars.all", defaultValue: "All turned on", table: "InboxQuiet")
            : String(localized: "quiet.calendars.some", defaultValue: "\(checked) of \(total) turned on", table: "InboxQuiet",
                     comment: "How many calendars the Inbox reads, e.g. 2 of 3 turned on")
    }

    static var rowHint: String { String(localized: "quiet.calendars.hint", defaultValue: "Opens the list of calendars", table: "InboxQuiet") }

    static var sheetIntro: String {
        String(localized: "quiet.calendars.intro", defaultValue: "We look for rental work only in the calendars you turn on. Turn off a day-job calendar to keep its meetings out of your Inbox.", table: "InboxQuiet")
    }

    static var workSubtitle: String { String(localized: "quiet.calendars.work", defaultValue: "Work account", table: "InboxQuiet") }
    static var otherAccount: String { String(localized: "quiet.calendars.other", defaultValue: "Other", table: "InboxQuiet") }

    static func promptTitle(_ calendar: String) -> String {
        String(localized: "quiet.prompt.title", defaultValue: "Stop checking “\(calendar)”?", table: "InboxQuiet",
               comment: "One-time question about a calendar, e.g. Stop checking “Work”?")
    }

    static func promptBody(_ count: Int) -> String {
        String(localized: "quiet.prompt.body", defaultValue: "You said \(count) events from this calendar aren’t rental work. You can change this in Settings.", table: "InboxQuiet",
               comment: "Why we ask, e.g. You said 3 events from this calendar aren’t rental work.")
    }

    static var promptStop: String { String(localized: "quiet.prompt.stop", defaultValue: "Stop checking", table: "InboxQuiet") }
    static var promptKeep: String { String(localized: "quiet.prompt.keep", defaultValue: "Keep checking", table: "InboxQuiet") }
    static var promptStoppedAnnouncement: String {
        String(localized: "quiet.prompt.stopped", defaultValue: "We stopped checking that calendar.", table: "InboxQuiet")
    }

    // The collapsed "Not sure" row and its screen.
    static var maybeTitle: String { String(localized: "quiet.maybe.title", defaultValue: "Not sure", table: "InboxQuiet") }
    static var maybeMeta: String { String(localized: "quiet.maybe.meta", defaultValue: "Might be rental work", table: "InboxQuiet") }
    static var maybeHint: String { String(localized: "quiet.maybe.hint", defaultValue: "Opens the items we aren’t sure about", table: "InboxQuiet") }
    static var maybeSection: String { String(localized: "quiet.maybe.section", defaultValue: "Check when you have time", table: "InboxQuiet") }
    static var maybeFooter: String {
        String(localized: "quiet.maybe.footer", defaultValue: "These aren’t counted in To confirm, and we never send an alert for them.", table: "InboxQuiet")
    }
    static var maybeEmpty: String { String(localized: "quiet.maybe.empty", defaultValue: "Nothing left to check.", table: "InboxQuiet") }
}
