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

enum ClassifierThresholds {
    /// At or above: "rental work" — a normal inbox card.
    static let likely = 0.60
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
    static let targetPrecisionAtLikely = 0.95
    static let targetAccuracyAtLikely = 0.93
    /// Share of real landlord items that must stay visible (≥ notSure).
    static let targetVisibleRecall = 0.95
    /// Category accuracy floors (landlord items). Rules on the held-out set are honest-low;
    /// the 85% bar applies to the on-device model.
    static let targetRulesCategoryTuning = 0.95
    static let targetRulesCategoryHoldout = 0.45
    static let targetModelCategoryHoldout = 0.85
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
    /// Evidence marker the rules add when a landlord keyword or property matched and noise
    /// words don't outweigh it.
    static let landlordSignalEvidence = "signal: landlord"
}

extension CaptureClassification {
    /// Band for display. Anything with landlord evidence (a keyword or property the rules
    /// matched, or a model "yes") is never hidden: at worst it is "Not sure", whatever its
    /// score — a model "no" or a low score cannot push it out of the inbox. Only items with
    /// no landlord signal at all are dropped.
    var band: ConfidenceBand {
        if confidence >= ClassifierThresholds.likely { return .likely }
        if hasLandlordEvidence { return .notSure }
        return .unlikely
    }

    var hasLandlordEvidence: Bool {
        isLandlordWork || evidence.contains { $0 == ClassifierThresholds.landlordSignalEvidence || $0.hasPrefix("model: yes") }
    }
}
