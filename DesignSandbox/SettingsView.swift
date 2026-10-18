import SwiftUI

/// Settings (Flighty inset-grouped list, Meetup sentence-case headers, Wispr toggle-with-subtitle rows).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var calendar = true
    @State private var receipts = true
    @State private var location = false
    @State private var notify = true
    @State private var pcc = true
    @State private var spouse = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text("MA")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LH.action)
                            .frame(width: 52, height: 52)
                            .background(LH.actionWash, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Maria Alvarez").font(.body.weight(.semibold))
                            Text("Pro · Paid once")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LH.positive)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(LH.positiveWash, in: Capsule())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    SubtitleToggle(symbol: "calendar", title: "Calendar",
                                   subtitle: "Suggest work from events. Titles are read on your iPhone.", isOn: $calendar)
                    SubtitleToggle(symbol: "doc.text", title: "Receipts from the Share sheet",
                                   subtitle: "Reads store, total and date. You add the hours.", isOn: $receipts)
                    SubtitleToggle(symbol: "location", title: "Location", badge: "BETA",
                                   subtitle: "Notice visits to your property addresses. Needs Always access.", isOn: $location)
                    SubtitleToggle(symbol: "bell.badge", title: "Ask when an event ends",
                                   subtitle: "At most twice a day, never after 9 pm.", isOn: $notify)
                    SubtitleToggle(symbol: "lock.icloud", title: "Private Cloud Compute",
                                   subtitle: "Apple's private servers help read hard receipts. Nothing is stored.", isOn: $pcc)
                } header: {
                    SectionHeader("Auto-capture")
                } footer: {
                    Text("Nothing goes in your record until you confirm it. Reading happens on your iPhone first.")
                }

                Section {
                    ValueRowNav(symbol: "target", title: "Goal", value: "REPS · 750 h")
                    ValueRowNav(symbol: "calendar.badge.clock", title: "Tax year", value: "2026")
                    SubtitleToggle(symbol: "person.2", title: "Track spouse hours",
                                   subtitle: "Counts toward the 750 hours if you file jointly.", isOn: $spouse)
                } header: { SectionHeader("Tax profile") }

                Section {
                    ValueRowNav(symbol: "house", title: "Properties", value: "2")
                    ValueRowNav(symbol: "tag", title: "Kinds of work", value: "8")
                    ValueRowNav(symbol: "icloud", title: "iCloud sync", value: "On")
                } header: { SectionHeader("Data") }

                Section {
                    ValueRowNav(symbol: "questionmark.circle", title: "Help", value: "")
                    ValueRowNav(symbol: "envelope", title: "Contact support", value: "")
                    ValueRowNav(symbol: "arrow.clockwise", title: "Restore purchase", value: "")
                } header: { SectionHeader("Support") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

struct SectionHeader: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.leading, -4)
            .padding(.bottom, 2)
    }
}

struct SubtitleToggle: View {
    var symbol: String
    var title: String
    var badge: String? = nil
    var subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(LH.action)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(LH.actionWash, in: Capsule())
                        }
                    }
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .tint(LH.action)
        .padding(.vertical, 4)
    }
}

struct ValueRowNav: View {
    var symbol: String
    var title: String
    var value: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 36)
    }
}
