import XCTest
@testable import LandlordHours

// MARK: - Inbox false positives (2.2 quick fix)
//
// Everything here is synthetic. The failure patterns come from the 2026-10-27 diagnosis: the
// live 7-day scan ran the 1.x matcher (any shared address word, "rent" inside "parent", no
// "not rental" signals), and a location match alone scored Likely.

@MainActor
final class InboxSuggestionFixTests: CalendarCaptureTestCase {
    enum Verdict: Equatable { case hidden, notSure, likely }

    private let oak = RentalProperty(name: "Oak Street Duplex", address: "412 Oak St, Austin, TX 78704", propertyType: .ltr)
    private let maple = RentalProperty(name: "Maple Cottage", address: "88 Maple Ave, Santa Rosa, CA 95404", propertyType: .ltr)
    private var properties: [RentalProperty] { [oak, maple] }
    private let oakAddress = "412 Oak St, Austin, TX 78704"

    private func rulesChain() -> ClassifierChain {
        ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
    }

    private func yesModelChain() -> ClassifierChain {
        let yes = OnDeviceAnswer(isRentalWork: true, category: .management, propertyRef: nil, confidence: 0.9, reason: "test")
        return ClassifierChain(onDevice: OnDeviceClassifier(backend: FakeOnDeviceBackend(answer: yes)))
    }

    private func candidate(_ title: String, location: String?, context: CalendarContext = CalendarContext()) -> CaptureCandidate {
        let start = date(2026, 6, 2, 10)
        return CaptureCandidate(sourceKey: "k:\(title)", kind: .calendar, start: start, end: start.addingTimeInterval(3600),
                                title: title, location: location, detectedAt: start, context: context)
    }

    private func verdict(_ title: String, location: String?, context: CalendarContext = CalendarContext(), chain: ClassifierChain? = nil) async -> Verdict {
        let outcome = await (chain ?? rulesChain()).evaluate(candidate(title, location: location, context: context), properties: properties)
        guard case .suggest(let classification) = outcome else { return .hidden }
        return classification.band == .likely ? .likely : .notSure
    }

    private let teamsLink = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc"

    // MARK: Scenarios (also driven through both scan paths below)

    private struct Scenario {
        let title: String
        let location: String?
        let context: CalendarContext
        let expected: Verdict
    }

    private var scenarios: [Scenario] {
        [
            // Hidden: a location match with a "not rental" signal beside it.
            Scenario(title: "Team sync", location: oakAddress, context: CalendarContext(attendeeCount: 6, url: teamsLink), expected: .hidden),
            Scenario(title: "Stylist - Jo", location: "Glow Salon, 412 Oak St, Austin", context: CalendarContext(), expected: .hidden),
            Scenario(title: "Haircut", location: oakAddress, context: CalendarContext(), expected: .hidden),
            Scenario(title: "Telehealth follow-up", location: "Remote", context: CalendarContext(), expected: .hidden),
            Scenario(title: "Annual follow up", location: "Remote, 412 Oak St, Austin", context: CalendarContext(), expected: .hidden),
            Scenario(title: "Weekly planning", location: oakAddress, context: CalendarContext(attendeeCount: 2, isRecurring: true), expected: .hidden),
            // Likely: a work word in the title, or a showing.
            Scenario(title: "Plumber at Oak Street Duplex", location: oakAddress, context: CalendarContext(), expected: .likely),
            Scenario(title: "Plumber", location: oakAddress, context: CalendarContext(), expected: .likely),
            Scenario(title: "Showing - Alex", location: oakAddress, context: CalendarContext(), expected: .likely),
            // A tenant call on Zoom is still shown.
            Scenario(title: "Tenant call - Oak Street Duplex", location: nil, context: CalendarContext(attendeeCount: 2, url: "https://us02web.zoom.us/j/123456789"), expected: .likely),
            Scenario(title: "Tenant call", location: "Zoom", context: CalendarContext(url: "https://us02web.zoom.us/j/123456789"), expected: .notSure),
            // The accepted trade-off: a bare name at a rental address is "Not sure", not Likely.
            Scenario(title: "Alex", location: oakAddress, context: CalendarContext(), expected: .notSure),
        ]
    }

    // MARK: Negative signals

    func testScenariosClassifyAsExpected() async {
        for scenario in scenarios {
            let result = await verdict(scenario.title, location: scenario.location, context: scenario.context)
            XCTAssertEqual(result, scenario.expected, "\(scenario.title) @ \(scenario.location ?? "-")")
        }
    }

