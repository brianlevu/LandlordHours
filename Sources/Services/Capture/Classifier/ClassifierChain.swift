import Foundation

// MARK: - Classifier chain
//
// Rules first (always), then Apple's on-device model when it is available and the rules
// result is not already decisive. Mute rules apply on EVERY entry point (classify, evaluate,
// batch): a muted item never reaches the model. Items with a landlord signal are never hidden:
// below the "likely" line they show as "Not sure this is rental work", even when the model
// says no. Only items with no landlord signal at all are dropped.
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

/// Progress of a batch run (the 90-day backfill).
struct ClassifierBatchProgress: Equatable {
    var completed: Int
    var total: Int
}

struct ClassifierChain: CaptureClassifier {
    typealias MuteRuleProvider = () async -> [CaptureMuteRule]

    let rules: RulesClassifier
    let onDevice: OnDeviceClassifier
    private let muteRuleProvider: MuteRuleProvider

    init(
        rules: RulesClassifier = RulesClassifier(),
        onDevice: OnDeviceClassifier = .makeDefault(),
        muteRules: @escaping MuteRuleProvider = { [] }
    ) {
        self.rules = rules
        self.onDevice = onDevice
        self.muteRuleProvider = muteRules
    }

    /// A chain whose mute rules come from the profile's inbox store.
    static func forStore(_ store: SuggestionStore, onDevice: OnDeviceClassifier = .makeDefault()) -> ClassifierChain {
        ClassifierChain(onDevice: onDevice, muteRules: { await MainActor.run { store.muteRules } })
    }

    /// The highest tier that can run on this device right now.
    var activeTier: Suggestion.Tier {
        onDevice.availability.isAvailable ? .onDevice : .rules
    }

    // MARK: CaptureClassifier

    /// Goes through the mute rules: a muted item comes back as "not rental work" with
    /// evidence "muted", and no model runs.
    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification {
        let mutes = await muteRuleProvider()
        if Self.isMuted(candidate, by: mutes) { return Self.mutedClassification(for: candidate) }
        return await classifyUnmuted(candidate, properties: properties, modelBudget: nil)
    }

    // MARK: Outcome (mutes + bands)

