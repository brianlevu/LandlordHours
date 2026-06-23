import SwiftUI
import WidgetKit
import ActivityKit

struct LandlordHoursWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: EngagementWidgetSnapshot
}

struct LandlordHoursWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LandlordHoursWidgetEntry {
        LandlordHoursWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (LandlordHoursWidgetEntry) -> Void) {
        completion(LandlordHoursWidgetEntry(date: Date(), snapshot: EngagementWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LandlordHoursWidgetEntry>) -> Void) {
        let entry = LandlordHoursWidgetEntry(date: Date(), snapshot: EngagementWidgetSnapshotStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct LandlordHoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: LandlordHoursWidgetEntry

    private var snapshot: EngagementWidgetSnapshot { entry.snapshot }
    private var colors: WidgetPalette { WidgetPalette(colorScheme: colorScheme) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                accessoryCircularWidget
            case .accessoryRectangular:
                accessoryRectangularWidget
            case .accessoryInline:
                accessoryInlineWidget
            case .systemSmall:
                smallWidget
            default:
                mediumWidget
            }
        }
        .containerBackground(colors.background, for: .widget)
        .widgetURL(deepLink(for: snapshot.recommendationDestination))
    }

    private var accessoryCircularWidget: some View {
        Gauge(value: snapshot.progress) {
            Image(systemName: snapshot.isTimerRunning ? "timer" : "house.fill")
                .font(.system(size: 11, weight: .bold))
        } currentValueLabel: {
            Text("\(Int((snapshot.progress * 100).rounded()))")
                .font(.system(size: 13, weight: .black, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(WidgetColor.violetLight)
        .widgetAccentable()
        .accessibilityLabel("\(Int((snapshot.progress * 100).rounded())) percent toward \(snapshot.targetLabel)")
    }

    private var accessoryRectangularWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(snapshot.headline)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            } icon: {
                Image(systemName: snapshot.isTimerRunning ? "timer" : "house.fill")
            }
            .widgetAccentable()

            Text(snapshot.actionLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)

            Text(accessoryDetail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var accessoryInlineWidget: some View {
        Label(accessoryInlineText, systemImage: snapshot.isTimerRunning ? "timer" : "house.fill")
    }

    @ViewBuilder
    private var smallWidget: some View {
        if snapshot.isTimerRunning {
            timerSmallWidget
        } else {
            standardSmallWidget
        }
    }

    private var standardSmallWidget: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.headline)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(smallDetail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            progressBar
        }
        .padding(14)
    }

    private var timerSmallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.action)
                    Text("Timer active")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }

                Text(timerElapsedDisplay)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("Review to save")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                compactActionChip
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var mediumWidget: some View {
        if snapshot.isTimerRunning {
            timerMediumWidget
        } else {
            standardMediumWidget
        }
    }

    private var standardMediumWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.headline)
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(snapshot.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(1.5)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                progressRing(size: 74, lineWidth: 8)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    progressBar
                    Text("\(Int(snapshot.yearHours.rounded()))h logged • \(snapshot.daysRemainingInYear)d left")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionChip
            }
        }
        .padding(15)
    }

    private var timerMediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Timer active")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(timerElapsedDisplay)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colors.action)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text("Review before saving.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colors.action)
                    Text("Session in progress")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .widgetGlassRounded(cornerRadius: 16, tint: colors.actionSurface)

                Spacer(minLength: 0)
                actionChip
            }
        }
        .padding(15)
    }

    private var header: some View {
        HStack(spacing: 7) {
            WidgetMark()
                .frame(width: 22, height: 22)

            Text("LandlordHours")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
        }
    }

    private var actionChip: some View {
        Text(snapshot.actionLabel)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(colors.action)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .widgetGlassCapsule(tint: colors.actionSurface)
    }

    private var compactActionChip: some View {
        Text(snapshot.actionLabel)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(colors.action)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .widgetGlassCapsule(tint: colors.actionSurface)
    }

    private var mediumStats: some View {
        HStack(spacing: 7) {
            statChip(value: "\(Int(snapshot.yearHours.rounded()))h", label: "logged", tint: colors.actionSurface, foreground: colors.action)
            if snapshot.propertyCount > 0 {
                statChip(value: "\(snapshot.daysRemainingInYear)d", label: "left", tint: colors.secondarySurface, foreground: colors.secondaryAccent)
            }
        }
    }

    private func statChip(value: String, label: String, tint: Color, foreground: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(foreground)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textTertiary)
                .lineLimit(1)
        }
        .frame(minWidth: 54, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .widgetGlassRounded(cornerRadius: 14, tint: tint)
    }

    private var smallDetail: String {
        if snapshot.propertyCount == 0 { return "Add property" }
        if snapshot.isTimerRunning { return "Review timer" }
        if snapshot.isBehindPace { return "Review pace" }
        if let lastLog = snapshot.lastLogDate {
            return "Last log \(relativeDay(lastLog))"
        }
        return snapshot.actionLabel
    }

    private var accessoryDetail: String {
        if snapshot.propertyCount == 0 { return "Setup needed" }
        if snapshot.isTimerRunning { return "Tap to open timer" }
        if snapshot.isStale { return "Refresh latest pace" }
        if snapshot.isBehindPace { return "\(Int(snapshot.requiredHoursToDate.rounded()))h pace target" }
        if let lastLog = snapshot.lastLogDate { return "Last log \(relativeDay(lastLog))" }
        return "\(Int(snapshot.yearHours.rounded()))h this year"
    }

    private var accessoryInlineText: String {
        if snapshot.propertyCount == 0 { return "LandlordHours setup" }
        if snapshot.isTimerRunning { return "Timer active \(timerElapsedDisplay)" }
        if snapshot.isStale { return "LandlordHours refresh" }
        if snapshot.isBehindPace { return "LandlordHours \(Int(snapshot.paceGapHours.rounded(.up)))h behind" }
        return "LandlordHours \(Int(snapshot.yearHours.rounded()))h of \(snapshot.targetShortLabel)"
    }

    private var progressSummary: String {
        "\(Int((snapshot.progress * 100).rounded()))% of \(snapshot.targetShortLabel)"
    }

    private var timerElapsedDisplay: String {
        guard let startTime = snapshot.timerStartTime else { return "0:00" }
        let elapsed = max(0, Int(Date().timeIntervalSince(startTime)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func progressRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(colors.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(colors.ringFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text("\(Int((snapshot.progress * 100).rounded()))%")
                    .font(.system(size: size > 70 ? 18 : 13, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(snapshot.targetShortLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int((snapshot.progress * 100).rounded())) percent toward \(snapshot.targetLabel)")
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colors.ringTrack)
                Capsule()
                    .fill(colors.ringFill)
                    .frame(width: max(6, proxy.size.width * snapshot.progress))
            }
        }
        .frame(height: 7)
        .accessibilityLabel("\(Int((snapshot.progress * 100).rounded())) percent toward \(snapshot.targetLabel)")
    }

    private func deepLink(for destination: EngagementDestination) -> URL {
        let appDestination: String
        switch destination {
        case .addProperty:
            appDestination = "properties"
        case .track, .timerReview:
            appDestination = "track"
        case .reports, .calendarReview, .export:
            appDestination = "reports"
        case .none:
            appDestination = "home"
        }
        return URL(string: "landlordhours://open?destination=\(appDestination)")!
    }

    private func relativeDay(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }
}

struct LandlordHoursWidget: Widget {
    let kind = EngagementWidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LandlordHoursWidgetProvider()) { entry in
            LandlordHoursWidgetView(entry: entry)
        }
        .configurationDisplayName("LandlordHours")
        .description("See your landlord-hour pace and the next useful action.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct LandlordHoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        LandlordHoursWidget()
        LandlordHoursTimerLiveActivity()
    }
}

struct LandlordHoursTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LandlordHoursTimerAttributes.self) { context in
            LiveTimerLockScreenView(state: context.state)
                .activityBackgroundTint(WidgetColor.lightBackground)
                .activitySystemActionForegroundColor(WidgetColor.violet)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.propertyName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)

                        Text(context.state.categoryName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetColor.violetLight)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveTimerElapsedText(startDate: context.state.startDate, compact: false, foreground: WidgetColor.violetLight)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Link(destination: URL(string: "landlordhours://open?destination=track")!) {
                            Label(context.state.isReviewNeeded ? "Review timer" : "Open timer", systemImage: "arrow.up.forward.app")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Text(context.state.isReviewNeeded ? "Needs review" : "Timer active")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetColor.darkTextSecondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "house.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetColor.violetLight)
            } compactTrailing: {
                LiveTimerElapsedText(startDate: context.state.startDate, compact: true)
            } minimal: {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetColor.violetLight)
            }
            .widgetURL(URL(string: "landlordhours://open?destination=track"))
            .keylineTint(WidgetColor.violet)
        }
    }
}

