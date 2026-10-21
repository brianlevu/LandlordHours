import Foundation

// MARK: - Rules classifier (tier .rules)
//
// Always available, every OS the app supports (iOS 17+), no model, no network. The main path
// for most users: Apple's model covers only Apple Intelligence devices.
struct RulesClassifier: CaptureClassifier {
    /// Calendar suggestions ALWAYS keep the category 1.x's calendar import computes
    /// (`CalendarImportService.categorizeEvent`), so a 1.1 device recognises a 2.0-confirmed
    /// event as already imported (AppViewModel.isDuplicateCalendarEntry compares category, hours
    /// and start). Not configurable: only non-calendar sources get the table/model category.
    static func usesLegacyCategory(_ kind: Suggestion.Kind) -> Bool { kind == .calendar }

    struct Options: Equatable {
        /// With exactly one property, a likely landlord item is proposed for it.
        var defaultToOnlyProperty = true
    }

    var options = Options()

    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification {
        classifySync(candidate, properties: properties)
    }

    func classifySync(_ candidate: CaptureCandidate, properties: [RentalProperty]) -> CaptureClassification {
        let text = [candidate.title, candidate.location ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let verdict = RulesEngine.evaluate(text: text, properties: properties, isEmail: candidate.kind == .gmail)
        let isLandlordWork = verdict.confidence >= ClassifierThresholds.likely

        var evidence = verdict.evidence
        var confidence = verdict.confidence
        if verdict.hasLandlordSignal {
            // Landlord-signal items are never hidden: at worst they are "Not sure".
            evidence.append(ClassifierThresholds.landlordSignalEvidence)
            confidence = max(confidence, ClassifierThresholds.notSure)
        }
        var propertyId = verdict.propertyId
        if propertyId == nil, options.defaultToOnlyProperty, isLandlordWork, properties.count == 1 {
            propertyId = properties[0].id
            evidence.append("default property: only property")
        }

        let category: ActivityCategory?
        if Self.usesLegacyCategory(candidate.kind) {
            category = LegacyCalendarCategory.category(forTitle: candidate.title)
        } else {
            category = verdict.category ?? (verdict.hasLandlordSignal ? .management : nil)
        }
        let finalCategory = DealSignal.apply(category, title: candidate.title)

        let (hours, basis) = Self.hours(for: candidate)
        return CaptureClassification(
            isLandlordWork: isLandlordWork,
            confidence: confidence,
            propertyId: propertyId,
            category: finalCategory,
            hours: hours,
            hoursBasis: basis,
            tier: .rules,
            evidence: evidence
        )
    }

    /// Calendar: the scheduled length, as 1.x computed it (raw hours, under 24). Location:
    /// the dwell. Receipts never guess hours.
    static func hours(for candidate: CaptureCandidate) -> (Double?, Suggestion.HoursBasis) {
        guard candidate.kind != .receipt, let end = candidate.end else { return (nil, .none) }
        let hours = end.timeIntervalSince(candidate.start) / 3600
        guard hours > 0, hours < 24 else { return (nil, .none) }
        return (hours, candidate.kind == .location ? .dwellCap : .scheduled)
    }
}

// MARK: - Deal signals (non-countable categories)
//
// Buying, selling, financing and negotiating a property are investor activities: they never
// count toward the 750-hour/REPS tests or material participation (`ActivityCategory.countsForREPS`).
// A suggestion for one must never carry a countable category, so a deal signal in the title
// wins over the 1.x calendar category, the keyword table and the model (verifier 2026-10-21:
// "Counteroffer on the Elm fourplex" and refinance/closing titles came out as Property
// Management, which counts). Calendar parity with 1.x is deliberately broken for these titles
// only: a 1.1 device may re-import such an event once as Management, which is the lesser harm.
enum DealSignal {
    /// Checked in this order; the first hit wins.
    static let contractNegotiation = [
        "counteroffer", "counter offer", "offer on", "make an offer", "submit offer", "submit an offer",
        "purchase agreement", "purchase contract", "sale agreement", "sales agreement", "sale contract",
        "sales contract", "purchase and sale", "earnest money", "negotiate purchase", "negotiate sale",
        "negotiate the purchase", "negotiate the sale", "sale price", "purchase price", "under contract",
    ]
    static let financing = [
        "refinance", "refinancing", "refi", "heloc", "lender", "lenders", "loan", "loans", "dscr",
        "pre approval", "preapproval", "rate lock", "cash out", "underwriting", "underwriter",
        "mortgage broker", "mortgage application", "closing on", "closing docs", "closing date",
        "closing documents", "appraisal", "appraiser",
    ]
    static let investing = [
        "deal analysis", "analyze deal", "new deal", "cap rate", "comps", "1031", "investment property",
        "potential rental", "potential property", "replacement property", "property to buy",
    ]

    /// The non-countable category a title's deal signal forces, or nil.
    static func category(forTitle title: String) -> ActivityCategory? {
        let text = RulesEngine.normalize(title)
        let padded = " \(text) "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        // Paying a loan or mortgage is bookkeeping, not a financing decision.
        let isPayment = has("payment") || has("pay") || has("autopay")
        if contractNegotiation.contains(where: has) { return .contractNegotiation }
        if !isPayment, financing.contains(where: has) { return .financing }
        if investing.contains(where: has) { return .investing }
        // Looking at a listing (not posting or refreshing one) is weighing a purchase.
        if has("listing") || has("listings"), has("look at") || has("for sale") {
            return .investing
        }
        return nil
    }

    /// The category to propose: a deal signal's non-countable category, else `category`.
    static func apply(_ category: ActivityCategory?, title: String) -> ActivityCategory? {
        Self.category(forTitle: title) ?? category
    }
}
