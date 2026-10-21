import SwiftUI
import WidgetKit

// MARK: - LandlordHours widget (extension entry point)
//
// One widget, five families: systemSmall, systemMedium, accessoryCircular, accessoryRectangular,
// accessoryInline (no systemLarge). The app writes `WidgetSurfaceSnapshot` to the App Group
// (WidgetSurfaceBuilder.swift); this extension only reads it. Views: WidgetSurfaceViews.swift.
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
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
            completion(Timeline(entries: [LandlordHoursWidgetEntry(date: now, snapshot: snapshot)], policy: .after(next)))
        }
    }

    /// Gallery sample: 212 of 750h, behind, 3 to confirm.
    static let gallerySample = WidgetSurfaceSnapshot(
        updatedAt: Date(timeIntervalSince1970: 1),
        taxYear: Calendar.current.component(.year, from: Date()),
        propertyCount: 2,
        hours: 212,
        goal: .reps750,
        goalHours: 750,
        requiredHoursToDate: 600,
        pendingCount: 3,
        timerStart: nil,
        timerPropertyName: nil,
        houseKeyframe: "k05_frame040",
        stageTitle: "Frame going up",
        nextStepLabel: "Roof at 500h"
    )
}

struct LandlordHoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: LandlordHoursWidgetEntry

    private var display: WidgetSurfaceDisplay { WidgetSurfaceDisplay(snapshot: entry.snapshot) }
    private var look: WidgetLook { renderingMode == .accented ? .accented : .fullColor }

    var body: some View {
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
                .containerBackground(for: .widget) { WidgetBlueprintPaper() }
                .widgetURL(display.url)
        default:
            WidgetMediumView(display: display, look: look)
                .containerBackground(for: .widget) { WidgetBlueprintPaper() }
                .widgetURL(display.url)
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

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LandlordHoursWidgetProvider()) { entry in
            LandlordHoursWidgetView(entry: entry)
        }
        .configurationDisplayName("Your hours")
        .description("Your house, your hours, and what’s waiting to confirm.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
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
        .configurationDisplayName("To confirm")
        .description("How many visits are waiting for you to confirm.")
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
