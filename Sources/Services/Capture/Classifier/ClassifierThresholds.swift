import Foundation

// MARK: - Confidence thresholds (committed from the calibration harness)
//
// Derived by `CalibrationTests` over Tests/Fixtures/calibration.json (175 hand-labelled
// titles: 135 tuning + 40 held out, written after the keyword table was frozen). Re-run that
// test and update these numbers whenever the keyword table, the logistic mapping, or the
// fixture labels change. The test fails if these stop meeting their targets.
//
// Rules, 2026-10-19 (see CalibrationTests output for the full sweep):
// - tuning set: zero errors for any `likely` in 0.50...0.65 → 0.60 sits inside that range;
// - held-out set: 95% landlord/not accuracy at 0.60, precision 100%, recall 90%.

enum ClassifierThresholds {
    /// At or above: "landlord work" — a normal inbox card.
    static let likely = 0.60
    /// At or above (and below `likely`), with at least one landlord signal: shown as
    /// "Not sure this is landlord work". Never hidden.
    static let notSure = 0.30
    /// Rules results this decisive skip the on-device model (saves battery on backfill).
    static let skipModelAbove = 0.97
    static let skipModelBelow = 0.02

    /// Calibration targets the committed thresholds must keep meeting (checked by tests).
    static let targetPrecisionAtLikely = 0.95
    static let targetAccuracyAtLikely = 0.93
    /// Share of real landlord items that must stay visible (≥ notSure).
    static let targetVisibleRecall = 0.95
}

/// How an inbox card presents a classification.
enum ConfidenceBand: String, Equatable {
    case likely
    /// "Not sure this is landlord work" — visible, never pre-selected.
    case notSure
    /// No landlord signal at all: not suggested.
    case unlikely

    static let notSureLabel = "Not sure this is landlord work"
}

extension CaptureClassification {
    /// Band for display. `notSure` needs some landlord evidence (a keyword, a property, or a
    /// model that said yes) so ordinary calendar noise is not flooded into the inbox.
    var band: ConfidenceBand {
        if confidence >= ClassifierThresholds.likely { return .likely }
        if confidence >= ClassifierThresholds.notSure && hasLandlordEvidence { return .notSure }
        return .unlikely
    }

    var hasLandlordEvidence: Bool {
        isLandlordWork || evidence.contains { $0.hasPrefix("keyword:") || $0.hasPrefix("property:") || $0.hasPrefix("model: yes") }
    }
}
