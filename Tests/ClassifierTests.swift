import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import LandlordHours

// MARK: - Fakes

final class FakeOnDeviceBackend: OnDeviceModelBackend {
    var availability: ModelAvailability
    var answer: OnDeviceAnswer?
    var error: Error?
    private(set) var requests: [OnDeviceRequest] = []

    init(availability: ModelAvailability = .available, answer: OnDeviceAnswer? = nil, error: Error? = nil) {
        self.availability = availability
        self.answer = answer
        self.error = error
    }

    func answer(_ request: OnDeviceRequest) async throws -> OnDeviceAnswer {
        requests.append(request)
        if let error { throw error }
        guard let answer else { throw OnDeviceClassifierError.unavailable(.systemNotReady) }
        return answer
    }
}

struct FakePCCStatus: PCCSystemStatusProviding {
    var value: ModelAvailability
    func status() -> ModelAvailability { value }
}

/// Thread-safe slow model for batch tests. Honours cancellation like the real one.
final class SlowFakeBackend: OnDeviceModelBackend, @unchecked Sendable {
    let availability: ModelAvailability = .available
    let delay: TimeInterval
    let slowDelay: TimeInterval
    let fixed: OnDeviceAnswer
    let startedAt = Date()
    private let lock = NSLock()
    private var _calls = 0
    private var _inFlight = 0
    private var _maxInFlight = 0
    private var _mainThreadCalls = 0

    init(delay: TimeInterval, slowDelay: TimeInterval? = nil, answer: OnDeviceAnswer) {
        self.delay = delay
        self.slowDelay = slowDelay ?? delay
        self.fixed = answer
    }

    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    var maxInFlight: Int { lock.lock(); defer { lock.unlock() }; return _maxInFlight }
    var mainThreadCalls: Int { lock.lock(); defer { lock.unlock() }; return _mainThreadCalls }

    func answer(_ request: OnDeviceRequest) async throws -> OnDeviceAnswer {
        let onMain = Thread.isMainThread
        lock.lock()
        _calls += 1
        _inFlight += 1
        _maxInFlight = max(_maxInFlight, _inFlight)
        if onMain { _mainThreadCalls += 1 }
        lock.unlock()
        defer { lock.lock(); _inFlight -= 1; lock.unlock() }
        let wait = request.title.hasPrefix("slow") ? slowDelay : delay
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        return fixed
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [ClassifierBatchProgress] = []
    func record(_ p: ClassifierBatchProgress) { lock.lock(); _values.append(p); lock.unlock() }
    var values: [ClassifierBatchProgress] { lock.lock(); defer { lock.unlock() }; return _values }
    var latest: ClassifierBatchProgress? { values.last }
}

private struct ModelBoom: Error {}

final class ClassifierTests: XCTestCase {
    private let oak = RentalProperty(name: "Oak Street Duplex", address: "412 Oak St, Austin, TX 78704", propertyType: .ltr)
    private let maple = RentalProperty(name: "Maple Cottage", address: "88 Maple Ave, Austin, TX 78702", propertyType: .ltr)
    private let lakeview = RentalProperty(name: "Lakeview Condo", address: "1500 Lakeshore Blvd Unit 4B, Austin, TX 78741", propertyType: .ltr)
    private var properties: [RentalProperty] { [oak, maple, lakeview] }

    private func candidate(
        _ title: String,
        kind: Suggestion.Kind = .calendar,
        hours: Double? = 1.5,
        location: String? = nil,
        containerId: String? = "cal-home"
    ) -> CaptureCandidate {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return CaptureCandidate(
            sourceKey: "cal:\(title.hashValue)",
            kind: kind,
            start: start,
            end: hours.map { start.addingTimeInterval($0 * 3600) },
            title: title,
            containerId: containerId,
            location: location,
            detectedAt: start
        )
    }

    private func answer(_ yes: Bool, _ confidence: Double, category: ActivityCategory? = nil, ref: String? = nil) -> OnDeviceAnswer {
        OnDeviceAnswer(isRentalWork: yes, category: category, propertyRef: ref, confidence: confidence, reason: "test")
    }

    // MARK: Rules table

    func testRulesTableHasNoDuplicatePhrases() {
        var seen = Set<String>()
        for signal in ClassifierKeywords.signals {
            XCTAssertTrue(seen.insert(signal.phrase + (signal.wholeWord ? "|w" : "")).inserted, "duplicate: \(signal.phrase)")
            XCTAssertEqual(signal.phrase, RulesEngine.normalize(signal.phrase), "phrase must be pre-normalized: \(signal.phrase)")
        }
    }

    func testRulesTableCoversThe1xKeywords() {
        // Every keyword 1.x's calendar import scanned for still moves the score toward landlord.
        let legacy = ["property", "tenant", "landlord", "repair", "maintenance", "plumber", "electrician",
                      "inspection", "lease", "rent", "showing", "walkthrough", "contractor", "hvac",
                      "cleaning", "move-in", "move-out", "appraisal"]
        for word in legacy {
            let verdict = RulesEngine.evaluate(text: word, properties: [])
            XCTAssertGreaterThan(verdict.score, 0, "\(word) lost its landlord signal")
        }
    }

