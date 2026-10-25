import SwiftUI

// MARK: - The 90-day look-back, in the Inbox (standard §1.1, §1.13)
//
// While the look-back runs: one grouped row, "Looking through your calendar…", how far it is and
// how many it has found, a thin progress line and Cancel. After a stop: "Run again". If calendar
// access went away: the Settings path. Suggestions stream into the list under it as they are
// classified. No blueprint paper (v2): `LHRowGroup`, `LHButton`, tokens.

struct BackfillProgressHeader: View {
    @ObservedObject var job: BackfillJob
    /// Found so far, from the same source as the tab badge (the inbox's backfill items).
    var found: Int
    var onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        switch job.phase {
        case .scanning(let completed, let total):
            scanning(completed: completed, total: total)
        case .cancelled:
            stopped
        case .blocked:
            blocked
        case .idle, .finished:
            EmptyView()
        }
    }

    // MARK: Scanning

    private func scanning(completed: Int, total: Int) -> some View {
        LHRowGroup {
            VStack(alignment: .leading, spacing: 10) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                          : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "backfill.scanning.title", defaultValue: "Looking through your calendar…", table: "Inbox"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                        // Two lines that each stay whole ("12 of 80 events" / "5 found so far"), so a
                        // count never wraps away from its words.
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.eventsLine(completed: completed, total: total))
                            if total > 0 && found > 0 {
                                Text(Self.foundLine(found))
                            }
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(colors.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(String(localized: "backfill.cancel", defaultValue: "Cancel", table: "Inbox")) { job.cancel() }
                        .buttonStyle(LHButton.tertiary)
                        .accessibilityHint(String(localized: "backfill.cancel.hint", defaultValue: "Stops looking back. You can run it again.", table: "Inbox"))
                        .accessibilityIdentifier("backfill.cancel")
                }
                BackfillProgressLine(fraction: total > 0 ? Double(completed) / Double(total) : 0)
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: LHMetrics.rowMinHeight)
        }
        // No count animation: the "found so far" number ticks in the same frame as the Inbox
        // badge (both read the inbox's backfill count).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "backfill.scanning.a11y",
                                   defaultValue: "Looking through your calendar. \(Self.detail(completed: completed, total: total, found: found))",
                                   table: "Inbox"))
        .accessibilityIdentifier("inbox.backfill.header")
    }

    static func eventsLine(completed: Int, total: Int) -> String {
        guard total > 0 else {
            return String(localized: "backfill.events.getting", defaultValue: "Getting your events", table: "Inbox")
        }
        return String(localized: "backfill.events.progress", defaultValue: "\(completed) of \(total) events", table: "Inbox")
    }

    static func foundLine(_ found: Int) -> String {
        String(localized: "backfill.found.line", defaultValue: "\(found) found so far", table: "Inbox")
    }

    /// "Getting your events" → "12 of 80 events · 5 found so far" (VoiceOver: one sentence).
    static func detail(completed: Int, total: Int, found: Int) -> String {
        guard total > 0 else { return eventsLine(completed: 0, total: 0) }
        let events = eventsLine(completed: completed, total: total)
        guard found > 0 else { return events }
        return "\(events) · \(foundLine(found))"
    }

    // MARK: Stopped

    private var stopped: some View {
        notice(
            title: String(localized: "backfill.stopped.title", defaultValue: "Stopped looking back", table: "Inbox"),
            message: found > 0
                ? String(localized: "backfill.stopped.found", defaultValue: "What we found so far is below. Run it again to finish the last 90 days.", table: "Inbox")
                : String(localized: "backfill.stopped.none", defaultValue: "Run it again any time to check the last 90 days.", table: "Inbox"),
            buttonTitle: String(localized: "backfill.runAgain", defaultValue: "Run again", table: "Inbox"),
            buttonIdentifier: "inbox.backfill.retry",
            action: onRetry
        )
        .accessibilityIdentifier("inbox.backfill.stopped")
    }

    // MARK: Blocked

    private var blocked: some View {
        notice(
            title: String(localized: "backfill.blocked.title", defaultValue: "We can’t read your calendar", table: "Inbox"),
            message: String(localized: "backfill.blocked.body", defaultValue: "Turn on Full Access for LandlordHours in Settings, then run it again.", table: "Inbox"),
            buttonTitle: String(localized: "backfill.settings", defaultValue: "Settings", table: "Inbox"),
            buttonIdentifier: "inbox.backfill.settings"
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
        .accessibilityIdentifier("inbox.backfill.blocked")
    }

    private func notice(title: String, message: String, buttonTitle: String, buttonIdentifier: String,
                        action: @escaping () -> Void) -> some View {
        LHRowGroup {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(buttonTitle, action: action)
                    .buttonStyle(LHButton.secondary)
                    .accessibilityIdentifier(buttonIdentifier)
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A thin progress line: `border` track, `action` fill.
struct BackfillProgressLine: View {
    var fraction: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.border)
                Capsule().fill(colors.action)
                    .frame(width: max(3, g.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}
