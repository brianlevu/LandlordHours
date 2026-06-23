import AppIntents
import Foundation

enum AppIntentNavigationRequest {
    static let pendingDestinationKey = "LandlordHours.pendingAppIntentDestination"
}

enum LandlordHoursIntentDestination: String, AppEnum {
    case home
    case properties
    case track
    case reports
    case settings

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "LandlordHours Destination")

    static var caseDisplayRepresentations: [LandlordHoursIntentDestination: DisplayRepresentation] = [
        .home: "Home",
        .properties: "Properties",
        .track: "Track Time",
        .reports: "Reports",
        .settings: "Settings"
    ]

    var tabIndex: Int {
        switch self {
        case .home: return 0
        case .properties: return 1
        case .track: return 2
        case .reports: return 3
        case .settings: return 4
        }
    }

    var confirmation: String {
        switch self {
        case .home: return "Opening your LandlordHours home."
        case .properties: return "Opening your properties."
        case .track: return "Opening time tracking."
        case .reports: return "Opening reports."
        case .settings: return "Opening settings."
        }
    }
}

struct OpenLandlordHoursIntent: AppIntent {
    static var title: LocalizedStringResource = "Open LandlordHours"
    static var description = IntentDescription("Open LandlordHours to a useful destination.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination", default: .track)
    var destination: LandlordHoursIntentDestination

    init() {
        destination = .track
    }

    init(destination: LandlordHoursIntentDestination) {
        self.destination = destination
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$destination)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(destination.rawValue, forKey: AppIntentNavigationRequest.pendingDestinationKey)
        return .result(dialog: IntentDialog(stringLiteral: destination.confirmation))
    }
}

struct GetLandlordHoursSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Landlord Hours"
    static var description = IntentDescription("Summarize this year's landlord hours, pace, and next useful action.")

    @Parameter(title: "Tax Year")
    var taxYear: Int?

    init() {
        taxYear = nil
    }

    init(taxYear: Int?) {
        self.taxYear = taxYear
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize landlord hours")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let year = taxYear ?? Calendar.current.component(.year, from: Date())
        let context = LandlordHoursIntentStore.engagementContext(taxYear: year)
        let snapshot = EngagementIntelligenceService.shared.snapshot(for: context)
        let recommendation = EngagementIntelligenceService.shared.recommendation(for: context)
        let summary = LandlordHoursIntentCopy.summaryDialog(
            year: year,
            context: context,
            snapshot: snapshot,
            recommendation: recommendation
        )
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

struct ReviewLandlordHoursNextActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Next Landlord Action"
    static var description = IntentDescription("Find the next useful action without showing generic reminders.")
    static var openAppWhenRun = true

    static var parameterSummary: some ParameterSummary {
        Summary("Review my next LandlordHours action")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = LandlordHoursIntentStore.engagementContext()
        let recommendation = EngagementIntelligenceService.shared.recommendation(for: context)
        let destination = LandlordHoursIntentCopy.intentDestination(for: recommendation)

        UserDefaults.standard.set(destination.rawValue, forKey: AppIntentNavigationRequest.pendingDestinationKey)

        if recommendation.surface == .none {
            return .result(dialog: IntentDialog(stringLiteral: "You logged recently. There is nothing urgent to review right now."))
        }

        return .result(dialog: IntentDialog(stringLiteral: "\(recommendation.title). \(recommendation.message)"))
    }
}

struct LandlordHoursShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLandlordHoursIntent(destination: .track),
            phrases: [
                "Log landlord time in \(.applicationName)",
                "Track landlord hours in \(.applicationName)"
            ],
            shortTitle: "Log Time",
            systemImageName: "clock"
        )

        AppShortcut(
            intent: OpenLandlordHoursIntent(destination: .reports),
            phrases: [
                "Show my landlord reports in \(.applicationName)",
                "Open landlord reports in \(.applicationName)"
            ],
            shortTitle: "Open Reports",
            systemImageName: "chart.bar"
        )

        AppShortcut(
            intent: GetLandlordHoursSummaryIntent(),
            phrases: [
                "Summarize my landlord hours in \(.applicationName)",
                "How am I doing in \(.applicationName)"
            ],
            shortTitle: "Year Summary",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: ReviewLandlordHoursNextActionIntent(),
            phrases: [
                "What should I do next in \(.applicationName)",
                "Review my next landlord action in \(.applicationName)"
            ],
            shortTitle: "Next Action",
            systemImageName: "checklist"
        )
    }
}

private enum LandlordHoursIntentStore {
    static func engagementContext(taxYear: Int = Calendar.current.component(.year, from: Date())) -> EngagementContext {
        EngagementContext(
            now: Date(),
            taxYear: taxYear,
            properties: loadProperties(),
            timeEntries: loadTimeEntries(),
            calendarDraftCount: 0,
            isTimerRunning: UserDefaults.standard.bool(forKey: UserScope.key("LandlordHours.timer")),
            timerStartTime: UserDefaults.standard.object(forKey: UserScope.key("timerStartTime")) as? Date,
            notificationPermission: .notDetermined,
            recentDismissals: [],
            isProUser: SubscriptionManager.shared.isPro,
            targetHours: GoalManager.shared.globalGoalType.hoursRequired
        )
    }

    private static func loadProperties() -> [RentalProperty] {
        guard let data = UserDefaults.standard.data(forKey: UserScope.key("LandlordHours.properties")),
              let properties = try? JSONDecoder().decode([RentalProperty].self, from: data) else {
            return []
        }
        return properties
    }

    private static func loadTimeEntries() -> [TimeEntry] {
        guard let data = UserDefaults.standard.data(forKey: UserScope.key("LandlordHours.entries")),
              let entries = try? JSONDecoder().decode([TimeEntry].self, from: data) else {
            return []
        }
        return entries
    }
}

private enum LandlordHoursIntentCopy {
    static func summaryDialog(
        year: Int,
        context: EngagementContext,
        snapshot: EngagementSnapshot,
        recommendation: EngagementRecommendation
    ) -> String {
        guard !context.properties.isEmpty else {
            return "No properties are set up yet. Add your first property before pace checks begin."
        }

        let hours = String(format: "%.1f", snapshot.yearHours)
        let daysLeft = snapshot.daysRemainingInYear
        let pace = snapshot.isBehindPace ? "behind pace" : "on pace"

        if recommendation.surface == .none {
            return "\(year): \(hours) qualifying hours logged, \(daysLeft) days left, and you are \(pace). No urgent action right now."
        }

        return "\(year): \(hours) qualifying hours logged, \(daysLeft) days left, and you are \(pace). \(recommendation.title): \(recommendation.message)"
    }

    static func intentDestination(for recommendation: EngagementRecommendation) -> LandlordHoursIntentDestination {
        switch recommendation.destination {
        case .addProperty: return .properties
        case .track, .timerReview: return .track
        case .reports, .export, .calendarReview: return .reports
        case .none: return .home
        }
    }
}