    func testWordBoundariesAndNoise() {
        XCTAssertGreaterThan(RulesEngine.evaluate(text: "Plumber at the rental", properties: []).confidence, ClassifierThresholds.likely)
        // "dr" is whole-word only: "Drive to Maple" must not be read as a doctor visit.
        XCTAssertGreaterThan(RulesEngine.evaluate(text: "Drive to Maple Cottage", properties: properties).confidence, ClassifierThresholds.likely)
        XCTAssertLessThan(RulesEngine.evaluate(text: "Dr. Patel annual physical", properties: properties).confidence, ClassifierThresholds.notSure)
        // "rent" inside other words is not rent.
        XCTAssertLessThan(RulesEngine.evaluate(text: "Parent pickup", properties: []).confidence, ClassifierThresholds.notSure)
        // Noise outweighs a landlord-sounding word.
        XCTAssertLessThan(RulesEngine.evaluate(text: "Rent tux for wedding", properties: []).confidence, ClassifierThresholds.notSure)
        XCTAssertLessThan(RulesEngine.evaluate(text: "Dentist - cleaning", properties: []).confidence, ClassifierThresholds.notSure)
    }

    func testCategoryVotes() {
        XCTAssertEqual(RulesEngine.evaluate(text: "Meet attorney re lease dispute", properties: []).category, .legal)
        XCTAssertEqual(RulesEngine.evaluate(text: "Collect rent / deposit checks", properties: []).category, .management)
        XCTAssertEqual(RulesEngine.evaluate(text: "Refinance call with lender", properties: []).category, .financing)
        XCTAssertEqual(RulesEngine.evaluate(text: "Reconcile rent ledger in QuickBooks", properties: []).category, .bookkeeping)
        XCTAssertNil(RulesEngine.evaluate(text: "Haircut", properties: []).category)
    }

    func testPropertyMatching() {
        XCTAssertEqual(RulesEngine.evaluate(text: "HVAC tune-up 412 Oak", properties: properties).propertyId, oak.id)
        XCTAssertEqual(RulesEngine.evaluate(text: "Gutter cleaning - Maple Cottage", properties: properties).propertyId, maple.id)
        XCTAssertEqual(RulesEngine.evaluate(text: "Toilet repair unit 4B", properties: properties).propertyId, lakeview.id)
        XCTAssertEqual(RulesEngine.evaluate(text: "Leak at 1500 Lakeshore", properties: properties).propertyId, lakeview.id)
        // City and state never match ("Austin" is in every address).
        XCTAssertNil(RulesEngine.evaluate(text: "Flight to Austin", properties: properties).propertyId)
        // Two properties tie → propose none.
        let twin = RentalProperty(name: "Maple Duplex", address: "5 Maple Ave", propertyType: .ltr)
        XCTAssertNil(RulesEngine.evaluate(text: "Maple repair", properties: [maple, twin]).propertyId)
    }

    func testAddressParts() {
        let parts = RulesEngine.addressParts("1500 Lakeshore Blvd Unit 4B, Austin, TX 78741")
        XCTAssertEqual(parts.number, "1500")
        XCTAssertEqual(parts.streetWords, ["lakeshore"])
        XCTAssertEqual(parts.unitTokens, ["4b"])
    }

    // MARK: RulesClassifier

    func testRulesClassifierCalendarKeeps1xCategoryAndScheduledHours() async {
        let c = candidate("Call CPA re Schedule E", hours: 1.5)
        let result = await RulesClassifier().classify(c, properties: properties)
        XCTAssertEqual(result.tier, .rules)
        XCTAssertTrue(result.isLandlordWork)
        // 1.x categorizeEvent → .management for this title; keeping it lets a 1.1 device dedupe.
        XCTAssertEqual(result.category, .management)
        XCTAssertEqual(result.hours ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(result.hoursBasis, .scheduled)

        // A non-calendar source gets the table category.
        let rich = await RulesClassifier().classify(candidate(c.title, kind: .gmail), properties: properties)
        XCTAssertEqual(rich.category, .bookkeeping)
    }

    /// WP1 constraint: for calendar sources the chain never changes the 1.x category, even when
    /// the on-device model proposes another one, for every calibration title. One exception: a
    /// deal title (buy, sell, finance, negotiate) gets its non-countable category, so investor
    /// hours never count toward REPS (verifier, 2026-10-21).
    func testCalendarCategoryEquals1xThroughTheChainForEveryCalibrationTitle() async throws {
        let fixture = try CalibrationFixture.load()
        let service = CalendarImportService.shared
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .contractNegotiation, ref: "P1"))
        let withModel = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let rulesOnly = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
        for item in fixture.items {
            // A loan, HOA or property tax payment is Bookkeeping whatever 1.x said (it filed "Property tax payment" under Management).
            let paid = DealSignal.isLoanPayment(" \(RulesEngine.normalize(item.title)) ")
            let expected = DealSignal.category(forTitle: item.title) ?? (paid ? .bookkeeping : service.categorizeEvent(title: item.title.lowercased()))
            let a = await withModel.classify(candidate(item.title), properties: properties)
            let b = await rulesOnly.classify(candidate(item.title), properties: properties)
            XCTAssertEqual(a.category, expected, "chain+model: \(item.title)")
            XCTAssertEqual(b.category, expected, "rules: \(item.title)")
        }
        XCTAssertFalse(backend.requests.isEmpty, "the model must have run on some titles")
    }

