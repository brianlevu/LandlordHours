import XCTest
import CloudKit
@testable import LandlordHours

// MARK: - Classifier v2 (2026-10-19 real-owner calibration findings)
//
// Every example here is synthetic: one per failure pattern found on a real owner's calendar
// and inbox. The real labelled set never enters the repo.

final class ClassifierV2Tests: XCTestCase {
    // Two long-term rentals and a short-term-rental room in the home the owner lives in.
    private let oak = RentalProperty(name: "Oak Street Duplex", address: "412 Oak St, Austin, TX 78704", propertyType: .ltr)
    private let cedar = RentalProperty(name: "Cedar Flats", address: "240 San Marco Ave, Austin, TX 78746", propertyType: .ltr)
    private let home = RentalProperty(
        name: "Birchwood Suite", address: "77 Birchwood Ln, Austin, TX 78745", propertyType: .str,
        aliases: ["Sunny Garden Room in Cozy Family Home", "Ridgeline Plumbing"], isOwnerOccupied: true
    )
    private var properties: [RentalProperty] { [oak, cedar, home] }
    private let homeAddress = "77 Birchwood Ln, Austin, TX 78745"

    private func candidate(_ title: String, kind: Suggestion.Kind = .calendar, location: String? = nil) -> CaptureCandidate {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return CaptureCandidate(sourceKey: "k:\(title)", kind: kind, start: start, end: start.addingTimeInterval(3600),
                                title: title, location: location, detectedAt: start)
    }

    private func rules(_ title: String, kind: Suggestion.Kind = .gmail, location: String? = nil, properties: [RentalProperty]? = nil) -> CaptureClassification {
        RulesClassifier().classifySync(candidate(title, kind: kind, location: location), properties: properties ?? self.properties)
    }

    private func answer(_ yes: Bool, _ confidence: Double, category: ActivityCategory? = nil) -> OnDeviceAnswer {
        OnDeviceAnswer(isRentalWork: yes, category: category, propertyRef: nil, confidence: confidence, reason: "test")
    }

    // MARK: 1. Aliases

    func testAliasMatchesListingTitleDespiteNoiseWordsInIt() {
        // Old rules: "family" and "reservation" noise pushed this to 0 and hid it.
        let c = rules("Airbnb: RE: Reservation for Sunny Garden Room in Cozy Family Home, Mar 3 - 5")
        XCTAssertGreaterThanOrEqual(c.confidence, ClassifierThresholds.likely)
        XCTAssertEqual(c.propertyId, home.id)
        XCTAssertEqual(c.category, .leasing)
        XCTAssertTrue(c.evidence.contains { $0.hasPrefix("property: also called") })
    }

    func testAliasMatchesAContractorAndVotesItsTradeCategory() {
        let c = rules("Ridgeline Plumbing: Quote for parts and labor")
        XCTAssertTrue(c.isLandlordWork)
        XCTAssertEqual(c.propertyId, home.id)
        XCTAssertEqual(c.category, .repairs)
        // Without the alias the same mail has no property.
        var noAlias = home
        noAlias.aliases = []
        XCTAssertNil(rules("Ridgeline Plumbing: Quote for parts and labor", properties: [oak, cedar, noAlias]).propertyId)
    }

    func testAliasNeedsTheWholePhraseAndTiesProposeNothing() {
        XCTAssertNil(rules("Sunny garden party").propertyId, "part of an alias is not a match")
        let twin = RentalProperty(name: "Twin", address: "1 Elm Rd", propertyType: .ltr, aliases: ["Ridgeline Plumbing"])
        XCTAssertNil(rules("Ridgeline Plumbing: invoice", properties: [home, twin]).propertyId)
    }

    func testAliasesAndLivesHereReachTheModelPrompt() {
        let request = OnDeviceClassifier.request(for: candidate("Reservation request", kind: .gmail), properties: properties)
        XCTAssertEqual(request.source, "email")
        let prompt = OnDeviceClassifier.prompt(for: request)
        XCTAssertTrue(prompt.contains("Item (email): Reservation request"))
        XCTAssertTrue(prompt.contains("P3: Birchwood Suite (77 Birchwood Ln); also called: Sunny Garden Room in Cozy Family Home; Ridgeline Plumbing; the user also lives here"))
        XCTAssertTrue(prompt.contains("P1: Oak Street Duplex (412 Oak St)\n"))
    }

