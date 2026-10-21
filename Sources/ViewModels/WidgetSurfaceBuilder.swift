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
    /// The snapshot the widget draws. `suggestions` defaults to the active profile's store.
    func widgetSurfaceSnapshot(now: Date = Date(), suggestions: [Suggestion]? = nil) -> WidgetSurfaceSnapshot {
        let year = Calendar.current.component(.year, from: now)
        let goal = houseGoal
        let hours = houseCountableHours(goal: goal, year: year)
        let progress = HouseProgress(hours: hours, goal: goal)
        let engagement = EngagementIntelligenceService.shared.snapshot(for: engagementContext(now: now, taxYear: year))
        let pending = InboxLogic.visible(suggestions ?? AppModelHost.shared.suggestionStore?.suggestions ?? [], now: now).count
        let timerName = isTimerRunning ? properties.first { $0.id == timerPropertyId }?.name : nil

        return WidgetSurfaceSnapshot(
            updatedAt: now,
            taxYear: year,
            propertyCount: properties.count,
            hours: hours,
            goal: WidgetSurfaceSnapshot.Goal(goal),
            goalHours: goal.targetHours,
            requiredHoursToDate: engagement.requiredHoursToDate,
            pendingCount: pending,
            timerStart: isTimerRunning ? timerStartTime : nil,
            timerPropertyName: timerName,
            houseKeyframe: progress.keyframe.rawValue,
            stageTitle: progress.stage.spokenName,
            nextStepLabel: progress.nextMilestoneLabel
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
