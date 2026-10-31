import SwiftUI

#if DEBUG
// MARK: - Pace reminders (2.3 design sandbox)
//
// Settings › Pace reminders: off until turned on, four kinds, quiet hours. Each notification is
// about pace OR one care item, never both. Fact first, then the number; no streaks, no guilt.

struct D23RemindersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var weekly = true
    @State private var behind = false
    @State private var care = true
    @State private var yearEnd = true
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                D23Section(title: "Your pace") {
                    LHRowGroup {
                        toggle("Weekly pace", "Sundays at 6 PM. Your hours this week and what’s left.", $weekly)
                        LHDivider(leadingInset: 16)
                        toggle("Behind pace", "Once, if you fall 2 weeks behind.", $behind)
                        LHDivider(leadingInset: 16)
                        toggle("Year end", "Dec 1 and Dec 20, with your total.", $yearEnd)
                    }
                }
                D23Section(title: "Your rentals") {
                    LHRowGroup {
                        toggle("Care plan", "When an item comes due at a rental. One at a time.", $care)
                    }
                }
                D23Section(title: "Quiet hours") {
                    LHRowGroup {
                        LHRow.Browse(title: "Never between", value: "8 PM – 8 AM", systemImage: "moon", tint: .neutral, action: {})
                    }
                }
                D23Section(title: "What a weekly pace looks like") {
                    D23NotificationCard(title: "Your week", message: "420 of 750 this year. About 38h a week gets you to 750 by Dec 31.",
                                        when: "Sun 6 PM", onCanvas: true)
                }
                LHFootnote("Pace reminders are about your hours. Care reminders are about upkeep, never hours.")
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhDetailScreen("Pace reminders", subtitle: "You pick which ones. A few a month at most.",
                        back: LHBackAction(label: "Back", identifier: "reminders.back") { dismiss() })
        .hidesAppTabBar()
        .accessibilityIdentifier("settings.reminders")
    }

    private func toggle(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        LHRow.Toggle(title, subtitle: subtitle, isOn: isOn)
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
    }
}

/// A notification as iOS draws it (mock): app tile, app name, time, title, body. On the canvas it
/// sits on a card surface; on the lock board it's a light material.
struct D23NotificationCard: View {
    let title: String
    let message: String
    let when: String
    var onCanvas = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            DormerTile(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dormer").font(.subheadline.weight(.semibold))
                        .foregroundStyle(onCanvas ? colors.textPrimary : Color.primary)
                    Spacer(minLength: 8)
                    Text(when).font(.footnote)
                        .foregroundStyle(onCanvas ? colors.textSecondary : Color.primary.opacity(0.7))
                }
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(onCanvas ? colors.textPrimary : Color.primary)
                Text(message).font(.subheadline)
                    .foregroundStyle(onCanvas ? colors.textPrimary : Color.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if onCanvas {
                shape.fill(colors.backgroundSecondary)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay { if onCanvas && colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
        .accessibilityElement(children: .combine)
    }
}

/// Two example notifications on a Lock Screen (mock of system UI): a weekly pace note and a
/// care item, sent separately.
struct D23LockBoard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(brandHex: "22408F"), Color(brandHex: "142A66"), Color(brandHex: "0B1230")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Sunday, November 1")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 36)
                Text("9:41")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .scaleEffect(2.4)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.top, 34)
                    .padding(.bottom, 30)
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    D23NotificationCard(title: "Your week",
                                        message: "420 of 750 this year. About 38h a week gets you to 750 by Dec 31.",
                                        when: "now")
                    D23NotificationCard(title: "Pine Cabin",
                                        message: "The gutters are due before the rains.",
                                        when: "Tue")
                }
                .padding(.horizontal, 10)
                .environment(\.colorScheme, .light)
                Text("MOCK OF SYSTEM UI")
                    .font(.caption2.weight(.semibold))
                    .monospaced()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.top, 24)
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
