import Foundation

// MARK: - Properties (2.0): the numbers each rental shows
//
// Every rental shows its OWN countable hours, counted the way Today's house counts them
// (TodayHouse.swift), so a row never shows an hour the hero would not:
//   - REPS: the real estate professional's own hours only (the IRS tests REPS for one spouse at a time).
//   - Material participation: owner + spouse, spouse only when tracked jointly (Tax Profile).
//   - Investor-only tasks (investing, financing, contract negotiation) never count.
// It reuses the tax engine; it never re-derives the rules. A grouping election changes what the
// MP TEST measures (all rentals as one activity), not what each rental's own row shows.

extension AppViewModel {
    /// This rental's countable hours for `year` under `goal` (default: the house goal).
    func propertyCountableHours(
        _ propertyId: UUID,
        goal: HouseGoal? = nil,
        year: Int = Calendar.current.component(.year, from: Date()),
        includeSpouse: Bool? = nil
    ) -> Double {
        let mine = timeEntries.filter { $0.propertyId == propertyId }
        switch goal ?? houseGoal {
        case .reps750:
            return TaxQualificationEngine.qualifyingRealEstateHours(entries: mine, participant: GoalManager.shared.repsParticipant, year: year)
        case .mp500, .mp100:
            let spouse = includeSpouse ?? tracksSpouseJointly
            return TaxQualificationEngine.materialParticipationStatus(
                entries: spouse ? mine : mine.filter { $0.participant == .selfParticipant },
                year: year,
                propertyId: propertyId,
                groupingElection: false
            ).ownerAndSpouseHours
        }
    }

    /// The entries behind `propertyCountableHours` (same filters), for the kinds breakdown.
    func propertyCountableEntries(
        _ propertyId: UUID,
        goal: HouseGoal? = nil,
        year: Int = Calendar.current.component(.year, from: Date()),
        includeSpouse: Bool? = nil
    ) -> [TimeEntry] {
        let calendar = Calendar.current
        let resolved = goal ?? houseGoal
        // REPS: the real estate professional's own entries, the same person `propertyCountableHours` counts.
        // Material participation: yours, plus your spouse's when tracked jointly.
        let spouse = includeSpouse ?? tracksSpouseJointly
        let repsPerson = GoalManager.shared.repsParticipant
        return timeEntries.filter {
            $0.propertyId == propertyId
                && calendar.component(.year, from: $0.date) == year
                && $0.countsForREPS
                && (resolved == .reps750
                    ? $0.participant == repsPerson
                    : ($0.participant == .selfParticipant || (spouse && $0.participant == .spouse)))
        }
    }

    /// Everything the list row and the detail page show for one rental.
    func propertyFigures(
        for property: RentalProperty,
        goal: HouseGoal? = nil,
        year: Int = Calendar.current.component(.year, from: Date())
    ) -> PropertyFigures {
        let calendar = Calendar.current
        let countable = propertyCountableEntries(property.id, goal: goal, year: year)
        var byKind: [ActivityCategory: Double] = [:]
        for entry in countable { byKind[entry.category, default: 0] += max(0, entry.hours) }
        var kinds: [PropertyFigures.Kind] = []
        for (category, hours) in byKind where hours > 0 {
            kinds.append(PropertyFigures.Kind(category: category, hours: hours))
        }
        kinds.sort { (a: PropertyFigures.Kind, b: PropertyFigures.Kind) -> Bool in
            if a.hours == b.hours { return a.category.rawValue < b.category.rawValue }
            return a.hours > b.hours
        }
        var all: [TimeEntry] = timeEntries.filter { $0.propertyId == property.id }
        all.sort { (a: TimeEntry, b: TimeEntry) -> Bool in
            if a.date == b.date { return a.createdAt > b.createdAt }
            return a.date > b.date
        }
        let thisYear = all.filter { calendar.component(.year, from: $0.date) == year }
        return PropertyFigures(
            hours: propertyCountableHours(property.id, goal: goal, year: year),
            entryCount: thisYear.count,
            lastDate: all.first?.date,
            kinds: Array(kinds.prefix(4)),
            recent: Array(all.prefix(3))
        )
    }

