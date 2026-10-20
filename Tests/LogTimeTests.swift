import XCTest
@testable import LandlordHours

// MARK: - Log time (2.0): parse → fill → Undo, the participant rule, non-countable logging,
// the timer (start / stop / discard / review) and a surfaced save failure. Written before the view.

@MainActor
final class LogFormFillTests: XCTestCase {
    private let pine = RentalProperty(name: "Pine Cabin", address: "88 Ridge Rd", propertyType: .str)
    private let oak = RentalProperty(name: "Oak Street Duplex", address: "214 Oak St", propertyType: .ltr)

    private func parse(_ text: String) async -> ParsedTimeEntry {
        let parsed = await AITimeEntryService.shared.parseTimeEntry(from: text, properties: [pine, oak])
        return try! XCTUnwrap(parsed)
    }

    func testNoteFillsPropertyCategoryAndSpokenHours() async {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        form.note = "Fixed the sink at Pine Cabin, 1 hour"
        let wrote = form.apply(await parse(form.note), source: .note, spouseTracking: false)
        XCTAssertEqual(form.propertyId, pine.id)
        XCTAssertEqual(form.category, .repairs)
        XCTAssertEqual(form.hours, 1)
        XCTAssertTrue(wrote.contains(.property))
        XCTAssertTrue(wrote.contains(.category))
        XCTAssertEqual(form.fillSource?.caption, "Filled from your note")
        XCTAssertTrue(form.canLog(properties: [pine, oak]))
    }

    func testCaptionNeverEndsInADanglingMiddot() {
        for source in [LogFillSource.note, .voice, .receipt, .visit("Mike's visit")] {
            XCTAssertFalse(source.caption.hasSuffix("·"), source.caption)
            XCTAssertFalse(source.caption.contains("·"), source.caption)
        }
        XCTAssertEqual(LogFillSource.visit("Mike's visit").caption, "Filled from Mike's visit")
    }

    func testFillNeverOverwritesWhatTheUserSet() async {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        form.setProperty(oak.id)
        form.setHours(2.5)
        form.setCategory(.leasing)
        form.note = "Fixed the sink at Pine Cabin, 1 hour"
        let wrote = form.apply(await parse(form.note), source: .note, spouseTracking: false)
        XCTAssertEqual(form.propertyId, oak.id)
        XCTAssertEqual(form.hours, 2.5)
        XCTAssertEqual(form.category, .leasing)
        XCTAssertTrue(wrote.isEmpty)
        XCTAssertNil(form.fillSource, "nothing filled, so no caption")
    }

    func testGuessedHoursAndFallbackCategoryAreNeverWritten() async {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        form.note = "Spent the afternoon on it"     // no hours said, no keyword
        let parsed = await parse(form.note)
        XCTAssertFalse(parsed.hoursAreExplicit)
        XCTAssertFalse(parsed.categoryMatched)
        form.apply(parsed, source: .note, spouseTracking: false)
        XCTAssertEqual(form.hours, 1, "the default stays; an estimate is a guess")
        XCTAssertNil(form.category, "no fake Management fill")
    }

    func testUndoPutsBackExactlyWhatWasThere() async {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        let before = (form.propertyId, form.category, form.hours, form.participant)
        form.note = "Showing at Oak Street Duplex for 2 hours"
        form.apply(await parse(form.note), source: .note, spouseTracking: false)
        XCTAssertEqual(form.propertyId, oak.id)
        XCTAssertEqual(form.hours, 2)
        XCTAssertTrue(form.canUndoFill)
        form.undoFill()
        XCTAssertEqual(form.propertyId, before.0)
        XCTAssertEqual(form.category, before.1)
        XCTAssertEqual(form.hours, before.2)
        XCTAssertEqual(form.participant, before.3)
        XCTAssertNil(form.fillSource)
        XCTAssertFalse(form.canUndoFill)
        XCTAssertEqual(form.note, "Showing at Oak Street Duplex for 2 hours", "Undo never touches the note")
    }

    func testRememberedCategoryCanBeReplacedByTheNote() async {
        let entry = TimeEntry(propertyId: pine.id, participant: .selfParticipant, category: .bookkeeping,
                              hours: 1, date: Date(), notes: "", attachments: [], importSource: nil)
        var form = LogForm.starting(properties: [pine], entries: [entry])
        XCTAssertEqual(form.category, .bookkeeping)
        XCTAssertTrue(form.categoryIsRemembered)
        XCTAssertEqual(form.propertyId, pine.id, "the only rental is preselected")
        form.note = "Fixed the leak"
        form.apply(await parse(form.note), source: .voice, spouseTracking: false)
        XCTAssertEqual(form.category, .repairs)
        XCTAssertEqual(form.fillSource, .voice)
    }

