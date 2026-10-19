import XCTest
@testable import LandlordHours

// MARK: - Inbox rules (pure)

@MainActor
final class InboxLogicTests: CaptureTestCase {
    private var now: Date!

    override func setUp() async throws {
        try await super.setUp()
        now = date(2026, 10, 16, 15)
    }

    private func s(_ key: String, start: Date, confidence: Double = 0.9, flagged: Bool = false, hours: Double? = 1,
                   basis: Suggestion.HoursBasis = .scheduled, property: UUID? = UUID(), category: ActivityCategory? = .repairs,
                   backfill: Bool = false, detectedAt: Date? = nil) -> Suggestion {
        Suggestion(sourceKey: "cal:\(key)", kind: .calendar, detectedAt: detectedAt ?? start, start: start,
                   end: hours.map { start.addingTimeInterval($0 * 3600) }, title: key, containerId: "CAL",
                   proposedPropertyId: property, proposedCategory: category, proposedHours: hours, hoursBasis: basis,
                   confidence: confidence, isBackfill: backfill, mightAlreadyBeLogged: flagged)
    }

    func testGroupsTodayThisWeekEarlierNewestFirst() {
        let items = [
            s("old", start: date(2026, 9, 1, 9)),
            s("today-am", start: date(2026, 10, 16, 9)),
            s("today-noon", start: date(2026, 10, 16, 12)),
            s("tue", start: date(2026, 10, 14, 9)),
            s("edge-week", start: date(2026, 10, 10, 9)),   // 6 days before today: this week
            s("edge-earlier", start: date(2026, 10, 9, 23)), // 7 days: earlier
        ]
        let sections = InboxLogic.sections(items, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.group), [.today, .thisWeek, .earlier])
        XCTAssertEqual(sections[0].items.map(\.title), ["today-noon", "today-am"])
        XCTAssertEqual(sections[1].items.map(\.title), ["tue", "edge-week"])
        XCTAssertEqual(sections[2].items.map(\.title), ["edge-earlier", "old"])
    }

    func testEmptyGroupsDroppedAndUpcomingAndResolvedHidden() {
        var confirmed = s("done", start: date(2026, 10, 15, 9))
        confirmed.state = .confirmed(entryId: UUID())
        var dismissed = s("no", start: date(2026, 10, 15, 9))
        dismissed.state = .dismissed(reason: .notLandlordWork)
        let upcoming = s("later", start: date(2026, 10, 16, 18), detectedAt: date(2026, 10, 16, 19))
        let sections = InboxLogic.sections([confirmed, dismissed, upcoming, s("x", start: date(2026, 10, 15, 9))], now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.group), [.thisWeek])
        XCTAssertEqual(sections[0].items.map(\.title), ["x"])
    }

    func testRankingByConfidenceThenNotFlaggedThenNewest() {
        let ranked = InboxLogic.ranked([
            s("low", start: date(2026, 10, 1), confidence: 0.4),
            s("flagged", start: date(2026, 10, 5), confidence: 0.9, flagged: true),
            s("older", start: date(2026, 10, 2), confidence: 0.9),
            s("newer", start: date(2026, 10, 3), confidence: 0.9),
            s("top", start: date(2026, 9, 1), confidence: 0.97),
        ])
        XCTAssertEqual(ranked.map(\.title), ["top", "newer", "older", "flagged", "low"])
    }

    func testBackfillShowsTopFifteenThenShowMore() {
        let items = (0..<20).map { s("b\($0)", start: date(2026, 9, 1 + $0), confidence: Double($0) / 20, backfill: true) }
            + [s("live", start: date(2026, 10, 15), confidence: 1)]
        let model = BackfillIntroModel()
        let preview = model.items(from: items)
        XCTAssertEqual(preview.count, 15)
        XCTAssertEqual(preview.first?.title, "b19", "Most confident first; live items are not backfill")
        XCTAssertFalse(preview.contains { $0.title == "live" })
        XCTAssertEqual(model.hiddenCount(from: items), 5)
        model.showAll = true
        XCTAssertEqual(model.items(from: items).count, 20)
        XCTAssertEqual(model.hiddenCount(from: items), 0)
    }

    func testBadges() {
        XCTAssertEqual(InboxLogic.badges(for: s("a", start: now, confidence: 0.6)),
                       SuggestionBadges(notSure: false, mightAlreadyBeLogged: false, needsHours: false))
        XCTAssertTrue(InboxLogic.badges(for: s("b", start: now, confidence: 0.59)).notSure, "Below the likely line")
        XCTAssertTrue(InboxLogic.badges(for: s("c", start: now, flagged: true)).mightAlreadyBeLogged)
        XCTAssertTrue(InboxLogic.badges(for: s("d", start: now, hours: nil, basis: .none)).needsHours)
        let receipt = Suggestion(sourceKey: "rcpt:1", kind: .receipt, detectedAt: now, start: now, title: "Depot",
                                 proposedHours: 3, hoursBasis: .scheduled)
        XCTAssertTrue(InboxLogic.badges(for: receipt).needsHours, "Receipts never carry hours")
    }

    func testQuickLogOnlyForCompleteScheduledUnflaggedItems() {
        let property = UUID()
        let ids: Set<UUID> = [property]
        XCTAssertTrue(InboxLogic.canQuickLog(s("ok", start: now, property: property), propertyIds: ids))
        XCTAssertFalse(InboxLogic.canQuickLog(s("dwell", start: now, basis: .dwellCap, property: property), propertyIds: ids))
        XCTAssertFalse(InboxLogic.canQuickLog(s("none", start: now, hours: nil, basis: .none, property: property), propertyIds: ids))
        XCTAssertFalse(InboxLogic.canQuickLog(s("flag", start: now, flagged: true, property: property), propertyIds: ids))
        XCTAssertFalse(InboxLogic.canQuickLog(s("noprop", start: now, property: nil), propertyIds: ids))
        XCTAssertFalse(InboxLogic.canQuickLog(s("deleted", start: now, property: UUID()), propertyIds: ids))
        XCTAssertFalse(InboxLogic.canQuickLog(s("nocat", start: now, property: property, category: nil), propertyIds: ids))
        XCTAssertTrue(InboxLogic.canQuickLog(s("unsure", start: now, confidence: 0.35, property: property), propertyIds: ids),
                      "Not sure is the user's call; a deliberate swipe may log it")
    }

    func testFormatting() {
        XCTAssertEqual(InboxFormat.hours(2), "2h")
        XCTAssertEqual(InboxFormat.hours(1.5), "1h 30m")
        XCTAssertEqual(InboxFormat.hours(0.75), "45m")
        XCTAssertEqual(InboxFormat.timeRange(start: date(2026, 10, 14, 9), end: date(2026, 10, 14, 11), calendar: calendar), "9–11")
        let start = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: date(2026, 10, 12))!
        XCTAssertEqual(InboxFormat.timeRange(start: start, end: start.addingTimeInterval(3600), calendar: calendar), "5:30–6:30")
        XCTAssertEqual(InboxFormat.day(date(2026, 10, 13, 9), now: now, calendar: calendar), "Tue")
        XCTAssertEqual(InboxFormat.day(date(2026, 10, 15, 9), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(InboxFormat.day(date(2026, 9, 3, 9), now: now, calendar: calendar), "Sep 3")
    }
}

