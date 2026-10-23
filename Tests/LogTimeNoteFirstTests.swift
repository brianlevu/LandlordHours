import XCTest
@testable import LandlordHours

// MARK: - Log time 2.1 (note-first): provenance, the default hours, "updated after you saw it",
// recents, the button's words, the first-rental save, and the reader's gate, cancel and cap.

private let pine = RentalProperty(name: "Pine Cabin", address: "88 Ridge Rd", propertyType: .str)
private let oak = RentalProperty(name: "Oak Street Duplex", address: "214 Oak St", propertyType: .ltr, aliases: ["Oak St"])
private let maple = RentalProperty(name: "Maple Court", address: "12 Maple Ct", propertyType: .ltr)

private func rules(_ text: String, _ properties: [RentalProperty] = [pine, oak, maple]) -> NoteReading {
    NoteRules.read(NoteReadRequest(text: text, properties: properties, spouseTracking: false))
}

private func entry(_ property: RentalProperty, _ category: ActivityCategory = .repairs, hours: Double = 1, daysAgo: Int = 0) -> TimeEntry {
    TimeEntry(propertyId: property.id, participant: .selfParticipant, category: category, hours: hours,
              date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(), notes: "")
}

final class LogFormProvenanceTests: XCTestCase {
    func testHoursStartAsADefaultAndAFillOrAHandEditClearsIt() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        XCTAssertTrue(form.hoursIsDefault)
        form.apply(rules("fixed the sink at Pine Cabin, 1 hour"), source: .note, spouseTracking: false)
        XCTAssertFalse(form.hoursIsDefault, "the note said 1 hour, so it is a fact, not a default")
        XCTAssertTrue(form.filled.contains(.hours))
        form.undoFill()
        XCTAssertTrue(form.hoursIsDefault, "Undo puts the default back")
        form.setHours(2)
        XCTAssertFalse(form.hoursIsDefault)
    }

    func testANoteThatNeverSaysHowLongKeepsTheDefault() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        form.apply(rules("met the plumber at Oak St"), source: .note, spouseTracking: false)
        XCTAssertTrue(form.hoursIsDefault)
        XCTAssertEqual(form.hours, 1)
    }

    func testProvenanceMatrix() {
        let remembered = entry(pine, .bookkeeping)
        var form = LogForm.starting(properties: [pine, oak], entries: [remembered])
        XCTAssertEqual(form.provenance(.category), .remembered)
        XCTAssertEqual(form.provenance(.hours), .defaultValue)
        XCTAssertEqual(form.provenance(.property), .defaultValue)
        let r = rules("fixed the sink at Oak St, 2 hours")
        form.apply(r, source: .note, spouseTracking: false)
        XCTAssertEqual(form.provenance(.property), .rules)
        XCTAssertEqual(form.provenance(.hours), .rules)
        var answer = r
        answer.category = .repairs
        answer.description = "Fixed the sink"
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, rulesBaseline: r)
        XCTAssertEqual(form.provenance(.description), .model)
        XCTAssertEqual(form.provenance(.property), .rules, "the model only agreed with the rules")
        form.setProperty(maple.id)
        XCTAssertEqual(form.provenance(.property), .user)
    }

    func testAFillNeverOverwritesAUserValueAndTheModelMayOverwriteTheRules() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        let r = rules("fixed the sink at Oak St, 2 hours")
        form.apply(r, source: .note, spouseTracking: false)
        XCTAssertEqual(form.propertyId, oak.id)
        var answer = r
        answer.propertyId = pine.id
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, rulesBaseline: r)
        XCTAssertEqual(form.propertyId, pine.id, "the model replaced the rules' value")
        form.setProperty(oak.id)
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, rulesBaseline: r)
        XCTAssertEqual(form.propertyId, oak.id, "never the user's")
        form.setHours(3)
        form.apply(rules("fixed the sink at Oak St, 5 hours"), source: .note, spouseTracking: false)
        XCTAssertEqual(form.hours, 3)
    }

    func testRulesThenModelIsOneUndo() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        let start = form
        let r = rules("fixed the sink at Pine Cabin, about 2 hours yesterday")
        form.apply(r, source: .note, spouseTracking: false)
        var answer = r
        answer.category = .repairs
        answer.description = "Fixed the sink at Pine Cabin"
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, rulesBaseline: r)
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, rulesBaseline: r)
        form.undoFill()
        XCTAssertEqual(form.propertyId, start.propertyId)
        XCTAssertEqual(form.category, start.category)
        XCTAssertEqual(form.hours, start.hours)
        XCTAssertTrue(Calendar.current.isDate(form.date, inSameDayAs: start.date))
        XCTAssertNil(form.recordDescription)
        XCTAssertTrue(form.hoursIsDefault)
        XCTAssertNil(form.fillSource)
    }

    func testANoteThatNamesNoKindTakesOffTheRememberedKindAndUndoPutsItBack() {
        var form = LogForm.starting(properties: [pine, oak], entries: [entry(pine, .bookkeeping)])
        XCTAssertEqual(form.category, .bookkeeping)
        form.apply(rules("walked Oak St with Mike"), source: .note, spouseTracking: false)
        XCTAssertEqual(form.propertyId, oak.id)
        XCTAssertNil(form.category, "never log a kind of work the note did not say")
        XCTAssertEqual(form.gap(properties: [pine, oak]), .kind)
        form.undoFill()
        XCTAssertEqual(form.category, .bookkeeping)
        XCTAssertTrue(form.categoryIsRemembered)
    }

    func testAKindTheUserPickedSurvivesANoteThatSaysNothingAboutIt() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        form.setCategory(.legal)
        form.apply(rules("walked Oak St with Mike"), source: .note, spouseTracking: false)
        XCTAssertEqual(form.category, .legal)
    }
}