    /// The Rentals list (v2): one row per rental with its own stage and lit state. The goal is the
    /// one Today measures each rental's own page against, so the thumbnail matches Today.
    func rentalRows(now: Date = InboxClock.now(), year: Int? = nil) -> [RentalRowModel] {
        let y = year ?? Calendar.current.component(.year, from: now)
        let goal = houseGoal
        return properties.map { p in
            RentalRowModel(id: p.id, name: p.name,
                           hours: propertyCountableHours(p.id, goal: goal, year: y),
                           goal: goal.targetHours,
                           lit: TodayWindowState.loggedToday(entries: timeEntries, rentalIDs: [p.id], now: now),
                           kind: p.propertyType)
        }
    }

    /// The rental page's hero, number block, pace and tiles, from this rental's own countable hours.
    func rentalPageFigures(for property: RentalProperty, now: Date = InboxClock.now(), year: Int? = nil) -> RentalPageFigures {
        let y = year ?? Calendar.current.component(.year, from: now)
        let goal = houseGoal
        let countable = propertyCountableEntries(property.id, goal: goal, year: y)
        let week = RentalWeek.hours(entries: countable, now: now)
        return RentalPageFigures.make(.init(
            hours: propertyCountableHours(property.id, goal: goal, year: y),
            goal: goal.targetHours,
            isRecord: GoalManager.shared.goalChoice == .record,
            thisWeek: week.thisWeek, lastWeek: week.lastWeek,
            year: y, now: now,
            daysOfData: RentalWeek.daysOfData(entries: countable, year: y, now: now)))
    }

    /// Free plan: one rental. True when adding another needs Pro.
    var propertiesAtFreeLimit: Bool {
        ProGate.isAtPropertyLimit(isPro: SubscriptionManager.shared.isPro, propertyCount: properties.count)
    }

    /// True for a material participation goal without a grouping election: each row can say
    /// "212h of 500h".
    var propertyGoalIsPerProperty: Bool {
        PropertyMeta.isPerPropertyTest(goal: houseGoal, groupingElection: TaxProfileManager.shared.groupingElection)
    }

    /// Whether the hero counts this rental toward the goal (same rule as Today's eyebrow).
    func heroCounts(_ property: RentalProperty) -> Bool {
        TaxQualificationEngine.countedProperties(properties).contains { $0.id == property.id }
    }

    /// The one rental Today names; nil when the count covers every rental.
    func todayFocusProperty(year: Int = Calendar.current.component(.year, from: Date())) -> RentalProperty? {
        TaxQualificationEngine.todayFocusProperty(
            entries: tracksSpouseJointly ? timeEntries : timeEntries.filter { $0.participant == .selfParticipant },
            properties: properties,
            year: year,
            groupingElection: TaxProfileManager.shared.groupingElection,
            countsPerRental: houseGoal != .reps750 && GoalManager.shared.goalChoice != .record
        )
    }
}

struct PropertyFigures {
    struct Kind: Equatable {
        let category: ActivityCategory
        let hours: Double
    }

    /// Countable hours this year (goal and spouse rules applied).
    let hours: Double
    /// Every entry for this rental this year.
    let entryCount: Int
    let lastDate: Date?
    /// Up to four kinds of countable work, largest first.
    let kinds: [Kind]
    /// The three newest entries for this rental (any year), as Records lists them.
    let recent: [TimeEntry]
}

enum PropertyMeta {
    /// "212h this year". A rental with its own target reads "12h of 100h" (the goal's own number:
    /// 100, 500) until it passes the line, then "120h this year" (the stage lives on the house
    /// art, never in the hours line). Only a rental the hero counts has a target, and only for a
    /// material participation goal WITHOUT a grouping election; under 750 the total lives on
    /// Today and a row shows hours only. Whole hours, rounded down so a row never runs ahead of
    /// the records.
    static func hoursLine(_ hours: Double, goal: HouseGoal, groupingElection: Bool, counted: Bool = true) -> String {
        let whole = Int(max(0, hours.isFinite ? hours : 0).rounded(.down))
        guard counted, isPerPropertyTest(goal: goal, groupingElection: groupingElection) else { return RentalsText.hoursThisYear(whole) }
        let target = Int(goal.targetHours)
        return whole < target
            ? String(localized: "rentals.hoursOfTarget", defaultValue: "\(whole)h of \(target)h", table: "Rentals")
            : RentalsText.hoursThisYear(whole)
    }

