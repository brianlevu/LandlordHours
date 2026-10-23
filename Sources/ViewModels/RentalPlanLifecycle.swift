import Foundation

// MARK: - Per-rental answers and plans across the rental lifecycle (2.1)
//
// The "did anyone else do more?" answer and the rental plan (overrides, who does most, Today's
// focus) are kept per rental. These hooks keep them in step with the rentals themselves:
//   - rentals loaded, pulled from iCloud or added: the 2.0 per-year answers are copied to any
//     rental that predates the migration (idempotent, see `migrateParticipationAnswers`);
//   - a rental deleted (here or on another device): its answers and plan go with it;
//   - profile switch, sign-out, data reset and account deletion: handled where the other
//     managers reload or reset (AppViewModel), with the keys listed in its local-data lists.

extension AppViewModel {
    /// Call after `properties` is loaded or changes (local load, iCloud pull, add).
    func rentalsDidLoadOrChange() {
        TaxProfileManager.shared.migrateParticipationAnswers(properties: properties)
    }

    /// Call after a rental is removed, so nothing it answered or chose is left behind.
    func rentalWasDeleted(_ id: UUID) {
        TaxProfileManager.shared.forgetParticipationAnswers(for: id)
        RentalPlanStore.shared.forget(id)
    }

    /// The "did anyone else do more?" answer for one rental, the way the tax engine reads it:
    /// the grouped activity's answer under the grouping election, else the rental's own.
    func participationAnswer(year: Int, propertyId: UUID?) -> Bool? {
        let grouped = TaxProfileManager.shared.groupingElection
        return TaxProfileManager.shared.noOneParticipatedMore(forYear: year, propertyId: grouped ? nil : propertyId)
    }
}

extension TaxProfileManager {
    /// Each rental's answer for `year` (unanswered rentals are left out). A value snapshot, so
    /// it can cross into a detached report build.
    func participationAnswers(forYear year: Int, properties: [RentalProperty]) -> [UUID: Bool] {
        var result: [UUID: Bool] = [:]
        for property in properties {
            if let answer = noOneParticipatedMore(forYear: year, propertyId: property.id) { result[property.id] = answer }
        }
        return result
    }

    /// Every answer stored for `year` (each rental and the grouped activity), in a stable order.
    /// Changes whenever ANY answer for that year changes.
    func participationFingerprint(year: Int) -> String {
        let prefix = "\(year)|"
        return participationAnswers
            .filter { $0.key.hasPrefix(prefix) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }
}
