import SwiftUI
import LucideIcons

#if DEBUG
struct EngagementLabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedScenario: EngagementLabScenario = .recentlyActive
    @State private var selectedSurface: EngagementLabSurface

    private let service = EngagementIntelligenceService()
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var context: EngagementContext { selectedScenario.context }
    private var snapshot: EngagementSnapshot { service.snapshot(for: context) }
    private var recommendation: EngagementRecommendation { service.recommendation(for: context) }

    init() {
        _selectedSurface = State(initialValue: EngagementLabSurface.fromLaunchArguments() ?? .notification)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                scenarioPicker
                recommendationSummary
                surfacePicker
                surfacePreview
                scenarioFacts
                qualityChecks
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, AppSpacing.tabContentBottomInset)
        }
        .background {
            LHMobileCanvas()
        }
        .navigationTitle("Engagement Lab")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .accessibilityIdentifier("settings.engagementLab")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LucideIcon(image: Lucide.bell, size: 22)
                    .foregroundStyle(colors.action)
                    .frame(width: 44, height: 44)
                    .background(colors.actionSurface)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Engagement Intelligence")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("Preview when the app should speak, and when silence is better.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenario")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(EngagementLabScenario.allCases) { scenario in
                    Button {
                        withAnimation(AppAnimation.smooth) {
                            selectedScenario = scenario
                        }
                    } label: {
                        scenarioTile(scenario)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("engagement.scenario.\(scenario.rawValue)")
                }
            }
        }
    }

    private func scenarioTile(_ scenario: EngagementLabScenario) -> some View {
        let isSelected = selectedScenario == scenario

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                LucideIcon(image: scenario.icon, size: 18)
                    .foregroundStyle(scenario.tint)
                    .frame(width: 32, height: 32)
                    .background(scenario.wash(colors))
                    .clipShape(Circle())

                Spacer(minLength: 0)

                if isSelected {
                    LucideIcon(image: Lucide.check, size: 15)
                        .foregroundStyle(AppColors.onAction)
                        .frame(width: 26, height: 26)
                        .background(scenario.tint)
                        .clipShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(scenario.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(scenario.shortLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(12)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                .strokeBorder(isSelected ? scenario.tint.opacity(0.82) : colors.border.opacity(0.34), lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private var recommendationSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                LucideIcon(image: recommendationIcon, size: 22)
                    .foregroundStyle(recommendationTint)
                    .frame(width: 42, height: 42)
                    .background(recommendationWash)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendationTitle)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    Text(recommendationMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                engagementPill(label: recommendation.surface.rawValue, color: recommendationTint, wash: recommendationWash)
                engagementPill(label: recommendation.destination.rawValue, color: colors.informational, wash: colors.informationalSurface)
                if recommendation.cooldownDays > 0 {
                    engagementPill(label: "\(recommendation.cooldownDays)d cooldown", color: colors.caution, wash: colors.cautionSurface)
                }
            }
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .strokeBorder(colors.border.opacity(0.30), lineWidth: 1)
        }
    }

    private var surfacePicker: some View {
        Picker("Surface", selection: $selectedSurface) {
            ForEach(EngagementLabSurface.allCases) { surface in
                Text(surface.title).tag(surface)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("engagement.surfacePicker")
    }

    @ViewBuilder
    private var surfacePreview: some View {
        switch selectedSurface {
        case .notification:
            notificationPreview
        case .widget:
            widgetPreview
        case .liveActivity:
            liveActivityPreview
        case .siri:
            siriPreview
        }
    }

    private var notificationPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewHeader("Notification", subtitle: "Should feel specific, quiet, and easy to dismiss.")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    WaveHouseIcon(size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LandlordHours")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text("now")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textTertiary)
                    }
                    Spacer()
                }

                Text(notificationTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)

                Text(notificationMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)

                if recommendation.surface != .none {
                    Text(actionLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.action)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 8, y: 4)
        }
        .previewCard(colors: colors)
        .accessibilityIdentifier("engagement.preview.notification")
    }

    private var widgetPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewHeader("Widget", subtitle: "Persistent memory without interruption.")

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        LHCompactLogo(size: 24)
                        Text("LandlordHours")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                    }

                    Text(widgetHeadline)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(widgetDetail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        engagementPill(label: widgetAction, color: colors.action, wash: colors.actionSurface)
                        engagementPill(label: "\(Int(snapshot.yearHours.rounded()))h logged", color: colors.action, wash: colors.actionSurface)
                        engagementPill(label: "\(Int(snapshot.daysRemainingInYear))d left", color: colors.informational, wash: colors.informationalSurface)
                    }
                }

                Spacer(minLength: 0)

                progressDial
            }
            .frame(height: 136)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.54 : 0.66),
                        colors.actionSurface.opacity(colorScheme == .dark ? 0.24 : 0.46)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .liquidGlassPanel(cornerRadius: 22, colors: colors, colorScheme: colorScheme)
        }
        .previewCard(colors: colors)
        .accessibilityIdentifier("engagement.preview.widget")
    }

    private var liveActivityPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewHeader("Live Activity", subtitle: "Use only for bounded work in progress.")

            VStack(spacing: 10) {
                dynamicIslandPreview

                HStack(spacing: 11) {
                    LucideIcon(image: Lucide.clock, size: 18)
                        .foregroundStyle(colors.action)
                        .frame(width: 34, height: 34)
                        .background(colors.actionSurface)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(liveActivityTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text(liveActivityMessage)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(liveActivityTime)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }

                HStack(spacing: 8) {
                    Text(recommendation.reason == .timerSafety ? "Review in app" : "Open timer")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.onAction)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .liquidGlassCapsule(tint: colors.action, colorScheme: colorScheme, foreground: true)

                    Text(recommendation.reason == .timerSafety ? "Timer active" : "No live surface")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .liquidGlassCapsule(tint: colors.backgroundTertiary, colorScheme: colorScheme)
                }
            }
            .padding(14)
            .liquidGlassPanel(cornerRadius: 24, colors: colors, colorScheme: colorScheme)
        }
        .previewCard(colors: colors)
        .accessibilityIdentifier("engagement.preview.liveActivity")
    }

    private var dynamicIslandPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Dynamic Island")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)

                Spacer()

                Text(recommendation.reason == .timerSafety ? "Active" : "Quiet")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(recommendation.reason == .timerSafety ? colors.positive : colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(recommendation.reason == .timerSafety ? colors.positiveSurface : colors.backgroundTertiary)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    LucideIcon(image: Lucide.house, size: 12)
                        .foregroundStyle(AppColors.primaryLight)
                    Text(liveActivityTime)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black)
                .clipShape(Capsule())

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Oak Street")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(recommendation.reason == .timerSafety ? "Review timer" : "Only while timing")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer(minLength: 6)

                    Text(recommendation.reason == .timerSafety ? "Review" : "Idle")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(recommendation.reason == .timerSafety ? AppColors.primaryLight : .white.opacity(0.58))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .padding(12)
        .liquidGlassPanel(cornerRadius: 20, colors: colors, colorScheme: colorScheme)
        .accessibilityIdentifier("engagement.dynamicIslandPreview")
    }

    private var siriPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewHeader("Siri / Shortcut", subtitle: "A concise answer plus the next useful action.")

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Text(siriUserPrompt)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.onAction)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(colors.action)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                HStack(alignment: .top, spacing: 10) {
                    LucideIcon(image: Lucide.sparkles, size: 16)
                        .foregroundStyle(colors.action)
                        .frame(width: 30, height: 30)
                        .background(colors.actionSurface)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(siriResponse)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .lineSpacing(2)

                        Text(actionLabel)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.action)
                    }
                    .padding(12)
                    .background(colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Spacer(minLength: 0)
                }
            }
        }
        .previewCard(colors: colors)
        .accessibilityIdentifier("engagement.preview.siri")
    }

    private var scenarioFacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                metricCard("Properties", value: "\(context.properties.count)")
                metricCard("Year hours", value: String(format: "%.1f", snapshot.yearHours))
                metricCard("Last log", value: lastLogLabel)
                metricCard("Calendar drafts", value: "\(context.calendarDraftCount)")
                metricCard("Dismissals", value: "\(context.recentDismissals.count)")
                metricCard("Timer", value: timerLabel)
            }
        }
    }

    private var qualityChecks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality Checks")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            VStack(spacing: 10) {
                qualityRow(
                    title: "Actionable",
                    value: recommendation.destination != .none ? "Yes" : "No action",
                    isPassing: recommendation.surface == .none || recommendation.destination != .none
                )
                qualityRow(
                    title: "Interruptive",
                    value: recommendation.surface == .notification ? "Yes" : "No",
                    isPassing: recommendation.surface != .notification || recommendation.reason == .calendarDraftsReady || recommendation.reason == .inactiveLogging || recommendation.reason == .yearEndExport
                )
                qualityRow(
                    title: "Cooldown",
                    value: recommendation.cooldownDays > 0 ? "\(recommendation.cooldownDays)d" : "None needed",
                    isPassing: recommendation.surface == .none || recommendation.cooldownDays > 0 || recommendation.surface == .homeNudge
                )
                qualityRow(
                    title: "Silence allowed",
                    value: recommendation.surface == .none ? "Chosen" : "Not this time",
                    isPassing: true
                )
            }
        }
        .previewCard(colors: colors)
    }

    private func previewHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
    }

    private func qualityRow(title: String, value: String, isPassing: Bool) -> some View {
        HStack(spacing: 10) {
            LucideIcon(image: isPassing ? Lucide.badgeCheck : Lucide.circleAlert, size: 17)
                .foregroundStyle(isPassing ? colors.positive : colors.caution)
                .frame(width: 28, height: 28)
                .background(isPassing ? colors.positiveSurface : colors.cautionSurface)
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func engagementPill(label: String, color: Color, wash: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .liquidGlassCapsule(tint: wash, colorScheme: colorScheme)
    }

    private var progressDial: some View {
        ZStack {
            Circle()
                .stroke(colors.primarySurface, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, snapshot.yearHours / context.targetHours))
                .stroke(colors.action, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(Int((snapshot.yearHours / context.targetHours) * 100))%")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text("\(Int(context.targetHours))h")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .frame(width: 68, height: 68)
    }

    private var recommendationIcon: UIImage {
        switch recommendation.reason {
        case .noActionNeeded: return Lucide.circleCheck
        case .setupProperty: return Lucide.building2
        case .inactiveLogging: return Lucide.clock
        case .timerSafety: return Lucide.timer
        case .calendarDraftsReady: return Lucide.calendarCheck
        case .behindPace: return Lucide.chartNoAxesCombined
        case .yearEndExport: return Lucide.fileText
        case .portfolioSummary: return Lucide.layoutGrid
        }
    }

    private var recommendationTint: Color {
        switch recommendation.reason {
        case .noActionNeeded, .portfolioSummary: return colors.positive
        case .setupProperty, .behindPace: return colors.action
        case .inactiveLogging, .timerSafety, .yearEndExport: return colors.caution
        case .calendarDraftsReady: return colors.informational
        }
    }

    private var recommendationWash: Color {
        switch recommendation.reason {
        case .noActionNeeded, .portfolioSummary: return colors.positiveSurface
        case .setupProperty, .behindPace: return colors.actionSurface
        case .inactiveLogging, .timerSafety, .yearEndExport: return colors.cautionSurface
        case .calendarDraftsReady: return colors.informationalSurface
        }
    }

    private var recommendationTitle: String {
        recommendation.surface == .none ? "Stay quiet" : recommendation.title
    }

    private var recommendationMessage: String {
        recommendation.surface == .none
            ? "The user has enough recent signal. No prompt should be shown."
            : recommendation.message
    }

    private var notificationTitle: String {
        recommendation.surface == .none ? "No notification" : recommendation.title
    }

    private var notificationMessage: String {
        recommendation.surface == .none
            ? "Silence is the correct notification experience for this scenario."
            : recommendation.message
    }

    private var widgetHeadline: String {
        if recommendation.reason == .behindPace { return "Behind pace" }
        if recommendation.reason == .portfolioSummary { return "\(context.properties.count) properties" }
        if recommendation.surface == .none { return "On track" }
        return "\(String(format: "%.0f", snapshot.yearHours))h logged"
    }

    private var widgetDetail: String {
        if recommendation.surface == .none {
            return "Recent log. Keep the widget quiet."
        }
        return recommendation.message
    }

    private var widgetAction: String {
        switch recommendation.destination {
        case .track: return "Log"
        case .reports: return "Reports"
        case .calendarReview: return "Review"
        case .export: return "Export"
        case .addProperty: return "Add"
        case .timerReview: return "Timer"
        case .none: return "Open"
        }
    }

    private var liveActivityTitle: String {
        recommendation.reason == .timerSafety ? recommendation.title : "No active session"
    }

    private var liveActivityMessage: String {
        recommendation.reason == .timerSafety
            ? recommendation.message
            : "Live Activity should stay unused until landlord work is actively being timed."
    }

    private var liveActivityTime: String {
        guard let hours = snapshot.timerAgeHours, hours > 0 else { return "--" }
        return String(format: "%.1fh", hours)
    }

    private var siriUserPrompt: String {
        switch recommendation.reason {
        case .noActionNeeded: return "How am I doing?"
        case .setupProperty: return "Set up LandlordHours"
        case .inactiveLogging: return "Remind me what to log"
        case .timerSafety: return "Stop landlord timer"
        case .calendarDraftsReady: return "Review landlord calendar items"
        case .behindPace: return "Am I on pace for REPS?"
        case .yearEndExport: return "Prepare my tax records"
        case .portfolioSummary: return "Summarize my landlord hours"
        }
    }

    private var siriResponse: String {
        if recommendation.surface == .none {
            return "You logged recently. I do not see anything urgent to review right now."
        }
        return "\(recommendation.title). \(recommendation.message)"
    }

    private var actionLabel: String {
        switch recommendation.destination {
        case .none: return "No action"
        case .addProperty: return "Open Add Property"
        case .track: return "Open Track"
        case .reports: return "Open Reports"
        case .calendarReview: return "Review Drafts"
        case .export: return "Open Export"
        case .timerReview: return "Review Timer"
        }
    }

    private var lastLogLabel: String {
        guard let days = snapshot.daysSinceLastLog else { return "Never" }
        if days == 0 { return "Today" }
        if days == 1 { return "1d ago" }
        return "\(days)d ago"
    }

    private var timerLabel: String {
        guard context.isTimerRunning, let hours = snapshot.timerAgeHours else { return "Off" }
        return String(format: "%.1fh", hours)
    }
}

private enum EngagementLabSurface: String, CaseIterable, Identifiable {
    case notification
    case widget
    case liveActivity
    case siri

    var id: String { rawValue }

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> EngagementLabSurface? {
        guard let index = arguments.firstIndex(of: "-LHEngagementSurface"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        switch arguments[index + 1].lowercased() {
        case "notification", "notifications":
            return .notification
        case "widget", "widgets":
            return .widget
        case "live", "liveactivity", "dynamicisland":
            return .liveActivity
        case "siri", "shortcut", "shortcuts":
            return .siri
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .notification: return "Notify"
        case .widget: return "Widget"
        case .liveActivity: return "Live"
        case .siri: return "Siri"
        }
    }
}

private enum EngagementLabScenario: String, CaseIterable, Identifiable {
    case setup
    case recentlyActive
    case inactive
    case dismissed
    case calendarDrafts
    case timerSafety
    case behindPace
    case yearEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "Needs setup"
        case .recentlyActive: return "Recently active"
        case .inactive: return "Quietly inactive"
        case .dismissed: return "Dismissed twice"
        case .calendarDrafts: return "Calendar candidates"
        case .timerSafety: return "Long timer"
        case .behindPace: return "Behind pace"
        case .yearEnd: return "Year-end export"
        }
    }

    var shortLabel: String {
        switch self {
        case .setup: return "No property yet"
        case .recentlyActive: return "Should stay quiet"
        case .inactive: return "14 days no log"
        case .dismissed: return "Suppress prompt"
        case .calendarDrafts: return "Review likely work"
        case .timerSafety: return "5h timer"
        case .behindPace: return "Widget nudge"
        case .yearEnd: return "Export moment"
        }
    }

    var icon: UIImage {
        switch self {
        case .setup: return Lucide.userPlus
        case .recentlyActive: return Lucide.circleCheck
        case .inactive: return Lucide.clock
        case .dismissed: return Lucide.circleSlash
        case .calendarDrafts: return Lucide.calendarCheck
        case .timerSafety: return Lucide.timer
        case .behindPace: return Lucide.chartNoAxesCombined
        case .yearEnd: return Lucide.fileText
        }
    }

    var tint: Color {
        switch self {
        case .setup, .behindPace: return AppColors.action
        case .recentlyActive: return AppColors.positive
        case .inactive, .dismissed, .timerSafety, .yearEnd: return AppColors.caution
        case .calendarDrafts: return AppColors.informational
        }
    }

    func wash(_ colors: AdaptiveColors) -> Color {
        switch self {
        case .setup, .behindPace: return colors.actionSurface
        case .recentlyActive: return colors.positiveSurface
        case .inactive, .dismissed, .timerSafety, .yearEnd: return colors.cautionSurface
        case .calendarDrafts: return colors.informationalSurface
        }
    }

    var context: EngagementContext {
        let now: Date
        switch self {
        case .behindPace:
            now = Self.date(year: 2026, month: 10, day: 1)
        case .yearEnd:
            now = Self.date(year: 2026, month: 12, day: 10)
        default:
            now = Self.date(year: 2026, month: 6, day: 15)
        }

        let property = RentalProperty(name: "Oak Street Duplex", address: "123 Oak St", propertyType: .ltr)
        let secondProperty = RentalProperty(name: "Pine Cottage", address: "88 Pine Ave", propertyType: .str)

        switch self {
        case .setup:
            return makeContext(now: now, properties: [], entries: [])
        case .recentlyActive:
            return makeContext(
                now: now,
                properties: [property],
                entries: [entry(property.id, date: Self.date(year: 2026, month: 6, day: 14), hours: 350)]
            )
        case .inactive:
            return makeContext(
                now: now,
                properties: [property],
                entries: [entry(property.id, date: Self.date(year: 2026, month: 6, day: 1), hours: 2)]
            )
        case .dismissed:
            return makeContext(
                now: now,
                properties: [property],
                entries: [entry(property.id, date: Self.date(year: 2026, month: 6, day: 1), hours: 2)],
                dismissals: [
                    EngagementDismissal(reason: .inactiveLogging, dismissedAt: Self.date(year: 2026, month: 6, day: 10)),
                    EngagementDismissal(reason: .inactiveLogging, dismissedAt: Self.date(year: 2026, month: 6, day: 12))
                ]
            )
        case .calendarDrafts:
            return makeContext(
                now: now,
                properties: [property],
                entries: [entry(property.id, date: Self.date(year: 2026, month: 6, day: 1), hours: 2)],
                calendarDraftCount: 2
            )
        case .timerSafety:
            return makeContext(
                now: Self.date(year: 2026, month: 6, day: 15, hour: 14),
                properties: [property],
                entries: [entry(property.id, date: Self.date(year: 2026, month: 6, day: 14), hours: 1)],
                isTimerRunning: true,
                timerStartTime: Self.date(year: 2026, month: 6, day: 15, hour: 9)
            )
        case .behindPace:
            return makeContext(
                now: now,
                properties: [property],
                entries: [entry(property.id, date: Self.date(year: 2026, month: 9, day: 28), hours: 100)]
            )
        case .yearEnd:
            return makeContext(
                now: now,
                properties: [property, secondProperty],
                entries: [
                    entry(property.id, date: Self.date(year: 2026, month: 11, day: 1), hours: 20),
                    entry(secondProperty.id, date: Self.date(year: 2026, month: 11, day: 5), hours: 6)
                ],
                isProUser: true
            )
        }
    }

    private func makeContext(
        now: Date,
        properties: [RentalProperty],
        entries: [TimeEntry],
        calendarDraftCount: Int = 0,
        isTimerRunning: Bool = false,
        timerStartTime: Date? = nil,
        dismissals: [EngagementDismissal] = [],
        isProUser: Bool = false
    ) -> EngagementContext {
        EngagementContext(
            now: now,
            taxYear: Calendar.current.component(.year, from: now),
            properties: properties,
            timeEntries: entries,
            calendarDraftCount: calendarDraftCount,
            isTimerRunning: isTimerRunning,
            timerStartTime: timerStartTime,
            notificationPermission: .authorized,
            recentDismissals: dismissals,
            isProUser: isProUser
        )
    }

    private func entry(_ propertyId: UUID, date: Date, hours: Double) -> TimeEntry {
        TimeEntry(
            propertyId: propertyId,
            participant: .selfParticipant,
            category: .management,
            hours: hours,
            date: date,
            notes: "Debug scenario"
        )
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date ?? Date()
    }
}

private extension View {
    @ViewBuilder
    func previewCard(colors: AdaptiveColors) -> some View {
        self
            .padding(14)
            .liquidGlassPanel(cornerRadius: AppCornerRadius.xl, colors: colors, colorScheme: nil)
    }

    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat, colors: AdaptiveColors, colorScheme: ColorScheme?) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.28 : 0.24))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .glassEffect(.regular.tint(colors.actionSurface.opacity(colorScheme == .dark ? 0.14 : 0.28)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colors.border.opacity(0.30), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(tint: Color, colorScheme: ColorScheme, foreground: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(foreground ? 0.74 : 0.52)), in: .rect(cornerRadius: 999))
        } else {
            self
                .background(tint)
                .clipShape(Capsule())
        }
    }
}
#endif
