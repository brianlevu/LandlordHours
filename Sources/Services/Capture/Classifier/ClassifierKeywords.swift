import Foundation

// MARK: - The one keyword table
//
// Consolidates the keyword knowledge that 1.x spread over `CalendarImportService.categorizeEvent`
// / `propertyKeywords` and `AITimeEntryService`'s category patterns, plus negative "noise"
// signals for the everyday calendar (dentist, soccer, standups) that 1.x never needed because
// it only scanned for positives. Those two files are left untouched; this table is what the
// 2.0 classifier reads.
//
// Each signal has:
// - `landlord`: how much it moves the "is this rental work?" score (negative = noise);
// - `category` + `categoryWeight`: which ActivityCategory it votes for, and how hard.
// Matching runs on normalized text (lowercased, diacritics folded, punctuation → spaces) and is
// word-prefix by default ("plumb" matches "plumber"), or whole-word when `wholeWord` is set
// ("dr" must not match "drive").

struct ClassifierSignal: Equatable {
    let phrase: String
    let landlord: Double
    let category: ActivityCategory?
    let categoryWeight: Double
    let wholeWord: Bool
    let role: Role
    /// Applies to email (.gmail) only: marketing and account words are ordinary on a calendar.
    let emailOnly: Bool

    /// How a signal combines with others (classifier v2).
    enum Role: Equatable, Hashable {
        case general
        /// A rental platform name (airbnb, vrbo): weak alone, scores next to a host action.
        case platform
        /// A host action (reservation request, guest, payout): pairs with a platform.
        case hostAction
        /// A hardware store: weak alone, scores next to a purchase word.
        case store
        /// A purchase word (order, receipt, invoice): pairs with a store.
        case purchase
    }

    init(_ phrase: String, _ landlord: Double, _ category: ActivityCategory? = nil, categoryWeight: Double? = nil, wholeWord: Bool = false, role: Role = .general, emailOnly: Bool = false) {
        self.phrase = phrase
        self.landlord = landlord
        self.category = category
        self.categoryWeight = categoryWeight ?? max(landlord, 0)
        self.wholeWord = wholeWord
        self.role = role
        self.emailOnly = emailOnly
    }
}

