import Foundation
import WidgetKit

// MARK: - Widget surface: what the app writes for the Home and Lock Screen widgets
//
// One builder for the widget snapshot (Sources/Shared/WidgetSurface.swift). The hours are Today's
// house hours (`houseCountableHours`: REPS = your own hours only; material participation combines
// spouses only when tracked jointly). The to-confirm count is the Inbox badge's count
// (`InboxLogic.visible`). The pace target is the engagement snapshot's, so the widget, Siri and
// Today agree.

extension AppViewModel {
    /// The Inbox's suggestions for the to-confirm count. Set by `AppModelHost` once it exists;
    /// empty before that (never touch `AppModelHost.shared` from AppViewModel.init).
    static var widgetSuggestionsProvider: @MainActor () -> [Suggestion] = { [] }

    /// The snapshot the widget draws. `suggestions` defaults to the active profile's store.
    func widgetSurfaceSnapshot(now: Date = Date(), suggestions: [Suggestion]? = nil) -> WidgetSurfaceSnapshot {
        let year = Calendar.current.component(.year, from: now)
        var goal = houseGoal
        var hours = houseCountableHours(goal: goal, year: year)
        var progress = HouseProgress(hours: hours, goal: goal)
        let engagement = EngagementIntelligenceService.shared.snapshot(for: engagementContext(now: now, taxYear: year))
        var required = engagement.requiredHoursToDate
        // 2.1: the widget follows Today's focus. A rental with its own target shows its own hours,
        // target and house (the same stage function as Today); "All rentals" and a rental without
        // a target of its own keep the goal's total.
        var focusName: String?
        let focus = WidgetFocus.make(self, year: year, now: now)
        if let focus {
            goal = focus.goal
            hours = focus.hours
            progress = HouseProgress(hours: focus.stageHours, goal: focus.goal)
            required = focus.requiredHoursToDate
            focusName = properties.count >= 2 ? focus.name : nil
        }
        let pending = InboxLogic.visible(suggestions ?? Self.widgetSuggestionsProvider(), now: now).count
        let timerName = isTimerRunning ? properties.first { $0.id == timerPropertyId }?.name : nil

        return WidgetSurfaceSnapshot(
            updatedAt: now,
            taxYear: year,
            propertyCount: properties.count,
            hours: hours,
            goal: WidgetSurfaceSnapshot.Goal(goal),
            goalHours: goal.targetHours,
            requiredHoursToDate: required,
            pendingCount: pending,
            timerStart: isTimerRunning ? timerStartTime : nil,
            timerPropertyName: timerName,
            houseKeyframe: progress.keyframe.rawValue,
            stageTitle: progress.stage.spokenName,
            nextStepLabel: progress.nextMilestoneLabel,
            focusName: focusName
        )
    }

    /// Writes the widget snapshot and asks WidgetKit to redraw. Cheap; called after every save,
    /// on Inbox changes and when the app comes to the foreground.
    func refreshWidgetSurface(now: Date = Date()) {
        guard isSignedIn else {
            WidgetSurfaceStore.save(.empty)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot = widgetSurfaceSnapshot(now: now)
        guard snapshot != lastWrittenWidgetSurface(ignoringTimeOf: snapshot) else { return }
        WidgetSurfaceStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The stored snapshot with `updatedAt` set to `snapshot`'s, so an unchanged surface is not
    /// rewritten (WidgetKit reloads are budgeted).
    private func lastWrittenWidgetSurface(ignoringTimeOf snapshot: WidgetSurfaceSnapshot) -> WidgetSurfaceSnapshot {
        var stored = WidgetSurfaceStore.load()
        stored.updatedAt = snapshot.updatedAt
        return stored
    }
}

extension WidgetSurfaceSnapshot.Goal {
    init(_ goal: HouseGoal) {
        switch goal {
        case .reps750: self = .reps750
        case .mp500: self = .mp500
        case .mp100: self = .mp100
        }
    }
}

/// The focused rental, when it has a target of its own: what the widget shows instead of the total.
struct WidgetFocus: Equatable {
    let name: String
    let hours: Double
    let goal: HouseGoal
    let stageHours: Double
    let requiredHoursToDate: Double

    @MainActor
    static func make(_ app: AppViewModel, year: Int, now: Date, calendar: Calendar = .current) -> WidgetFocus? {
        guard let property = app.todayFocusProperty(year: year),
              case .ownTarget(let target) = app.rentalPlan(for: property).track else { return nil }
        let track = RentalTrack.ownTarget(hours: target)
        let hours = app.rentalHours(property, year: year)
        let day = Double(calendar.ordinality(of: .day, in: .year, for: now) ?? 1)
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: now)?.count ?? 365)
        return WidgetFocus(name: property.name, hours: hours, goal: RentalTrack.houseGoal(forHours: target),
                           stageHours: RentalStage.hours(track: track, hours: hours),
                           requiredHoursToDate: Double(target) * day / daysInYear)
    }
}
