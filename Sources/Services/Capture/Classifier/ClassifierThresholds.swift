import Foundation

// MARK: - Confidence thresholds (committed from the calibration harness)
//
// Derived by `CalibrationTests` over Tests/Fixtures/calibration.json (215 hand-labelled
// titles: 175 tuning + 40 held out, written after the keyword table was frozen; categories
// follow the review relabel: routine upkeep = Repairs, compliance inspections = Legal).
// Re-run that test and update these numbers whenever the keyword table, the logistic
// mapping, or the fixture labels change. The test fails if these stop meeting their targets.
//
// Rules, 2026-10-19 (see the CALIBRATION lines in the test log for the full sweep):
// - tuning: 99.4% landlord/not at 0.60 (zero false positives for any `likely` in 0.50...0.65);
// - held-out: 97.5% landlord/not, precision 96%, recall 100%, property 100%,
//   but category only 48%: keyword categories don't generalise. Calendar items keep the 1.x
//   category anyway; non-calendar category quality is the on-device model's job, and its
//   85% held-out floor is asserted whenever the model actually runs.
//
// Classifier v2, 2026-10-19 (real-owner calibration; the real set stays private and local):
// fixture + 44 synthetic "realworld" items (one or more per real failure pattern). Rules at
// 0.60: tuning 100%, held-out precision 96% / recall 100%, realworld precision 100% / recall
// 100%. On the owner's private held-out split the shipped rules scored precision ~0.4; see
// the WP2b report for the before/after table. `likely` stays 0.60: sweeping 0.5–0.9 did not
// fix precision (false positives were single strong signals at 0.82).
//
// 2.2 retune, 2026-10-27 (980 synthetic Jev-labelled events, inbox-tune/report.md): `likely`
// 0.70 (held-out precision .879 / recall .817, was .862 / .704 at 0.60). Calendar event
// signals: video link 0, 3+ attendees 1, the other four unchanged.

enum ClassifierThresholds {
    /// At or above: "rental work" — a normal inbox card.
    static let likely = 0.70
    /// Confidence floor for items with a landlord signal: they show as "Not sure this is
    /// rental work" (never hidden) and their confidence never drops below this.
    static let notSure = 0.30
    /// Classifier v2 "Not sure" band: an item shows as "Not sure" only with a rules score of at
    /// least `RulesEngine.notSureMinScore` (1.5), a property or alias match, or a model "yes"
    /// at this confidence or more. Any keyword hit used to be enough, which filled the inbox
    /// with 26–36% of all real-world negatives (2026-10-19 owner calibration).
    static let modelYesNotSure = 0.5
    /// Rules results this decisive skip the on-device model (saves battery on backfill).
    static let skipModelAbove = 0.97
    static let skipModelBelow = 0.02