enum ClassifierKeywords {
    // swiftlint:disable comma
    static let signals: [ClassifierSignal] = [
        // Leasing & tenant relations
        .init("tenant",             2.5, .leasing, categoryWeight: 1),
        .init("landlord",           2.5),
        .init("lease",              2.5, .leasing),
        .init("leasing",            2.5, .leasing),
        .init("sublease",           2.5, .leasing),
        .init("rent",               2.5, .leasing, wholeWord: true),
        .init("rents",              2.5, .leasing, wholeWord: true),
        .init("rental",             2.5, .leasing, categoryWeight: 0.5),
        .init("rentals",            2.5, .leasing, categoryWeight: 0.5),
        .init("renter",             2.5, .leasing),
        .init("rent increase",      0.5, .leasing, categoryWeight: 3),
        .init("showing",            2.5, .leasing),
        .init("open house",         1.5, .leasing),
        .init("applicant",          2.0, .leasing),
        .init("application",        0.8, .leasing),
        .init("screen",             1.0, .leasing),
        .init("background check",   1.5, .leasing),
        .init("listing",            1.5, .leasing),
        .init("zillow",             2.0, .leasing),
        .init("apartments com",     2.5, .leasing),
        .init("move in",            2.5, .leasing),
        .init("move out",           2.5, .leasing, categoryWeight: 0.5),
        .init("walkthrough",        2.0, .leasing, categoryWeight: 0.5),
        .init("walk through",       2.0, .leasing, categoryWeight: 0.5),
        .init("vacan",              2.0, .leasing, categoryWeight: 1),
        .init("deposit",            1.5, .leasing),
        .init("renew",              0.8, .leasing),
        .init("addendum",           1.5, .leasing),
        .init("inquir",             0.5, .leasing, role: .hostAction),
        .init("mailbox key",        1.0, .leasing),
        .init("complaint",          0.8, .leasing),
        // Platforms are weak alone (their marketing and account mail outnumber host work);
        // they score next to a host action. Guest bookings, requests, inquiries and messages
        // are leasing (guest relations = tenant relations); reviews and listing admin are
        // management; payouts and tax forms are bookkeeping.
        .init("vrbo",               1.2, .leasing, categoryWeight: 0.5, role: .platform),
        .init("airbnb",             1.2, .leasing, categoryWeight: 0.5, role: .platform),
        .init("homeaway",           1.2, .leasing, categoryWeight: 0.5, role: .platform),
        .init("reservation request", 3.0, .leasing, categoryWeight: 3, role: .hostAction),
        .init("booking request",    2.0, .leasing, categoryWeight: 3, role: .hostAction),
        .init("reservation confirmed", 2.0, .leasing, categoryWeight: 3, role: .hostAction),
        .init("reservation for",    1.5, .leasing, categoryWeight: 3, role: .hostAction),
        .init("reservation at",     1.5, .leasing, categoryWeight: 3, role: .hostAction),
        .init("inquiry for",        1.0, .leasing, categoryWeight: 3, role: .hostAction),
        .init("guest",              0.8, .leasing, categoryWeight: 1, role: .hostAction),
        .init("check in",           0.5, .leasing, role: .hostAction),
        .init("review for",         1.5, .management, categoryWeight: 3, role: .hostAction),
        .init("to review",          1.0, .management, categoryWeight: 3, role: .hostAction),
        .init("review from guest",  1.5, .management, categoryWeight: 3, role: .hostAction),
        .init("payout",             1.5, .bookkeeping, categoryWeight: 3, role: .hostAction),
        .init("hosting",            1.0, .management, categoryWeight: 2, role: .hostAction),
        .init("co host",            1.5, .management, categoryWeight: 2, role: .hostAction),
        .init("property is live",   1.5, .leasing, categoryWeight: 3, role: .hostAction),
        .init("tax form",           1.5, .bookkeeping, categoryWeight: 3, role: .hostAction),
        .init("str",                1.5, .management, wholeWord: true),
        .init("guest checkout",     1.5, .management, categoryWeight: 3),
        .init("section 8",          2.5, .legal, categoryWeight: 3),

        // Property management
        .init("collect rent",       0.5, .management, categoryWeight: 6),
        .init("rent collection",    0.5, .management, categoryWeight: 6),
        .init("rent payment",       0.5, .management, categoryWeight: 6),
        .init("property manager",   2.5, .management, categoryWeight: 3),
        .init("property management", 2.5, .management, categoryWeight: 3),
        .init("manage",             1.0, .management),
        .init("maintenance request", 2.0, .management, categoryWeight: 4),
        .init("pest",               1.5, .repairs),
        .init("exterminat",         1.5, .repairs),
        .init("landscap",           1.2, .repairs),
        .init("lawn",               0.8, .repairs),
        .init("mow",                0.8, .repairs),
        .init("snow removal",       1.2, .repairs),
        .init("turnover",           2.0, .repairs, categoryWeight: 2.5, role: .hostAction),
        .init("clean",              0.6, .repairs, categoryWeight: 1.5),
        .init("rekey",              2.0, .repairs),
        .init("locksmith",          1.5, .repairs),
        .init("smoke detector",     1.2, .repairs, categoryWeight: 2),
        .init("smoke alarm",        1.2, .repairs, categoryWeight: 2),
        .init("air filter",         1.2, .repairs, categoryWeight: 2),
        .init("filters",            0.6, .repairs),
        .init("dishwasher",         1.2, .repairs),
        .init("draining",           0.8, .repairs),
        .init("mold",               1.5, .repairs),
        .init("fire inspection",    1.5, .legal, categoryWeight: 3),
        .init("inspector",          1.2, .legal, categoryWeight: 2),
        .init("rental registration", 2.0, .legal, categoryWeight: 3),
        .init("late payment",       1.5, .management, categoryWeight: 3),
        .init("late fee",           1.5, .management, categoryWeight: 3),
        .init("pm",                 1.0, .management, categoryWeight: 2, wholeWord: true),
        .init("board meeting",      0.5, .management, categoryWeight: 2),
        .init("inspect",            1.5, .management),
        .init("hoa",                1.2, .management, wholeWord: true),
        .init("utility transfer",   1.0, .management, categoryWeight: 2),
        .init("utilities",          0.6, .management),
        .init("restock",            0.6, .management),
        // Scheduling and hand-offs are management even when the job is upkeep.
        .init("schedule",           0.0, .management, categoryWeight: 3),
        .init("keys",               0.5, .management, categoryWeight: 2),

        // Repairs & maintenance
        .init("repair",             1.5, .repairs, categoryWeight: 2),
        .init("fix",                0.8, .repairs, categoryWeight: 1.5),
        .init("broke",              0.8, .repairs),
        .init("leak",               1.5, .repairs),
        .init("plumb",              2.0, .repairs),
        .init("electrician",        2.0, .repairs),
        .init("electrical",         1.2, .repairs),
        .init("hvac",               2.0, .repairs),
        .init("furnace",            1.5, .repairs),
        .init("heater",             1.2, .repairs),
        .init("handyman",           2.5, .repairs),
        .init("drywall",            1.5, .repairs),
        .init("patch",              0.8, .repairs),
        .init("paint",              0.8, .repairs, categoryWeight: 1.5),
        .init("roof",               1.5, .repairs),
        .init("gutter",             1.2, .repairs, categoryWeight: 2),
        .init("toilet",             1.2, .repairs),
        .init("disposal",           1.2, .repairs),
        .init("appliance",          1.2, .repairs),
        .init("window",             0.4, .repairs),
        .init("maintenance",        1.5, .repairs),
        .init("tune up",            1.0, .repairs),
        .init("estimate",           0.6, .repairs),

        // Renovations & improvements
        .init("remodel",            1.5, .renovations, categoryWeight: 3),
        .init("renovat",            1.5, .renovations, categoryWeight: 3),
        .init("flooring",           1.2, .renovations),
        .init("install",            0.6, .renovations),
        .init("contractor",         2.0, .renovations, categoryWeight: 1),
        .init("bids",               1.0, .renovations),
        .init("quotes",             0.8, .renovations),
        .init("fence",              0.8, .renovations),
        .init("replacement",        0.5, .renovations, categoryWeight: 0.3),
        .init("deck",               0.5, .renovations),

        // Bookkeeping & financial
        .init("bookkeep",           2.5, .bookkeeping),
        .init("quickbooks",         2.5, .bookkeeping),
        .init("ledger",             1.5, .bookkeeping),
        .init("reconcile",          1.5, .bookkeeping),
        .init("expense",            1.2, .bookkeeping),
        .init("schedule e",         2.5, .bookkeeping, wholeWord: true),
        // Rental tax work (cost segregation, depreciation): bookkeeping.
        .init("cost seg",           2.5, .bookkeeping, categoryWeight: 4),
        .init("segregation",        2.0, .bookkeeping, categoryWeight: 4),
        .init("depreciation",       2.0, .bookkeeping, categoryWeight: 4),
        .init("1098",               1.5, .bookkeeping),
        .init("cpa",               1.5, .bookkeeping, wholeWord: true),
        .init("accountant",         1.5, .bookkeeping),
        .init("1099",               2.0, .bookkeeping),
        .init("property tax",       2.0, .bookkeeping, categoryWeight: 4),
        .init("tax",                0.6, .bookkeeping),
        .init("receipt",            1.0, .bookkeeping, role: .purchase),
        .init("invoice",            1.0, .bookkeeping, role: .purchase),
        .init("order",              0.0, wholeWord: true, role: .purchase),
        .init("purchase",           0.0, role: .purchase),
        .init("dues",               0.8, .bookkeeping),
        .init("statements",         1.0, .bookkeeping, categoryWeight: 2),
        .init("year end",           1.0, .bookkeeping),
        .init("bill",               0.5, .bookkeeping, categoryWeight: 2, wholeWord: true),
        .init("assessment",         0.6, .bookkeeping),
        .init("buildium",           2.5, .bookkeeping, categoryWeight: 0.5),
        .init("stessa",             2.5, .bookkeeping),
        .init("appfolio",           2.5, .management, categoryWeight: 0.5),

        // Legal & compliance
        .init("evict",              2.5, .legal, categoryWeight: 3),
        .init("attorney",           1.2, .legal, categoryWeight: 2.5),
        .init("lawyer",             1.2, .legal, categoryWeight: 2.5),
        .init("court",              0.8, .legal),
        .init("hearing",            1.0, .legal),
        .init("permit",             1.5, .legal, categoryWeight: 3),
        .init("code enforcement",   2.5, .legal, categoryWeight: 4),
        .init("compliance",         1.2, .legal),
        .init("legal",              1.0, .legal),
        .init("dispute",            0.8, .legal),
        .init("notice",             0.8, .legal, categoryWeight: 0.3),

        // Insurance & claims
        .init("insurance",          1.2, .insurance, categoryWeight: 2),
        .init("landlord insurance", 1.0, .insurance, categoryWeight: 4),
        .init("non renew",          1.0, .insurance, categoryWeight: 2),
        .init("adjuster",           2.0, .insurance),
        .init("claim",              0.8, .insurance, categoryWeight: 2),
        .init("water damage",       1.5, .insurance),

        // Travel to property
        .init("drive to",           0.8, .travel, categoryWeight: 3),
        // Stores are weak alone and vote repairs; they score next to a purchase word.
        .init("home depot",         0.6, .repairs, categoryWeight: 2, role: .store),
        .init("lowes",              0.6, .repairs, categoryWeight: 2, role: .store),
        .init("lowe s",             0.6, .repairs, categoryWeight: 2, role: .store),
        .init("hardware store",     1.2, .travel, categoryWeight: 3),
        .init("supplies",           0.8),

        // Financing (investor-level, not REPS-countable)
        .init("refinanc",           1.2, .financing, categoryWeight: 3),
        .init("lender",             1.2, .financing, categoryWeight: 2),
        .init("mortgage",           0.8, .financing),
        // Paying an existing loan or bill is bookkeeping (counts), with enough weight to be "likely".
        .init("mortgage payment",   2.0, .bookkeeping, categoryWeight: 5),
        .init("monthly mortgage",   2.0, .bookkeeping, categoryWeight: 5),
        .init("pay mortgage",       2.0, .bookkeeping, categoryWeight: 5),
        .init("pay the mortgage",   2.0, .bookkeeping, categoryWeight: 5),
        .init("loan payment",       2.0, .bookkeeping, categoryWeight: 5),
        .init("hoa payment",        1.0, .bookkeeping, categoryWeight: 5),
        .init("hoa dues",           1.0, .bookkeeping, categoryWeight: 5),
        .init("property tax payment", 1.0, .bookkeeping, categoryWeight: 5),
        .init("loan",               0.8, .financing),
        .init("appraisal",          1.5, .financing, categoryWeight: 3),
        .init("closing",            1.0, .financing),

        // Investing (investor-level)
        .init("deal",               0.8, .investing, categoryWeight: 1.5),
        .init("analyze",            0.6, .investing),
        .init("tour",               0.5, .investing),
        .init("potential",          0.4, .investing),
        .init("1031",               2.0, .investing, categoryWeight: 3),

        // Contract negotiation (investor-level)
        .init("negotiat",           1.0, .contractNegotiation, categoryWeight: 2),
        .init("purchase contract",  2.0, .contractNegotiation, categoryWeight: 3),
        .init("contract",           0.6, .contractNegotiation, wholeWord: true),
        .init("offer",              0.6, .contractNegotiation),

        // Generic property words (no category vote)
        .init("property",           1.5),
        .init("properties",         1.5),
        .init("duplex",             2.0),
        .init("triplex",            2.0),
        .init("fourplex",           2.0),
        .init("multifamily",        2.0),
        .init("unit",               0.8, wholeWord: true),
        .init("units",              0.8, wholeWord: true),

        // Noise: the rest of a landlord's calendar
        .init("dentist",           -4.0),
        .init("dental",            -3.0),
        .init("doctor",            -4.0),
        .init("dr",                -3.0, wholeWord: true),
        .init("physical",          -2.0),
        .init("therapy",           -3.0),
        .init("flu shot",          -3.0),
        .init("pediatric",         -3.0),
        .init("soccer",            -4.0),
        .init("practice",          -1.5),
        .init("recital",           -4.0),
        .init("piano",             -2.0),
        .init("swim",              -2.5),
        .init("birthday",          -3.0),
        .init("wedding",           -3.0),
        .init("baby shower",       -3.0),
        .init("dinner",            -2.0),
        .init("lunch",             -1.2),
        .init("coffee",            -1.2),
        .init("standup",           -4.0),
        .init("stand up",          -4.0),
        .init("1 1",               -3.0, wholeWord: true),
        .init("one on one",        -3.0),
        .init("sprint",            -3.0),
        .init("retro",             -3.0, wholeWord: true),
        .init("okr",               -3.0),
        .init("all hands",         -4.0),
        .init("sync",              -1.5, wholeWord: true),
        .init("interview",         -3.0),
        .init("candidate",         -2.0),
        .init("flight",            -3.0),
        .init("gym",               -4.0, wholeWord: true),
        .init("yoga",              -4.0),
        .init("haircut",           -4.0),
        .init("date night",        -4.0),
        .init("school",            -2.5),
        .init("pta",               -3.0, wholeWord: true),
        .init("parent teacher",    -3.0),
        .init("vet",               -3.0, wholeWord: true),
        .init("oil change",        -3.0),
        .init("car",               -1.5, wholeWord: true),
        .init("dmv",               -3.0, wholeWord: true),
        .init("church",            -4.0),
        .init("book club",         -4.0),
        .init("code review",       -4.0),
        .init("deploy",            -4.0),
        .init("grocer",            -3.0),
        .init("costco",            -2.0),
        .init("netflix",           -4.0),
        .init("watch party",       -3.0),
        .init("offsite",           -3.0),
        .init("performance review", -4.0),
        .init("business review",   -4.0),
        .init("product team",      -3.0),
        .init("team",              -1.0, wholeWord: true),
        .init("kids",              -1.5, wholeWord: true),
        .init("kid",               -1.5, wholeWord: true),
        .init("bike",              -1.5),
        .init("garage",            -0.8),
        .init("our house",         -2.0),
        .init("our home",          -2.0),
        .init("basketball",        -4.0),
        .init("tux",               -2.0, wholeWord: true),
        .init("fantasy",           -3.0),
        .init("demo",              -1.5),
        .init("work",              -1.5, wholeWord: true),
        .init("conference",        -1.0),
        .init("reservation",       -1.0),
        // Social events (often at a home the owner lives in).
        .init("bbq",               -3.0, wholeWord: true),
        .init("barbecue",          -3.0),
        .init("party",             -2.5, wholeWord: true),
        .init("third party",        2.5),   // cancels "party": a vendor, not a social event
        .init("celebration",       -2.5),
        .init("housewarming",      -3.0),
        .init("get together",      -2.5),
        .init("festival",          -2.5),
        // Marketing, newsletters and account mail (rental platforms, stores, tax vendors).
        // Email only: on a calendar these words are ordinary ("Tenant feedback").
        .init("discount",          -2.5, emailOnly: true),
        .init("promotion",         -2.5, emailOnly: true),
        .init("promo",             -2.5, wholeWord: true, emailOnly: true),
        .init("deals",             -2.0, wholeWord: true, emailOnly: true),
        .init("sale",              -2.0, wholeWord: true, emailOnly: true),
        .init("savings",           -2.0, emailOnly: true),
        .init("stays",             -2.0, wholeWord: true, emailOnly: true),
        .init("you should see",    -2.5, emailOnly: true),
        .init("password",          -4.0, emailOnly: true),
        .init("secure code",       -4.0, emailOnly: true),
        .init("security code",     -4.0, emailOnly: true),
        .init("verification code", -4.0, emailOnly: true),
        .init("verify your",       -3.0, emailOnly: true),
        .init("sign in",           -2.0, emailOnly: true),
        .init("webinar",           -3.0, emailOnly: true),
        .init("newsletter",        -3.0, emailOnly: true),
        .init("unsubscribe",       -3.0, emailOnly: true),
        .init("digest",            -3.0, emailOnly: true),
        .init("tips",              -2.0, wholeWord: true, emailOnly: true),
        .init("feedback",          -2.0, emailOnly: true),
        .init("rewards",           -2.0, emailOnly: true),
        .init("your cart",         -3.0, emailOnly: true),
        .init("more updates",      -3.0, emailOnly: true),
        .init("other updates",     -3.0, emailOnly: true),
        .init("host updates",      -3.0, emailOnly: true),
        .init("bookings",          -1.5, wholeWord: true, emailOnly: true),
        .init("car rental",        -4.0),
        .init("industry",          -2.0, wholeWord: true),
        .init("expert call",       -3.0),
        .init("rental car",        -4.0),
        .init("alert",             -1.5, wholeWord: true, emailOnly: true),
        .init("alerts",            -1.5, wholeWord: true, emailOnly: true),
        .init("mom",               -1.5, wholeWord: true),
        .init("family",            -1.5),
    ]
    // swiftlint:enable comma