    func evaluate(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> ClassifierOutcome {
        let mutes = await muteRuleProvider()
        return await outcome(candidate, properties: properties, mutes: mutes, modelBudget: nil)
    }

    private func outcome(
        _ candidate: CaptureCandidate,
        properties: [RentalProperty],
        mutes: [CaptureMuteRule],
        modelBudget: TimeInterval?
    ) async -> ClassifierOutcome {
        if Self.isMuted(candidate, by: mutes) { return .muted }
        let classification = await classifyUnmuted(candidate, properties: properties, modelBudget: modelBudget)
        switch classification.band {
        case .likely, .notSure: return .suggest(classification)
        case .unlikely: return .skip(classification)
        }
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

    static func mutedClassification(for candidate: CaptureCandidate) -> CaptureClassification {
        CaptureClassification(
            isLandlordWork: false,
            confidence: 0,
            propertyId: nil,
            category: nil,
            hours: nil,
            hoursBasis: .none,
            tier: .rules,
            evidence: ["muted"]
        )
    }

    // MARK: Batch (90-day backfill)

    /// Classifies many candidates off the main actor. At most `maxConcurrent` items are in
    /// flight (so at most that many on-device model calls). Each model call gets
    /// `perItemBudget` seconds; past that the item keeps its rules result. Throws
    /// `CancellationError` when the calling task is cancelled, after in-flight items stop.
    /// `progress` is called from a background task after each item; hop to the main actor
    /// before touching UI. Results are in input order. `onResult` (WP-L streaming) gets each
    /// item's index and outcome as soon as it is classified, just before its progress call.
    func classifyBatch(
        _ candidates: [CaptureCandidate],
        properties: [RentalProperty],
        maxConcurrent: Int = 2,
        perItemBudget: TimeInterval = 4,
        onResult: @escaping @Sendable (_ index: Int, _ outcome: ClassifierOutcome) -> Void = { _, _ in },
        progress: @escaping @Sendable (ClassifierBatchProgress) -> Void = { _ in }
    ) async throws -> [ClassifierOutcome] {
        let total = candidates.count
        guard total > 0 else { return [] }
        let mutes = await muteRuleProvider()
        let width = max(1, maxConcurrent)
        var results = [ClassifierOutcome?](repeating: nil, count: total)
        var completed = 0

        try await withThrowingTaskGroup(of: (Int, ClassifierOutcome).self) { group in
            var next = 0
            func addNext() {
                guard next < total else { return }
                let index = next
                let candidate = candidates[index]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    let result = await self.outcome(candidate, properties: properties, mutes: mutes, modelBudget: perItemBudget)
                    try Task.checkCancellation()
                    return (index, result)
                }
            }
            for _ in 0..<min(width, total) { addNext() }
            while let (index, result) = try await group.next() {
                results[index] = result
                completed += 1
                onResult(index, result)
                progress(ClassifierBatchProgress(completed: completed, total: total))
                try Task.checkCancellation()
                addNext()
            }
        }
        return results.map { $0 ?? .muted }
    }

    // MARK: Policy

    private func classifyUnmuted(_ candidate: CaptureCandidate, properties: [RentalProperty], modelBudget: TimeInterval?) async -> CaptureClassification {
        let base = rules.classifySync(candidate, properties: properties)
        guard shouldAskModel(candidate, rulesResult: base) else { return base }
        let model: OnDeviceClassifier.OnDeviceResult?
        if let budget = modelBudget {
            model = await modelResult(candidate, properties: properties, budget: budget)
        } else {
            model = await onDevice.classify(candidate, properties: properties)
        }
        guard let model else { return base }
        return merge(rules: base, model: model, candidate: candidate, properties: properties)
    }

    private enum ModelRace {
        case answered(OnDeviceClassifier.OnDeviceResult?)
        case timedOut
    }

    /// The model's answer, or nil when it fails or runs past `budget` (the call is cancelled).
    private func modelResult(_ candidate: CaptureCandidate, properties: [RentalProperty], budget: TimeInterval) async -> OnDeviceClassifier.OnDeviceResult? {
        let onDevice = self.onDevice
        return await withTaskGroup(of: ModelRace.self) { group in
            group.addTask { .answered(await onDevice.classify(candidate, properties: properties)) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(budget, 0) * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            if case .answered(let result) = first { return result }
            return nil
        }
    }

    /// Sources the on-device model may see. Receipts are PCC's job (2.1). Gmail stays
    /// rules-only until the v2 prompt and property aliases are validated on real email: on the
    /// 2026-10-19 owner calibration the shipped model made the chain worse on email.
    static let modelKinds: Set<Suggestion.Kind> = [.calendar, .location]

    func shouldAskModel(_ candidate: CaptureCandidate, rulesResult: CaptureClassification) -> Bool {
        guard Self.modelKinds.contains(candidate.kind) else { return false }
        // Points away from rental work: nothing the model says brings it back.
        if rulesResult.evidence.contains(ClassifierThresholds.notRentalEvidence) { return false }
        guard onDevice.availability.isAvailable else { return false }
        if rulesResult.confidence >= ClassifierThresholds.skipModelAbove { return false }
        if rulesResult.confidence <= ClassifierThresholds.skipModelBelow { return false }
        return true
    }

    /// Rules and model each get half the vote on confidence; an item with a landlord signal
    /// never drops below the "Not sure" floor. A property the rules matched by name or
    /// address wins over the model's pick. Calendar categories stay on the 1.x value, except
    /// that a deal title (buy, sell, finance, negotiate) always gets its non-countable category.
    func merge(
        rules base: CaptureClassification,
        model: OnDeviceClassifier.OnDeviceResult,
        candidate: CaptureCandidate,
        properties: [RentalProperty]
    ) -> CaptureClassification {
        var result = base
        result.confidence = (base.confidence + model.confidence) / 2
        if base.evidence.contains(ClassifierThresholds.landlordSignalEvidence) {
            result.confidence = max(result.confidence, ClassifierThresholds.notSure)
        }
        // A match on the location alone stays "Not sure", whatever the model says.
        if base.evidence.contains(ClassifierThresholds.locationOnlyEvidence) {
            result.confidence = min(result.confidence, ClassifierThresholds.likely - 0.01)
        }
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

        // Calendar: the 1.x category is never overridden (1.1 dedupe). The model's category is
        // used only for non-calendar sources.
        if !RulesClassifier.usesLegacyCategory(candidate.kind), let category = model.category {
            result.category = category
        }
        // A deal title is never countable, whatever the model said (calendar included).
        result.category = DealSignal.apply(result.category, title: candidate.title)

        // Only a confident model "yes" (>= modelYesNotSure) can keep an item visible on its own.
        let reason = model.reason.isEmpty ? "" : " – \(model.reason)"
        let vote: String
        if model.isRentalWork {
            vote = model.confidence >= ClassifierThresholds.modelYesNotSure ? "yes" : "weak yes"
        } else {
            vote = "no"
        }
        result.evidence.append("model: \(vote)\(reason)")
        return result
    }
}