    // MARK: 2. "I live here"

    func testSocialEventsAtTheOwnersHomeAreNotWork() {
        for title in ["Game night", "BBQ with the neighbors", "Housewarming party", "Book club"] {
            let c = rules(title, kind: .calendar, location: homeAddress)
            XCTAssertFalse(c.isLandlordWork, title)
            XCTAssertEqual(c.band, .unlikely, title)
        }
        // The same event at a rental (not owner-occupied) is an address match on the location
        // alone (2.2): shown as "Not sure", never "Likely".
        let atRental = rules("Game night", kind: .calendar, location: "412 Oak St, Austin, TX 78704")
        XCTAssertFalse(atRental.isLandlordWork)
        XCTAssertEqual(atRental.band, .notSure)
        XCTAssertEqual(atRental.propertyId, oak.id)
    }

    func testWorkAtTheOwnersHomeStillCountsWithAWorkKeyword() {
        let c = rules("Fix leaking faucet in guest room", kind: .calendar, location: homeAddress)
        XCTAssertTrue(c.isLandlordWork)
        XCTAssertEqual(c.propertyId, home.id)
        // The address boost is weak (x0.4) for a home the owner lives in.
        let rental = RulesEngine.evaluate(text: "Fix leaking faucet 412 Oak St", properties: properties)
        let lived = RulesEngine.evaluate(text: "Fix leaking faucet 77 Birchwood Ln", properties: properties)
        XCTAssertEqual(rental.score - lived.score, RulesEngine.propertyAddressBoost * (1 - RulesEngine.ownerOccupiedFactor), accuracy: 0.0001)
    }

    func testANameThatIsJustTheStreetIsWeakForAHomeTheOwnerLivesIn() {
        XCTAssertFalse(rules("Birthday celebration at Birchwood", kind: .calendar).isLandlordWork)
        XCTAssertEqual(rules("Birchwood", kind: .calendar).band, .unlikely)
    }

    // MARK: 3. Strict address matching

    func testStreetMatchNeedsEveryStreetWord() {
        // "San" alone (a place-name prefix) used to match the two-word street.
        XCTAssertNil(RulesEngine.evaluate(text: "Parking at San Antonio airport", properties: properties).propertyId)
        XCTAssertNil(RulesEngine.evaluate(text: "Spa day San Marcos Springs Resort", properties: properties).propertyId)
        XCTAssertFalse(rules("Parking at San Antonio airport", kind: .calendar).isLandlordWork)
        // Number + every street word, or every street word alone, still match.
        XCTAssertEqual(RulesEngine.evaluate(text: "Leak at 240 San Marco", properties: properties).propertyId, cedar.id)
        XCTAssertEqual(RulesEngine.evaluate(text: "Smoke detector check at San Marco", properties: properties).propertyId, cedar.id)
        // A number with only part of the street is not an address.
        XCTAssertNil(RulesEngine.evaluate(text: "240 San Diego Ave", properties: properties).propertyId)
    }

    func testGenericStreetWordsAloneNeverMatch() {
        let parts = RulesEngine.addressParts("240 San Marco Ave, Austin, TX")
        XCTAssertEqual(parts.streetWords, ["san", "marco"])
        XCTAssertEqual(RulesEngine.addressParts("2777 4th St, Austin").streetWords, ["4th"])
        let lake = RentalProperty(name: "Shore House", address: "9 Lake St, Austin, TX", propertyType: .ltr)
        XCTAssertNil(RulesEngine.evaluate(text: "Lake day with kids", properties: [lake]).propertyId)
        XCTAssertNil(RulesEngine.evaluate(text: "Ave Maria concert", properties: [lake]).propertyId)
        XCTAssertEqual(RulesEngine.evaluate(text: "Plumber at 9 Lake", properties: [lake]).propertyId, lake.id)
    }