final class LogUpdatedAfterSeenTests: XCTestCase {
    private func filledByRules() -> (LogForm, NoteReading) {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        let r = rules("replaced the water heater at Oak St, 3 hours")
        form.apply(r, source: .note, spouseTracking: false)
        return (form, r)
    }

    func testALateModelChangeIsKeptForTheRowsOwnUndo() throws {
        var (form, r) = filledByRules()
        let first = try XCTUnwrap(form.category)
        var answer = r
        answer.category = first == .renovations ? .repairs : .renovations
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, late: true, rulesBaseline: r)
        XCTAssertNotEqual(form.category, first)
        XCTAssertEqual(form.updatedAfterSeen[.category], .category(first))
        form.undoUpdate(.category)
        XCTAssertEqual(form.category, first)
        XCTAssertEqual(form.provenance(.category), .user, "a value put back by hand is the user's")
        XCTAssertNil(form.updatedAfterSeen[.category])
        // And a later fill never touches it.
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, late: true, rulesBaseline: r)
        XCTAssertEqual(form.category, first)
    }

    func testAnEarlyModelChangeIsNotFlagged() throws {
        var (form, r) = filledByRules()
        var answer = r
        answer.category = form.category == .renovations ? .repairs : .renovations
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, late: false, rulesBaseline: r)
        XCTAssertTrue(form.updatedAfterSeen.isEmpty)
    }

    func testAHandEditClearsTheUpdateNote() throws {
        var (form, r) = filledByRules()
        var answer = r
        answer.category = form.category == .renovations ? .repairs : .renovations
        form.apply(answer, source: .note, spouseTracking: false, tier: .model, late: true, rulesBaseline: r)
        form.setCategory(.legal)
        XCTAssertTrue(form.updatedAfterSeen.isEmpty)
    }
}

final class LogButtonWordsTests: XCTestCase {
    func testTheButtonNamesTheFirstGapInOrder() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        func title() -> String { LogTimeFormat.buttonTitle(form: form, properties: [pine, oak]) }
        XCTAssertEqual(title(), "Pick a rental")
        form.setProperty(pine.id)
        XCTAssertEqual(title(), "Pick the kind of work")
        form.setCategory(.repairs)
        form.setHours(0)
        XCTAssertEqual(title(), "Add how long it took")
        form.setHours(1.5)
        XCTAssertEqual(title().replacingOccurrences(of: "\u{00A0}", with: " "), "Log 1h 30m at Pine Cabin")
    }

    func testAPastDayRidesOnTheButton() {
        var form = LogForm.starting(properties: [pine], entries: [entry(pine)])
        form.setDate(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let text = LogTimeFormat.buttonTitle(form: form, properties: [pine]).replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertEqual(text, "Log 1h at Pine Cabin · Yesterday")
        let ax = LogTimeFormat.buttonTitle(form: form, properties: [pine], ax: true).replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertEqual(ax, "Log 1h at Pine Cabin Yesterday")
    }

    func testFirstRunNamesBothThings() {
        var form = LogForm.starting(properties: [], entries: [])
        form.setCategory(.repairs)
        XCTAssertEqual(LogTimeFormat.buttonTitle(form: form, properties: [], firstRunName: "  "), "Name your rental")
        let text = LogTimeFormat.buttonTitle(form: form, properties: [], firstRunName: "Pine Cabin").replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertEqual(text, "Add Pine Cabin and log 1h")
    }

    func testTheEyebrowFollowsTheEntrysDate() {
        let past = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        XCTAssertFalse(LogTimeFormat.eyebrow(past).hasPrefix("Today"))
        XCTAssertTrue(LogTimeFormat.eyebrow(Date()).hasPrefix("Today"))
        XCTAssertEqual(LogTimeFormat.dayWord(Date()), "Today")
    }
}

