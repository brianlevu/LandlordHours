import XCTest
@testable import LandlordHours

// MARK: - Calibration harness
//
// Runs the classifier over Tests/Fixtures/calibration.json (hand-labelled titles) and reports
// accuracy plus a threshold sweep. The committed `ClassifierThresholds` must keep meeting
// their targets; when the table or labels change, read the sweep in the test log
// ("CALIBRATION" lines) and recommit the thresholds.
//
// The fixture has three splits: "tuning" (the keyword table was shaped against it, so its
// numbers are optimistic), "holdout" (written after the table was frozen — the honest
// number) and "realworld" (classifier v2: synthetic items, one or more per failure pattern
// found on a real owner's calendar and inbox; the real data never enters the repo).

struct CalibrationFixture: Decodable {
    struct Property: Decodable {
        let key: String
        let name: String
        let address: String
        /// "str" or "ltr" (default ltr).
        var type: String?
        var ownerOccupied: Bool?
        var aliases: [String]?
    }
    struct Item: Decodable {
        let title: String
        let landlord: Bool
        let category: String?
        let property: String?
        let split: String
        /// "calendar" or "email" (realworld split); the email title is "sender: subject".
        var kind: String?
        var location: String?
    }

    let properties: [Property]
    let items: [Item]

    static func load() throws -> CalibrationFixture {
        let bundle = Bundle(for: CalibrationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "calibration", withExtension: "json"), "calibration.json missing from test bundle")
        return try JSONDecoder().decode(CalibrationFixture.self, from: Data(contentsOf: url))
    }

    /// Fixture keys → app properties (stable ids per run).
    func rentalProperties() -> [String: RentalProperty] {
        Dictionary(uniqueKeysWithValues: properties.map {
            ($0.key, RentalProperty(name: $0.name, address: $0.address, propertyType: $0.type == "str" ? .str : .ltr,
                                    aliases: $0.aliases ?? [], isOwnerOccupied: $0.ownerOccupied ?? false))
        })
    }

    static func category(named name: String?) -> ActivityCategory? {
        guard let name else { return nil }
        let map: [String: ActivityCategory] = [
            "repairs": .repairs, "management": .management, "leasing": .leasing, "bookkeeping": .bookkeeping,
            "legal": .legal, "insurance": .insurance, "travel": .travel, "renovations": .renovations,
            "investing": .investing, "financing": .financing, "contractNegotiation": .contractNegotiation,
        ]
        return map[name]
    }
}

struct CalibrationScore {
    var total = 0
    var correct = 0
    var truePositive = 0
    var falsePositive = 0
    var falseNegative = 0
    var visibleLandlord = 0
    var landlord = 0
    var categoryCorrect = 0
    var propertyCorrect = 0

    var accuracy: Double { Double(correct) / Double(max(total, 1)) }
    var precision: Double { Double(truePositive) / Double(max(truePositive + falsePositive, 1)) }
    var recall: Double { Double(truePositive) / Double(max(landlord, 1)) }
    var visibleRecall: Double { Double(visibleLandlord) / Double(max(landlord, 1)) }
    var categoryAccuracy: Double { Double(categoryCorrect) / Double(max(landlord, 1)) }
    var propertyAccuracy: Double { Double(propertyCorrect) / Double(max(landlord, 1)) }

    var summary: String {
        String(format: "n=%d acc=%.3f precision=%.3f recall=%.3f visible=%.3f category=%.3f property=%.3f",
               total, accuracy, precision, recall, visibleRecall, categoryAccuracy, propertyAccuracy)
    }
}

final class CalibrationTests: XCTestCase {
    private func candidate(_ title: String, kind: Suggestion.Kind, location: String? = nil) -> CaptureCandidate {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return CaptureCandidate(sourceKey: "cal:\(title)", kind: kind, start: start, end: start.addingTimeInterval(3600), title: title, location: location, detectedAt: start)
    }

