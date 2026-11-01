import SwiftUI
import UserNotifications

// MARK: - Settings › Pace reminders (2.3 package D, frame n1)
//
// Four opt-in kinds in three groups, quiet hours, and a preview of the weekly note. Everything is
// off until the person turns it on. Turning the first one on asks for notification permission;
// a "no" leaves the switch off and says where to change it.

/// Asks the system about notification permission. A seam so the model is unit-testable.
protocol NudgeAuthorizing {
    func status() async -> UNAuthorizationStatus
    func request() async -> Bool
}

struct SystemNudgeAuthorizer: NudgeAuthorizing {
    func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

@MainActor
final class RemindersSettingsModel: ObservableObject {
    @Published private(set) var settings: NudgeSettings
    @Published private(set) var permissionBlocked = false
    @Published private(set) var probeLines: [String] = []

    private let store: NudgeSettingsStore
    private let authorizer: NudgeAuthorizing
    private let rebuild: @MainActor (String) async -> Void

    init(store: NudgeSettingsStore = NudgeSettingsStore(),
         authorizer: NudgeAuthorizing = SystemNudgeAuthorizer(),
         rebuild: @escaping @MainActor (String) async -> Void = { await NudgeScheduler.shared.rebuild(reason: $0) }) {
        self.store = store
        self.authorizer = authorizer
        self.rebuild = rebuild
        self.settings = store.load()
    }

    func binding(_ kind: NudgeKind) -> Binding<Bool> {
        Binding(get: { self.settings.isOn(kind) }, set: { on in Task { await self.set(kind, on: on) } })
    }

    func set(_ kind: NudgeKind, on: Bool) async {
        guard settings.isOn(kind) != on else { return }
        if on {
            var status = await authorizer.status()
            if status == .notDetermined { _ = await authorizer.request(); status = await authorizer.status() }
            guard status == .authorized || status == .provisional || status == .ephemeral else {
                permissionBlocked = true
                return
            }
            permissionBlocked = false
        }
        settings.set(kind, on)
        store.save(settings)
        if !on { NudgeScheduler.recordDisabled(kind) }
        await rebuild("settings")
        await refreshProbe()
    }

    func setQuietHours(start: Int, end: Int) async {
        settings.quietStartHour = start
        settings.quietEndHour = end
        store.save(settings)
        await rebuild("quiet-hours")
        await refreshProbe()
    }

    func refreshProbe() async {
        #if DEBUG
        if NudgeDebug.probeOn { probeLines = await NudgeDebug.pendingLines() }
        #endif
    }

    /// The weekly note as it would read now: the person's own numbers, or an example with none yet.
    func weeklyPreview(now: Date = Date()) -> NotificationText {
        if let facts = NudgeScheduler.liveFacts(now: now, calendar: .current), facts.yearHours > 0 {
            return NudgeCopy.weekly(hours: NudgePolicy.wholeHours(facts.yearHours), target: NudgePolicy.wholeHours(facts.targetHours),
                                    perWeek: NudgePolicy.hoursPerWeek(facts))
        }
        return NudgeCopy.weekly(hours: 420, target: 750, perWeek: 38)
    }