    func testValidationSaysWhatsMissingInPlainWords() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        XCTAssertEqual(form.missingMessage(properties: [pine, oak]), "Pick a property to log this.")
        form.setProperty(pine.id)
        form.setHours(0)
        XCTAssertEqual(form.missingMessage(properties: [pine, oak]), "Add how long it took to log this.")
        form.setHours(0.5)
        XCTAssertEqual(form.missingMessage(properties: [pine, oak]), "Pick the kind of work to log this.")
        form.setCategory(.management)
        XCTAssertNil(form.missingMessage(properties: [pine, oak]))
        XCTAssertEqual(LogForm.starting(properties: [], entries: []).missingMessage(properties: []), "Add a property to log this.")
    }

    func testHoursStepInQuarterHoursAndClampToADay() {
        var form = LogForm()
        form.setHours(0)
        form.stepHours(up: false)
        XCTAssertEqual(form.hours, 0)
        form.stepHours(up: true)
        XCTAssertEqual(form.hours, 0.25)
        form.setHours(30)
        XCTAssertEqual(form.hours, 24)
        form.setHours(1.1)
        XCTAssertEqual(form.hours, 1.0)
    }

    func testFormatting() {
        XCTAssertEqual(LogTimeFormat.logButton(1.5), "Log 1h 30m")
        XCTAssertEqual(LogTimeFormat.logButton(0), "Log time")
        XCTAssertEqual(LogTimeFormat.loggedToast(hours: 1.5, propertyName: "Pine Cabin"), "Logged 1h 30m at Pine Cabin")
        XCTAssertEqual(LogTimeFormat.clock(4447), "1:14:07")
        XCTAssertEqual(LogTimeFormat.clock(42), "0:42")
        // No dangling middot: the "·" is glued to the next word with a no-break space.
        let eyebrow = LogTimeFormat.eyebrow(Date())
        XCTAssertTrue(eyebrow.hasPrefix("Today \u{00B7}\u{00A0}"), eyebrow)
        XCTAssertFalse(eyebrow.contains("\u{00B7} "), eyebrow)
    }
}

// MARK: - Who

@MainActor
final class LogParticipantRuleTests: XCTestCase {
    private let pine = RentalProperty(name: "Pine Cabin", address: "88 Ridge Rd", propertyType: .str)

    func testWithoutSpouseTrackingEveryEntryIsYourOwn() async {
        var form = LogForm.starting(properties: [pine], entries: [])
        form.note = "My wife fixed the sink at Pine Cabin, 1 hour"
        let parsed = await AITimeEntryService.shared.parseTimeEntry(from: form.note, properties: [pine])!
        XCTAssertEqual(parsed.participant, .spouse)
        form.apply(parsed, source: .note, spouseTracking: false)
        XCTAssertEqual(form.participant, .selfParticipant)
        form.participant = .spouse     // even a stale value is saved as your own
        XCTAssertEqual(form.participantToSave(spouseTracking: false), .selfParticipant)
        XCTAssertFalse(LogParticipantRule.showsPicker(spouseTracking: false))
    }

    func testWithSpouseTrackingTheNoteCanFillSpouse() async {
        var form = LogForm.starting(properties: [pine], entries: [])
        form.note = "My wife fixed the sink at Pine Cabin, 1 hour"
        let parsed = await AITimeEntryService.shared.parseTimeEntry(from: form.note, properties: [pine])!
        let wrote = form.apply(parsed, source: .note, spouseTracking: true)
        XCTAssertTrue(wrote.contains(.participant))
        XCTAssertEqual(form.participantToSave(spouseTracking: true), .spouse)
        XCTAssertTrue(LogParticipantRule.showsPicker(spouseTracking: true))
    }

    func testAHandPickedParticipantWins() async {
        var form = LogForm.starting(properties: [pine], entries: [])
        form.setParticipant(.selfParticipant)
        form.note = "Spouse showed Pine Cabin, 1 hour"
        let parsed = await AITimeEntryService.shared.parseTimeEntry(from: form.note, properties: [pine])!
        form.apply(parsed, source: .note, spouseTracking: true)
        XCTAssertEqual(form.participant, .selfParticipant)
    }
}