final class LogRecentsTests: XCTestCase {
    func testLastThreeDistinctNewestFirst() {
        let entries = [entry(pine, .repairs, hours: 1, daysAgo: 5), entry(pine, .repairs, hours: 1, daysAgo: 3),
                       entry(oak, .leasing, hours: 0.5, daysAgo: 2), entry(maple, .legal, hours: 2, daysAgo: 1),
                       entry(oak, .management, hours: 1, daysAgo: 0)]
        let recents = LogRecents.derive(entries: entries, properties: [pine, oak, maple])
        XCTAssertEqual(recents.count, 3)
        XCTAssertEqual(recents.map(\.category), [.management, .legal, .leasing])
        XCTAssertEqual(LogRecents.title(recents[2], properties: [pine, oak, maple]), "Leasing · Oak Street Duplex · 30m")
    }

    func testHiddenUntilTwoEntriesAndSkipsDeletedRentals() {
        XCTAssertTrue(LogRecents.derive(entries: [entry(pine)], properties: [pine]).isEmpty)
        let two = [entry(pine), entry(oak, .leasing)]
        XCTAssertEqual(LogRecents.derive(entries: two, properties: [pine]).count, 1)
        XCTAssertEqual(LogRecents.derive(entries: [entry(pine), entry(pine)], properties: [pine]).count, 1, "duplicates collapse")
    }

    func testARecentFillsThreeFieldsAsTheUsersOwn() {
        var form = LogForm.starting(properties: [pine, oak], entries: [])
        form.applyRecent(LogRecent(propertyId: oak.id, category: .leasing, hours: 0.5))
        XCTAssertEqual(form.propertyId, oak.id)
        XCTAssertEqual(form.category, .leasing)
        XCTAssertEqual(form.hours, 0.5)
        XCTAssertEqual(form.provenance(.property), .user)
        XCTAssertFalse(form.hoursIsDefault)
        XCTAssertNil(form.fillSource, "no caption, no mark: these are yours")
    }
}

@MainActor
final class LogFirstEntryTests: XCTestCase {
    override func tearDown() async throws {
        AppViewModel.debugFailNextWrite = false
        try await super.tearDown()
    }

    private func emptyViewModel() -> AppViewModel {
        let vm = AppViewModel()
        vm.suppressCelebrations = true
        vm.properties = []
        vm.timeEntries = []
        return vm
    }

    func testTheRentalAndTheEntryLandTogether() {
        let vm = emptyViewModel()
        var events: [String] = []
        Analytics.testSpy = { name, _ in events.append(name) }
        defer { Analytics.testSpy = nil }
        let result = vm.logFirstEntry(propertyName: "  Pine Cabin ", participant: .selfParticipant, category: .repairs,
                                      hours: 1, date: Date(), notes: "fixed the sink")
        let id = try! XCTUnwrap(result.entryId)
        XCTAssertEqual(vm.properties.map(\.name), ["Pine Cabin"])
        XCTAssertEqual(vm.properties.first?.propertyType, .ltr)
        XCTAssertEqual(vm.properties.first?.address, "")
        XCTAssertEqual(vm.timeEntries.first?.id, id)
        XCTAssertEqual(vm.timeEntries.first?.propertyId, vm.properties.first?.id)
        XCTAssertTrue(events.contains("property_added"))
    }

    func testAFailedWriteLeavesNeitherBehind() {
        let vm = emptyViewModel()
        AppViewModel.debugFailNextWrite = true
        let result = vm.logFirstEntry(propertyName: "Pine Cabin", participant: .selfParticipant, category: .repairs,
                                      hours: 1, date: Date(), notes: "")
        XCTAssertEqual(result, .failed(LogSaveResult.writeFailedMessage))
        XCTAssertTrue(vm.properties.isEmpty, "the rental was taken back out")
        XCTAssertTrue(vm.timeEntries.isEmpty)
    }

    func testAnEmptyNameIsRefusedAndTheFreeLimitIsChecked() {
        let vm = emptyViewModel()
        XCTAssertEqual(vm.logFirstEntry(propertyName: "   ", participant: .selfParticipant, category: .repairs,
                                        hours: 1, date: Date(), notes: ""), .failed(LogSaveResult.missingNameMessage))
        XCTAssertFalse(FirstPropertyDraft(name: " ").isValid)
        XCTAssertEqual(FirstPropertyDraft(name: " Pine Cabin ").makeProperty().name, "Pine Cabin")
        // One rental already and not Pro: a second can't slip in through this path.
        if !SubscriptionManager.shared.isPro {
            vm.properties = [pine]
            XCTAssertEqual(vm.logFirstEntry(propertyName: "Oak", participant: .selfParticipant, category: .repairs,
                                            hours: 1, date: Date(), notes: ""), .failed(LogSaveResult.missingPropertyMessage))
            XCTAssertEqual(vm.properties.count, 1)
        }
    }
}