    func testPersonNameShowingWithTheAddressAsLocation() {
        // 2.2: the address is the only evidence, so this is "Not sure" (shown), never "Likely".
        let c = rules("Jordan Lee and Pat", kind: .calendar, location: "240 San Marco Ave, Austin, TX 78746")
        XCTAssertFalse(c.isLandlordWork)
        XCTAssertEqual(c.band, .notSure)
        XCTAssertEqual(c.propertyId, cedar.id)
    }

    // MARK: 4. Platform and store names

    func testPlatformNameAloneIsNotWorkButHostActionsAre() {
        for title in ["Airbnb: Set up discounts for the fall season", "Vrbo: Increase bookings with powerful promotions",
                      "Airbnb: Lisbon stays you should see", "Vrbo: Your password was updated",
                      "Airbnb: Your security code is 482910", "Vrbo: Webinar - pricing tips for hosts",
                      "Airbnb: Your reservation in Denver is confirmed", "Vrbo: Host Updates: March"] {
            XCTAssertLessThan(rules(title).confidence, ClassifierThresholds.likely, title)
            XCTAssertEqual(rules(title).band, .unlikely, title)
        }
        XCTAssertLessThan(rules("Airbnb").confidence, ClassifierThresholds.likely, "a platform name alone")
        for title in ["Airbnb: Reminder: 5 hours left to reply to Dana's reservation request",
                      "Vrbo: Payout sent for your stay", "Airbnb: Write a review for Sam",
                      "Vrbo: Tax form required for payments", "Vrbo: Your property is live on Vrbo"] {
            let c = rules(title)
            XCTAssertTrue(c.isLandlordWork, title)
            XCTAssertEqual(c.propertyId, home.id, "the only short-term rental: \(title)")
        }
        XCTAssertEqual(rules("Airbnb: Write a review for Sam").category, .management)
        XCTAssertEqual(rules("Vrbo: Payout sent for your stay").category, .bookkeeping)
        XCTAssertEqual(rules("Airbnb: Reminder: 5 hours left to reply to Dana's reservation request").category, .leasing)
    }

    func testStoreNameNeedsAPurchase() {
        XCTAssertEqual(rules("Home Depot: 20% off patio furniture this weekend").band, .unlikely)
        XCTAssertEqual(rules("Lowe's: Deals of the week on grills").band, .unlikely)
        XCTAssertLessThan(rules("Home Depot").confidence, ClassifierThresholds.likely)
        let receipt = rules("Home Depot: Your receipt for order 1234")
        XCTAssertTrue(receipt.isLandlordWork)
        XCTAssertTrue(receipt.evidence.contains("pair: store + purchase"))
    }

    // MARK: 5. Mailing lists and newsletters

    func testMailingListsAndNewslettersArePenalised() {
        for title in ["Sam via Neighbors: [maple-neighbors] Anyone know a good plumber?",
                      "Parent group: [oakhill-parents] Contractor recommendations for a deck",
                      "City Planning: Permit center newsletter - new fees",
                      "Neighborhood Digest: roof repair question and 4 more posts",
                      "HomeFinder: New listings near you and 12 more updates",
                      "Tax Helper Co: Newsletter - five tips before you file"] {
            let c = rules(title)
            XCTAssertFalse(c.isLandlordWork, title)
            XCTAssertEqual(c.band, .unlikely, title)
        }
        XCTAssertTrue(RulesEngine.hasMailingListTag("[list] hi"))
        XCTAssertFalse(RulesEngine.hasMailingListTag("Vrbo 123 [ ref ]"), "a spaced bracket is not a list tag")
        // The list name never matches a property.
        let maple = RentalProperty(name: "Maple Cottage", address: "88 Maple Ave", propertyType: .ltr)
        XCTAssertNil(RulesEngine.evaluate(text: "[maple-neighbors] lost cat", properties: [maple], isEmail: true).propertyId)
    }