// MARK: - Saving (house, REPS, failure)

@MainActor
final class LogTimeSaveTests: CaptureTestCase {
    private var savedSpouse = false
    private var savedGoal: HourGoalType = .reps

    override func setUp() async throws {
        try await super.setUp()
        savedSpouse = TaxProfileManager.shared.spouseTracking
        savedGoal = GoalManager.shared.globalGoalType
        GoalManager.shared.globalGoalType = .reps
    }

    override func tearDown() async throws {
        TaxProfileManager.shared.spouseTracking = savedSpouse
        GoalManager.shared.globalGoalType = savedGoal
        AppViewModel.debugFailNextWrite = false
        TodayHouseEvents.shared.takeConfirm()
        try await super.tearDown()
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    func testNonCountableWorkIsLoggedButNeverFeedsTheHouseOrREPS() {
        let (vm, oak) = makeViewModel()
        for category in LogCategoryGroups.notCounted {
            let houseBefore = vm.houseCountableHours(goal: .reps750)
            let repsBefore = vm.repsStatus(participant: .selfParticipant, year: year).realEstateHours
            let mpBefore = vm.houseCountableHours(goal: .mp500)
            let result = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: category,
                                         hours: 3, date: Date(), notes: "Lender call")
            XCTAssertNotNil(result.entryId, "\(category) can be logged")
            XCTAssertTrue(vm.timeEntries.contains { $0.id == result.entryId }, "kept in the record")
            XCTAssertEqual(vm.houseCountableHours(goal: .reps750), houseBefore, accuracy: 0.001, "\(category) never builds the house")
            XCTAssertEqual(vm.repsStatus(participant: .selfParticipant, year: year).realEstateHours, repsBefore, accuracy: 0.001)
            XCTAssertEqual(vm.houseCountableHours(goal: .mp500), mpBefore, accuracy: 0.001)
        }
        XCTAssertEqual(Set(LogCategoryGroups.notCounted), [.investing, .financing, .contractNegotiation])
        XCTAssertTrue(Set(LogCategoryGroups.counted).isDisjoint(with: LogCategoryGroups.notCounted))
        XCTAssertEqual(Set(LogCategoryGroups.counted + LogCategoryGroups.notCounted), Set(ActivityCategory.allCases))
    }

    func testCountableWorkBuildsTheHouse() {
        let (vm, oak) = makeViewModel()
        let before = vm.houseCountableHours(goal: .reps750)
        _ = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 1.5, date: Date(), notes: "")
        XCTAssertEqual(vm.houseCountableHours(goal: .reps750), before + 1.5, accuracy: 0.001)
    }

    func testSpouseEntryNeverFillsYourREPS() {
        let (vm, oak) = makeViewModel()
        TaxProfileManager.shared.spouseTracking = true
        let before = vm.houseCountableHours(goal: .reps750)
        _ = vm.logTimeEntry(propertyId: oak, participant: .spouse, category: .repairs, hours: 2, date: Date(), notes: "")
        XCTAssertEqual(vm.houseCountableHours(goal: .reps750), before, accuracy: 0.001)
    }

    func testAFailedWriteIsSurfacedAndNothingIsHalfSaved() {
        let (vm, oak) = makeViewModel()
        let count = vm.timeEntries.count
        AppViewModel.debugFailNextWrite = true
        let result = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs,
                                     hours: 1, date: Date(), notes: "Sink")
        XCTAssertEqual(result, .failed(LogSaveResult.writeFailedMessage))
        XCTAssertEqual(vm.timeEntries.count, count, "the entry was taken back out")
        XCTAssertNotNil(vm.persistenceError)
        // The next try works.
        let retry = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs,
                                    hours: 1, date: Date(), notes: "Sink")
        XCTAssertNotNil(retry.entryId)
        XCTAssertNil(vm.persistenceError)
    }

    func testMissingPropertyOrHoursIsRefused() {
        let (vm, oak) = makeViewModel()
        XCTAssertEqual(vm.logTimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 1, date: Date(), notes: ""),
                       .failed(LogSaveResult.missingPropertyMessage))
        XCTAssertEqual(vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 0, date: Date(), notes: ""),
                       .failed(LogSaveResult.missingHoursMessage))
    }

    func testVoiceAndTimerSourcesAreRecorded() {
        let (vm, oak) = makeViewModel()
        let voice = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 1, date: Date(), notes: "", source: .voice)
        let timer = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 1, date: Date(), notes: "", source: .timer)
        XCTAssertEqual(vm.timeEntries.first { $0.id == voice.entryId }?.source, .voice)
        XCTAssertEqual(vm.timeEntries.first { $0.id == timer.entryId }?.source, .timer)
        XCTAssertEqual(RecordSourceBadge.voice.title, EntrySource.voice.displayName, "one source vocabulary")
        XCTAssertEqual(RecordSourceBadge.calendarImport.title, EntrySource.calendar.displayName)
    }
}