// MARK: - Inbox view model (swipe, undo, mute)

/// A plan that allows no more entries (stands in for WP-P's free-tier rules).
private final class LimitedAppViewModel: AppViewModel {
    override func canAddTimeEntry() -> Bool { false }
}

@MainActor
final class InboxViewModelTests: CaptureTestCase {
    private var app: AppViewModel!
    private var propertyId: UUID!
    private var store: SuggestionStore!
    private var now: Date!

    override func setUp() async throws {
        try await super.setUp()
        (app, propertyId) = makeViewModel()
        store = makeStore()
        now = Date()
    }

    private func model(spouse: Bool = false, app: AppViewModel? = nil, store: SuggestionStore?? = nil) -> InboxViewModel {
        let resolvedStore: SuggestionStore? = store ?? self.store
        let model = InboxViewModel(app: app ?? self.app, storeProvider: { resolvedStore }, now: { [now] in now! },
                                   calendar: calendar, spouseTracking: { spouse }, undoWindow: .infinity)
        model.reload()
        return model
    }

    private func seed(_ items: [Suggestion]) {
        store.ingest(items, existingEntries: app.timeEntries, calendar: calendar)
    }

    private func item(_ id: String, daysAgo: Int = 1, property: UUID?? = nil, hours: Double? = 2) -> Suggestion {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!.addingTimeInterval(10 * 3600)
        return calendarSuggestion(externalId: id, start: start, title: "Plumber \(id)",
                                  propertyId: property ?? propertyId, hours: hours, category: .repairs)
    }

