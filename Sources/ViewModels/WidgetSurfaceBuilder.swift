import Foundation
import WidgetKit

// MARK: - Widget surface: what the app writes for the Home and Lock Screen widgets
//
// One builder for the widget snapshot (Sources/Shared/WidgetSurface.swift). The hours are Today's
// house hours (`houseCountableHours`: REPS = your own hours only; material participation combines
// spouses only when tracked jointly). The to-confirm count is the Inbox badge's count
// (`InboxLogic.visible`). The pace is Today's own (linear share of the goal, one-hour rounding,
// waits for two weeks or ten hours), so the widget and Today agree.

extension AppViewModel {
    /// The Inbox's suggestions for the to-confirm count. Set by `AppModelHost` once it exists;
    /// empty before that (never touch `AppModelHost.shared` from AppViewModel.init).
    static var widgetSuggestionsProvider: @MainActor () -> [Suggestion] = { [] }

    /// The snapshot the widget draws. `suggestions` defaults to the active profile's store.
    func widgetSurfaceSnapshot(now: Date = Date(), suggestions: [Suggestion]? = nil) -> WidgetSurfaceSnapshot {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let goal = houseGoal
        let goalHours = goal.targetHours
        let isRecord = GoalManager.shared.goalChoice == .record
        let visible = InboxLogic.visible(suggestions ?? Self.widgetSuggestionsProvider(), now: now)
        let timerName = isTimerRunning ? properties.first { $0.id == timerPropertyId }?.name : nil

        // Today's pace: the linear share of the goal the calendar says you should have by now.
        let day = Double(calendar.ordinality(of: .day, in: .year, for: now) ?? 1)
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: now)?.count ?? 365)
        let expected = goalHours * day / daysInYear
        let firstEntry = timeEntries.filter { calendar.component(.year, from: $0.date) == year }.map(\.date).min()
        let daysOfData = firstEntry.map {
            max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0)
        } ?? 0

        // Every rental's own house: its hours against the goal, its own stage, its own lit state.
        let figures: [WidgetRentalFigure] = properties.map { property in
            let hours = propertyCountableHours(property.id, goal: goal, year: year)
            return WidgetRentalFigure(
                id: property.id.uuidString,
                name: property.name,
                hours: hours,
                stage: CraftStage.stage(hours: hours, goal: goalHours).rawValue,
                lit: TodayWindowState.loggedToday(entries: timeEntries, rentalIDs: [property.id], now: now, calendar: calendar),
                behindBy: isRecord ? 0 : max(0, expected - hours)
            )
        }
        // One rental: its own countable hours (REPS: your own, never a spouse's). Two or more: the
        // sum across them, the same number Today's "All rentals" page shows.
        let hours = figures.count > 1 ? figures.reduce(0) { $0 + $1.hours } : houseCountableHours(goal: goal, year: year)
        let stage = CraftStage.stage(hours: hours, goal: goalHours)
        let paceReady = hours >= TodayHeroCopy.paceMinHours || daysOfData >= TodayHeroCopy.paceMinDays
        let rows: [WidgetConfirmRow] = visible.sorted { $0.start > $1.start }.prefix(5).map { s in
            let rental = s.proposedPropertyId.flatMap { id in properties.first { $0.id == id }?.name }
            let proposed = (s.proposedHours ?? 0) > 0 ? s.proposedHours : nil
            return WidgetConfirmRow(
                key: s.sourceKey,
                title: s.title,
                rentalName: rental,
                hours: proposed,
                canConfirm: rental != nil && s.proposedCategory != nil && proposed != nil
            )
        }

        return WidgetSurfaceSnapshot(
            updatedAt: now,
            taxYear: year,
            propertyCount: properties.count,
            hours: hours,
            goal: WidgetSurfaceSnapshot.Goal(goal),
            goalHours: goalHours,
            requiredHoursToDate: expected,
            pendingCount: visible.count,
            timerStart: isTimerRunning ? timerStartTime : nil,
            timerPropertyName: timerName,
            houseKeyframe: "",
            stageTitle: stage.spokenName,
            nextStepLabel: "",
            houseStage: stage.rawValue,
            loggedToday: TodayWindowState.loggedToday(entries: timeEntries, now: now, calendar: calendar),
            paceReady: paceReady,
            isRecord: isRecord,
            rentals: figures,
            confirmRows: rows
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
