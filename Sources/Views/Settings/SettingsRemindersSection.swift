import SwiftUI

// MARK: - Settings › Pace reminders (2.3, package D)
//
// SettingsView places this right after the auto-capture section, inside its List and
// NavigationStack. One Section holds the "Pace reminders" row, which pushes RemindersSettingsView
// (frame n1). The value reads "Off" until the person turns a kind on.
struct SettingsRemindersSection: View {
    @State private var showing = false
    @State private var summary = SettingsRemindersSection.summaryText(NudgeScheduler.currentSettings())
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            LHRow.Browse(title: NudgeStrings.t("settings.reminders.title", "Pace reminders"),
                         meta: NudgeStrings.t("settings.reminders.meta", "Hours and care, only if you want them"),
                         value: summary, systemImage: "bell", tint: .neutral,
                         action: { showing = true })
                .longTailRow()
                .accessibilityIdentifier("settings.paceReminders")
        } header: {
            LHSectionHeader(NudgeStrings.t("settings.reminders.section", "Reminders")).textCase(nil)
        }
        .navigationDestination(isPresented: $showing) { RemindersSettingsView() }
        .onChange(of: showing) { _, isShowing in
            if !isShowing { summary = Self.summaryText(NudgeScheduler.currentSettings()) }
        }
        .onAppear {
            summary = Self.summaryText(NudgeScheduler.currentSettings())
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-LHOpenReminders") { showing = true }
            #endif
        }
    }

    static func summaryText(_ settings: NudgeSettings) -> String {
        let count = settings.enabledKinds.count
        return count == 0 ? NudgeStrings.t("settings.reminders.off", "Off") : NudgeStrings.f("settings.reminders.on", "%lld on", count)
    }
}
