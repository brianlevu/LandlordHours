import AppIntents
import Foundation
import SwiftUI

// MARK: - Siri and App Shortcuts (2.0 surfaces lane)
//
// Tile colour navy (closest ShortcutTileColor to blueprint #1E3FA6; purple retired). Destinations
// use the 2.0 names: Today, Inbox, Records, Properties, Log time (plus Reports and Settings, which
// open from Today). Copy: the surfaces copy sheet §5. Raw values keep the 1.x strings so
// destinations already persisted by notifications, intents and widgets keep resolving.

enum AppIntentNavigationRequest {
    static let pendingDestinationKey = "LandlordHours.pendingAppIntentDestination"
}

enum LandlordHoursIntentDestination: String, AppEnum {
    case home
    case inbox
    case records
    case properties
    case track
    case reports
    case settings

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Place in LandlordHours")

    static var caseDisplayRepresentations: [LandlordHoursIntentDestination: DisplayRepresentation] = [
        .home: "Today",
        .inbox: "Inbox",
        .records: "Records",
        .properties: "Properties",
        .track: "Log time",
        .reports: "Reports",
        .settings: "Settings"
    ]

    var tabIndex: Int {
        switch self {
        case .home: return ShellTab.todayIndex
        case .inbox: return ShellTab.inboxIndex
        case .records: return ShellTab.recordsIndex
        case .properties: return ShellTab.propertiesIndex
        case .track: return ShellTab.logTimeIndex
        case .reports: return ShellTab.reportsIndex
        case .settings: return ShellTab.settingsIndex
        }
    }

    var confirmation: String {
        switch self {
        case .home: return "Opening Today."
        case .inbox: return "Opening Inbox."
        case .records: return "Opening Records."
        case .properties: return "Opening Properties."
        case .track: return "Opening Log time."
        case .reports: return "Opening Reports."
        case .settings: return "Opening Settings."
        }
    }
}

struct OpenLandlordHoursIntent: AppIntent {
    static var title: LocalizedStringResource = "Open LandlordHours"
    static var description = IntentDescription("Open LandlordHours to Today, Inbox, Records, Properties or Log time.")
    static var openAppWhenRun = true

    @Parameter(title: "Place", default: .track)
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
    static var title: LocalizedStringResource = "Check my hours"
    static var description = IntentDescription("Your hours this year, your pace, and what’s waiting to confirm.")

    @Parameter(title: "Tax Year")
    var taxYear: Int?

    init() {
        taxYear = nil
    }

    init(taxYear: Int?) {
        self.taxYear = taxYear
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Check my hours")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let year = taxYear ?? Calendar.current.component(.year, from: Date())
        let (summary, surface) = await LandlordHoursIntentStore.summary(taxYear: year)
        return .result(
            dialog: IntentDialog(stringLiteral: summary),
            view: LandlordHoursSiriSnippet(display: WidgetSurfaceDisplay(snapshot: surface))
        )
    }
}

struct ReviewLandlordHoursNextActionIntent: AppIntent {
    static var title: LocalizedStringResource = "See what’s waiting"
    static var description = IntentDescription("Open what needs you next, starting with anything to confirm.")
    static var openAppWhenRun = true

    static var parameterSummary: some ParameterSummary {
        Summary("See what’s waiting in LandlordHours")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (dialog, destination) = await LandlordHoursIntentStore.nextAction()
        UserDefaults.standard.set(destination.rawValue, forKey: AppIntentNavigationRequest.pendingDestinationKey)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct LandlordHoursShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLandlordHoursIntent(destination: .track),
            phrases: [
                "Log time in \(.applicationName)",
                "Log rental work in \(.applicationName)"
            ],
            shortTitle: "Log time",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: ReviewLandlordHoursNextActionIntent(),
            phrases: [
                "What’s waiting in \(.applicationName)",
                "Show what to confirm in \(.applicationName)",
                "What should I do next in \(.applicationName)"
            ],
            shortTitle: "To confirm",
            systemImageName: "tray.fill"
        )

        AppShortcut(
            intent: GetLandlordHoursSummaryIntent(),
            phrases: [
                "How many hours do I have in \(.applicationName)",
                "How am I doing in \(.applicationName)"
            ],
            shortTitle: "My hours",
            systemImageName: "house.fill"
        )

        AppShortcut(
            intent: OpenLandlordHoursIntent(destination: .records),
            phrases: [
                "Show my records in \(.applicationName)"
            ],
            shortTitle: "Records",
            systemImageName: "list.bullet.rectangle.fill"
        )
    }
}

/// Intents read the single model owned by `AppModelHost` (the app process, with or without a
/// scene), never a second decode of UserDefaults that could disagree with unsaved state.
private enum LandlordHoursIntentStore {
    @MainActor
    static func engagementContext(taxYear: Int = Calendar.current.component(.year, from: Date())) -> EngagementContext {
        // Same builder as the widget, so Siri, the widget and Today's house count alike.
        AppModelHost.shared.viewModel.engagementContext(
            taxYear: taxYear,
            isTimerRunning: UserDefaults.standard.bool(forKey: UserScope.key("LandlordHours.timer")),
            timerStartTime: UserDefaults.standard.object(forKey: UserScope.key("timerStartTime")) as? Date
        )
    }

