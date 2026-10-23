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
        "closing documents", "appraisal", "appraisals", "appraiser", "loan application", "loan applications",
        "pre approved", "cash out refi", "mortgage preapproval", "mortgage pre approval", "mortgage quote", "mortgage rate",
        "mortgage rates",
    ]
    static let investing = [
        "deal analysis", "analyze deal", "new deal", "cap rate", "comps", "1031", "investment property",
        "potential rental", "potential property", "replacement property", "property to buy", "broker for the sale",
        "broker for a sale", "broker opinion", "bpo", "exchange accommodator", "qualified intermediary",
    ]

    /// Words that put a bare "closing" in a purchase or sale ("Closing at the title company"),
    /// not "Closing the gate".
    static let closingContext = [
        "title company", "title", "escrow", "sale", "purchase", "buyer", "buyers", "seller", "sellers", "attorney",
        "lender", "docs", "documents", "disclosure", "costs", "date", "table", "settlement",
    ]
    /// Who a purchase or sale negotiation is with. A tenant or lease negotiation stays Leasing.
    static let negotiationContext = [
        "seller", "sellers", "buyer", "buyers", "agent", "broker", "realtor", "purchase", "sale", "price", "offer",
    ]
    static let tenantContext = ["tenant", "tenants", "lease", "leases", "renewal", "rent", "guest", "applicant", "deposit"]

    // Vocabulary by concept (matched whole-word or whole-phrase after normalize; apostrophes and
    // hyphens become spaces, so "buyer's agent" is "buyer s agent"). Every group below is
    // guarded by `tenantContext`: "Offer lease renewal to tenant" stays Leasing.

    /// Offers and documents of a purchase or sale.
    static let offersAndDocuments = [
        "offer", "offers", "loi", "letter of intent", "psa", "listing agreement", "list for sale",
        "listing for sale", "put on the market", "put it on the market", "put the house on the market",
        "on the market", "sell", "selling", "sale of", "sell the", "sell my",
    ]
    /// Stages of a transaction.
    static let transactionStages = [
        "escrow", "earnest money", "under contract", "contingency", "contingencies", "due diligence",
        "inspection period", "final walk through", "final walkthrough", "title search", "title commitment",
    ]
    /// Words that need a purchase or sale around them to be a deal ("Walkthrough for the purchase").
    static let weakStages = ["walk through", "walkthrough", "inspection", "inspections", "survey", "appraisal review"]
    static let transactionContext = [
        "purchase", "buy", "buying", "buyer", "buyers", "seller", "sellers", "sale", "sell", "selling", "escrow",
        "offer", "acquisition", "closing", "listing", "contingency", "lender", "loan",
    ]
    /// Agents and brokers of a deal.
    static let dealAgents = [
        "buyer s agent", "seller s agent", "buyers agent", "sellers agent", "listing agent", "selling agent",
        "buyer agent", "seller agent", "buyer s broker", "seller s broker",
    ]
    /// Phrases that void a "contingency" ("contingency fund") or similar.
    static let notDeal = ["contingency fund", "contingency plan", "contingency budget", "contingency reserve", "tax appraisal", "tax appraisals"]
    /// More underwriting and investing vocabulary.
    static let investingExtra = ["acquisition", "acquisitions", "pro forma", "proforma", "underwrite", "underwriting a deal", "off market deal"]

    /// The non-countable category a title's deal signal forces, or nil.
    static func category(forTitle title: String) -> ActivityCategory? {
        let padded = " \(RulesEngine.normalize(title)) "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        let isPayment = isLoanPayment(padded)
        let isTenantMatter = tenantContext.contains(where: has)
        let voided = notDeal.contains(where: has)
        if contractNegotiation.contains(where: has) { return .contractNegotiation }
        let negotiates = ["negotiate", "negotiation", "negotiations", "negotiating"].contains(where: has)
        if negotiates, !isTenantMatter, negotiationContext.contains(where: has) { return .contractNegotiation }
        let lists = has("list") || has("listing") || has("listings")
        let looks = has("look at") || has("tour") || has("view")
        // Listing the user's own property for sale is selling; looking at a listing is buying.
        if has("listing agreement") || (lists && has("for sale") && !looks) { return .contractNegotiation }
        if has("underwriting") || has("underwrite"), has("deal") || has("deals") { return .investing }
        if !isPayment, !(voided && (has("appraisal") || has("appraisals"))), financing.contains(where: has) { return .financing }
        if has("closing"), closingContext.contains(where: has) { return .financing }
        if !isTenantMatter {
            // "Contingency fund" and "contingency plan" are budgeting, not a purchase contingency.
            let stages = voided ? transactionStages.filter { !$0.hasPrefix("contingenc") } : transactionStages
            if stages.contains(where: has) || (!voided && offersAndDocuments.contains(where: has)) { return .contractNegotiation }
            if weakStages.contains(where: has), transactionContext.contains(where: has) { return .contractNegotiation }
        }
        if !isTenantMatter, dealAgents.contains(where: has) { return .investing }
        if investing.contains(where: has) { return .investing }
        if !isTenantMatter, investingExtra.contains(where: has) { return .investing }
        if lists, has("look at") || has("for sale") { return .investing }
        return nil
    }

    /// "Pay the mortgage", "Record the loan payment", "autopay for the loan": paying an existing
    /// loan is bookkeeping, which counts, not a financing decision.
    static func isLoanPayment(_ padded: String) -> Bool {
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        // A new loan, a refinance, a closing or a loan application is a deal, even beside "payment"
        // ("Refinance payment estimate", "Closing costs and first mortgage payment").
        if dealLoanWords.contains(where: has) { return false }
        if has("monthly mortgage") { return true }
        let paymentWord = ["pay", "pays", "paid", "paying", "payment", "payments", "autopay", "installment", "installments"].contains(where: has)
        let debt = ["mortgage", "mortgages", "loan", "loans", "heloc", "note", "hoa", "property tax", "property taxes"].contains(where: has)
        return paymentWord && debt
    }

    /// Words that make a loan title a deal (non-countable) even when a payment word is beside them.
    static let dealLoanWords = [
        "refinance", "refinancing", "refi", "new loan", "new mortgage", "loan application", "loan applications",
        "mortgage application", "application", "applications", "closing", "close", "pre approval", "preapproval",
        "pre approved", "cash out", "rate lock", "origination", "underwriting", "underwriter", "lender", "lenders",
        "mortgage broker", "quote", "apply", "applying",
    ]

    /// The category to propose: a deal signal's non-countable category, else `category`. A loan
    /// or mortgage payment that came out as Financing (keyword table or model) is Bookkeeping.
    static func apply(_ category: ActivityCategory?, title: String) -> ActivityCategory? {
        if let deal = Self.category(forTitle: title) { return deal }
        let padded = " \(RulesEngine.normalize(title)) "
        // Whatever category came in (Financing from the table, Management from the calendar).
        if isLoanPayment(padded) { return .bookkeeping }
        // The keyword table reads any "closing" as Financing; with no deal word beside it
        // ("closing the pool", "closing up for winter") it is ordinary upkeep.
        if category == .financing, padded.contains(" closing ") { return .management }
        return category
    }
}