    /// Review fix: list tags and marketing/account words are email-only. On a calendar they are
    /// ordinary words, and "party" is whole-word.
    func testCalendarTitlesAreNotHitByEmailNegatives() {
        let plumber = rules("[Oak] Plumber", kind: .calendar)
        XCTAssertTrue(plumber.isLandlordWork, "[Oak] Plumber")
        XCTAssertFalse(plumber.evidence.contains("not landlord: mailing list"))
        XCTAssertEqual(plumber.propertyId, oak.id, "the bracketed name still names the property on a calendar")

        let feedback = rules("Tenant feedback", kind: .calendar)
        XCTAssertTrue(feedback.isLandlordWork, "Tenant feedback")
        XCTAssertFalse(feedback.evidence.contains("not landlord: feedback"))

        let inspection = rules("Third party inspection", kind: .calendar)
        XCTAssertNotEqual(inspection.band, .unlikely, "Third party inspection stays visible")
        XCTAssertTrue(inspection.evidence.contains("keyword: third party"), "\"third party\" cancels \"party\"")
        XCTAssertFalse(rules("Partyka roof repair", kind: .calendar).evidence.contains("not landlord: party"))

        // The same words still count against email.
        XCTAssertTrue(rules("Vrbo: Your feedback is important to us").evidence.contains("not landlord: feedback"))
        XCTAssertTrue(rules("Neighbors: [oak-list] plumber?").evidence.contains("not landlord: mailing list"))
        // Social words are not email-only.
        XCTAssertFalse(rules("Housewarming party", kind: .calendar, location: homeAddress).isLandlordWork)
    }

    func testContractIsWholeWordSoContractorCountsOnce() {
        let verdict = RulesEngine.evaluate(text: "Contractor walkthrough", properties: [])
        XCTAssertFalse(verdict.evidence.contains("keyword: contract"))
        XCTAssertTrue(verdict.evidence.contains("keyword: contractor"))
    }

    func testOtherSensesOfTopicWords() {
        XCTAssertFalse(rules("Win a car rental for the weekend").isLandlordWork)
        XCTAssertFalse(rules("Expert call - rent industry trends", kind: .calendar).isLandlordWork)
    }

    // MARK: 6. Rental tax

    func testRentalTaxKeywords() {
        let cases: [(String, ActivityCategory)] = [
            ("Cost segregation study kickoff call", .bookkeeping),
            ("Cost seg report review", .bookkeeping),
            ("Update depreciation schedule for the rentals", .bookkeeping),
            ("Send 1099s to contractors", .bookkeeping),
            ("CPA: Schedule E draft for the duplex", .bookkeeping),
            ("Pay property tax", .bookkeeping),
            ("Agent Co: Landlord insurance renewal quote", .insurance),
        ]
        for (title, category) in cases {
            let c = rules(title)
            XCTAssertTrue(c.isLandlordWork, title)
            XCTAssertEqual(c.category, category, title)
        }
    }

    // MARK: 8. "Not sure" band

    func testNotSureBandNeedsScoreOrPropertyOrConfidentModel() async {
        // One weak keyword (score < 1.5) no longer reaches the inbox.
        for title in ["Supplies", "Window", "Estimate", "Renew", "Tour", "Upload receipt"] {
            XCTAssertEqual(rules(title, kind: .calendar).band, .unlikely, title)
        }
        // Score >= 1.5 or a property match: "Not sure".
        XCTAssertEqual(rules("Check for mold", kind: .calendar).band, .notSure)
        XCTAssertEqual(rules("Lunch near Oak Street Duplex", kind: .calendar).band, .notSure)

        // A model "yes" rescues an item into "Not sure" only at confidence >= 0.5.
        let weakYes = ClassifierChain(onDevice: OnDeviceClassifier(backend: FakeOnDeviceBackend(answer: answer(true, 0.45))))
        let strongYes = ClassifierChain(onDevice: OnDeviceClassifier(backend: FakeOnDeviceBackend(answer: answer(true, 0.6))))
        let title = "Prep paperwork for Friday"
        let a = await weakYes.classify(candidate(title), properties: properties)
        let b = await strongYes.classify(candidate(title), properties: properties)
        XCTAssertEqual(a.band, .unlikely)
        XCTAssertTrue(a.evidence.contains { $0.hasPrefix("model: weak yes") })
        XCTAssertEqual(b.band, .notSure)
        XCTAssertEqual(ClassifierThresholds.likely, 0.60, "the likely threshold stays at 0.60")
    }