    func testSwipeLogSavesImmediatelyWithUndo() {
        let a = item("A"), b = item("B", daysAgo: 2)
        seed([a, b])
        let model = model()
        XCTAssertEqual(model.badgeCount, 2)

        XCTAssertEqual(model.swipeLog(a), .logged)
        let entries = app.timeEntries.filter { $0.sourceKey == a.sourceKey }
        XCTAssertEqual(entries.count, 1, "Saved at once: nothing is lost if the app dies inside the Undo window")
        XCTAssertEqual(entries[0].id, a.entryId(profileId: profileId))
        XCTAssertEqual(entries[0].hours, 2)
        XCTAssertNotNil(entries[0].confirmedAt)
        XCTAssertEqual(store.suggestion(forKey: a.sourceKey)!.state, .confirmed(entryId: entries[0].id))
        XCTAssertEqual(model.badgeCount, 1)
        XCTAssertEqual(model.toast?.message, "Logged 2h")
        if case .logged(_, let entryId, let hours)? = model.toast?.undo {
            XCTAssertEqual(entryId, entries[0].id)
            XCTAssertEqual(hours, 2)
        } else {
            XCTFail("Undo offered for the saved log")
        }
    }

    func testUndoLogDeletesTheEntryAndRestoresTheRow() {
        let a = item("A")
        seed([a])
        let model = model()
        model.swipeLog(a)
        XCTAssertEqual(model.badgeCount, 0)
        model.undo()
        XCTAssertTrue(app.timeEntries.filter { $0.sourceKey != nil }.isEmpty, "Undo deletes through deleteTimeEntry")
        XCTAssertTrue(store.suggestion(forKey: a.sourceKey)!.isPending)
        XCTAssertEqual(model.badgeCount, 1)
        XCTAssertNil(model.toast)
        // Logging again after Undo works and keeps the same derived id.
        XCTAssertEqual(model.swipeLog(a), .logged)
        XCTAssertEqual(app.timeEntries.filter { $0.sourceKey == a.sourceKey }.map(\.id), [a.entryId(profileId: profileId)])
    }

    func testDismissSavesAndUndoRestores() {
        let a = item("A"), b = item("B", daysAgo: 3)
        seed([a, b])
        let model = model()
        model.dismiss(a)
        XCTAssertTrue(store.isDismissed(a.sourceKey), "Saved at once")
        model.undo()
        XCTAssertFalse(store.isDismissed(a.sourceKey))
        XCTAssertTrue(store.suggestion(forKey: a.sourceKey)!.isPending)
        model.dismiss(b)
        XCTAssertEqual(store.suggestion(forKey: b.sourceKey)!.state, .dismissed(reason: .notLandlordWork))
        XCTAssertTrue(app.timeEntries.filter { $0.sourceKey != nil }.isEmpty, "Dismiss never writes entries")
    }

    func testUndoOnlyReversesTheLatestAction() {
        let a = item("A"), b = item("B", daysAgo: 2)
        seed([a, b])
        let model = model()
        model.swipeLog(a)
        model.dismiss(b)
        model.undo()
        XCTAssertFalse(store.isDismissed(b.sourceKey))
        XCTAssertEqual(app.timeEntries.filter { $0.sourceKey == a.sourceKey }.count, 1, "The earlier log stays")
    }

    func testFailedConfirmKeepsTheItemAndSaysWhy() {
        let limited = LimitedAppViewModel()
        limited.suppressCelebrations = true
        let a = item("A")
        seed([a])
        let model = model(app: limited)
        XCTAssertEqual(model.swipeLog(a), .failed)
        XCTAssertTrue(limited.timeEntries.filter { $0.sourceKey != nil }.isEmpty)
        XCTAssertTrue(store.suggestion(forKey: a.sourceKey)!.isPending, "Still in the inbox")
        XCTAssertEqual(model.badgeCount, 1)
        XCTAssertEqual(model.toast?.kind, .problem)
        XCTAssertNil(model.toast?.undo)
        XCTAssertEqual(model.toast?.message, "Not saved. Your plan has reached its limit.")
    }

