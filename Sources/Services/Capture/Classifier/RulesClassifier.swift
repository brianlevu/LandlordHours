import Foundation

// MARK: - Rules classifier (tier .rules)
//
// Always available, every OS the app supports (iOS 17+), no model, no network. The main path
// for most users: Apple's model covers only Apple Intelligence devices.
struct RulesClassifier: CaptureClassifier {
    /// Calendar suggestions ALWAYS keep the category 1.x's calendar import computes
    /// (`CalendarImportService.categorizeEvent`), so a 1.1 device recognises a 2.0-confirmed
    /// event as already imported (AppViewModel.isDuplicateCalendarEntry compares category, hours
    /// and start). Not configurable: only non-calendar sources get the table/model category.
    static func usesLegacyCategory(_ kind: Suggestion.Kind) -> Bool { kind == .calendar }

    struct Options: Equatable {
        /// With exactly one property, a likely landlord item is proposed for it.
        var defaultToOnlyProperty = true
    }

    var options = Options()

    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification {
        classifySync(candidate, properties: properties)
    }

    func classifySync(_ candidate: CaptureCandidate, properties: [RentalProperty]) -> CaptureClassification {
        let text = [candidate.title, candidate.location ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let verdict = RulesEngine.evaluate(text: text, properties: properties, isEmail: candidate.kind == .gmail)
        let isLandlordWork = verdict.confidence >= ClassifierThresholds.likely

        var evidence = verdict.evidence
        var confidence = verdict.confidence
        if verdict.hasLandlordSignal {
            // Landlord-signal items are never hidden: at worst they are "Not sure".
            evidence.append(ClassifierThresholds.landlordSignalEvidence)
            confidence = max(confidence, ClassifierThresholds.notSure)
        }
        var propertyId = verdict.propertyId
        if propertyId == nil, options.defaultToOnlyProperty, isLandlordWork, properties.count == 1 {
            propertyId = properties[0].id
            evidence.append("default property: only property")
        }

        let category: ActivityCategory?
        if Self.usesLegacyCategory(candidate.kind) {
            category = LegacyCalendarCategory.category(forTitle: candidate.title)
        } else {
            category = verdict.category ?? (verdict.hasLandlordSignal ? .management : nil)
        }

        let (hours, basis) = Self.hours(for: candidate)
        return CaptureClassification(
            isLandlordWork: isLandlordWork,
            confidence: confidence,
            propertyId: propertyId,
            category: category,
            hours: hours,
            hoursBasis: basis,
            tier: .rules,
            evidence: evidence
        )
    }

    /// Calendar: the scheduled length, as 1.x computed it (raw hours, under 24). Location:
    /// the dwell. Receipts never guess hours.
    static func hours(for candidate: CaptureCandidate) -> (Double?, Suggestion.HoursBasis) {
        guard candidate.kind != .receipt, let end = candidate.end else { return (nil, .none) }
        let hours = end.timeIntervalSince(candidate.start) / 3600
        guard hours > 0, hours < 24 else { return (nil, .none) }
        return (hours, candidate.kind == .location ? .dwellCap : .scheduled)
    }
}
