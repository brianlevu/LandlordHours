import Foundation

extension CaptureCandidate {
    /// Hours the event is scheduled for, computed the way 1.x did: `(end - start) / 3600`.
    var scheduledHours: Double? {
        guard let end, end > start else { return nil }
        return end.timeIntervalSince(start) / 3600.0
    }
}

/// Stand-in rules until WP2's classifier lands: the 1.x keyword filter, category and property
/// matching, behind the real `CaptureClassifier` seam. Replace by injecting another classifier.
struct PlaceholderCalendarClassifier: CaptureClassifier {
    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification {
        let service = CalendarImportService.shared
        let text = (candidate.title + " " + (candidate.location ?? "")).lowercased()
        let related = service.propertyKeywords.contains { text.contains($0) }
        let property = service.matchProperty(from: text, properties: properties)
        return CaptureClassification(
            isLandlordWork: related || property != nil,
            confidence: related ? 0.5 : (property != nil ? 0.4 : 0.1),
            propertyId: property?.id,
            // 1.x computed the category from the lowercased title only.
            category: service.categorizeEvent(title: candidate.title.lowercased()),
            hours: candidate.scheduledHours,
            hoursBasis: .scheduled,
            tier: .rules,
            evidence: related ? ["Calendar event title looks like property work"] : []
        )
    }
}

/// What one calendar scan did.
struct CalendarScanResult: Equatable {
    var access: CalendarAccess
    /// Newly added pending suggestions (what a notifier may announce).
    var added: [Suggestion]
    var skipped: CalendarSkipCounts
    /// The scan stopped before finishing (the user cancelled the backfill, or the task was
    /// cancelled). Nothing from it was ingested; the backfill is NOT complete.
    var cancelled = false

    static func blocked(_ access: CalendarAccess) -> CalendarScanResult {
        CalendarScanResult(access: access, added: [], skipped: CalendarSkipCounts())
    }
}

// MARK: - Coordinator
//
// detect → classify → build suggestions → SuggestionStore.ingest. The store does the dedupe:
// dismissed keys never return, items already recorded (this key, a derived id, or a matching
// 1.x import) are stored as confirmed, and items that look manually logged are flagged.
//
// Hours and start stay exactly as 1.x computed them: the scheduled length of the event, not
// whatever a classifier says, so a 1.1 device skips an event confirmed on a 2.0 device. The
// classifier proposes property and category only. (1.1 skips by property + category + hours +
// start + title, so a classifier that changes the category for a given title can let a 1.1
// device re-import; WP2 must account for that.)
@MainActor
final class CalendarCaptureCoordinator {
    private let detector: CalendarDetector
    private let classifier: CaptureClassifier
    private let store: SuggestionStore
    private let clock: () -> Date
    private let calendar: Calendar

    init(
        detector: CalendarDetector,
        classifier: CaptureClassifier = PlaceholderCalendarClassifier(),
        store: SuggestionStore,
        clock: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.detector = detector
        self.classifier = classifier
        self.store = store
        self.clock = clock
        self.calendar = calendar
    }

    /// Current permission. A scan never prompts on its own.
    var access: CalendarAccess { detector.access }

    /// Asks for full calendar access when undetermined. Denied / limited / restricted come back
    /// unchanged: the caller sends the user to Settings (an app can't re-prompt).
    func requestAccessIfNeeded() async -> CalendarAccess {
        detector.access == .notDetermined ? await detector.requestAccess() : detector.access
    }

    /// Day-1 scan of the last 90 days.
    func scanBackfill(properties: [RentalProperty], entries: [TimeEntry]) async -> CalendarScanResult {
        await scan(detector.backfillInterval(now: clock(), calendar: calendar), properties: properties, entries: entries)
    }

    /// Scan of the next 7 days.
    func scanUpcoming(properties: [RentalProperty], entries: [TimeEntry]) async -> CalendarScanResult {
        await scan(detector.upcomingInterval(now: clock(), calendar: calendar), properties: properties, entries: entries)
    }