    /// Calibration targets the committed thresholds must keep meeting (checked by tests).
    ///
    /// Retargeted 2026-10-31 for `likely` 0.60 -> 0.70 (the owner chose fewer false suggestions).
    /// The 980-event Jev-labelled tuning set (2026-10-27, `inbox-tune/report.md`) is why: at 0.70
    /// its held-out precision rose .862 -> .879 and recall .704 -> .817. This hand-labelled
    /// fixture (310 titles, shaped around the old table with 0.60 as its best point) moves the
    /// other way: all-data accuracy .955 -> .923 and recall .933 -> .882, while precision holds
    /// (.995 -> .994) and held-out precision is .958. Accuracy and recall therefore drop; precision
    /// does not, and its target is unchanged. The new floors sit about one item under what the
    /// committed rules score today, so a further slip still fails: all-data accuracy .9226 vs
    /// 0.92 (286 of 310 needed; 1 item of slack), recall .882 vs 0.87. Held-out is 40 titles, so
    /// one item is 0.025; its floor (0.90) is two items under .925.
    static let targetPrecisionAtLikely = 0.95
    static let targetAccuracyAtLikely = 0.92
    static let targetAccuracyHoldoutAtLikely = 0.90
    /// Share of real landlord items that clear `likely` (was .933 at 0.60).
    static let targetRecallAtLikely = 0.87
    /// Most accuracy the committed `likely` may give up against the best point on the sweep
    /// (0.968 at 0.25) in exchange for precision. Today the gap is 0.045.
    static let maxAccuracyGivenUpForPrecision = 0.05
    /// Share of real landlord items that must stay visible (≥ notSure).
    static let targetVisibleRecall = 0.95
    /// Category accuracy floors (landlord items). Rules on the held-out set are honest-low.
    /// Model floor: the first real run (2026-10-21, slim sim with Siri & Intelligence kept on,
    /// and the host Mac's model via scripts/clf-eval-host) scored 0.44 with the old prompt; the
    /// 0.85 bar had never run before and was a placeholder. With category definitions in the
    /// prompt the model scores 0.84 (host) to 0.88 (simulator, where the test asks about each
    /// title as an email), 21-22/25. One item moves this by 0.04, so the floor sits one item
    /// under the lowest run. The old prompt fails it badly.
    static let targetRulesCategoryTuning = 0.95
    static let targetRulesCategoryHoldout = 0.45
    static let targetModelCategoryHoldout = 0.80
}

/// How an inbox card presents a classification.
enum ConfidenceBand: String, Equatable {
    case likely
    /// "Not sure this is rental work" — visible, never pre-selected.
    case notSure
    /// No landlord signal at all: not suggested.
    case unlikely

    static let notSureLabel = "Not sure this is rental work"
}

extension ClassifierThresholds {
    /// Evidence marker the rules add to a calendar item that points away from rental work (a
    /// location match beside a video call, a team invite, a salon). Nothing brings it back:
    /// the on-device model is not asked and its "yes" cannot make the item visible.
    /// Confidence ceiling for a match on the location alone (tuned 2026-10-27).
    static let locationOnlyMaxConfidence = 0.59
    static let notRentalEvidence = "signal: not rental"
    /// Evidence marker on an item whose only landlord evidence is its location. The chain keeps
    /// its confidence under `likely` even when the model agrees.
    static let locationOnlyEvidence = "capped: location only"

    /// Evidence marker the rules add when a landlord keyword or property matched and noise
    /// words don't outweigh it.
    static let landlordSignalEvidence = "signal: landlord"

    /// Evidence marker on a calendar item that passed the positive-signal gate (2.3 F, "G2"): it
    /// names a rental, an address, a rental word of 0.6 or more, or a hardware store. Only these
    /// items are shown to the on-device model, and only on these can a model "yes" keep an item
    /// visible. The model may move an item that has a cue; it can never create one.
    static let rentalCueEvidence = "signal: rental cue"
}

extension CaptureClassification {
    /// Band for display. Anything with landlord evidence (a keyword or property the rules
    /// matched, or a model "yes" on an item with a rental cue) is never hidden: at worst it is
    /// "Not sure", whatever its score. "Not sure" items sit behind the Inbox's collapsed "Not
    /// sure" row (2.3 F), never in the main list, never counted, never notified.
    var band: ConfidenceBand {
        if confidence >= ClassifierThresholds.likely { return .likely }
        if hasLandlordEvidence { return .notSure }
        return .unlikely
    }

    var hasLandlordEvidence: Bool {
        if evidence.contains(ClassifierThresholds.notRentalEvidence) { return false }
        if isLandlordWork || evidence.contains(ClassifierThresholds.landlordSignalEvidence) { return true }
        // 2.3 F: a model "yes" counts only on an item the rules gave a rental cue. On v2.2 a "yes"
        // alone surfaced 15 of 42 office look-alikes (1:1s, writing blocks) as "Not sure".
        return evidence.contains(ClassifierThresholds.rentalCueEvidence) && evidence.contains { $0.hasPrefix("model: yes") }
    }
}
