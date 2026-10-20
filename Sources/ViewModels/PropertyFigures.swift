import Foundation

// MARK: - Properties (2.0): the numbers each rental shows
//
// Every rental shows its OWN countable hours, counted the way Today's house counts them
// (TodayHouse.swift), so a row never shows an hour the hero would not:
//   - REPS: your own hours only (the IRS tests REPS for one spouse at a time).
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
            return TaxQualificationEngine.qualifyingRealEstateHours(entries: mine, participant: .selfParticipant, year: year)
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
        let spouse = resolved == .reps750 ? false : (includeSpouse ?? tracksSpouseJointly)
        return timeEntries.filter {
            $0.propertyId == propertyId
                && calendar.component(.year, from: $0.date) == year
                && $0.countsForREPS
                && ($0.participant == .selfParticipant || (spouse && $0.participant == .spouse))
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

    /// Free plan: one rental. True when adding another needs Pro.
    var propertiesAtFreeLimit: Bool {
        PropertyLimit.isAtLimit(isPro: SubscriptionManager.shared.isPro, propertyCount: properties.count)
    }

    /// True when the MP 500/100 test is measured per rental (no grouping election), so each row
    /// can say "212h of 500h".
    var propertyGoalIsPerProperty: Bool {
        houseGoal != .reps750 && !TaxProfileManager.shared.groupingElection
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

// MARK: - The mini-house stage

/// The property mini-house uses Today's one absolute scale (HouseProgress): slab at 100h,
/// roof at 500h, finished above 750h, floor rule throughout.
enum PropertyHouseStage {
    static func keyframe(for hours: Double) -> HouseKeyframe { HouseProgress.keyframe(for: hours) }
    static func stage(for hours: Double) -> HouseStage { HouseProgress(hours: hours, goal: .reps750).stage }
}

enum PropertyMeta {
    /// "212h this year", or for a per-property MP goal "212h of 500h" / "520h · roof’s on".
    /// Whole hours, rounded down so a row never runs ahead of the records.
    static func hoursLine(_ hours: Double, goal: HouseGoal, perPropertyGoal: Bool) -> String {
        let whole = Int(max(0, hours.isFinite ? hours : 0).rounded(.down))
        guard perPropertyGoal, goal != .reps750 else { return "\(whole)h this year" }
        let target = Int(goal.targetHours)
        if hours < goal.targetHours { return "\(whole)h of \(target)h" }
        return goal == .mp500 ? "\(whole)h · roof’s on" : "\(whole)h · past \(target)h"
    }

    /// "Long stays" / "A few nights" (never LTR/STR).
    static func kindLabel(_ type: PropertyType) -> String {
        type == .ltr ? "Long stays" : "A few nights"
    }
}

// MARK: - Free limit

enum PropertyLimit {
    static let freeProperties = 1

    static func isAtLimit(isPro: Bool, propertyCount: Int) -> Bool {
        !isPro && propertyCount >= freeProperties
    }

    static let lockLine = "Free covers one rental."

    /// What stays active while previewing (the paywall law): the rental they have keeps working.
    static func keepsLine(firstPropertyName: String?) -> String {
        let name = firstPropertyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((name?.isEmpty == false ? name! : "Your rental")) keeps tracking. Nothing is lost."
    }

    static let paywallContext: PaywallContext = .secondProperty
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

/// The delete alert says what deleteProperty actually does: the rental, its entries and their
/// photos go, on this iPhone and (tombstoned) in iCloud.
struct PropertyDeletion: Identifiable, Equatable {
    let property: RentalProperty
    let entryCount: Int
    var id: UUID { property.id }

    var title: String {
        switch entryCount {
        case 0: return "Delete \(property.name)?"
        case 1: return "Delete \(property.name) and its 1 entry?"
        default: return "Delete \(property.name) and its \(entryCount) entries?"
        }
    }

    var message: String {
        switch entryCount {
        case 0: return "It’s removed from this iPhone and iCloud. This can’t be undone."
        case 1: return "Its entry and any photos are deleted too, on this iPhone and in iCloud. This can’t be undone."
        default: return "Its \(entryCount) entries and their photos are deleted too, on this iPhone and in iCloud. This can’t be undone."
        }
    }

    @MainActor
    static func make(for property: RentalProperty, in viewModel: AppViewModel) -> PropertyDeletion {
        PropertyDeletion(property: property, entryCount: viewModel.timeEntries.filter { $0.propertyId == property.id }.count)
    }

    /// Through the view model, which tombstones the property and its entries for iCloud.
    @MainActor
    func perform(in viewModel: AppViewModel) {
        viewModel.deleteProperty(property)
    }
}