    /// Deal titles must never carry a countable category on any source, whatever the model
    /// answers (it is asked here to say Property Management for P1).
    func testDealTitlesAlwaysGetANonCountableCategory() async {
        let deals: [(String, ActivityCategory)] = [
            ("Counteroffer on the Elm fourplex", .contractNegotiation),
            ("Counter-offer on the Birch Rd triplex", .contractNegotiation),
            ("Submit offer on 22 Pine St duplex", .contractNegotiation),
            ("Review purchase agreement with seller's agent", .contractNegotiation),
            ("Negotiate sale price for Maple Cottage", .contractNegotiation),
            ("Refinance call with lender - duplex", .financing),
            ("Refi call with Chase - Maple Cottage", .financing),
            ("HELOC application for Oak Street Duplex", .financing),
            ("Rate lock deadline - Lakeview refinance", .financing),
            ("Send bank statements to lender for DSCR loan", .financing),
            ("Closing on Elm fourplex", .financing),
            ("Closing docs signing - Pine St duplex", .financing),
            ("Run cap rate on Birch Rd triplex", .investing),
            ("Pull comps for 22 Pine St", .investing),
            ("1031 exchange - identify replacement property", .investing),
            ("Tour potential rental on Walnut Ave", .investing),
            ("Look at duplex listing in Eastside", .investing),
            ("Negotiation call with the seller's agent", .contractNegotiation),
            ("Negotiate price with the buyer's agent", .contractNegotiation),
            ("List the Pine Street house for sale with the broker", .contractNegotiation),
            ("Sign listing agreement for Cedar Flats", .contractNegotiation),
            ("Closing at the title company at 9am", .financing),
            ("Escrow closing call for the Pine St duplex", .financing),
            ("Escrow walkthrough for the Birch duplex purchase", .contractNegotiation),
            ("Draft LOI for the 6-unit on 3rd St", .contractNegotiation),
            ("Inspection contingency call with buyer's agent", .contractNegotiation),
            ("Earnest money wire due Friday - Pine St duplex", .contractNegotiation),
            ("Review inspection period extension with the seller", .contractNegotiation),
            ("Due diligence checklist for the Eastside fourplex", .contractNegotiation),
            ("Final walk-through for the Walnut Ave purchase", .contractNegotiation),
            ("Put the Maple Cottage on the market", .contractNegotiation),
            ("Meet broker to sell the Lakeview house", .contractNegotiation),
            ("Counter on PSA for the Elm Ave fourplex", .contractNegotiation),
            ("Sign broker agreement for the sale of Pine St", .contractNegotiation),
            ("Loan application documents for the 8-unit", .financing),
            ("Call mortgage broker about pre-approval", .financing),
            ("Appraisal ordered by lender for Oak Street Duplex", .financing),
            ("Cash-out refi quote for Lakeview", .financing),
            ("Build pro forma for the 12-unit acquisition", .investing),
            ("Underwriting the Hamilton St deal with partners", .investing),
            ("Intro call with buyer's agent about Eastside duplexes", .investing),
        ]
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .management, ref: "P1"))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        for (title, expected) in deals {
            for kind in [Suggestion.Kind.calendar, .location, .gmail] {
                let c = await chain.classify(candidate(title, kind: kind), properties: properties)
                XCTAssertEqual(c.category, expected, "\(kind): \(title)")
                XCTAssertEqual(c.category?.countsForREPS, false, "\(kind): \(title) must not count")
            }
        }
    }

    func testCountableTitlesWithDealLikeWordsKeepTheirCategory() {
        for title in ["Post listing on Zillow", "Vacancy - update rental listing photos", "Mortgage payment for Oak Street Duplex",
                      "Loan payment autopay - Maple", "Virtual tour video for listing", "Fix sink at Oak",
                      "Negotiate lease renewal with tenant", "Negotiation with tenant over late rent", "Closing the gate at Maple",
                      "Closing up the pool for winter",
                      "Tenant lease renewal negotiation for Oak Street Duplex", "Offer lease renewal to tenant at Maple Cottage", "Collect rent from tenants - Lakeview", "Return deposit from tenant - Oak Street Duplex", "Pay property tax bill for Cedar Flats", "Closing up the pool for winter - Maple Cottage", "Closing the gate and checking locks at Lakeview", "Autopay for the mortgage on Oak Street Duplex", "Review contingency fund for repairs at Lakeview", "Move-out walkthrough with tenant at Maple Cottage"] {
            XCTAssertNil(DealSignal.category(forTitle: title), title)
        }
    }

    /// Paying an existing loan is bookkeeping, which counts; it must never come out as Financing
    /// (non-countable) from the keyword table or the model, on any source.
    func testLoanAndMortgagePaymentsStayCountable() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .financing))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        for title in ["Pay the mortgage payment", "Record the mortgage payment", "Set up autopay for the loan payment",
                      "Pay HELOC installment - Maple"] {
            for kind in [Suggestion.Kind.calendar, .location, .gmail] {
                let c = await chain.classify(candidate(title, kind: kind), properties: properties)
                XCTAssertNotEqual(c.category, .financing, "\(kind): \(title)")
                if let category = c.category { XCTAssertTrue(category.countsForREPS, "\(kind): \(title)") }
            }
            let rules = await RulesClassifier().classify(candidate(title, kind: .gmail), properties: properties)
            XCTAssertNotEqual(rules.category, .financing, "rules email: \(title)")
        }
    }

    /// A clear payment title is Bookkeeping and confident on every source, whatever category came in
    /// (the calendar's 1.x category for "Making Monthly Mortgage Payment" is Management).
    func testPaymentTitlesAreConfidentBookkeeping() {
        for title in ["Making Monthly Mortgage Payment", "Mortgage payment", "Monthly mortgage", "Pay mortgage",
                      "Loan payment - Maple", "HOA payment - Lakeview", "Property tax payment - Oak"] {
            for kind in [Suggestion.Kind.calendar, .location, .gmail] {
                let c = RulesClassifier().classifySync(candidate(title, kind: kind), properties: properties)
                XCTAssertEqual(c.category, .bookkeeping, "\(kind): \(title)")
                XCTAssertGreaterThanOrEqual(c.confidence, ClassifierThresholds.likely, "\(kind): \(title)")
                XCTAssertTrue(c.isLandlordWork, "\(kind): \(title)")
            }
        }
        XCTAssertEqual(DealSignal.apply(.management, title: "Making Monthly Mortgage Payment"), .bookkeeping)
    }

    /// Refinances, new loans, closings and applications stay deals even with a payment word beside them.
    func testPaymentWordsDoNotPullDealsIntoBookkeeping() {
        for title in ["Refinance payment estimate", "Refi: compare new mortgage payment", "New loan payment options for the fourplex",
                      "Closing costs and first mortgage payment", "Mortgage application - monthly payment review",
                      "Loan application payment schedule", "Lender call about mortgage payment quote"] {
            let c = DealSignal.apply(.management, title: title)
            XCTAssertNotEqual(c, .bookkeeping, title)
            XCTAssertNotEqual(c, .management, title)
            XCTAssertEqual(c?.countsForREPS, false, title)
        }
    }

    /// Closing, escrow, earnest-money and wire-to-title events are deal activity (non-counting),
    /// while property tax and mortgage payments stay Bookkeeping.
    func testClosingAndEscrowPaymentsAreDealsButTaxAndMortgagePaymentsAreBookkeeping() async {
        for title in ["Closing payment wire", "Wire to title for the Elm closing", "Wire earnest money", "Escrow payment - Elm fourplex",
                      "Earnest money payment", "Closing costs payment"] {
            for kind in [Suggestion.Kind.calendar, .gmail] {
                let c = RulesClassifier().classifySync(candidate(title, kind: kind), properties: properties)
                XCTAssertEqual(c.category?.countsForREPS, false, "\(kind): \(title)")
            }
        }
        for title in ["Property tax payment - Oak", "Mortgage payment", "Making Monthly Mortgage Payment"] {
            let c = RulesClassifier().classifySync(candidate(title, kind: .calendar), properties: properties)
            XCTAssertEqual(c.category, .bookkeeping, title)
        }
    }

    func testAliasGroundingMatchesWholeWordsOnly() {
        let oakAlias = RentalProperty(name: "Birch House", address: "9 Elm Rd, Austin, TX", propertyType: .ltr, aliases: ["Oak"])
        func pick(_ title: String) -> UUID? {
            let request = OnDeviceClassifier.request(for: candidate(title), properties: [oakAlias])
            return OnDeviceClassifier.map(answer(true, 0.9, ref: "P1"), request: request, properties: [oakAlias]).propertyId
        }
        XCTAssertNil(pick("Flight from Oakland airport"))
        XCTAssertEqual(pick("Oak: gutters"), oakAlias.id)
    }

    func testDecoratedPropertyRefsAreNormalized() {
        XCTAssertEqual(OnDeviceClassifier.normalizedRef("P3: Lakeview Condo (1500 Lakeshore Blvd)"), "P3")
        XCTAssertEqual(OnDeviceClassifier.normalizedRef(" p2 "), "P2")
        XCTAssertEqual(OnDeviceClassifier.normalizedRef("Property P1"), "P1")
        XCTAssertNil(OnDeviceClassifier.normalizedRef("none"))
        XCTAssertNil(OnDeviceClassifier.normalizedRef("APT12"))
        let request = OnDeviceClassifier.request(for: candidate("AC not cooling at Lakeview"), properties: properties)
        let mapped = OnDeviceClassifier.map(answer(true, 0.9, ref: "P3: Lakeview Condo…"), request: request, properties: properties)
        XCTAssertEqual(mapped.propertyId, lakeview.id)
    }

    func testLegacyCategoryMatches1xForEveryCalibrationTitle() throws {
        let fixture = try CalibrationFixture.load()
        let service = CalendarImportService.shared
        for item in fixture.items {
            XCTAssertEqual(
                LegacyCalendarCategory.category(forTitle: item.title),
                service.categorizeEvent(title: item.title.lowercased()),
                item.title
            )
        }
    }

    func testReceiptsNeverGetHoursAndAllDayEventsGetNone() async {
        let receipt = await RulesClassifier().classify(candidate("Home Depot receipt", kind: .receipt), properties: properties)
        XCTAssertNil(receipt.hours)
        XCTAssertEqual(receipt.hoursBasis, .none)
        let allDay = await RulesClassifier().classify(candidate("Tenant move-in", hours: 24), properties: properties)
        XCTAssertNil(allDay.hours)
    }

    func testOnlyPropertyDefaultNeedsALikelyItem() async {
        let likely = await RulesClassifier().classify(candidate("Plumber for kitchen leak"), properties: [oak])
        XCTAssertEqual(likely.propertyId, oak.id)
        let noise = await RulesClassifier().classify(candidate("Lunch with Alex"), properties: [oak])
        XCTAssertNil(noise.propertyId)
    }

    // MARK: On-device availability → rules fallback

    func testEveryUnavailableStateFallsBackToRules() async {
        let states: [ModelUnavailableReason] = [.osTooOld, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .systemNotReady]
        for reason in states {
            let backend = FakeOnDeviceBackend(availability: .unavailable(reason), answer: answer(true, 0.99))
            let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
            let c = candidate("Prep 1031 exchange docs")
            let result = await chain.classify(c, properties: properties)
            let rulesOnly = await RulesClassifier().classify(c, properties: properties)
            XCTAssertEqual(result, rulesOnly, "\(reason)")
            XCTAssertEqual(result.tier, .rules)
            XCTAssertTrue(backend.requests.isEmpty, "model must not be called when \(reason)")
            XCTAssertEqual(chain.activeTier, .rules)
        }
    }

    func testModelErrorFallsBackToRules() async {
        let backend = FakeOnDeviceBackend(availability: .available, error: ModelBoom())
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let c = candidate("Upload receipts to Stessa")
        let result = await chain.classify(c, properties: properties)
        let rulesOnly = await RulesClassifier().classify(c, properties: properties)
        XCTAssertEqual(result, rulesOnly)
        XCTAssertEqual(backend.requests.count, 1)
    }

    func testDefaultBackendBelowIOS26IsUnavailable() {
        let classifier = OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld))
        XCTAssertEqual(classifier.availability, .unavailable(.osTooOld))
    }

    // MARK: Chain with the model

    func testModelRescuesAnUnknownTitleIntoNotSure() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.85, category: .investing))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let result = await chain.classify(candidate("Prep paperwork for Friday"), properties: properties)
        XCTAssertEqual(result.tier, .onDevice)
        XCTAssertEqual(result.band, .notSure)
        XCTAssertFalse(result.isLandlordWork)
        XCTAssertTrue(result.evidence.contains { $0.hasPrefix("model: yes") })
    }

    func testDecisiveRulesSkipTheModel() async {
        let backend = FakeOnDeviceBackend(answer: answer(false, 0.0))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        _ = await chain.classify(candidate("Plumber at Oak St - kitchen leak"), properties: properties)
        _ = await chain.classify(candidate("Dentist - cleaning"), properties: properties)
        XCTAssertTrue(backend.requests.isEmpty)
    }

    func testReceiptsNeverReachTheOnDeviceChainModel() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        _ = await chain.classify(candidate("Ace Hardware", kind: .receipt, hours: nil), properties: properties)
        XCTAssertTrue(backend.requests.isEmpty)
    }

    func testMergeKeepsRulesPropertyAnd1xCalendarCategory() async {
        // Rules matched Maple by name; the model points elsewhere and picks another category.
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .repairs, ref: "P1"))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let c = candidate("Smoke alarm battery swap Maple")
        let result = await chain.classify(c, properties: properties)
        XCTAssertEqual(result.propertyId, maple.id)
        XCTAssertEqual(result.category, LegacyCalendarCategory.category(forTitle: c.title))
        XCTAssertEqual(result.tier, .onDevice)

        // Non-calendar kinds take the model's category; an unknown property ref is ignored.
        let backend2 = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .repairs, ref: "P9"))
        let chain2 = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend2))
        let visit = await chain2.classify(candidate("Swap air filters", kind: .location), properties: properties)
        XCTAssertEqual(visit.category, .repairs)
        XCTAssertNil(visit.propertyId)
    }

    func testModelPropertyRefMapsToId() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .repairs, ref: "p2"))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        _ = await chain.classify(candidate("Mold remediation"), properties: properties)
        XCTAssertEqual(backend.requests.first?.properties.map(\.ref), ["P1", "P2", "P3"])
        // A grounded pick ("the cottage" names nothing, "maple" does) maps case-insensitively.
        let request = OnDeviceClassifier.request(for: candidate("Mold remediation, maple cottage"), properties: properties)
        let mapped = OnDeviceClassifier.map(answer(true, 0.9, category: .repairs, ref: "p2"), request: request, properties: properties)
        XCTAssertEqual(mapped.propertyId, maple.id)
    }

    /// 2026-10-21 calibration: the model picked P1 for 12 of 25 held-out items that named no
    /// property. A pick is kept only when the title or location names that property.
    func testModelPropertyPickMustBeNamedInTheItem() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .repairs, ref: "P1"))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let ungrounded = await chain.classify(candidate("Mold remediation"), properties: properties)
        XCTAssertNil(ungrounded.propertyId, "model defaulted to P1 with no property named")

        func pick(_ title: String, location: String? = nil, ref: String, in props: [RentalProperty]) -> UUID? {
            let request = OnDeviceClassifier.request(for: candidate(title, location: location), properties: props)
            return OnDeviceClassifier.map(answer(true, 0.9, ref: ref), request: request, properties: props).propertyId
        }
        XCTAssertEqual(pick("Fix sink at Oak", ref: "P1", in: properties), oak.id)
        XCTAssertEqual(pick("Fix sink", location: "1500 Lakeshore Blvd", ref: "P3", in: properties), lakeview.id)
        XCTAssertNil(pick("Clean gutters at the duplex", ref: "P1", in: properties), "generic type word is not a name")
        XCTAssertNil(pick("Late fee notice to unit 2", ref: "P2", in: properties))
        let aliased = RentalProperty(name: "Birch House", address: "9 Elm Rd, Austin, TX", propertyType: .str, aliases: ["Cozy Loft by the Lake"])
        XCTAssertEqual(pick("Inquiry for Cozy Loft by the Lake", ref: "P1", in: [aliased]), aliased.id)
    }

    func testModelNoIsCappedAndCleansAnswer() {
        let request = OnDeviceClassifier.request(for: candidate("x"), properties: properties)
        let mapped = OnDeviceClassifier.map(answer(false, 0.95, category: .repairs, ref: "P1"), request: request, properties: properties)
        XCTAssertLessThanOrEqual(mapped.confidence, 0.4)
        XCTAssertNil(mapped.category)
        XCTAssertNil(mapped.propertyId)
        let wild = OnDeviceClassifier.map(answer(true, 7), request: request, properties: properties)
        XCTAssertEqual(wild.confidence, 1)
        let nan = OnDeviceClassifier.map(answer(true, .nan), request: request, properties: properties)
        XCTAssertEqual(nan.confidence, 0)
    }

    func testPromptCarriesOnlyTheEventAndPropertyList() {
        let request = OnDeviceClassifier.request(for: candidate("Fix sink", location: "412 Oak St"), properties: [oak])
        let prompt = OnDeviceClassifier.prompt(for: request)
        XCTAssertTrue(prompt.contains("Item (calendar event): Fix sink"))
        XCTAssertTrue(prompt.contains("P1: Oak Street Duplex (412 Oak St)"))
        XCTAssertFalse(prompt.contains(oak.id.uuidString))
        XCTAssertTrue(OnDeviceClassifier.instructions.contains("Never give tax"))
        XCTAssertTrue(OnDeviceClassifier.instructions.contains("low confidence"))
    }

    // MARK: Bands, mutes

    func testLowConfidenceStaysVisibleAsNotSure() async {
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .deviceNotEligible)))
        let outcome = await chain.evaluate(candidate("Check for mold"), properties: properties)
        guard case .suggest(let c) = outcome else { return XCTFail("expected suggest, got \(outcome)") }
        XCTAssertEqual(c.band, .notSure)
        XCTAssertEqual(ConfidenceBand.notSureLabel, "Not sure this is rental work")

        let noise = await chain.evaluate(candidate("Kids soccer practice"), properties: properties)
        guard case .skip = noise else { return XCTFail("expected skip, got \(noise)") }
    }

    /// Review fix 1, tightened in classifier v2: an item with a real landlord signal (a rules
    /// score of at least 1.5, or a property match) is never hidden, not by a weak score and not
    /// by a model "no". A single weak keyword alone no longer reaches the inbox (see
    /// ClassifierV2Tests.testNotSureBandNeedsScoreOrPropertyOrConfidentModel).
    func testKeywordItemsAreNeverHiddenEvenWhenTheModelSaysNo() async {
        let backend = FakeOnDeviceBackend(answer: answer(false, 0.0))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let weak = ["Check for mold", "Call locksmith", "Exterminator visit", "Pest control", "Lunch near Maple Cottage", "Lunch near Lakeshore"]
        for title in weak {
            let outcome = await chain.evaluate(candidate(title), properties: properties)
            guard case .suggest(let c) = outcome else { XCTFail("\(title) was hidden: \(outcome)"); continue }
            XCTAssertEqual(c.band, .notSure, title)
            XCTAssertGreaterThanOrEqual(c.confidence, ClassifierThresholds.notSure, title)
        }
        XCTAssertFalse(backend.requests.isEmpty, "the model's no must have been consulted")
        // Same without the model.
        let rulesOnly = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
        for title in weak {
            let c = await rulesOnly.classify(candidate(title), properties: properties)
            XCTAssertNotEqual(c.band, .unlikely, title)
        }
        // No landlord signal, or noise that outweighs the keyword → dropped.
        for title in ["Haircut", "Rent tux for wedding", "Dentist - cleaning"] {
            let outcome = await rulesOnly.evaluate(candidate(title), properties: properties)
            guard case .skip = outcome else { XCTFail("\(title) should drop: \(outcome)"); continue }
        }
    }

    /// Review fix 3: mutes apply through classify() too, so integrators can't bypass them.
    func testMuteRulesApplyOnEveryEntryPoint() async throws {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9))
        let byTitle = CaptureMuteRule(match: .titleContains, value: "stessa")
        let byCalendar = CaptureMuteRule(match: .containerId, value: "cal-work")
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend), muteRules: { [byTitle, byCalendar] })

        let a = await chain.evaluate(candidate("Upload receipts to Stessa"), properties: properties)
        let b = await chain.evaluate(candidate("Tenant call", containerId: "cal-work"), properties: properties)
        XCTAssertEqual(a, .muted)
        XCTAssertEqual(b, .muted)

        let direct = await chain.classify(candidate("Plumber for Stessa unit"), properties: properties)
        XCTAssertFalse(direct.isLandlordWork)
        XCTAssertEqual(direct.evidence, ["muted"])
        XCTAssertEqual(direct.band, .unlikely)

        // Through the CaptureClassifier protocol, as an integrator would hold it.
        let asProtocol: CaptureClassifier = chain
        let viaProtocol = await asProtocol.classify(candidate("Tenant call", containerId: "cal-work"), properties: properties)
        XCTAssertEqual(viaProtocol.evidence, ["muted"])

        let batch = try await chain.classifyBatch([candidate("Stessa export"), candidate("Plumber at Oak")], properties: properties)
        XCTAssertEqual(batch.first, .muted)
        XCTAssertNotEqual(batch.last, .muted)
        XCTAssertTrue(backend.requests.isEmpty, "a muted item must never reach the model")
    }

    @MainActor
    func testChainReadsMuteRulesFromTheStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wp2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SuggestionStore(userId: "u1", baseDirectory: dir)
        store.addMuteRule(CaptureMuteRule(match: .titleContains, value: "HOA"))
        let chain = ClassifierChain.forStore(store, onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
        let outcome = await chain.evaluate(candidate("Lakeview HOA board meeting"), properties: properties)
        XCTAssertEqual(outcome, .muted)
        let direct = await chain.classify(candidate("Lakeview HOA board meeting"), properties: properties)
        XCTAssertEqual(direct.evidence, ["muted"])
    }

    // MARK: Batch (review fix 2)

    private func backfill(_ count: Int, prefix: String = "Upload receipts to Stessa") -> [CaptureCandidate] {
        (0..<count).map { i in
            var c = candidate("\(prefix) #\(i)")
            c.sourceKey = "cal:batch:\(i)"
            return c
        }
    }

    @MainActor
    func testBatchOf300RunsOffTheMainThreadWithBoundedConcurrency() async throws {
        let backend = SlowFakeBackend(delay: 0.005, answer: answer(true, 0.9, category: .bookkeeping))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let progress = ProgressRecorder()
        let items = backfill(300)

        // Started from the main actor on purpose: the work must still run elsewhere.
        let task = Task { @MainActor in
            try await chain.classifyBatch(items, properties: self.properties, maxConcurrent: 2, perItemBudget: 2) { progress.record($0) }
        }

        // Main-thread heartbeat while the batch runs.
        var maxGap: TimeInterval = 0
        var last = Date()
        while progress.latest?.completed != 300 {
            try await Task.sleep(nanoseconds: 2_000_000)
            let now = Date()
            maxGap = max(maxGap, now.timeIntervalSince(last))
            last = now
            if now.timeIntervalSince(backend.startedAt) > 30 { break }
        }
        let results = try await task.value

        XCTAssertEqual(results.count, 300)
        XCTAssertEqual(backend.calls, 300)
        XCTAssertEqual(backend.mainThreadCalls, 0, "the model ran on the main thread")
        XCTAssertLessThanOrEqual(backend.maxInFlight, 2)
        XCTAssertGreaterThanOrEqual(backend.maxInFlight, 2, "expected two calls in flight")
        XCTAssertLessThan(maxGap, 0.25, "main thread stalled for \(maxGap)s")
        XCTAssertEqual(progress.values.map(\.completed), Array(1...300))
        XCTAssertTrue(progress.values.allSatisfy { $0.total == 300 })
        for case .suggest(let c) in results { XCTAssertEqual(c.tier, .onDevice) }
    }

    func testBatchCancellationStopsTheWork() async throws {
        let backend = SlowFakeBackend(delay: 0.02, answer: answer(true, 0.9))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let progress = ProgressRecorder()
        let items = backfill(300)
        let task = Task.detached {
            try await chain.classifyBatch(items, properties: self.properties, maxConcurrent: 2, perItemBudget: 2) { progress.record($0) }
        }
        while (progress.latest?.completed ?? 0) < 10 { try await Task.sleep(nanoseconds: 2_000_000) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled batch must throw")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let callsAtCancel = backend.calls
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(backend.calls, callsAtCancel, "model calls continued after cancel")
        XCTAssertLessThan(callsAtCancel, 40)
        XCTAssertLessThan(progress.latest?.completed ?? 300, 300)
    }

    func testBatchPerItemBudgetFallsBackToRules() async throws {
        // "slow" titles take 3 s; the budget is 50 ms, so they keep the rules result.
        let backend = SlowFakeBackend(delay: 0.001, slowDelay: 3, answer: answer(true, 0.95, category: .legal))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let items = backfill(4, prefix: "slow mold check") + backfill(4, prefix: "Upload receipts to Stessa")
        let started = Date()
        let results = try await chain.classifyBatch(items, properties: properties, maxConcurrent: 2, perItemBudget: 0.05)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "budget not enforced")
        let rules = RulesClassifier()
        for (i, outcome) in results.enumerated() {
            guard case .suggest(let c) = outcome else { XCTFail("item \(i) hidden: \(outcome)"); continue }
            if i < 4 {
                XCTAssertEqual(c, rules.classifySync(items[i], properties: properties), "slow item \(i) should keep rules")
            } else {
                XCTAssertEqual(c.tier, .onDevice)
            }
        }
    }

    // MARK: PCC receipt reader

    private func pcc(user: Bool = true, flag: Bool = true, system: ModelAvailability = .available) -> PCCReceiptReader {
        let defaults = UserDefaults(suiteName: "wp2-pcc-\(UUID().uuidString)")!
        let settings = PCCSettings(defaults: defaults)
        settings.isEnabled = user
        return PCCReceiptReader(settings: settings, isFlagEnabled: { flag }, system: FakePCCStatus(value: system))
    }

    private let receipt = ReceiptReadRequest(recognizedText: "ACE HARDWARE $42.10", imageData: nil, sourceKey: "rcpt:abc")

    func testPCCSettingDefaultsOn() {
        let defaults = UserDefaults(suiteName: "wp2-pcc-default-\(UUID().uuidString)")!
        XCTAssertTrue(PCCSettings(defaults: defaults).isEnabled)
    }

    func testPCCGatesFallBackToRules() async {
        let cases: [(PCCReceiptReader, ModelUnavailableReason)] = [
            (pcc(user: false), .disabledByUser),
            (pcc(flag: false), .disabledByFlag),
            (pcc(system: .unavailable(.osTooOld)), .osTooOld),
            (pcc(system: .unavailable(.deviceNotEligible)), .deviceNotEligible),
            (pcc(system: .unavailable(.systemNotReady)), .systemNotReady),
            (pcc(system: .unavailable(.quotaReached(resetDate: nil))), .quotaReached(resetDate: nil)),
            (pcc(system: .available), .notYetSupported),
        ]
        for (reader, expected) in cases {
            let outcome = await reader.read(receipt)
            XCTAssertEqual(outcome, .useRules(expected))
        }
        // The user switch wins over everything else.
        XCTAssertEqual(pcc(user: false, flag: false, system: .available).availability(), .unavailable(.disabledByUser))
    }

    func testPCCIsReceiptsOnly() {
        XCTAssertTrue(PCCReceiptReader.mayProcess(kind: .receipt))
        XCTAssertFalse(PCCReceiptReader.mayProcess(kind: .calendar))
        XCTAssertFalse(PCCReceiptReader.mayProcess(kind: .location))
        XCTAssertFalse(PCCReceiptReader.mayProcess(kind: .gmail))
    }

    func testPCCQuotaErrorMapsToRulesFallback() throws {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, *) else { throw XCTSkip("PCC types need iOS 27") }
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(.init(resetDate: reset, debugDescription: "limit"))
        XCTAssertEqual(SystemPCCStatus.reason(for: quota), .quotaReached(resetDate: reset))
        let down = PrivateCloudComputeLanguageModel.Error.serviceUnavailable(.init(debugDescription: "down"))
        XCTAssertEqual(SystemPCCStatus.reason(for: down), .serviceUnavailable)
        XCTAssertNil(SystemPCCStatus.reason(for: ModelBoom()))
        // The live status call must not crash on any device/simulator.
        _ = SystemPCCStatus().status()
        #else
        throw XCTSkip("FoundationModels not in this SDK")
        #endif
    }
}