    /// Scores `classify` on the items in `split` (nil = all). Category is the rich table
    /// category (kind .gmail avoids the 1.x calendar-category compatibility rule).
    private func score(
        _ fixture: CalibrationFixture,
        split: String?,
        likely: Double = ClassifierThresholds.likely,
        classify: (CaptureCandidate, [RentalProperty]) async -> CaptureClassification
    ) async -> CalibrationScore {
        let byKey = fixture.rentalProperties()
        let list = fixture.properties.compactMap { byKey[$0.key] }
        var s = CalibrationScore()
        for item in fixture.items where split == nil || item.split == split {
            let c = await classify(candidate(item.title, kind: .gmail, location: item.location), list)
            let saysYes = c.confidence >= likely
            s.total += 1
            if saysYes == item.landlord { s.correct += 1 }
            if saysYes && item.landlord { s.truePositive += 1 }
            if saysYes && !item.landlord { s.falsePositive += 1 }
            if !saysYes && item.landlord { s.falseNegative += 1 }
            if item.landlord {
                s.landlord += 1
                if c.band != .unlikely { s.visibleLandlord += 1 }
                if c.category == CalibrationFixture.category(named: item.category) { s.categoryCorrect += 1 }
                let expected = item.property.flatMap { byKey[$0]?.id }
                if c.propertyId == expected { s.propertyCorrect += 1 }
            }
        }
        return s
    }

    func testFixtureShape() throws {
        let fixture = try CalibrationFixture.load()
        XCTAssertGreaterThanOrEqual(fixture.items.count, 120)
        XCTAssertGreaterThanOrEqual(fixture.items.filter { !$0.landlord }.count, 40, "needs real non-landlord noise")
        XCTAssertGreaterThanOrEqual(fixture.items.filter { $0.split == "holdout" }.count, 30)
        for item in fixture.items where item.landlord {
            XCTAssertNotNil(CalibrationFixture.category(named: item.category), "unlabelled category: \(item.title)")
        }
    }

    func testRulesCalibrationAndCommittedThresholds() async throws {
        let fixture = try CalibrationFixture.load()
        let rules = RulesClassifier()
        let classify: (CaptureCandidate, [RentalProperty]) async -> CaptureClassification = { await rules.classify($0, properties: $1) }

        for split in ["tuning", "holdout", "realworld", nil] as [String?] {
            let s = await score(fixture, split: split, classify: classify)
            print("CALIBRATION rules split=\(split ?? "all") likely=\(ClassifierThresholds.likely) notSure=\(ClassifierThresholds.notSure) \(s.summary)")
        }

        // Threshold sweep over everything (for recommitting).
        var best = (threshold: 0.0, accuracy: 0.0)
        for step in 4...18 {
            let t = Double(step) * 0.05
            let s = await score(fixture, split: nil, likely: t, classify: classify)
            print(String(format: "CALIBRATION sweep likely=%.2f acc=%.3f precision=%.3f recall=%.3f", t, s.accuracy, s.precision, s.recall))
            if s.accuracy > best.accuracy { best = (t, s.accuracy) }
        }
        print(String(format: "CALIBRATION best likely=%.2f acc=%.3f (committed %.2f)", best.threshold, best.accuracy, ClassifierThresholds.likely))

        // The committed thresholds must keep meeting their targets on all data and held-out data.
        let all = await score(fixture, split: nil, classify: classify)
        let holdout = await score(fixture, split: "holdout", classify: classify)
        XCTAssertGreaterThanOrEqual(all.precision, ClassifierThresholds.targetPrecisionAtLikely)
        XCTAssertGreaterThanOrEqual(all.accuracy, ClassifierThresholds.targetAccuracyAtLikely)
        XCTAssertGreaterThanOrEqual(all.visibleRecall, ClassifierThresholds.targetVisibleRecall)
        XCTAssertGreaterThanOrEqual(holdout.accuracy, ClassifierThresholds.targetAccuracyAtLikely)
        XCTAssertGreaterThanOrEqual(holdout.precision, ClassifierThresholds.targetPrecisionAtLikely)
        XCTAssertGreaterThanOrEqual(all.propertyAccuracy, 0.9)
        // Category floors (asserted, not just printed).
        let tuning = await score(fixture, split: "tuning", classify: classify)
        XCTAssertGreaterThanOrEqual(tuning.categoryAccuracy, ClassifierThresholds.targetRulesCategoryTuning, "rules category, tuning")
        XCTAssertGreaterThanOrEqual(holdout.categoryAccuracy, ClassifierThresholds.targetRulesCategoryHoldout, "rules category, held-out")
        // Classifier v2: the synthetic real-world failure patterns (platform marketing, mailing
        // lists, social events at an owner-occupied home, street collisions, alias matches).
        let realworld = await score(fixture, split: "realworld", classify: classify)
        XCTAssertGreaterThanOrEqual(realworld.precision, ClassifierThresholds.targetPrecisionAtLikely, "real-world patterns precision")
        XCTAssertGreaterThanOrEqual(realworld.visibleRecall, ClassifierThresholds.targetVisibleRecall, "real-world patterns visible recall")
        XCTAssertGreaterThanOrEqual(realworld.propertyAccuracy, 0.9, "real-world patterns property")
        // The committed value must sit within 0.02 of the best accuracy on the sweep.
        XCTAssertGreaterThanOrEqual(all.accuracy, best.accuracy - 0.02)
        XCTAssertLessThan(ClassifierThresholds.notSure, ClassifierThresholds.likely)
    }

