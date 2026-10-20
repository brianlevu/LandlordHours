import SwiftUI

// §4 Notifications — every notification 2.0 sends, with rewritten copy.
// Sent today (release/2.0): the end-of-visit prompt (EndOfEventScheduler), its follow-ups
// (CaptureActionSupport), and two engagement nudges that reach `.notification`: no logging for
// 7+ days, and the Nov–Dec "make your PDF" nudge. No weekly summary exists.
// Copy rule: the event name is the title; the body is one plain question or sentence.

struct SFNote: Identifiable {
    var id: String { title + body }
    var title: String
    var body: String
    var time: String
}

enum SFNotes {
    static let endOfVisit = SFNote(title: "Plumber visit just ended", body: "Log 2h at Pine Cabin?", time: "now")
    static let quiet = SFNote(title: "Anything for your rentals lately?", body: "Nothing logged in 9 days. Add what you did while you still remember it.", time: "9:00 AM")
    static let yearEnd = SFNote(title: "Tax time is coming", body: "You have 212h logged for 2026. You can make the PDF for your CPA any time.", time: "Yesterday")

    static let maybeLogged = SFNote(title: "Plumber visit", body: "This might already be in your records. Tap to check before saving.", time: "now")
    static let moved = SFNote(title: "Showing at Pine Cabin", body: "This moved on your calendar. Tap to check the time before saving.", time: "8m ago")
    static let muteOffer = SFNote(title: "Dentist", body: "Got it, that’s not rental work. Stop suggesting events like this one?", time: "1h ago")
    static let queued = SFNote(title: "Call with Sam", body: "Not logged yet, because iCloud didn’t finish syncing. Tap to check it.", time: "Yesterday")
}

struct SFNotificationPlatter: View {
    let n: SFNote
    var expanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SFAppIcon(size: 38).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(n.title).font(.system(size: 15, weight: .semibold)).lineLimit(expanded ? 3 : 1)
                    Spacer(minLength: 6)
                    Text(n.time).font(.system(size: 13)).foregroundStyle(secondary)
                }
                Text(n.body).font(.system(size: 15)).lineLimit(expanded ? 6 : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.55)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var primary: Color { scheme == .dark ? .white : Color(hex: 0x111111) }
    private var secondary: Color { scheme == .dark ? .white.opacity(0.62) : Color(hex: 0x3C3C43).opacity(0.85) }
}

struct SFNotificationLock: View {
    enum Set { case main, followUps }
    let set: Set

    private var notes: [SFNote] {
        switch set {
        case .main: [SFNotes.endOfVisit, SFNotes.quiet, SFNotes.yearEnd]
        case .followUps: [SFNotes.maybeLogged, SFNotes.moved, SFNotes.muteOffer, SFNotes.queued]
        }
    }

    var body: some View {
        SFLockChrome(inlineView: nil) {
            EmptyView()
        } below: {
            VStack(spacing: 8) {
                ForEach(notes) { SFNotificationPlatter(n: $0) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .layoutPriority(1)
        }
    }
}

/// Long-press on the end-of-visit prompt: the platter grows and the three actions appear.
struct SFNotificationExpanded: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            SFWallpaper().blur(radius: 24).overlay(Color.black.opacity(scheme == .dark ? 0.35 : 0.12)).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 150)
                SFNotificationPlatter(n: SFNotes.endOfVisit, expanded: true)
                VStack(spacing: 0) {
                    action("Log it", "checkmark.circle")
                    Divider().overlay(divider)
                    action("Edit…", "pencil")
                    Divider().overlay(divider)
                    action("Not rental work", "xmark.circle")
                }
                .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.55)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(width: 250)
                Spacer()
                HStack { Spacer(); SystemMockTag(); Spacer() }
            }
            .padding(.horizontal, 10)
        }
    }

    private var divider: Color { scheme == .dark ? .white.opacity(0.15) : .black.opacity(0.12) }

    private func action(_ t: String, _ s: String) -> some View {
        HStack {
            Text(t).font(.system(size: 17))
            Spacer()
            Image(systemName: s).font(.system(size: 17))
        }
        .foregroundStyle(scheme == .dark ? .white : Color(hex: 0x111111))
        .padding(.horizontal, 16).frame(height: 46)
    }
}