private struct LiveTimerLockScreenView: View {
    let state: LandlordHoursTimerAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            WidgetMark()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.isReviewNeeded ? "Open to review timer" : "Tracking landlord work")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetColor.textPrimary)
                    .lineLimit(1)

                Text(state.propertyName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetColor.textSecondary)
                    .lineLimit(1)

                Text(state.categoryName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetColor.violet)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            LiveTimerElapsedText(startDate: state.startDate, compact: false)
        }
        .padding(16)
        .widgetURL(URL(string: "landlordhours://open?destination=track"))
    }
}

private struct LiveTimerElapsedText: View {
    let startDate: Date
    let compact: Bool
    var foreground: Color? = nil

    var body: some View {
        Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
            .font(.system(size: compact ? 12 : 18, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(foreground ?? (compact ? WidgetColor.violetLight : WidgetColor.textPrimary))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityLabel("Timer elapsed")
    }
}

private struct WidgetMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [WidgetColor.violet, WidgetColor.violetDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "house.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: 1)

            Image(systemName: "clock")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 4, y: -4)
        }
    }
}

private struct WidgetPalette {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark ? WidgetColor.darkBackground : WidgetColor.lightBackground
    }

    var textPrimary: Color {
        colorScheme == .dark ? WidgetColor.darkTextPrimary : WidgetColor.textPrimary
    }

    var textSecondary: Color {
        colorScheme == .dark ? WidgetColor.darkTextSecondary : WidgetColor.textSecondary
    }

    var textTertiary: Color {
        colorScheme == .dark ? WidgetColor.darkTextTertiary : WidgetColor.textTertiary
    }

    var action: Color {
        colorScheme == .dark ? WidgetColor.violetLight : WidgetColor.violet
    }

    var actionSurface: Color {
        colorScheme == .dark ? WidgetColor.darkActionSurface : WidgetColor.actionSurface
    }

    var secondaryAccent: Color {
        colorScheme == .dark ? WidgetColor.skyLight : WidgetColor.sky
    }

    var secondarySurface: Color {
        colorScheme == .dark ? WidgetColor.darkSkySurface : WidgetColor.skySurface
    }

    var ringTrack: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : WidgetColor.ringTrack
    }

    var ringFill: LinearGradient {
        LinearGradient(colors: [action, WidgetColor.violetLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private enum WidgetColor {
    static let lightBackground = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let darkBackground = Color(red: 0.05, green: 0.05, blue: 0.10)
    static let textPrimary = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let textSecondary = Color(red: 0.43, green: 0.43, blue: 0.51)
    static let textTertiary = Color(red: 0.66, green: 0.66, blue: 0.74)
    static let darkTextPrimary = Color(red: 0.91, green: 0.91, blue: 0.94)
    static let darkTextSecondary = Color(red: 0.66, green: 0.66, blue: 0.74)
    static let darkTextTertiary = Color(red: 0.43, green: 0.43, blue: 0.51)
    static let violet = Color(red: 0.48, green: 0.41, blue: 0.93)
    static let violetLight = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let violetDeep = Color(red: 0.36, green: 0.29, blue: 0.79)
    static let actionSurface = Color(red: 0.93, green: 0.91, blue: 1.0)
    static let darkActionSurface = Color(red: 0.18, green: 0.17, blue: 0.29)
    static let sky = Color(red: 0.42, green: 0.71, blue: 0.93)
    static let skyLight = Color(red: 0.58, green: 0.77, blue: 0.99)
    static let skySurface = Color(red: 0.88, green: 0.94, blue: 1.0)
    static let darkSkySurface = Color(red: 0.10, green: 0.14, blue: 0.20)
    static let ringTrack = Color(red: 0.88, green: 0.86, blue: 0.93)
}

private extension View {
    @ViewBuilder
    func widgetGlassCapsule(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(0.62)), in: .rect(cornerRadius: 999))
        } else {
            self
                .background(tint)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    func widgetGlassRounded(cornerRadius: CGFloat, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint.opacity(0.58)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