    @MainActor
    static func summary(taxYear: Int) -> (String, WidgetSurfaceSnapshot) {
        let model = AppModelHost.shared.viewModel
        let context = engagementContext(taxYear: taxYear)
        let snapshot = EngagementIntelligenceService.shared.snapshot(for: context)
        let surface = model.widgetSurfaceSnapshot()
        let text = LandlordHoursIntentCopy.summaryDialog(
            year: taxYear,
            context: context,
            snapshot: snapshot,
            recommendation: EngagementIntelligenceService.shared.recommendation(for: context),
            pendingCount: surface.pendingCount
        )
        return (text, surface)
    }

    @MainActor
    static func nextAction() -> (String, LandlordHoursIntentDestination) {
        let context = engagementContext()
        let recommendation = EngagementIntelligenceService.shared.recommendation(for: context)
        let pending = AppModelHost.shared.viewModel.widgetSurfaceSnapshot().pendingCount
        return LandlordHoursIntentCopy.nextAction(recommendation: recommendation, pendingCount: pending, hasProperty: !context.properties.isEmpty)
    }
}

enum LandlordHoursIntentCopy {
    /// "You have 212 of your 750 hours for 2026. You’re 388 hours behind pace, and 3 visits are waiting
    /// for you to confirm." The hours follow Today's rule (REPS: your own hours only).
    static func summaryDialog(
        year: Int,
        context: EngagementContext,
        snapshot: EngagementSnapshot,
        recommendation: EngagementRecommendation,
        pendingCount: Int = 0
    ) -> String {
        guard !context.properties.isEmpty else {
            return "You haven’t added a property yet. Add one in LandlordHours and we’ll start finding your rental work."
        }

        let hours = Int(max(0, snapshot.yearHours).rounded(.down))
        let target = Int(context.targetHours)
        let waiting = pendingCount == 1 ? "1 visit is waiting for you to confirm" : "\(pendingCount) visits are waiting for you to confirm"

        if snapshot.yearHours > context.targetHours {
            let lead = "You have \(hours) hours for \(year), past your \(target)-hour goal."
            return pendingCount > 0 ? "\(lead) \(waiting.prefix(1).uppercased() + waiting.dropFirst())." : lead
        }

        let lead = "You have \(hours) of your \(target) hours for \(year)."
        let gap = Int(max(0, snapshot.requiredHoursToDate - snapshot.yearHours).rounded(.up))
        let pace = snapshot.isBehindPace ? "You’re \(gap) \(gap == 1 ? "hour" : "hours") behind pace" : "You’re on pace"
        if pendingCount > 0 {
            return "\(lead) \(pace), and \(waiting)."
        }
        return "\(lead) \(pace)."
    }

    /// Where "See what's waiting" goes: anything to confirm first, then the next useful action.
    static func nextAction(recommendation: EngagementRecommendation, pendingCount: Int, hasProperty: Bool) -> (String, LandlordHoursIntentDestination) {
        if !hasProperty {
            return ("You haven’t added a property yet. Opening Properties.", .properties)
        }
        if pendingCount > 0 {
            let line = pendingCount == 1 ? "1 visit is waiting for you to confirm." : "\(pendingCount) visits are waiting for you to confirm."
            return (line, .inbox)
        }
        if recommendation.surface == .none {
            return ("You’re all caught up. Nothing is waiting for you.", .home)
        }
        return ("\(recommendation.title). \(recommendation.message)", intentDestination(for: recommendation))
    }

    static func intentDestination(for recommendation: EngagementRecommendation) -> LandlordHoursIntentDestination {
        switch recommendation.destination {
        case .addProperty: return .properties
        case .track, .timerReview: return .track
        case .calendarReview: return .inbox
        case .reports, .export: return .reports
        case .none: return .home
        }
    }
}

// MARK: - Siri snippet (ShowsSnippetView)

/// The Today hero in miniature, read-only: the number, the pace and "3 to confirm". Theme-fixed
/// blueprint like the hero. Text uses Dynamic Type styles; the number scales with @ScaledMetric;
/// the house sits back (dimmed) so no text is read over it, and fades further at accessibility sizes.
struct LandlordHoursSiriSnippet: View {
    let display: WidgetSurfaceDisplay
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var houseSize: CGFloat = 170
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(WidgetInk.drafting)
                .fixedSize(horizontal: false, vertical: true)
            if display.state == .noProperty {
                Text("Add a property to start the house.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WidgetInk.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                Text(display.number)
                    .font(.system(size: numberSize, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(WidgetInk.primary)
                    .padding(.top, 2)
                Text(display.goalText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WidgetInk.secondary)
                Color.clear.frame(height: 14)
                if let status = display.status, display.state != .timer {
                    (Text(Image(systemName: status.symbol)) + Text(" " + status.text))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WidgetInk.tone(status.tone))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if display.pendingCount > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "tray.fill").imageScale(.small)
                        Text("\(display.pendingCount) to confirm")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetInk.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 30)
                    .background(Capsule().fill(WidgetInk.primary))
                    .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            WidgetHouse(keyframe: display.snapshot.houseKeyframe)
                .frame(width: min(houseSize, 200), height: min(houseSize, 200))
                .offset(x: 4, y: 8)
                // Dimmed so the amber pace line never sits on a bright render (gate minor, 3.02:1).
                .opacity(dynamicTypeSize.isAccessibilitySize ? 0.3 : 0.6)
                .accessibilityHidden(true)
        }
        .background(WidgetBlueprintPaper())
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "Your REPS hours · 2026" with no-break spaces, so the middot never ends a line (AX3 minor).
    private var eyebrow: String {
        display.mediumLabel.replacingOccurrences(of: " · ", with: "\u{00A0}·\u{00A0}")
    }
}