    /// A per-rental target applies only to material participation without grouping.
    static func isPerPropertyTest(goal: HouseGoal, groupingElection: Bool) -> Bool {
        goal != .reps750 && !groupingElection
    }

    /// "Long stays" / "A few nights" (never LTR/STR).
    static func kindLabel(_ type: PropertyType) -> String { RentalsText.kind(type) }
}

// MARK: - Free limit

/// Properties' names for the free-limit rules. ProGate is the single source (WP-P).
enum PropertyLimit {
    static let freeProperties = ProGate.freeRentals

    static func isAtLimit(isPro: Bool, propertyCount: Int) -> Bool {
        ProGate.isAtPropertyLimit(isPro: isPro, propertyCount: propertyCount)
    }

    static let lockLine = ProGate.lockLine(.propertiesLimit)

    /// What stays active while previewing (the paywall law): the rental they have keeps working.
    static func keepsLine(firstPropertyName: String?) -> String {
        ProGate.keepsLine(.propertiesLimit, firstPropertyName: firstPropertyName)
    }

    static let paywallContext: PaywallContext = ProGate.context(for: .propertiesLimit)
}

// MARK: - Seal

enum SealPalette: Int, CaseIterable, Equatable {
    case blueprint, timber, terracotta, brass, slate
}

enum PropertySealStyle {
    /// Initials of the first two words, skipping "The", "A", "An" and words that don't start with
    /// a letter; one word gives its first two letters.
    static func monogram(_ name: String) -> String {
        let skip: Set<String> = ["the", "a", "an"]
        let words = name.split(separator: " ")
            .filter { $0.first?.isLetter == true && !skip.contains($0.lowercased()) }
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        let word = words.first.map(String.init) ?? name.trimmingCharacters(in: .whitespaces)
        return String(word.prefix(2)).uppercased()
    }

    /// Colour by creation order, cycling the five palettes, so neighbours differ and a rental
    /// keeps its colour (creation order never changes). The model stores no colour.
    static func palette(for property: RentalProperty, in properties: [RentalProperty]) -> SealPalette {
        let ordered = properties.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        let index = ordered.firstIndex { $0.id == property.id } ?? 0
        return SealPalette(rawValue: index % SealPalette.allCases.count) ?? .blueprint
    }
}

// MARK: - Delete

/// The delete alert says what deleteProperty actually does: the rental, its logged time and their
/// photos go, on this iPhone and (tombstoned) in iCloud. §1.21: title ≤ 6 words, ≤ 2 sentences,
/// verb buttons ("Delete", "Keep").
struct PropertyDeletion: Identifiable, Equatable {
    let property: RentalProperty
    let entryCount: Int
    /// Every hour logged at this rental (any year), as the alert says it.
    var loggedHours: Double = 0
    var id: UUID { property.id }

    var title: String { RentalsText.deleteTitle }

    var message: String {
        let hours = entryCount == 0 || loggedHours <= 0 ? nil : LHFormat.hours(loggedHours)
        return RentalsText.deleteMessage(name: property.name, hours: hours)
    }

    @MainActor
    static func make(for property: RentalProperty, in viewModel: AppViewModel) -> PropertyDeletion {
        let mine = viewModel.timeEntries.filter { $0.propertyId == property.id }
        return PropertyDeletion(property: property, entryCount: mine.count,
                                loggedHours: mine.reduce(0) { $0 + max(0, $1.hours.isFinite ? $1.hours : 0) })
    }

    /// Through the view model, which tombstones the property and its entries for iCloud.
    @MainActor
    func perform(in viewModel: AppViewModel) {
        viewModel.deleteProperty(property)
    }
}