    /// Words that never identify a property on their own (property-name and address matching).
    static let propertyStopWords: Set<String> = [
        "the", "and", "for", "with", "unit", "units", "house", "home", "property", "rental",
        "duplex", "triplex", "fourplex", "apartment", "apartments", "condo", "cottage", "building",
        "street", "st", "avenue", "ave", "road", "rd", "drive", "dr", "lane", "ln", "court", "ct",
        "place", "pl", "blvd", "boulevard", "way", "hwy", "highway", "suite", "ste", "apt",
        "north", "south", "east", "west", "n", "s", "e", "w",
    ]

    /// Place-name words that never identify a street on their own ("San", "Lake"): a street
    /// made only of these needs the house number too.
    static let placeWords: Set<String> = [
        "san", "santa", "santo", "los", "las", "del", "el", "la", "lake", "mount", "mt",
        "port", "fort", "saint", "park", "bay", "hill", "hills", "valley", "beach", "river",
        "spring", "springs", "creek", "view", "new", "old", "great", "little", "upper", "lower",
    ]
}

// MARK: - 1.x calendar category (compatibility)
//
// A byte-for-byte copy of `CalendarImportService.categorizeEvent(title:)` (1.x). A 1.1 device
// skips re-importing a calendar event only when the category it computes matches the stored
// entry (AppViewModel.isDuplicateCalendarEntry), so calendar suggestions keep this category by
// default. A unit test proves parity with the 1.x function.
enum LegacyCalendarCategory {
    static func category(forTitle title: String) -> ActivityCategory {
        let t = title.lowercased()
        if t.contains("repair") || t.contains("fix") || t.contains("plumber") || t.contains("electrician") || t.contains("hvac") || t.contains("clean") || t.contains("maintenance") || t.contains("lawn") {
            return .repairs
        } else if t.contains("tenant") || t.contains("lease") || t.contains("rent") || t.contains("showing") {
            return .leasing
        } else if t.contains("inspect") || t.contains("walkthrough") || t.contains("appraisal") || t.contains("travel") {
            return .travel
        } else if t.contains("closing") || t.contains("realtor") || t.contains("contractor") || t.contains("renovati") {
            return .renovations
        } else if t.contains("insurance") || t.contains("claim") {
            return .insurance
        } else if t.contains("legal") || t.contains("compliance") || t.contains("evict") {
            return .legal
        }
        return .management
    }
}