    func testTeamSyncWithAttendeesAndVideoLinkAtARentalStreetIsHidden() async {
        let result = await verdict("Team sync", location: oakAddress, context: CalendarContext(attendeeCount: 6, url: teamsLink))
        XCTAssertEqual(result, .hidden)
    }

    func testSalonVisitAtARentalStreetIsHidden() async {
        let result = await verdict("Stylist - Jo", location: "Glow Salon, 412 Oak St, Austin")
        XCTAssertEqual(result, .hidden)
    }

    func testTelehealthOrRemoteAppointmentIsHidden() async {
        let telehealth = await verdict("Telehealth follow-up", location: "Remote")
        let remote = await verdict("Annual follow up", location: "Remote, 412 Oak St, Austin")
        XCTAssertEqual(telehealth, .hidden)
        XCTAssertEqual(remote, .hidden)
    }

    func testWeeklyRecurringMeetingWithAttendeesIsHidden() async {
        let result = await verdict("Weekly planning", location: oakAddress, context: CalendarContext(attendeeCount: 2, isRecurring: true))
        XCTAssertEqual(result, .hidden)
    }

    func testEventOrganizedByOthersOnAWorkCalendarIsHidden() async {
        let result = await verdict("Quarterly review", location: oakAddress, context: CalendarContext(organizedByOther: true, isWorkCalendar: true))
        XCTAssertEqual(result, .hidden)
    }

    func testVideoLinkInTheNotesAloneCountsAgainst() async {
        let notes = "Join Zoom Meeting https://us02web.zoom.us/j/123456789"
        let result = await verdict("Planning", location: oakAddress, context: CalendarContext(notes: notes))
        XCTAssertEqual(result, .hidden)
    }

    func testEachVideoServiceIsRecognised() async {
        for link in ["https://us02web.zoom.us/j/1", "https://meet.google.com/abc-defg-hij", teamsLink, "https://acme.webex.com/meet/jo"] {
            let result = await verdict("Planning", location: oakAddress, context: CalendarContext(url: link))
            XCTAssertEqual(result, .hidden, link)
        }
    }

    func testAModelYesCannotBringBackAHiddenItem() async {
        let chain = yesModelChain()
        let teamSync = await verdict("Team sync", location: oakAddress, context: CalendarContext(attendeeCount: 6, url: teamsLink), chain: chain)
        let salon = await verdict("Stylist - Jo", location: "Glow Salon, 412 Oak St, Austin", chain: chain)
        XCTAssertEqual(teamSync, .hidden)
        XCTAssertEqual(salon, .hidden)
    }

    // MARK: Positives stay

    func testPlumberAtARentalIsLikely() async {
        let named = await verdict("Plumber at Oak Street Duplex", location: oakAddress)
        let atStreet = await verdict("Plumber", location: oakAddress)
        XCTAssertEqual(named, .likely)
        XCTAssertEqual(atStreet, .likely)
    }

    func testShowingIsLikely() async {
        let result = await verdict("Showing - Alex", location: oakAddress)
        XCTAssertEqual(result, .likely)
    }

    func testTenantCallOnZoomWithRentalWordsIsStillShown() async {
        let named = await verdict("Tenant call - Oak Street Duplex", location: nil,
                                  context: CalendarContext(attendeeCount: 2, url: "https://us02web.zoom.us/j/123456789"))
        XCTAssertEqual(named, .likely)
        // No property named: the video link takes the score down, but a tenant word keeps it visible.
        let bare = await verdict("Tenant call", location: "Zoom", context: CalendarContext(url: "https://us02web.zoom.us/j/123456789"))
        XCTAssertEqual(bare, .notSure)
    }

    // MARK: Location alone

    func testPersonNameOnlyAtARentalAddressIsNotSure() async {
        let result = await verdict("Alex", location: oakAddress)
        XCTAssertEqual(result, .notSure, "The accepted trade-off: shown, but never Likely")
    }

    func testALocationMatchAloneNeverReachesLikely() async {
        for title in ["Alex", "Quick stop", "Lunch with Sam", "Catch up"] {
            let outcome = await rulesChain().evaluate(candidate(title, location: oakAddress), properties: properties)
            switch outcome {
            case .suggest(let c): XCTAssertLessThan(c.confidence, ClassifierThresholds.likely, title)
            case .skip, .muted: break
            }
        }
    }