    /// Day-1 backfill through the WP2 chain's batch API, with progress (the backfill intro).
    /// Likely and "Not sure" items are both kept (low confidence is shown, never hidden); muted
    /// and no-signal items are dropped. Hours and start stay 1.x's (see type comment).
    func scanBackfillBatched(
        chain: ClassifierChain,
        properties: [RentalProperty],
        entries: [TimeEntry],
        progress: @escaping @Sendable (ClassifierBatchProgress) -> Void = { _ in }
    ) async -> CalendarScanResult {
        let interval = detector.backfillInterval(now: clock(), calendar: calendar)
        let candidates: [CaptureCandidate]
        do {
            candidates = try await detector.detect(in: interval)
        } catch CalendarCaptureError.noAccess(let access) {
            return .blocked(access)
        } catch {
            return .blocked(detector.access)
        }
        let outcomes: [ClassifierOutcome]
        do {
            outcomes = try await chain.classifyBatch(candidates, properties: properties, progress: progress)
        } catch {
            // classifyBatch throws only on cancellation.
            return CalendarScanResult(access: .fullAccess, added: [], skipped: detector.lastSkipCounts, cancelled: true)
        }
        guard !Task.isCancelled else {
            return CalendarScanResult(access: .fullAccess, added: [], skipped: detector.lastSkipCounts, cancelled: true)
        }
        var suggestions: [Suggestion] = []
        for (candidate, outcome) in zip(candidates, outcomes) {
            guard case .suggest(let classification) = outcome else { continue }
            suggestions.append(prepared(Suggestion(candidate: candidate, classification: classification), candidate: candidate, properties: properties))
        }
        let added = store.ingest(suggestions, existingEntries: entries, calendar: calendar)
        return CalendarScanResult(access: .fullAccess, added: added, skipped: detector.lastSkipCounts)
    }

    private func prepared(_ suggestion: Suggestion, candidate: CaptureCandidate, properties: [RentalProperty]) -> Suggestion {
        var suggestion = suggestion
        suggestion.proposedHours = candidate.scheduledHours
        suggestion.hoursBasis = .scheduled
        if let id = suggestion.proposedPropertyId, !properties.contains(where: { $0.id == id }) {
            suggestion.proposedPropertyId = nil
        }
        if suggestion.sourceKey.hasPrefix("cal-local:") {
            suggestion.evidence.append("This calendar gave no shared event id, so the same event may show up again on another device")
        }
        return suggestion
    }

    private func scan(_ interval: DateInterval, properties: [RentalProperty], entries: [TimeEntry]) async -> CalendarScanResult {
        let candidates: [CaptureCandidate]
        do {
            candidates = try await detector.detect(in: interval)
        } catch CalendarCaptureError.noAccess(let access) {
            return .blocked(access)
        } catch {
            return .blocked(detector.access)
        }

        var suggestions: [Suggestion] = []
        for candidate in candidates {
            let classification = await classifier.classify(candidate, properties: properties)
            guard classification.isLandlordWork else { continue }
            var suggestion = Suggestion(candidate: candidate, classification: classification)
            // Keep 1.x's values (see type comment).
            suggestion.proposedHours = candidate.scheduledHours
            suggestion.hoursBasis = .scheduled
            // A property the profile no longer has can't be proposed.
            if let id = suggestion.proposedPropertyId, !properties.contains(where: { $0.id == id }) {
                suggestion.proposedPropertyId = nil
            }
            if suggestion.sourceKey.hasPrefix("cal-local:") {
                suggestion.evidence.append("This calendar gave no shared event id, so the same event may show up again on another device")
            }
            suggestions.append(suggestion)
        }
        let added = store.ingest(suggestions, existingEntries: entries, calendar: calendar)
        return CalendarScanResult(access: .fullAccess, added: added, skipped: detector.lastSkipCounts)
    }
}
