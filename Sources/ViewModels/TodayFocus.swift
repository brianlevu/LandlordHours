import Foundation

// MARK: - What Today is focused on (2.1)
//
// One value drives the hero, the flag on the house, the eyebrow, the subtitle, the pace cards and
// the widget: the focus. The owner changes it by tapping a rental (or "All rentals") on Today;
// until they do, Today starts on the default (see `RentalPlanning.defaultFocus`).

extension AppViewModel {
    /// The context the plan rules read, from the live goal, grouping, rentals and the owner's answers.
    var rentalPlanContext: RentalPlanContext {
        RentalPlanStore.shared.context(
            properties: properties,
            goal: GoalManager.shared.goalChoice,
            grouping: TaxProfileManager.shared.groupingElection)
    }

    var rentalPlanMode: RentalPlanMode { RentalPlanning.mode(rentalPlanContext) }

    /// How one rental is tracked right now.
    func rentalPlan(for property: RentalProperty) -> RentalPlan {
        RentalPlanning.plan(for: property, rentalPlanContext)
    }

    /// This rental's hours counted the way ITS plan counts them: a rental with a 100 or 500 target
    /// against that test; any other against the profile's goal.
    func rentalHours(_ property: RentalProperty, year: Int = Calendar.current.component(.year, from: Date())) -> Double {
        let plan = rentalPlan(for: property)
        let goal: HouseGoal? = plan.track.hasOwnTarget ? plan.track.targetHours.map(RentalTrack.houseGoal(forHours:)) : nil
        return propertyCountableHours(property.id, goal: goal, year: year)
    }

    /// The focus Today is on now: the owner's choice if it still applies, else the default.
    /// "All rentals" only exists when the profile has one shared total or a record.
    func resolvedTodayFocus(year: Int = Calendar.current.component(.year, from: Date())) -> TodayFocusChoice {
        let ctx = rentalPlanContext
        let mode = RentalPlanning.mode(ctx)
        let chosen = RentalPlanStore.shared.chosenFocus(in: properties)
        switch (mode, chosen) {
        case (.perRental, .rental(let id)?): return .rental(id)
        case (.perRental, _):
            let def = RentalPlanning.defaultFocus(ctx) { id in
                properties.first { $0.id == id }.map { rentalHours($0, year: year) } ?? 0
            }
            return def.map(TodayFocusChoice.rental) ?? .all
        case (_, let c?): return c
        default: return .all
        }
    }
}