    /// "8 PM – 8 AM"
    func quietHoursLabel() -> String {
        guard settings.quietStartHour != settings.quietEndHour else { return NudgeStrings.t("reminders.quiet.none", "Off") }
        return "\(Self.hourLabel(settings.quietStartHour)) – \(Self.hourLabel(settings.quietEndHour))"
    }

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

struct RemindersSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var model = RemindersSettingsModel()
    @State private var showingQuietHours = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                section(NudgeStrings.t("reminders.section.pace", "Your pace")) {
                    LHRowGroup {
                        toggle(.weeklyPace, "reminders.weekly", NudgeStrings.t("reminders.weekly.title", "Weekly pace"),
                               NudgeStrings.t("reminders.weekly.subtitle", "Sundays at 6 PM. Your hours this week and what’s left."))
                        LHDivider(leadingInset: 16)
                        toggle(.behindPace, "reminders.behind", NudgeStrings.t("reminders.behind.title", "Behind pace"),
                               NudgeStrings.t("reminders.behind.subtitle", "Once, if you fall 2 weeks behind."))
                        LHDivider(leadingInset: 16)
                        toggle(.yearEnd, "reminders.yearEnd", NudgeStrings.t("reminders.yearEnd.title", "Year end"),
                               NudgeStrings.t("reminders.yearEnd.subtitle", "Dec 1 and Dec 20, with your total."))
                    }
                }
                section(NudgeStrings.t("reminders.section.rentals", "Your rentals")) {
                    LHRowGroup {
                        toggle(.carePlan, "reminders.care", NudgeStrings.t("reminders.care.title", "Care plan"),
                               NudgeStrings.t("reminders.care.subtitle", "When an item comes due at a rental. One at a time."))
                    }
                }
                if model.permissionBlocked {
                    LHRowGroup {
                        LHRow.Browse(title: NudgeStrings.t("reminders.blocked.title", "Notifications are off"),
                                     meta: NudgeStrings.t("reminders.blocked.meta", "Turn them on for Dormer in Settings."),
                                     systemImage: "bell.slash", tint: .caution, wrapsMeta: true,
                                     action: { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } })
                    }
                    .accessibilityIdentifier("reminders.blocked")
                }
                section(NudgeStrings.t("reminders.section.quiet", "Quiet hours")) {
                    LHRowGroup {
                        LHRow.Browse(title: NudgeStrings.t("reminders.quiet.title", "Never between"), value: model.quietHoursLabel(),
                                     systemImage: "moon", tint: .neutral, action: { showingQuietHours = true })
                            .accessibilityIdentifier("reminders.quiet")
                    }
                }
                section(NudgeStrings.t("reminders.section.preview", "What a weekly pace looks like")) {
                    let note = model.weeklyPreview()
                    NudgePreviewCard(title: note.title, message: note.body,
                                     when: NudgeStrings.t("reminders.preview.when", "Sun 6 PM"))
                        .accessibilityIdentifier("reminders.preview")
                }
                LHFootnote(NudgeStrings.t("reminders.footnote", "Pace reminders are about your hours. Care reminders are about upkeep, never hours."))
                #if DEBUG
                if NudgeDebug.probeOn { probe }
                #endif
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhDetailScreen(NudgeStrings.t("reminders.title", "Pace reminders"),
                        subtitle: NudgeStrings.t("reminders.subtitle", "You pick which ones. A few a month at most."),
                        back: LHBackAction(label: NudgeStrings.t("reminders.back", "Back"), identifier: "reminders.back") { dismiss() })
        .hidesAppTabBar()
        .accessibilityIdentifier("settings.reminders")
        .sheet(isPresented: $showingQuietHours) { QuietHoursSheet(model: model) }
        .task { await model.refreshProbe() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(title).padding(.horizontal, 4)
            content()
        }
    }

    private func toggle(_ kind: NudgeKind, _ id: String, _ title: String, _ subtitle: String) -> some View {
        LHRow.Toggle(title, subtitle: subtitle, isOn: model.binding(kind))
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .accessibilityIdentifier(id)
    }

    #if DEBUG
    private var probe: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.probeLines.isEmpty ? "none" : model.probeLines.joined(separator: "\n"))
                .font(.caption2.monospaced())
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("nudge.probe")
            Text("quiet \(model.settings.quietStartHour)-\(model.settings.quietEndHour) on \(model.settings.enabledKinds.map(\.rawValue).joined(separator: ","))")
                .font(.caption2.monospaced())
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("nudge.probe.settings")
            Button("Refresh") { Task { await model.refreshProbe() } }
                .font(.caption2)
                .accessibilityIdentifier("nudge.probe.refresh")
        }
    }
    #endif
}

// MARK: - Quiet hours

private struct QuietHoursSheet: View {
    @ObservedObject var model: RemindersSettingsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var start: Int
    @State private var end: Int
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(model: RemindersSettingsModel) {
        self.model = model
        _start = State(initialValue: model.settings.quietStartHour)
        _end = State(initialValue: model.settings.quietEndHour)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LHRowGroup {
                    HStack(alignment: .top, spacing: 0) {
                        wheel(NudgeStrings.t("reminders.quiet.from", "From"), $start, id: "reminders.quiet.start")
                        wheel(NudgeStrings.t("reminders.quiet.to", "Until"), $end, id: "reminders.quiet.end")
                    }
                    .padding(.vertical, 8)
                }
                LHFootnote(NudgeStrings.t("reminders.quiet.footnote", "Nothing is sent in this window. A reminder due then waits until it ends."))
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 32)
        }
        .background(colors.background)
        .lhSheetScreen(NudgeStrings.t("reminders.quiet.sheetTitle", "Quiet hours"), onClose: { dismiss() }, background: colors.background)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("reminders.quiet.sheet")
        .onChange(of: start) { _, _ in save() }
        .onChange(of: end) { _, _ in save() }
    }

    private func save() { Task { await model.setQuietHours(start: start, end: end) } }

    /// A captioned hour wheel: "From" and "Until" side by side, the way iOS sets a time range.
    private func wheel(_ title: String, _ value: Binding<Int>, id: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textSecondary)
                .padding(.top, 8)
            Picker(title, selection: value) {
                ForEach(0..<24, id: \.self) { Text(RemindersSettingsModel.hourLabel($0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 150)
            .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - A notification as iOS draws it

/// The weekly note, drawn like a system notification: app tile, app name, time, title, body.
struct NudgePreviewCard: View {
    let title: String
    let message: String
    let when: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            DormerTile(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dormer").font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    Spacer(minLength: 8)
                    Text(when).font(.footnote).foregroundStyle(colors.textSecondary)
                }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                Text(message).font(.subheadline).foregroundStyle(colors.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background { shape.fill(colors.backgroundSecondary) }
        .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
        .accessibilityElement(children: .combine)
    }
}