    func testNoStoreNeverClaimsLogged() {
        let a = item("A")
        let model = model(store: .some(nil))
        XCTAssertEqual(model.swipeLog(a), .failed, "No profile: nothing saved, and it says so")
        XCTAssertNil(model.log(a, edits: SuggestionEdits()))
        XCTAssertEqual(model.toast?.kind, .problem)
        XCTAssertEqual(model.toast?.message, InboxViewModel.noProfileMessage)
        XCTAssertTrue(app.timeEntries.filter { $0.sourceKey != nil }.isEmpty)
    }

    func testPropertyDeletedAfterLoadingOpensSheetNotSilentLoss() {
        let a = item("A")
        seed([a])
        let model = model()
        app.deleteProperty(app.properties[0])
        XCTAssertEqual(model.swipeLog(a), .needsSheet)
        XCTAssertEqual(model.log(a, edits: SuggestionEdits()), .needsInput(missing: [.property]))
        XCTAssertTrue(app.timeEntries.isEmpty)
        XCTAssertTrue(store.suggestion(forKey: a.sourceKey)!.isPending)
    }

    func testConfirmRespectsCanAddTimeEntry() {
        let limited = LimitedAppViewModel()
        limited.suppressCelebrations = true
        limited.addProperty(name: "Oak", address: "1 Oak St", type: .ltr)
        let a = item("A", property: .some(limited.properties[0].id))
        XCTAssertEqual(limited.confirm(a, store: store), .needsInput(missing: [.plan]))
    }

    func testSwipeOnIncompleteOrFlaggedItemOpensSheet() {
        let noProperty = item("NP", property: .some(nil))
        seed([noProperty])
        let model = model()
        XCTAssertEqual(model.swipeLog(noProperty), .needsSheet)
        XCTAssertEqual(model.sheetSuggestion?.sourceKey, noProperty.sourceKey)
        XCTAssertNil(model.toast)
    }

    func testSwipeRechecksAlreadyLoggedAtTapTime() {
        let a = item("A")
        seed([a])
        let model = model()
        XCTAssertTrue(model.canQuickLog(model.visible[0]))
        app.timeEntries.append(TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs,
                                         hours: 2, date: a.start))
        XCTAssertEqual(model.swipeLog(a), .needsSheet, "Flagged at tap time, so the sheet asks")
        XCTAssertTrue(model.sheetSuggestion!.mightAlreadyBeLogged)
    }

    func testSheetLogRequiresHoursWhenBasisIsNone() {
        var receiptLike = item("R", hours: nil)
        receiptLike.hoursBasis = .none
        seed([receiptLike])
        let model = model()
        XCTAssertEqual(model.log(receiptLike, edits: SuggestionEdits()), .needsInput(missing: [.hours]))
        XCTAssertNil(model.toast)
        XCTAssertNil(model.log(receiptLike, edits: SuggestionEdits(hours: 1.25, participant: .spouse)))
        let entry = app.timeEntries.first { $0.sourceKey == receiptLike.sourceKey }
        XCTAssertEqual(entry?.hours, 1.25)
        XCTAssertEqual(entry?.participant, .spouse)
        XCTAssertEqual(model.toast?.message, "Logged 1h 15m")
    }

    func testMuteHidesMatchingItemsAndUndoRestoresThem() {
        let a = item("A"), b = calendarSuggestion(externalId: "B", start: item("x", daysAgo: 4).start,
                                                   title: "Plumber A follow-up", propertyId: propertyId)
        let other = calendarSuggestion(externalId: "C", start: item("y", daysAgo: 5).start, title: "Showing", propertyId: propertyId)
        seed([a, b, other])
        let model = model()
        let rule = InboxLogic.muteRule(forTitleOf: a)!
        model.mute(a, rule: rule)
        XCTAssertEqual(model.visible.map(\.sourceKey), [other.sourceKey], "Everything the rule covers leaves together")
        XCTAssertEqual(store.muteRules.map(\.value), ["Plumber A"], "Saved at once")
        model.undo()
        XCTAssertTrue(store.muteRules.isEmpty)
        XCTAssertEqual(model.badgeCount, 3)
        XCTAssertFalse(store.isDismissed(a.sourceKey))
        model.mute(a, rule: rule)
        XCTAssertEqual(store.pending.map(\.sourceKey), [other.sourceKey])
        XCTAssertTrue(store.isDismissed(a.sourceKey))
    }

    func testSpousePickerOnlyWhenSpouseIsTracked() {
        XCTAssertFalse(model(spouse: false).showsSpousePicker)
        XCTAssertTrue(model(spouse: true).showsSpousePicker)
    }

    func testBackfillBannerCountsOnlyBackfillItems() {
        var old = item("OLD", daysAgo: 30)
        old.isBackfill = true
        seed([old, item("NEW")])
        XCTAssertEqual(model().backfillCount, 1)
    }
}