    // MARK: 9. Email is rules-only; calendar keeps the 1.x category

    func testEmailNeverReachesTheModel() async throws {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.99, category: .investing))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let email = candidate("Accountant: question about the rentals", kind: .gmail)
        let viaChain = await chain.classify(email, properties: properties)
        XCTAssertEqual(viaChain, RulesClassifier().classifySync(email, properties: properties))
        XCTAssertEqual(viaChain.tier, .rules)
        _ = try await chain.classifyBatch([email, candidate("Vrbo: Payout sent", kind: .gmail)], properties: properties)
        XCTAssertTrue(backend.requests.isEmpty, "Gmail stays rules-only until the v2 prompt and aliases are validated")
        // Calendar still asks the model.
        _ = await chain.classify(candidate("Prep paperwork for Friday"), properties: properties)
        XCTAssertEqual(backend.requests.count, 1)
    }

    func testCalendarKeeps1xCategoryForEveryV2Pattern() async {
        let backend = FakeOnDeviceBackend(answer: answer(true, 0.9, category: .contractNegotiation))
        let chain = ClassifierChain(onDevice: OnDeviceClassifier(backend: backend))
        let service = CalendarImportService.shared
        let titles = ["Airbnb: Reservation request for Sunny Garden Room in Cozy Family Home", "Ridgeline Plumbing quote",
                      "Cost segregation study kickoff call", "Jordan Lee and Pat", "Guest turnover cleaning",
                      "Update depreciation schedule", "Vrbo payout", "BBQ with the neighbors"]
        for title in titles {
            let c = await chain.classify(candidate(title, location: homeAddress), properties: properties)
            XCTAssertEqual(c.category, service.categorizeEvent(title: title.lowercased()), title)
        }
        XCTAssertFalse(backend.requests.isEmpty)
    }

    // MARK: Migration safety

    func testOldPropertyJSONDecodesWithDefaults() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","address":"1 Main St","propertyType":"LTR","createdAt":0}
        """
        let decoder = JSONDecoder()
        let p = try decoder.decode(RentalProperty.self, from: Data(json.utf8))
        XCTAssertEqual(p.aliases, [])
        XCTAssertFalse(p.isOwnerOccupied)
        XCTAssertEqual(p.modifiedAt, p.createdAt)
    }

    func testNewFieldsRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(home)
        let back = try JSONDecoder().decode(RentalProperty.self, from: data)
        XCTAssertEqual(back, home)
        XCTAssertEqual(back.aliases, home.aliases)
        XCTAssertTrue(back.isOwnerOccupied)
    }

    func testCleanedAliasesTrimsAndDedupes() {
        XCTAssertEqual(RentalProperty.cleanedAliases(["  Sunny Room ", "", "sunny room", "Vendor", "   "]), ["Sunny Room", "Vendor"])
    }

    func testCleanedAliasesEnforcesLimits() {
        // Under 3 characters: dropped (the matcher ignores them).
        XCTAssertEqual(RentalProperty.cleanedAliases(["ab", " x ", "abc"]), ["abc"])
        // Each name is cut to 80 characters.
        let long = String(repeating: "a", count: 120)
        XCTAssertEqual(RentalProperty.cleanedAliases([long]).first?.count, RentalProperty.aliasMaxLength)
        // At most 10 names, first ones kept.
        let many = (1...15).map { "Vendor \($0)" }
        XCTAssertEqual(RentalProperty.cleanedAliases(many), Array(many.prefix(RentalProperty.maxAliases)))
        // Applied on the way out to CloudKit and back.
        var p = oak
        p.aliases = many + ["no"]
        let back = CloudKitSyncService.property(from: CloudKitSyncService.record(for: p, zoneID: zone, appUserId: nil))
        XCTAssertEqual(back?.aliases.count, RentalProperty.maxAliases)
    }

    private let zone = CKRecordZone.ID(zoneName: "LandlordHoursZone", ownerName: CKCurrentUserDefaultName)

    func testNewFieldsRoundTripThroughCloudKit() throws {
        let record = CloudKitSyncService.record(for: home, zoneID: zone, appUserId: "u")
        for key in record.allKeys() { XCTAssertNotNil(record[key], "\(key) written as nil") }
        XCTAssertEqual(record[CloudKitSyncService.PropertyField.aliases] as? [String], home.aliases)
        let back = try XCTUnwrap(CloudKitSyncService.property(from: record))
        XCTAssertEqual(back.id, home.id)
        XCTAssertEqual(back.aliases, home.aliases)
        XCTAssertTrue(back.isOwnerOccupied)
        XCTAssertEqual(back.propertyType, .str)
    }

    func testPropertyFieldsAreAlwaysWrittenAndNeverNil() throws {
        let record = CloudKitSyncService.record(for: oak, zoneID: zone, appUserId: nil)
        let keys = Set(record.allKeys())
        for field in CloudKitSyncService.PropertyField.all {
            XCTAssertTrue(keys.contains(field), "\(field) is always sent")
        }
        XCTAssertNil(record["appUserId"])
        for key in record.allKeys() { XCTAssertNotNil(record[key], "\(key) written as nil") }
        for key in record.changedKeys() { XCTAssertNotNil(record[key], "\(key) changed to nil") }
    }

    /// Clearing must sync: set an alias and "I live here", then clear both.
    func testClearingAliasesAndLivesHereIsPushed() throws {
        var p = oak
        p.aliases = ["Ridgeline Plumbing"]
        p.isOwnerOccupied = true
        let set = CloudKitSyncService.record(for: p, zoneID: zone, appUserId: nil)
        XCTAssertEqual(set[CloudKitSyncService.PropertyField.aliases] as? [String], ["Ridgeline Plumbing"])
        XCTAssertEqual(set[CloudKitSyncService.PropertyField.isOwnerOccupied] as? Int64, 1)

        p.aliases = []
        p.isOwnerOccupied = false
        let cleared = CloudKitSyncService.record(for: p, zoneID: zone, appUserId: nil)
        XCTAssertEqual(cleared[CloudKitSyncService.PropertyField.aliases] as? [String], [])
        XCTAssertEqual(cleared[CloudKitSyncService.PropertyField.aliasCount] as? Int64, 0)
        XCTAssertEqual(cleared[CloudKitSyncService.PropertyField.isOwnerOccupied] as? Int64, 0)
        XCTAssertTrue(cleared.changedKeys().contains(CloudKitSyncService.PropertyField.aliasCount))
        XCTAssertTrue(cleared.changedKeys().contains(CloudKitSyncService.PropertyField.isOwnerOccupied))
        let back = try XCTUnwrap(CloudKitSyncService.property(from: cleared))
        XCTAssertEqual(back.aliases, [])
        XCTAssertFalse(back.isOwnerOccupied)

        // The server may drop an empty list; a stale list with aliasCount 0 still reads as cleared.
        cleared[CloudKitSyncService.PropertyField.aliases] = ["Stale"]
        XCTAssertEqual(CloudKitSyncService.property(from: cleared)?.aliases, [])
    }

    func testPropertyRecordWrittenBy11DecodesWithDefaults() throws {
        let record = CKRecord(recordType: "Property", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        record["name"] = "Old"
        record["address"] = "1 Main St"
        record["propertyType"] = PropertyType.ltr.rawValue
        record["createdAt"] = Date()
        record["modifiedAt"] = Date()
        let p = try XCTUnwrap(CloudKitSyncService.property(from: record))
        XCTAssertEqual(p.aliases, [])
        XCTAssertFalse(p.isOwnerOccupied)
    }
}