// MARK: - Timer

@MainActor
final class LogTimerTests: CaptureTestCase {
    override func tearDown() async throws {
        StoppedTimerDraftStore.clear()
        try await super.tearDown()
    }

    func testStartStopToReviewKeepsTheDraftUntilLogged() {
        let (vm, oak) = makeViewModel()
        vm.startTimer(propertyId: oak, category: .repairs)
        XCTAssertTrue(vm.isTimerRunning)
        let start = vm.timerStartTime!
        // Stop: the draft is stored before the running timer ends.
        let draft = StoppedTimerDraft(elapsed: 4447, propertyId: oak, category: .repairs, startDate: start, participant: .selfParticipant, notes: "")
        StoppedTimerDraftStore.save(draft)
        vm.cancelTimer()
        XCTAssertFalse(vm.isTimerRunning)
        XCTAssertEqual(StoppedTimerDraftStore.load(), draft, "survives closing the sheet")
        XCTAssertEqual(draft.reviewHours, 1.25, accuracy: 0.0001, "1:14:07 → 1h 15m")
        XCTAssertEqual(TimerReviewMath.ranCaption(elapsed: 4447), "Timer ran 1h 14m")

        let result = vm.logTimeEntry(propertyId: oak, participant: .selfParticipant, category: draft.category,
                                     hours: draft.reviewHours, date: draft.startDate, notes: "Sink", source: .timer)
        XCTAssertNotNil(result.entryId)
        StoppedTimerDraftStore.clear()
        XCTAssertNil(StoppedTimerDraftStore.load())
        XCTAssertEqual(vm.timeEntries.last?.date, start, "the entry is dated when the timer started")
    }

    func testDiscardThenUndoRestoresTheSameRunningTimer() {
        let (vm, oak) = makeViewModel()
        vm.startTimer(propertyId: oak, category: .leasing)
        let start = vm.timerStartTime!
        vm.cancelTimer()
        XCTAssertFalse(vm.isTimerRunning)
        XCTAssertEqual(vm.timeEntries.count, 0, "discard saves nothing")
        vm.restoreTimer(propertyId: oak, category: .leasing, startTime: start)
        XCTAssertTrue(vm.isTimerRunning)
        XCTAssertEqual(vm.timerStartTime, start, "Undo keeps the original start")
        XCTAssertEqual(vm.timerCategory, .leasing)
        vm.cancelTimer()
    }

    func testReviewHoursRules() {
        XCTAssertEqual(TimerReviewMath.reviewHours(elapsed: 30), 0, "under a minute isn't logged")
        XCTAssertEqual(TimerReviewMath.reviewHours(elapsed: 90), 5.0 / 60, accuracy: 0.0001, "at least 5 minutes once it ran a minute")
        XCTAssertEqual(TimerReviewMath.reviewHours(elapsed: 3600 + 12 * 60), 70.0 / 60, accuracy: 0.0001, "1h 12m → 1h 10m")
        XCTAssertEqual(TimerReviewMath.reviewHours(elapsed: 30 * 3600), 24, "capped at a day")
        XCTAssertTrue(TimerReviewMath.wasCapped(elapsed: 30 * 3600))
        XCTAssertEqual(TimerReviewMath.ranCaption(elapsed: 20), "Timer ran under a minute")
    }

    func testDraftReadsTheOneXKey() {
        let (_, oak) = makeViewModel()
        // 1.x wrote the same shape under the same key: it still loads.
        let json = """
        {"elapsed":5400,"propertyId":"\(oak.uuidString)","category":"Repairs & Maintenance","startDate":0,"participant":"Self","notes":"old"}
        """
        UserDefaults.standard.set(Data(json.utf8), forKey: StoppedTimerDraftStore.key)
        XCTAssertEqual(StoppedTimerDraftStore.load()?.notes, "old")
        XCTAssertEqual(StoppedTimerDraftStore.load()?.reviewHours, 1.5)
    }
}
