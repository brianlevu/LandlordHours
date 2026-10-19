import Foundation

// MARK: - Classifier chain
//
// Rules first (always), then Apple's on-device model when it is available and the rules
// result is not already decisive. Muted items are dropped before any model runs. Results
// below the "likely" line stay visible as "Not sure this is landlord work" — never hidden —
// as long as something (a keyword, a property, or the model) points at landlord work.
//
// PCC is not part of this chain: it is receipts-only (PCCReceiptReader, 2.1). Calendar titles
// only ever reach the on-device model.

enum ClassifierOutcome: Equatable {
    /// A mute rule covers it ("stop suggesting things like this"). No model ran.
    case muted
    /// Goes to the inbox. `classification.band` is `.likely` or `.notSure`.
    case suggest(CaptureClassification)
    /// No landlord evidence at all: not suggested.
    case skip(CaptureClassification)
}

struct ClassifierChain: CaptureClassifier {
    let rules: RulesClassifier
    let onDevice: OnDeviceClassifier

    init(rules: RulesClassifier = RulesClassifier(), onDevice: OnDeviceClassifier = .makeDefault()) {
        self.rules = rules
        self.onDevice = onDevice
    }

    /// The highest tier that can run on this device right now.
    var activeTier: Suggestion.Tier {
        onDevice.availability.isAvailable ? .onDevice : .rules
    }

    // MARK: CaptureClassifier

    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification {
        let base = rules.classifySync(candidate, properties: properties)
        guard shouldAskModel(candidate, rulesResult: base) else { return base }
        guard let model = await onDevice.classify(candidate, properties: properties) else { return base }
        return merge(rules: base, model: model, candidate: candidate, properties: properties)
    }

    // MARK: Outcome (mutes + bands)

    func evaluate(_ candidate: CaptureCandidate, properties: [RentalProperty], muteRules: [CaptureMuteRule]) async -> ClassifierOutcome {
        if Self.isMuted(candidate, by: muteRules) { return .muted }
        let classification = await classify(candidate, properties: properties)
        switch classification.band {
        case .likely, .notSure: return .suggest(classification)
        case .unlikely: return .skip(classification)
        }
    }

    /// Reads the mute rules from the profile's inbox store.
    @MainActor
    func evaluate(_ candidate: CaptureCandidate, properties: [RentalProperty], store: SuggestionStore) async -> ClassifierOutcome {
        let mutes = store.muteRules
        return await evaluate(candidate, properties: properties, muteRules: mutes)
    }

    /// Same matching as `CaptureMuteRule.mutes(_:)`, applied before classification.
    static func isMuted(_ candidate: CaptureCandidate, by muteRules: [CaptureMuteRule]) -> Bool {
        guard !muteRules.isEmpty else { return false }
        let probe = Suggestion(
            sourceKey: candidate.sourceKey,
            kind: candidate.kind,
            detectedAt: candidate.detectedAt,
            start: candidate.start,
            title: candidate.title,
            containerId: candidate.containerId
        )
        return muteRules.contains { $0.mutes(probe) }
    }

    // MARK: Policy

    func shouldAskModel(_ candidate: CaptureCandidate, rulesResult: CaptureClassification) -> Bool {
        // Receipts are PCC's job (2.1); calendar, location and Gmail stay on device.
        guard candidate.kind != .receipt else { return false }
        guard onDevice.availability.isAvailable else { return false }
        if rulesResult.confidence >= ClassifierThresholds.skipModelAbove { return false }
        if rulesResult.confidence <= ClassifierThresholds.skipModelBelow { return false }
        return true
    }

    /// Rules and model each get half the vote on confidence. A property the rules matched by
    /// name or address wins over the model's pick. Calendar categories stay on the 1.x value
    /// when the rules classifier is set to keep them.
    func merge(
        rules base: CaptureClassification,
        model: OnDeviceClassifier.OnDeviceResult,
        candidate: CaptureCandidate,
        properties: [RentalProperty]
    ) -> CaptureClassification {
        var result = base
        result.confidence = (base.confidence + model.confidence) / 2
        result.isLandlordWork = result.confidence >= ClassifierThresholds.likely
        result.tier = .onDevice

        let rulesMatchedProperty = base.evidence.contains { $0.hasPrefix("property:") }
        if !rulesMatchedProperty {
            if let modelProperty = model.propertyId {
                result.propertyId = modelProperty
            } else if base.propertyId != nil && !result.isLandlordWork {
                result.propertyId = nil   // the only-property default needs a "likely" item
            }
        }
        if result.propertyId == nil, result.isLandlordWork, properties.count == 1, rules.options.defaultToOnlyProperty {
            result.propertyId = properties[0].id
        }

        let keepLegacy = candidate.kind == .calendar && rules.options.legacyCalendarCategory
        if !keepLegacy, let category = model.category {
            result.category = category
        }

        let reason = model.reason.isEmpty ? "" : " – \(model.reason)"
        result.evidence.append("model: \(model.isRentalWork ? "yes" : "no")\(reason)")
        return result
    }
}
