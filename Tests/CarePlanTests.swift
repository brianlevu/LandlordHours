import XCTest
@testable import LandlordHours

// MARK: - Care plan A (2.3, package B): the catalog, the plan, the done log, the hour chips, the
// Log time prefill and the due source for package D. Tests read keys and ids, never English
// wording (standard C.1a), except where a chip's number is the point.

@MainActor
final class CarePlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private let pine = RentalProperty(name: "Pine Cabin", address: "12 Pine Rd, Portland, OR 97201", propertyType: .ltr)
    private let lakeside = RentalProperty(name: "Lakeside A-Frame", address: "3 Shore Rd, Lake Placid, NY", propertyType: .str)
    private var oct31: Date { date(2026, 10, 31) }

    private func entry(_ rental: RentalProperty, _ hours: Double, _ day: Date) -> TimeEntry {
        TimeEntry(propertyId: rental.id, participant: .selfParticipant, category: .repairs, hours: hours, date: day, notes: "")
    }

    private func ids(_ section: CarePlanSection?) -> [String] { section?.items.map(\.id) ?? [] }

    // MARK: Climate and season

    func testClimateComesFromTheStateInTheAddress() {
        XCTAssertEqual(CareClimate.from(address: "12 Pine Rd, Portland, OR 97201"), .wet)
        XCTAssertEqual(CareClimate.from(address: "3 Shore Rd, Lake Placid, NY"), .snowy)
        XCTAssertEqual(CareClimate.from(address: "1 Main St, Phoenix, Arizona"), .hotDry)
        XCTAssertEqual(CareClimate.from(address: "9 Bay Dr, Tampa, FL"), .humid)
        XCTAssertEqual(CareClimate.from(address: "5 Elm St, Charleston, West Virginia"), .snowy, "west virginia, not virginia")
    }

    func testAnAddressWithoutAStateGetsTheGeneralPlan() {
        XCTAssertEqual(CareClimate.from(address: "12 Pine Rd"), .general)
        XCTAssertEqual(CareClimate.from(address: ""), .general)
        XCTAssertEqual(CareClimate.from(address: "88 Ridge Rd, Big Bear"), .general)
        XCTAssertEqual(CareClimate.from(address: "12 Oregon St"), .general, "the street is never read as a state")
        XCTAssertEqual(CareClimate.from(address: "14 OR Lane, Springfield"), .general, "a code in the street part is ignored")
    }

    func testSeasonsByMonthAndWhenTheyStart() {
        XCTAssertEqual(CareSeason.of(date(2026, 10, 31), calendar: calendar), .fall)
        XCTAssertEqual(CareSeason.of(date(2026, 12, 1), calendar: calendar), .winter)
        XCTAssertEqual(CareSeason.of(date(2027, 2, 28), calendar: calendar), .winter)
        XCTAssertEqual(CareSeason.of(date(2026, 3, 1), calendar: calendar), .spring)
        XCTAssertEqual(CareSeason.of(date(2026, 7, 4), calendar: calendar), .summer)
        XCTAssertEqual(CareSeason.start(of: date(2026, 10, 31), calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        XCTAssertEqual(CareSeason.start(of: date(2027, 1, 15), calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)),
                       "January's winter began the December before")
    }

    // MARK: The plan

    func testLongStaysWithWetWintersMatchTheApprovedFrame() {
        let plan = CarePlan.make(rental: pine, logs: [], now: oct31, calendar: calendar)
        XCTAssertEqual(plan.climate, .wet)
        XCTAssertEqual(plan.sections.map(\.kind), [.thisSeason(.fall), .later(.winter), .later(.spring)])
        XCTAssertEqual(ids(plan.sections.first), ["gutters", "outdoorTaps", "alarms", "furnaceFilter"])
        XCTAssertEqual(ids(plan.sections[1]), ["sinkLeaks", "waterHeater", "atticDamp"])
        XCTAssertEqual(ids(plan.sections[2]), ["dryerVent", "reseal"])
        XCTAssertEqual(plan.todayItems.map(\.id), ["gutters", "outdoorTaps", "alarms"])
    }

    func testShortStaysWithSnowyWintersAddBetweenStays() {
        let plan = CarePlan.make(rental: lakeside, logs: [], now: oct31, calendar: calendar)
        XCTAssertEqual(plan.climate, .snowy)
        XCTAssertEqual(plan.sections.first?.kind, .thisSeason(.fall))
        XCTAssertEqual(ids(plan.sections.first), ["iceMelt", "hotTub", "alarms", "heatTape"])
        XCTAssertEqual(plan.sections[1].kind, .betweenStays)
        XCTAssertEqual(ids(plan.sections[1]), ["walkThrough", "firstAid"])
        XCTAssertEqual(ids(plan.sections[2]), ["roofSnow", "furnaceService"])
    }

    func testTypeAndClimateChangeTheItems() {
        let longSnowy = RentalProperty(name: "A", address: "1 A St, Denver, CO", propertyType: .ltr)
        let plan = CarePlan.make(rental: longSnowy, logs: [], now: oct31, calendar: calendar)
        let all = plan.sections.flatMap { $0.items.map(\.id) }
        XCTAssertFalse(all.contains("hotTub"), "the hot tub is a short-stay item")
        XCTAssertFalse(all.contains("walkThrough"), "no Between stays for long stays")
        XCTAssertFalse(all.contains("gutters"), "snowy places get ice melt, not the wet-winter gutters")
        let generalShort = RentalProperty(name: "B", address: "", propertyType: .str)
        let general = CarePlan.make(rental: generalShort, logs: [], now: oct31, calendar: calendar)
        XCTAssertEqual(general.climate, .general)
        XCTAssertTrue(general.sections.contains { $0.kind == .betweenStays })
        XCTAssertFalse(general.sections.flatMap(\.items).isEmpty)
    }

    func testEveryClimateAndTypeHasSomethingThisSeasonAllYear() {
        for climate in CareClimate.allCases {
            for type in PropertyType.allCases {
                for month in 1...12 {
                    let rental = RentalProperty(name: "R", address: "", propertyType: type)
                    let plan = CarePlan.make(rental: rental, logs: [], now: date(2026, month, 15), calendar: calendar, climate: climate)
                    XCTAssertGreaterThanOrEqual(plan.todayItems.count, 1, "\(climate) \(type) month \(month)")
                }
            }
        }
    }

    func testOnlyCadenceItemsSayDueNowAndOnlyThisSeason() {
        let plan = CarePlan.make(rental: pine, logs: [], now: oct31, calendar: calendar)
        let alarms = plan.sections[0].items.first { $0.id == "alarms" }
        let gutters = plan.sections[0].items.first { $0.id == "gutters" }
        let heater = plan.sections[1].items.first { $0.id == "waterHeater" }
        XCTAssertEqual(alarms?.meta, CareText.dueNow(CareText.when("alarms", type: .ltr)))
        XCTAssertEqual(gutters?.meta, CareText.when("gutters", type: .ltr))
        XCTAssertEqual(heater?.meta, CareText.when("waterHeater", type: .ltr), "a later season is never due now")
    }

    func testShortStaysTimeTheAlarmsBetweenStays() {
        XCTAssertNotEqual(CareText.when("alarms", type: .str), CareText.when("alarms", type: .ltr))
        XCTAssertEqual(CareText.when("gutters", type: .str), CareText.when("gutters", type: .ltr))
    }

    // MARK: Done

    func testALogThisSeasonMarksTheItemDoneAndMovesItLast() {
        let e = entry(pine, 1, date(2026, 10, 4))
        let logs = CareDoneLog.logs(records: [CareRecord(taskID: "gutters", entryID: e.id)], entries: [e])
        let plan = CarePlan.make(rental: pine, logs: logs, now: oct31, calendar: calendar)
        XCTAssertEqual(ids(plan.sections.first), ["outdoorTaps", "alarms", "furnaceFilter", "gutters"])
        let done = plan.sections[0].items.last
        XCTAssertTrue(done?.isDone ?? false)
        XCTAssertEqual(done?.meta, CareText.logged(hours: 1, on: date(2026, 10, 4), calendar: calendar))
        XCTAssertEqual(plan.todayItems.map(\.id), ["outdoorTaps", "alarms", "furnaceFilter"], "Today shows what's next")
        XCTAssertFalse(plan.dueNow.contains { $0.id == "gutters" })
    }

    func testALogBeforeTheSeasonOrAtAnotherRentalIsNotDone() {
        let lastYear = entry(pine, 1, date(2025, 10, 4))
        let summer = entry(pine, 1, date(2026, 8, 20))
        let elsewhere = entry(lakeside, 1, date(2026, 10, 4))
        let records = [lastYear, summer, elsewhere].map { CareRecord(taskID: "gutters", entryID: $0.id) }
        let logs = CareDoneLog.logs(records: records, entries: [lastYear, summer, elsewhere])
        let plan = CarePlan.make(rental: pine, logs: logs, now: oct31, calendar: calendar)
        XCTAssertFalse(plan.sections[0].items.first { $0.id == "gutters" }?.isDone ?? true)
    }

    func testAllDoneStillShowsThreeOnToday() {
        let tasks = ["gutters", "outdoorTaps", "alarms", "furnaceFilter"]
        let entries = tasks.map { _ in entry(pine, 1, date(2026, 10, 10)) }
        let records = zip(tasks, entries).map { CareRecord(taskID: $0, entryID: $1.id) }
        let plan = CarePlan.make(rental: pine, logs: CareDoneLog.logs(records: records, entries: entries), now: oct31, calendar: calendar)
        XCTAssertEqual(plan.todayItems.count, 3)
        XCTAssertTrue(plan.todayItems.allSatisfy(\.isDone))
        XCTAssertTrue(plan.dueNow.isEmpty)
    }

    func testTheDoneLineReadsTheLiveEntry() {
        var e = entry(pine, 1, date(2026, 10, 4))
        let record = CareRecord(taskID: "gutters", entryID: e.id)
        e.hours = 1.5
        let logs = CareDoneLog.logs(records: [record], entries: [e])
        XCTAssertEqual(logs.first?.hours, 1.5, "an edited entry shows its new hours")
        XCTAssertTrue(CareDoneLog.logs(records: [record], entries: []).isEmpty, "a deleted entry drops out")
    }

    func testTheStoreRecordsPerKeyAndIgnoresUnknownTasksAndRepeats() {
        let defaults = UserDefaults(suiteName: "CarePlanTests-\(UUID().uuidString)")!
        var profile = "a"
        let log = CareDoneLog(defaults: defaults, key: { "careDone.v1.\(profile)" })
        let id = UUID()
        log.record(task: "gutters", entry: id)
        log.record(task: "gutters", entry: id)
        log.record(task: "notATask", entry: UUID())
        XCTAssertEqual(log.records, [CareRecord(taskID: "gutters", entryID: id)])
        XCTAssertEqual(CareDoneLog(defaults: defaults, key: { "careDone.v1.a" }).records.count, 1, "persists")
        profile = "b"
        XCTAssertTrue(log.logs(entries: []).isEmpty)
        XCTAssertTrue(log.records.isEmpty, "another profile has its own records")
    }

    // MARK: Chips

    func testWithNoHistoryOnlyTheFixedShortOptions() {
        let chips = CareHourChips.chips(history: [])
        XCTAssertEqual(chips.map(\.kind), [.fixed, .fixed, .fixed])
        XCTAssertEqual(chips.map(\.hours), CareHourChips.fixed)
    }

    func testLastTimeIsTheOwnLatestLogToTheMinute() {
        let a = entry(pine, 4.0 / 3.0, date(2025, 10, 4)), b = entry(pine, 2, date(2024, 10, 4))
        let logs = CareDoneLog.logs(records: [a, b].map { CareRecord(taskID: "gutters", entryID: $0.id) }, entries: [a, b])
        let chips = CareHourChips.chips(history: CareDoneLog.history(task: "gutters", rental: pine.id, in: logs))
        XCTAssertEqual(chips.first?.kind, .lastTime)
        XCTAssertEqual(chips.first?.hours ?? 0, 80.0 / 60.0, accuracy: 0.0001, "1h 20m, not snapped to a quarter hour")
        XCTAssertEqual(chips.first?.title, CareText.lastTime(LHFormat.hours(4.0 / 3.0)))
        let typical = chips.first { $0.kind == .typical }
        XCTAssertNotNil(typical)
        XCTAssertEqual(typical?.title, CareText.typical(CareHourChips.range(4.0 / 3.0, 2)))
        XCTAssertEqual(typical?.hours ?? 0, (4.0 / 3.0 + 2) / 2, accuracy: 0.02, "the middle of the person's own logs")
    }

    func testTypicalNeedsTwoDifferentLogsAndChipsNeverRepeatAValue() {
        let a = entry(pine, 1, date(2025, 10, 4)), b = entry(pine, 1, date(2024, 10, 4))
        let logs = CareDoneLog.logs(records: [a, b].map { CareRecord(taskID: "gutters", entryID: $0.id) }, entries: [a, b])
        let chips = CareHourChips.chips(history: CareDoneLog.history(task: "gutters", rental: pine.id, in: logs))
        XCTAssertFalse(chips.contains { $0.kind == .typical }, "1h and 1h is no range")
        XCTAssertEqual(chips.filter { $0.hours == 1 }.count, 1, "the fixed 1h is dropped when Last time is 1h")
        XCTAssertEqual(Set(chips.map(\.id)).count, chips.count)
        XCTAssertLessThanOrEqual(chips.count, CareHourChips.maxChips)
    }

    func testThisRentalsLastTimeComesFirst() {
        let here = entry(pine, 1, date(2025, 10, 4)), there = entry(lakeside, 3, date(2026, 10, 1))
        let logs = CareDoneLog.logs(records: [here, there].map { CareRecord(taskID: "alarms", entryID: $0.id) }, entries: [here, there])
        XCTAssertEqual(CareDoneLog.history(task: "alarms", rental: pine.id, in: logs).first?.entryID, here.id)
        XCTAssertEqual(CareDoneLog.history(task: "alarms", rental: nil, in: logs).first?.entryID, there.id)
    }

    func testRangeWording() {
        XCTAssertEqual(CareHourChips.range(1, 2), String(localized: "care.chip.rangeHours", defaultValue: "\(1)–\(2)h", table: "CarePlan"))
        XCTAssertEqual(CareHourChips.range(0.75, 1.5),
                       String(localized: "care.chip.range", defaultValue: "\(LHFormat.hours(0.75))–\(LHFormat.hours(1.5))", table: "CarePlan"))
    }

    // MARK: Log time prefill: hours never prefilled

    func testACareRowOpensLogTimeWithHoursEmpty() {
        let task = CarePlanCatalog.task(id: "gutters")!
        let prefill = CarePrefill.make(task: task, rental: pine)
        let form = LogForm.care(prefill, properties: [pine, lakeside], now: oct31)
        XCTAssertEqual(form.hours, 0, "never a guessed number")
        XCTAssertFalse(form.hoursIsDefault)
        XCTAssertFalse(form.isUserSet(.hours))
        XCTAssertEqual(form.propertyId, pine.id)
        XCTAssertEqual(form.category, task.kind)
        XCTAssertEqual(form.careTaskID, "gutters")
        XCTAssertTrue(form.note.hasPrefix(task.doneNote))
        XCTAssertEqual(form.gap(properties: [pine, lakeside]), .hours)
        XCTAssertFalse(form.canLog(properties: [pine, lakeside]))
        XCTAssertEqual(LogTimeFormat.buttonTitle(form: form, properties: [pine, lakeside], now: oct31), CareText.setHowLong)
    }

    func testEveryCarePrefillStartsEmptyForEveryTask() {
        for task in CarePlanCatalog.tasks {
            let form = LogForm.care(CarePrefill.make(task: task, rental: lakeside), properties: [lakeside], now: oct31)
            XCTAssertEqual(form.hours, 0, task.id)
            XCTAssertEqual(form.gap(properties: [lakeside]), .hours, task.id)
        }
    }

    func testOneChipTapSetsTheHoursAndTheButtonLogs() {
        let prefill = CarePrefill.make(task: CarePlanCatalog.task(id: "gutters")!, rental: pine)
        var form = LogForm.care(prefill, properties: [pine], now: oct31)
        form.setChipHours(80.0 / 60.0)
        XCTAssertEqual(form.hours, 80.0 / 60.0, accuracy: 0.0001)
        XCTAssertTrue(form.isUserSet(.hours))
        XCTAssertTrue(form.canLog(properties: [pine]))
        XCTAssertTrue(LogTimeFormat.buttonTitle(form: form, properties: [pine], now: oct31).contains(LHFormat.hours(80.0 / 60.0).replacingOccurrences(of: " ", with: "\u{00A0}")))
        XCTAssertNotEqual(LogTimeFormat.buttonTitle(form: form, properties: [pine], now: oct31), CareText.setHowLong)
    }

    func testAPlainLogStillStartsAtOneHourAndSaysAddHowLong() {
        let form = LogForm.starting(properties: [pine], entries: [])
        XCTAssertNil(form.careTaskID)
        XCTAssertEqual(form.hours, 1)
        var empty = form
        empty.setHours(0)
        XCTAssertNotEqual(LogTimeFormat.buttonTitle(form: empty, properties: [pine]), CareText.setHowLong)
    }

    func testTheCareRouteHasItsOwnId() {
        let prefill = CarePrefill.make(task: CarePlanCatalog.task(id: "gutters")!, rental: pine)
        XCTAssertTrue(LogSheetRoute.care(prefill).id.hasPrefix("care-gutters-"))
        XCTAssertNotEqual(LogSheetRoute.care(prefill), .log)
    }

    // MARK: Words

    func testEveryTaskHasItsWordsAndASymbol() {
        for task in CarePlanCatalog.tasks {
            XCTAssertNotEqual(task.title, "care.task.\(task.id).title", task.id)
            XCTAssertFalse(task.title.isEmpty)
            XCTAssertFalse(task.doneNote.isEmpty)
            for type in PropertyType.allCases { XCTAssertFalse(task.when(for: type).isEmpty, "\(task.id) \(type)") }
            XCTAssertNotNil(UIImage(systemName: task.symbol), "\(task.id): \(task.symbol)")
        }
        XCTAssertEqual(Set(CarePlanCatalog.tasks.map(\.id)).count, CarePlanCatalog.tasks.count, "ids are unique")
    }

    func testTheCatalogTableHoldsEveryTaskKey() {
        for (key, value) in CareText.taskStrings {
            XCTAssertEqual(Bundle.main.localizedString(forKey: key, value: "MISSING", table: "CarePlan"), value, key)
        }
        for key in ["care.rule", "care.today.seePlan", "care.log.setHowLong", "care.plan.title"] {
            XCTAssertNotEqual(Bundle.main.localizedString(forKey: key, value: "MISSING", table: "CarePlan"), "MISSING", key)
        }
    }

    func testNoWordTheStandardRetiresAndNoHoursPitch() {
        let banned = ["qualify", "qualified", "audit-ready", "evidence", "proof", "compliance", "add hours", "more hours",
                      "iphone", "ipad"]
        var all = CareText.taskStrings.map(\.value)
        all += [CareText.rule, CareText.lockLine, CareText.lockKeeps, CareText.openHint, CareText.doneHint, CareText.setHowLong]
        for type in PropertyType.allCases { for climate in CareClimate.allCases { all.append(CareText.footnote(type: type, climate: climate)) } }
        for text in all {
            for word in banned { XCTAssertFalse(text.lowercased().contains(word), "\"\(text)\" has \"\(word)\"") }
        }
    }

    // MARK: Due source (package D)

    func testTheDueSourceNamesThisSeasonsOpenItems() {
        let e = entry(pine, 1, date(2026, 10, 4))
        let logs = CareDoneLog.logs(records: [CareRecord(taskID: "gutters", entryID: e.id)], entries: [e])
        let source = CarePlanDueSource(snapshot: { CareDueSnapshot(rentals: [self.pine], logs: logs) }, calendar: calendar)
        let due = source.dueItems(for: pine.id, on: oct31)
        XCTAssertEqual(due.map(\.id), ["outdoorTaps", "alarms", "furnaceFilter"])
        XCTAssertTrue(due.allSatisfy { $0.rentalID == pine.id })
        XCTAssertEqual(due.first?.due, CareSeason.start(of: oct31, calendar: calendar))
        XCTAssertTrue(source.dueItems(for: UUID(), on: oct31).isEmpty, "an unknown rental has nothing due")
        XCTAssertTrue(CarePlanDueSource(snapshot: { .empty }).dueItems(for: pine.id, on: oct31).isEmpty, "nothing before the snapshot")
    }

    func testTheLiveSourceReadsTheSnapshotBSets() {
        let saved = CareDue.snapshot
        defer { CareDue.update(rentals: saved.rentals, logs: saved.logs) }
        CareDue.update(rentals: [pine], logs: [])
        XCTAssertFalse(CareDue.source.dueItems(for: pine.id, on: oct31).isEmpty)
        CareDue.update(rentals: [], logs: [])
        XCTAssertTrue(CareDue.source.dueItems(for: pine.id, on: oct31).isEmpty)
    }

    // MARK: Which rental Today shows

    func testTodayShowsTheFocusedRentalElseTheOnlyElseTheBusiest() {
        let now = oct31
        XCTAssertEqual(TodayCareSlot.rental(for: lakeside.id, properties: [pine, lakeside], entries: [], now: now)?.id, lakeside.id)
        XCTAssertEqual(TodayCareSlot.rental(for: nil, properties: [lakeside], entries: [], now: now)?.id, lakeside.id)
        XCTAssertEqual(TodayCareSlot.rental(for: nil, properties: [pine, lakeside], entries: [], now: now)?.id, pine.id, "a tie keeps the first")
        let busy = [entry(lakeside, 5, date(2026, 6, 1)), entry(pine, 2, date(2026, 6, 1)), entry(pine, 9, date(2025, 6, 1))]
        XCTAssertEqual(TodayCareSlot.rental(for: nil, properties: [pine, lakeside], entries: busy, now: now)?.id, lakeside.id,
                       "this year's hours, not last year's")
        XCTAssertNil(TodayCareSlot.rental(for: nil, properties: [], entries: [], now: now))
    }
}