// MARK: - Opt-in gating

@MainActor
final class CaptureOptInTests: CaptureTestCase {
    func testEverythingDefaultsOff() {
        XCTAssertFalse(EventPromptsConsent.isEnabled())
        XCTAssertFalse(CaptureOptIn.calendarSuggestionsEnabled())
        XCTAssertFalse(EventPromptsConsent.isEnabled(userId: nil), "No profile, no prompts")
    }

    func testUpgraderSeesWhatsNewOnceAndNewUsersDoNot() {
        XCTAssertTrue(CaptureOptIn.shouldShowWhatsNew(hasCompletedOnboarding: true, arguments: []))
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(hasCompletedOnboarding: false, arguments: []),
                       "New users answer in onboarding")
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(hasCompletedOnboarding: true, arguments: ["-LHMockScenario", "occasional"]),
                       "Seeded test launches stay quiet")
        XCTAssertTrue(CaptureOptIn.shouldShowWhatsNew(hasCompletedOnboarding: true, arguments: ["-LHMockScenario", "x", "-LHShowWhatsNew"]))
        CaptureOptIn.recordChoice(calendar: false, eventPrompts: false)
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(hasCompletedOnboarding: true, arguments: []), "Answered once, never again")
    }

    func testPromptsNeedAnExplicitYesAndCalendar() {
        CaptureOptIn.recordChoice(calendar: false, eventPrompts: true)
        XCTAssertFalse(EventPromptsConsent.isEnabled(), "No calendar, no event prompts")
        CaptureOptIn.recordChoice(calendar: true, eventPrompts: false)
        XCTAssertTrue(CaptureOptIn.calendarSuggestionsEnabled())
        XCTAssertFalse(EventPromptsConsent.isEnabled(), "Calendar alone does not turn on notifications")
        CaptureOptIn.recordChoice(calendar: true, eventPrompts: true)
        XCTAssertTrue(EventPromptsConsent.isEnabled())
        CaptureOptIn.recordChoice(calendar: false, eventPrompts: true)
        XCTAssertFalse(EventPromptsConsent.isEnabled(), "Turning calendar off turns prompts off")
    }

    func testOptInWritesWP4sConsentFlag() {
        XCTAssertFalse(CapturePromptConsent.isEnabled(profileId: profileId))
        CaptureOptIn.recordChoice(calendar: true, eventPrompts: true)
        XCTAssertTrue(CapturePromptConsent.isEnabled(profileId: profileId), "WP4's scheduler reads this flag")
        let (app, _) = makeViewModel()
        XCTAssertTrue(app.eventPromptsEnabled)
        CaptureOptIn.recordChoice(calendar: true, eventPrompts: false)
        XCTAssertFalse(app.eventPromptsEnabled)
    }

    func testOptInIsPerProfile() {
        CaptureOptIn.recordChoice(calendar: true, eventPrompts: true)
        let other = "other-\(UUID().uuidString.prefix(6))"
        XCTAssertFalse(EventPromptsConsent.isEnabled(userId: other))
        XCTAssertFalse(CaptureOptIn.whatsNewSeen(userId: other))
        AppViewModel.clearScopedAccountData(for: profileId)
        XCTAssertFalse(EventPromptsConsent.isEnabled(), "Profile reset clears the opt-in")
    }
}

// MARK: - Backfill intro

private struct FakeBackfillScanner: BackfillScanning {
    var access: CalendarAccess = .fullAccess
    var found = 3
    var cancelled = false
    func scan(progress: @escaping @Sendable (ClassifierBatchProgress) -> Void) async -> BackfillScanOutcome {
        for i in 1...4 { progress(ClassifierBatchProgress(completed: i, total: 4)) }
        return BackfillScanOutcome(access: access, foundCount: found, cancelled: cancelled)
    }
}

