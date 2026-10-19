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
        let twin = RentalProperty(name: "Maple Duplex", address: "9 Elm St", propertyType: .ltr)
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

        var opts = RulesClassifier.Options()
        opts.legacyCalendarCategory = false
        let rich = await RulesClassifier(options: opts).classify(c, properties: properties)
        XCTAssertEqual(rich.category, .bookkeeping)
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
        let result = await chain.classify(candidate("Prep 1031 exchange docs"), properties: properties)
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
        let gmail = await chain2.classify(candidate("Swap air filters", kind: .gmail), properties: properties)
        XCTAssertEqual(gmail.category, .repairs)
        XCTAssertNil(gmail.propertyId)
    }

    func testModelPropertyRefMapsToId() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .repairs, ref: "p2"))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let result = await chain.classify(candidate("Mold remediation"), properties: properties)
        XCTAssertEqual(result.propertyId, maple.id)
        XCTAssertEqual(backend.requests.first?.properties.map(\.ref), ["P1", "P2", "P3"])
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
        XCTAssertTrue(prompt.contains("Event title: Fix sink"))
        XCTAssertTrue(prompt.contains("P1: Oak Street Duplex (412 Oak St)"))
        XCTAssertFalse(prompt.contains(oak.id.uuidString))
        XCTAssertTrue(OnDeviceClassifier.instructions.contains("Never give tax"))
        XCTAssertTrue(OnDeviceClassifier.instructions.contains("low confidence"))
    }

    // MARK: Bands, mutes

    func testLowConfidenceStaysVisibleAsNotSure() async {
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .deviceNotEligible)))
        let outcome = await chain.evaluate(candidate("Upload receipts to Stessa"), properties: properties, muteRules: [])
        guard case .suggest(let c) = outcome else { return XCTFail("expected suggest, got \(outcome)") }
        XCTAssertEqual(c.band, .notSure)
        XCTAssertEqual(ConfidenceBand.notSureLabel, "Not sure this is landlord work")

        let noise = await chain.evaluate(candidate("Kids soccer practice"), properties: properties, muteRules: [])
        guard case .skip = noise else { return XCTFail("expected skip, got \(noise)") }
    }

    func testMuteRulesStopClassificationBeforeAnyModel() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let byTitle = CaptureMuteRule(match: .titleContains, value: "stessa")
        let byCalendar = CaptureMuteRule(match: .containerId, value: "cal-work")
        let a = await chain.evaluate(candidate("Upload receipts to Stessa"), properties: properties, muteRules: [byTitle])
        let b = await chain.evaluate(candidate("Tenant call", containerId: "cal-work"), properties: properties, muteRules: [byCalendar])
        XCTAssertEqual(a, .muted)
        XCTAssertEqual(b, .muted)
        XCTAssertTrue(backend.requests.isEmpty)
    }

    @MainActor
    func testChainReadsMuteRulesFromTheStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wp2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SuggestionStore(userId: "u1", baseDirectory: dir)
        store.addMuteRule(CaptureMuteRule(match: .titleContains, value: "HOA"))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
        let outcome = await chain.evaluate(candidate("Lakeview HOA board meeting"), properties: properties, store: store)
        XCTAssertEqual(outcome, .muted)
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
