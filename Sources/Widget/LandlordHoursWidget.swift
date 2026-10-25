import SwiftUI
import WidgetKit

// MARK: - LandlordHours widget (extension entry point)
//
// One widget, every family the app ships: systemSmall, systemMedium, systemLarge, systemExtraLarge
// (iPad Home Screen), systemExtraLargePortrait (iPad Lock Screen in landscape, iOS 27), and the
// Lock Screen accessoryCircular, accessoryRectangular and accessoryInline. The app writes
// `WidgetSurfaceSnapshot` to the App Group (WidgetSurfaceBuilder.swift); this extension only reads
// it. Views: WidgetSurfaceViews.swift. Look: the crafted house on the dusk page in light and the
// night page in dark (standard §H.5), the mono mark B on small and the Lock Screen.
//
// The 1.x timer Live Activity was removed with the violet palette: the app ships with
// NSSupportsLiveActivities = NO, so it never ran, and 2.0 has no approved Live Activity design.

struct LandlordHoursWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSurfaceSnapshot
}

struct LandlordHoursWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LandlordHoursWidgetEntry {
        LandlordHoursWidgetEntry(date: Date(), snapshot: Self.gallerySample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LandlordHoursWidgetEntry) -> Void) {
        let stored = WidgetSurfaceStore.load()
        // The widget gallery shows a real-looking sample until the app has written a snapshot.
        let snapshot = context.isPreview && stored.updatedAt.timeIntervalSince1970 == 0 ? Self.gallerySample : stored
        completion(LandlordHoursWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LandlordHoursWidgetEntry>) -> Void) {
        let snapshot = WidgetSurfaceStore.load()
        let now = Date()
        if snapshot.timerStart != nil {
            // The inline family can't tick on its own: one entry a minute for the next hour.
            let entries = (0..<60).map { LandlordHoursWidgetEntry(date: now.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .atEnd))
        } else {
            // Windows are lit for the day hours were logged: a second entry at midnight puts the
            // lights out even if the app is not opened (Today does the same on a new day).
            var entries = [LandlordHoursWidgetEntry(date: now, snapshot: snapshot)]
            if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
                entries.append(LandlordHoursWidgetEntry(date: midnight, snapshot: snapshot.nextDay()))
            }
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    /// Gallery sample: one rental, 212 of 750 hours, behind, lit today, 3 to confirm.
    static let gallerySample = WidgetSurfaceSnapshot(
        updatedAt: Date(timeIntervalSince1970: 1),
        taxYear: Calendar.current.component(.year, from: Date()),
        propertyCount: 1,
        hours: 212,
        goal: .reps750,
        goalHours: 750,
        requiredHoursToDate: 600,
        pendingCount: 3,
        timerStart: nil,
        timerPropertyName: nil,
        houseKeyframe: "",
        stageTitle: "Frame going up",
        nextStepLabel: "",
        houseStage: "craft_frame70",
        loggedToday: true,
        paceReady: true,
        isRecord: false,
        rentals: [WidgetRentalFigure(id: "pine", name: "Pine Cabin", hours: 212, stage: "craft_frame70", lit: true, behindBy: 388)],
        confirmRows: [
            WidgetConfirmRow(key: "a", title: "Plumber visit", rentalName: "Pine Cabin", hours: 2),
            WidgetConfirmRow(key: "b", title: "Tenant walkthrough", rentalName: "Pine Cabin", hours: 1.5),
            WidgetConfirmRow(key: "c", title: "Hardware store run", rentalName: "Pine Cabin", hours: 1),
        ]
    )
}

struct LandlordHoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: LandlordHoursWidgetEntry

    private var display: WidgetSurfaceDisplay { WidgetSurfaceDisplay(snapshot: entry.snapshot) }
    private var look: WidgetLook { renderingMode == .accented ? .accented : .fullColor }

    var body: some View {
        content.widgetTypeCap()
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            WidgetCircularHoursView(display: display)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(display.url)
        case .accessoryRectangular:
            WidgetRectangularView(display: display)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(display.url)
        case .accessoryInline:
            WidgetInlineView(display: display)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(display.url)
        case .systemSmall:
            WidgetSmallView(display: display, look: look)
                .containerBackground(for: .widget) { WidgetPage(withHouse: false) }
                .widgetURL(display.url)
        case .systemLarge:
            WidgetLargeView(display: display, look: look)
                .containerBackground(for: .widget) { WidgetPage() }
                .widgetURL(display.url)
        case .systemExtraLarge:
            WidgetExtraLargeView(display: display, look: look)
                .containerBackground(for: .widget) { WidgetPage() }
                .widgetURL(display.url)
        default:
            if #available(iOS 27.0, *), family == .systemExtraLargePortrait {
                WidgetExtraLargePortraitView(display: display, look: look)
                    .containerBackground(for: .widget) { WidgetPage() }
                    .widgetURL(display.url)
            } else {
                WidgetMediumView(display: display, look: look)
                    .containerBackground(for: .widget) { WidgetPage() }
                    .widgetURL(display.url)
            }
        }
    }
}

/// "What's waiting" on the Lock Screen: the Inbox count in a circle.
struct LandlordHoursPendingWidgetView: View {
    let entry: LandlordHoursWidgetEntry
    private var display: WidgetSurfaceDisplay { WidgetSurfaceDisplay(snapshot: entry.snapshot) }

    var body: some View {
        WidgetCircularPendingView(display: display)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(display.pendingURL)
    }
}

struct LandlordHoursWidget: Widget {
    let kind = WidgetSurfaceStore.widgetKind

    private static var families: [WidgetFamily] {
        var all: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                                   .accessoryCircular, .accessoryRectangular, .accessoryInline]
        if #available(iOS 27.0, *) { all.append(.systemExtraLargePortrait) }
        return all
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LandlordHoursWidgetProvider()) { entry in
            LandlordHoursWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("widget.config.name", defaultValue: "Your hours", table: "Widgets"))
        .description(LocalizedStringResource("widget.config.description", defaultValue: "Your house, your hours, and what is waiting to confirm.", table: "Widgets"))
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}

/// The second circular: the to-confirm count (same source as the Inbox badge).
struct LandlordHoursPendingWidget: Widget {
    static let kind = "LandlordHoursPendingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LandlordHoursWidgetProvider()) { entry in
            LandlordHoursPendingWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("widget.pending.name", defaultValue: "To confirm", table: "Widgets"))
        .description(LocalizedStringResource("widget.pending.description", defaultValue: "How many visits are waiting for you to confirm.", table: "Widgets"))
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct LandlordHoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        LandlordHoursWidget()
        LandlordHoursPendingWidget()
    }
}

#Preview("Medium", as: .systemMedium) {
    LandlordHoursWidget()
} timeline: {
    LandlordHoursWidgetEntry(date: .now, snapshot: LandlordHoursWidgetProvider.gallerySample)
    LandlordHoursWidgetEntry(date: .now, snapshot: LandlordHoursWidgetProvider.gallerySample.nextDay())
}

#Preview("Large", as: .systemLarge) {
    LandlordHoursWidget()
} timeline: {
    LandlordHoursWidgetEntry(date: .now, snapshot: LandlordHoursWidgetProvider.gallerySample)
}

#Preview("Small", as: .systemSmall) {
    LandlordHoursWidget()
} timeline: {
    LandlordHoursWidgetEntry(date: .now, snapshot: LandlordHoursWidgetProvider.gallerySample)
}