    func testALocationMatchWithNoNegativeSignalStaysVisible() async {
        let outcome = await rulesChain().evaluate(candidate("Alex", location: oakAddress), properties: properties)
        guard case .suggest(let c) = outcome else { return XCTFail("Not sure must stay visible") }
        XCTAssertEqual(c.band, .notSure)
        XCTAssertEqual(c.propertyId, oak.id)
    }

    func testASharedCityWordNeverMatchesAProperty() async {
        // "Santa Rosa" is the city of Maple Cottage's address, not its street.
        XCTAssertNil(CalendarImportService.shared.matchProperty(from: "lunch at santa rosa plaza", properties: properties))
        XCTAssertNil(CalendarImportService.shared.matchProperty(from: "austin offsite", properties: properties))
        let result = await verdict("Lunch", location: "Santa Rosa Plaza, Santa Rosa, CA")
        XCTAssertEqual(result, .hidden)
    }

    func testTheLegacyMatcherStillFindsTheStreetOrTheName() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.matchProperty(from: "plumber at 412 oak st", properties: properties)?.id, oak.id)
        XCTAssertEqual(service.matchProperty(from: "maple cottage walkthrough", properties: properties)?.id, maple.id)
    }

    func testParentNeverMatchesRent() async {
        let service = CalendarImportService.shared
        XCTAssertFalse(service.matchesPropertyKeyword("parent coffee"))
        XCTAssertFalse(service.matchesPropertyKeyword("Meet the parents"))
        XCTAssertTrue(service.matchesPropertyKeyword("Rent collection"))
        XCTAssertTrue(service.matchesPropertyKeyword("Rental walkthrough"))
        XCTAssertTrue(service.matchesPropertyKeyword("Move-in day"))

        let placeholder = await PlaceholderCalendarClassifier().classify(candidate("Meet the parents", location: nil), properties: properties)
        XCTAssertFalse(placeholder.isLandlordWork)
        XCTAssertFalse(placeholder.hasLandlordEvidence)
    }

    // MARK: Scan paths

    private func snapshot(_ id: String, _ scenario: Scenario, start: Date) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            externalId: id, eventIdentifier: "LOCAL-\(id)", title: scenario.title, location: scenario.location,
            start: start, end: start.addingTimeInterval(3600),
            occurrenceDate: start, hasRecurrenceRules: scenario.context.isRecurring,
            attendeeCount: scenario.context.attendeeCount, url: scenario.context.url, notes: scenario.context.notes,
            organizedByOther: scenario.context.organizedByOther, isWorkCalendar: scenario.context.isWorkCalendar
        )
    }

    func testTheDetectorCarriesTheCalendarContextToTheClassifier() async throws {
        let scenario = Scenario(title: "Planning", location: oakAddress,
                                context: CalendarContext(attendeeCount: 4, url: teamsLink, notes: "agenda", organizedByOther: true, isWorkCalendar: true, isRecurring: true),
                                expected: .hidden)
        let found = try await makeDetector(FakeCalendarSource(events: [snapshot("CTX", scenario, start: date(2026, 5, 4, 10))]))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        let context = try XCTUnwrap(found.first?.context)
        XCTAssertEqual(context.attendeeCount, 4)
        XCTAssertEqual(context.url, teamsLink)
        XCTAssertEqual(context.notes, "agenda")
        XCTAssertTrue(context.organizedByOther)
        XCTAssertTrue(context.isWorkCalendar)
        XCTAssertTrue(context.isRecurring)
    }

    /// Past copies for the 90-day backfill, future copies for the 7-day scan: the same events.
    private func scanBoth(_ scenarios: [Scenario], chain: ClassifierChain) async -> (backfill: [Suggestion], live: [Suggestion]) {
        let past = scenarios.enumerated().map { snapshot("P\($0.offset)", $0.element, start: date(2026, 5, 20, 8 + $0.offset)) }
        let future = scenarios.enumerated().map { snapshot("F\($0.offset)", $0.element, start: date(2026, 6, 3, 8 + $0.offset)) }
        let backfillStore = makeStore()
        let liveStore = SuggestionStore(userId: profileId + "-live", baseDirectory: baseDir)
        let backfill = await makeCoordinator(FakeCalendarSource(events: past), store: backfillStore)
            .scanBackfillBatched(chain: chain, properties: properties, entries: [])
        let live = await makeCoordinator(FakeCalendarSource(events: future), store: liveStore, classifier: chain)
            .scanUpcoming(properties: properties, entries: [])
        return (backfill.added, live.added)
    }

    func testTheLiveScanAndTheBackfillGiveTheSameVerdicts() async {
        let all = scenarios
        let (backfill, live) = await scanBoth(all, chain: rulesChain())
        for scenario in all {
            let past = backfill.first { $0.title == scenario.title }
            let next = live.first { $0.title == scenario.title }
            switch scenario.expected {
            case .hidden:
                XCTAssertNil(past, "backfill: \(scenario.title)")
                XCTAssertNil(next, "live: \(scenario.title)")
            case .notSure, .likely:
                XCTAssertNotNil(past, "backfill: \(scenario.title)")
                XCTAssertNotNil(next, "live: \(scenario.title)")
                XCTAssertEqual(past?.confidence ?? -1, next?.confidence ?? -2, accuracy: 0.0001, scenario.title)
                XCTAssertEqual((next?.confidence ?? 0) >= ClassifierThresholds.likely, scenario.expected == .likely, scenario.title)
            }
        }
    }

    func testTheLiveScanKeepsTheNotSureTierVisible() async throws {
        let alex = Scenario(title: "Alex", location: oakAddress, context: CalendarContext(), expected: .notSure)
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: [snapshot("F", alex, start: date(2026, 6, 3, 10))]), store: store, classifier: rulesChain())
            .scanUpcoming(properties: properties, entries: [])
        let added = try XCTUnwrap(result.added.first)
        XCTAssertLessThan(added.confidence, ClassifierThresholds.likely)
        XCTAssertTrue(store.pending.contains { $0.id == added.id })
    }

    func testTheLiveScanKeepsTheHoursAndCategoryOf1x() async throws {
        let showing = Scenario(title: "Showing - Alex", location: oakAddress, context: CalendarContext(), expected: .likely)
        let result = await makeCoordinator(FakeCalendarSource(events: [snapshot("F", showing, start: date(2026, 6, 3, 10))]), store: makeStore(), classifier: rulesChain())
            .scanUpcoming(properties: properties, entries: [])
        let s = try XCTUnwrap(result.added.first)
        XCTAssertEqual(s.proposedHours, 1)
        XCTAssertEqual(s.hoursBasis, .scheduled)
        XCTAssertEqual(s.proposedCategory, LegacyCalendarCategory.category(forTitle: "Showing - Alex"), "1.1 dedupe keeps the 1.x category")
    }

    func testARealRefreshClassifiesWithTheChainNotThe1xMatcher() {
        let coordinator = CaptureNotificationRefresher.defaultCoordinator(store: makeStore())
        XCTAssertTrue(coordinator.classifier is ClassifierChain)
    }

    // MARK: Tags and "might be logged"

    func testNotSureShowsAheadOfMightBeLogged() {
        let s = calendarSuggestion(start: date(2026, 6, 2, 10), propertyId: oak.id)
        let both = SuggestionBadges(notSure: true, mightAlreadyBeLogged: true, needsHours: false)
        let tag = SuggestionRowView.tag(s, badges: both, limit: .none, colors: AdaptiveColors(colorScheme: .light))
        XCTAssertEqual(tag?.text, "Not sure")
        let onlyLogged = SuggestionBadges(notSure: false, mightAlreadyBeLogged: true, needsHours: false)
        XCTAssertEqual(SuggestionRowView.tag(s, badges: onlyLogged, limit: .none, colors: AdaptiveColors(colorScheme: .light))?.text, "Might be logged")
    }

    func testMightBeLoggedNeedsTheLoggedHoursToMatchTheEventWithin15Minutes() {
        let s = calendarSuggestion(start: date(2026, 6, 2, 10), propertyId: oak.id, hours: 1)
        func manual(_ hours: Double, property: UUID? = nil) -> TimeEntry {
            TimeEntry(propertyId: property ?? oak.id, participant: .selfParticipant, category: .repairs, hours: hours, date: date(2026, 6, 2, 16))
        }
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(1)], calendar: calendar))
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(1.25)], calendar: calendar), "15 minutes apart")
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(0.75)], calendar: calendar), "15 minutes apart")
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(1.5)], calendar: calendar), "30 minutes apart")
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(4)], calendar: calendar), "A long day at the rental is not this event")
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(1, property: UUID())], calendar: calendar), "Another rental")
    }
}