    /// Runs Apple's on-device model over the fixture when this simulator/device has it.
    /// Simulators use the host Mac's model, which needs Apple Intelligence on the Mac.
    func testOnDeviceModelCalibrationWhenAvailable() async throws {
        let classifier = OnDeviceClassifier.makeDefault()
        guard classifier.availability.isAvailable else {
            print("CALIBRATION on-device skipped: \(classifier.availability)")
            throw XCTSkip("On-device model unavailable here: \(classifier.availability)")
        }
        let fixture = try CalibrationFixture.load()
        let chain = ClassifierChain(onDevice: classifier)

        // Model alone: its own yes/no and category.
        let byKey = fixture.rentalProperties()
        let list = fixture.properties.compactMap { byKey[$0.key] }
        var modelCorrect = 0, modelCategory = 0, landlord = 0, answered = 0
        for item in fixture.items {
            guard let r = await classifier.classify(candidate(item.title, kind: .gmail, location: item.location), properties: list) else { continue }
            answered += 1
            if r.isRentalWork == item.landlord { modelCorrect += 1 }
            if item.landlord {
                landlord += 1
                if r.category == CalibrationFixture.category(named: item.category) { modelCategory += 1 }
            }
        }
        print(String(format: "CALIBRATION model-only answered=%d/%d acc=%.3f category=%.3f",
                     answered, fixture.items.count, Double(modelCorrect) / Double(max(answered, 1)), Double(modelCategory) / Double(max(landlord, 1))))

        // The chain only asks the model about calendar events and visits (Gmail stays rules-only),
        // so score it as calendar events: that is the production path. Category there is the 1.x
        // value by design, so read landlord/not and property from these lines.
        var chainHoldout = CalibrationScore()
        for split in ["tuning", "holdout", nil] as [String?] {
            let s = await score(fixture, split: split) { c, props in
                var cal = c
                cal.kind = .calendar
                return await chain.classify(cal, properties: props)
            }
            if split == "holdout" { chainHoldout = s }
            print("CALIBRATION chain(calendar) split=\(split ?? "all") \(s.summary)")
        }
        // A slim simulator can report the model available while the host model service is
        // unreachable (every call fails). The chain then fell back to rules above; report it.
        if answered == 0 {
            print("CALIBRATION on-device skipped: model reported available but every call failed (rules fallback used)")
            throw XCTSkip("Model reported available but no call succeeded here; chain fell back to rules")
        }
        // The model carries non-calendar category quality: assert its held-out floor.
        var heldLandlord = 0, heldCategory = 0
        for item in fixture.items where item.split == "holdout" && item.landlord {
            heldLandlord += 1
            if let r = await classifier.classify(candidate(item.title, kind: .gmail), properties: list),
               r.category == CalibrationFixture.category(named: item.category) { heldCategory += 1 }
        }
        let heldAccuracy = Double(heldCategory) / Double(max(heldLandlord, 1))
        print(String(format: "CALIBRATION model-only holdout category=%.3f", heldAccuracy))
        XCTAssertGreaterThanOrEqual(heldAccuracy, ClassifierThresholds.targetModelCategoryHoldout)
        // The model must not make shipped calendar suggestions worse than rules alone.
        let rulesHoldout = await score(fixture, split: "holdout") { c, props in
            var cal = c
            cal.kind = .calendar
            return await RulesClassifier().classify(cal, properties: props)
        }
        XCTAssertGreaterThanOrEqual(chainHoldout.precision, rulesHoldout.precision, "chain precision vs rules, held-out")
        XCTAssertGreaterThanOrEqual(chainHoldout.propertyAccuracy, rulesHoldout.propertyAccuracy - 0.05, "chain property vs rules, held-out")
        XCTAssertGreaterThanOrEqual(chainHoldout.visibleRecall, ClassifierThresholds.targetVisibleRecall)
    }
}