/// Runs until cancelled (like a long 90-day scan).
private struct SlowBackfillScanner: BackfillScanning {
    func scan(progress: @escaping @Sendable (ClassifierBatchProgress) -> Void) async -> BackfillScanOutcome {
        for _ in 0..<200 {
            if Task.isCancelled { return BackfillScanOutcome(access: .fullAccess, foundCount: 0, cancelled: true) }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return BackfillScanOutcome(access: .fullAccess, foundCount: 5)
    }
}

@MainActor
final class BackfillIntroTests: CalendarCaptureTestCase {
    func testRunEndsInResultsAndMarksBackfillDone() async {
        let model = BackfillIntroModel()
        await model.run(FakeBackfillScanner(), revealAvailable: false)
        XCTAssertEqual(model.phase, .results)
        XCTAssertEqual(model.foundCount, 3)
        XCTAssertTrue(CaptureOptIn.backfillCompleted())
    }

    func testRevealShowsFirstWhenWPHHookIsInstalled() async {
        let model = BackfillIntroModel()
        await model.run(FakeBackfillScanner(), revealAvailable: true)
        XCTAssertEqual(model.phase, .reveal)
        model.finishReveal()
        XCTAssertEqual(model.phase, .results)
        let empty = BackfillIntroModel()
        await empty.run(FakeBackfillScanner(found: 0), revealAvailable: true)
        XCTAssertEqual(empty.phase, .results, "Nothing found: no reveal")
    }

    func testCancelledScanIsNotMarkedComplete() async {
        let model = BackfillIntroModel()
        await model.run(FakeBackfillScanner(cancelled: true), revealAvailable: false)
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertFalse(CaptureOptIn.backfillCompleted(), "A cancelled look-back can run again")
    }

    func testCancelButtonStopsAScanInFlight() async {
        let model = BackfillIntroModel()
        let finished = expectation(description: "scan task ended")
        model.start(SlowBackfillScanner(), revealAvailable: false) { finished.fulfill() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        model.cancel()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertFalse(CaptureOptIn.backfillCompleted())
    }

    func testCoordinatorReportsCancelledAndIngestsNothing() async {
        let (app, _) = makeViewModel()
        let store = makeStore()
        let source = FakeCalendarSource(events: [
            event("PLUMB", start: date(2026, 5, 10, 9), hours: 2, title: "Plumber at Oak"),
        ])
        let coordinator = makeCoordinator(source, store: store)
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
        let properties = app.properties, entries = app.timeEntries
        let task = Task { await coordinator.scanBackfillBatched(chain: chain, properties: properties, entries: entries) }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertTrue(store.suggestions.isEmpty, "Nothing ingested from a cancelled scan")
    }

    func testDeniedCalendarIsBlocked() async {
        let model = BackfillIntroModel()
        await model.run(FakeBackfillScanner(access: .denied), revealAvailable: false)
        XCTAssertEqual(model.phase, .blocked(.denied))
        XCTAssertFalse(CaptureOptIn.backfillCompleted())
    }

    func testBatchedBackfillUsesTheChainAndKeepsNotSureItems() async {
        let (app, oak) = makeViewModel()
        let store = makeStore()
        let source = FakeCalendarSource(events: [
            event("PLUMB", start: date(2026, 5, 10, 9), hours: 2, title: "Plumber at Oak"),
            event("DENT", start: date(2026, 5, 11, 9), hours: 1, title: "Dentist"),
        ])
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
        let counter = ProgressCounter()
        let result = await makeCoordinator(source, store: store).scanBackfillBatched(
            chain: chain, properties: app.properties, entries: app.timeEntries
        ) { counter.record($0) }
        XCTAssertEqual(result.access, .fullAccess)
        let keys = store.pending.map(\.title)
        XCTAssertTrue(keys.contains("Plumber at Oak"))
        XCTAssertFalse(keys.contains("Dentist"), "No landlord signal: not suggested")
        let plumber = store.pending.first { $0.title == "Plumber at Oak" }!
        XCTAssertTrue(plumber.isBackfill)
        XCTAssertEqual(plumber.hoursBasis, .scheduled)
        XCTAssertEqual(plumber.proposedHours, 2)
        XCTAssertEqual(plumber.proposedPropertyId, oak)
        XCTAssertEqual(counter.last, ClassifierBatchProgress(completed: 2, total: 2))
    }
}

private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ClassifierBatchProgress?
    func record(_ p: ClassifierBatchProgress) { lock.lock(); value = p; lock.unlock() }
    var last: ClassifierBatchProgress? { lock.lock(); defer { lock.unlock() }; return value }
}