final class NoteReaderGateCancelCapTests: XCTestCase {
    private func defaults(_ on: Bool) -> NoteReadingSettings {
        let suite = UserDefaults(suiteName: "lh.test.notereading.\(UUID().uuidString)")!
        suite.set(on, forKey: NoteReadingSettings.enabledKey)
        return NoteReadingSettings(defaults: suite)
    }

    private let closedPCC = PCCGate(settings: PCCSettings(), isFlagEnabled: { false }, system: NoteReaderDebug.ScriptedPCCStatus())
    private let noPCC = UnavailableNoteBackend(tier: .pcc, reason: .disabledByFlag)
    private func request(_ text: String = "fixed the sink at Oak St, 2 hours") -> NoteReadRequest {
        NoteReadRequest(text: text, properties: [pine, oak, maple], spouseTracking: false)
    }

    func testTheSwitchOffClosesBothModelsButTheRulesStillRead() async {
        let chain = NoteReaderChain(onDevice: NoteReaderDebug.ScriptedNoteBackend(delay: 0, partial: false), pcc: noPCC,
                                    pccGate: closedPCC, cache: NoteReadCache(), settings: defaults(false))
        XCTAssertFalse(chain.hasModel)
        XCTAssertEqual(chain.onDeviceAvailability(), .unavailable(.disabledByUser))
        XCTAssertEqual(chain.pccAvailability(), .unavailable(.disabledByUser))
        let outcome = await chain.read(request())
        XCTAssertEqual(outcome.onDevice, .unavailable(.disabledByUser))
        XCTAssertEqual(outcome.reading, NoteRules.read(request()), "the rules are the answer")
        XCTAssertEqual(outcome.reading.propertyId, oak.id)
    }

    func testTheSwitchOnLetsTheModelAnswer() async {
        let chain = NoteReaderChain(onDevice: NoteReaderDebug.ScriptedNoteBackend(delay: 0, partial: false), pcc: noPCC,
                                    pccGate: closedPCC, cache: NoteReadCache(), settings: defaults(true))
        XCTAssertTrue(chain.hasModel)
        let outcome = await chain.read(request())
        XCTAssertEqual(outcome.onDevice, .answered)
        XCTAssertNotNil(outcome.reading.description)
    }

    func testCancellingTheReadReturnsAtOnceWithTheRules() async {
        let chain = NoteReaderChain(onDevice: NoteReaderDebug.ScriptedNoteBackend(delay: 3600, partial: false), pcc: noPCC,
                                    pccGate: closedPCC, onDeviceTimeout: 3600, cache: NoteReadCache(), settings: defaults(true))
        let started = Date()
        let task = Task { await chain.read(request()) }
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let outcome = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "Log never waits on the model")
        XCTAssertEqual(outcome.reading.propertyId, oak.id)
        XCTAssertNil(outcome.reading.description)
    }

    func testOneReadNeverRunsPastTheOverallCap() async {
        let chain = NoteReaderChain(onDevice: NoteReaderDebug.ScriptedNoteBackend(delay: 3600, partial: false), pcc: noPCC,
                                    pccGate: closedPCC, onDeviceTimeout: 3600, cache: NoteReadCache(), settings: defaults(true),
                                    overallCap: 0.3)
        let started = Date()
        let outcome = await chain.read(request())
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertTrue(outcome.onDevice == .capped || outcome.onDevice == .cancelled || outcome.onDevice == .timedOut, "\(outcome.onDevice)")
        XCTAssertEqual(outcome.reading.propertyId, oak.id)
    }
}

final class LogAnalyticsTests: XCTestCase {
    func testEventsCarryCountsAndEnumsNeverText() {
        var seen: [(String, [String: Any])] = []
        Analytics.testSpy = { seen.append(($0, $1)) }
        defer { Analytics.testSpy = nil }
        Analytics.logOpened(mode: "log", hasRentals: true, recentsShown: false)
        Analytics.noteFilled(tier: .model, fields: 3, voice: false)
        Analytics.fieldEdited(field: .hours)
        Analytics.readFailed(reason: .timedOut)
        Analytics.fillUndone(); Analytics.recentUsed(); Analytics.manualPathOpened()
        Analytics.propertyCreatedInline(); Analytics.logTappedWhileReading(); Analytics.fillUpdatedAfterSeen(fields: 1)
        XCTAssertEqual(seen.map(\.0), ["log_opened", "note_filled", "field_edited", "read_failed", "fill_undone", "recent_used",
                                       "manual_path_opened", "property_created_inline", "log_tapped_while_reading", "fill_updated_after_seen"])
        for (_, properties) in seen {
            for value in properties.values { XCTAssertFalse(value is String && (value as! String).contains(" "), "free text in \(properties)") }
        }
    }
}
