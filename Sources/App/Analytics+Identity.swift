import Foundation

// MARK: - Package K's identity events (§7)
//
// Counts and fixed values only: never an id, an email, a name or record content. 2.2 removes
// `profile_created`, `restore_offered` and `restore_completed` (there are no profiles).

extension Analytics {
    /// The migration finished (S10), once per device.
    static func recordsUnified(stats: RecordSetMigration.CloudStats, groups: GroupsFile?) {
        let list = groups?.groups ?? []
        capture("records_unified", properties: [
            "groups": list.filter { $0.entryCount > 0 || $0.propertyCount > 0 }.count,
            "combined": list.filter { $0.status == .combine }.count,
            "spouse": list.filter { $0.status == .spouse }.count,
            "aside": list.filter { $0.status == .aside }.count,
            "pending": list.filter { $0.status == .pending }.count,
            "settings_only": list.filter(\.settingsOnly).count,
            "stale_baselines": stats.stale,
            "unparsed": stats.unparsed,
            "untagged_adopted": stats.untaggedAdopted,
            "r5_removed": stats.r5Removed,
            "capture_dedupe": stats.captureDedupe,
            "delta_abandoned": stats.deltaAbandoned,
            "kinds_email": list.filter { LegacyGroupKind.of($0.id) == .email && $0.entryCount + $0.propertyCount > 0 }.count,
            "kinds_local": list.filter { LegacyGroupKind.of($0.id) == .local && $0.entryCount + $0.propertyCount > 0 }.count,
            "kinds_apple": list.filter { LegacyGroupKind.of($0.id) == .apple && $0.id != IdentityZone.household && $0.entryCount + $0.propertyCount > 0 }.count
        ])
    }

    static func mergeQuestionAnswered(_ answer: String) {
        capture("merge_question_answered", properties: ["answer": answer])
    }

    static func bulkPromptShown(count: Int) {
        capture("bulk_prompt_shown", properties: ["count": count])
    }

    static func bulkAnswered(kept: Bool, count: Int) {
        capture(kept ? "bulk_kept" : "bulk_removed", properties: ["count": count])
    }

    static func zoneGonePromptShown() { capture("zone_gone_prompt_shown") }

    static func zoneGoneAnswered(_ answer: String) {
        capture("zone_gone_answered", properties: ["answer": answer])
    }

    static func settingsEmptyEditDiscarded() { capture("settings_empty_edit_discarded") }

    static func identitySettingsConflict(adopted: Bool) {
        capture("settings_conflict", properties: ["result": adopted ? "adopted" : "won"])
    }

    static func identityReadIncomplete() { capture("icloud_read_incomplete") }

    static func identityDeltaAbandoned() { capture("delta_abandoned") }

    /// One record type's push failed (diagnosis §7.3): the type and the CKError code only.
    static func syncPushFailed(recordType: String, code: Int) {
        capture("sync_push_failed", properties: ["record_type": recordType, "ck_error": code])
    }

    /// `icloud_state` once per launch: available, no_account, restricted, quota_exceeded, ...
    static func icloudState(_ state: ICloudAccountState, quotaExceeded: Bool) {
        let value: String
        if quotaExceeded { value = "quota_exceeded" } else {
            switch state {
            case .available: value = "available"
            case .noAccount: value = "no_account"
            case .restricted: value = "restricted"
            case .temporarilyUnavailable: value = "temporarily_unavailable"
            case .couldNotDetermine: value = "could_not_determine"
            case .unsupported: value = "unsupported"
            }
        }
        capture("icloud_state", properties: ["state": value])
    }

    static func deleteAllData(iCloud: Bool) {
        capture("delete_all_data", properties: ["icloud": iCloud])
    }

    /// The §2.3 invariant failed at a step (Release): counts only.
    static func identityInvariantViolation(step: String, count: Int) {
        capture("invariant_violation", properties: ["step": step, "count": count])
    }
}
