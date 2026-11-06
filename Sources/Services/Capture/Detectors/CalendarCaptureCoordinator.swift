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
        let related = service.matchesPropertyKeyword(text)
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

/// Whether a classifier outcome is shown in the Inbox. One answer for the live scan, the backfill
/// and the one-time cleanup, so they can never disagree about the same event.
enum CalendarVisibility {
    /// The classification to show, or nil to hide. A hidden item with a landlord word in its title
    /// is kept as "Not sure" (confidence at least 0.30), unless the rules marked it as clearly
    /// not rental work (a personal appointment, a remote place). Muted items are nil: a mute is
    /// the user's rule, handled by the caller.
    ///
    /// `keepKeywordTitles`: the cleanup of items already in the Inbox. It never deletes one with a
    /// landlord word in its title, even when the rules marked it not rental; it drops to "Not sure".
    static func shown(_ outcome: ClassifierOutcome, title: String, keepKeywordTitles: Bool = false) -> CaptureClassification? {
        switch outcome {
        case .suggest(let classification):
            return classification
        case .skip(var classification):
            guard keepKeywordTitles || !classification.evidence.contains(ClassifierThresholds.notRentalEvidence),
                  RulesEngine.titleHasLandlordKeyword(title) else { return nil }
            classification.confidence = max(classification.confidence, ClassifierThresholds.notSure)
            classification.evidence.append(ClassifierThresholds.landlordSignalEvidence)
            return classification
        case .muted:
            return nil
        }
    }
}

/// What the one-time pending cleanup did.
struct InboxCleanupResult: Equatable {
    var removed = 0
    var updated = 0
}

/// What one calendar scan did.
struct CalendarScanResult: Equatable {
    var access: CalendarAccess
    /// Newly added pending suggestions (what a notifier may announce).
    var added: [Suggestion]
    var skipped: CalendarSkipCounts
    /// The scan stopped before finishing (the user cancelled the backfill, or the task was
    /// cancelled). The backfill is NOT complete. Items streamed before the stop stay pending in
    /// the inbox (`added` lists them); nothing after the stop is ingested.
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
    let classifier: CaptureClassifier
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

    /// Scan of the next 7 days. With a `ClassifierChain` it runs the same path as the backfill
    /// (rules, then the on-device model, "Not sure" kept), so the two always agree. Any other
    /// classifier is asked one event at a time.
    func scanUpcoming(properties: [RentalProperty], entries: [TimeEntry]) async -> CalendarScanResult {
        let interval = detector.upcomingInterval(now: clock(), calendar: calendar)
        if let chain = classifier as? ClassifierChain {
            return await scanBatched(interval: interval, chain: chain, properties: properties, entries: entries, skipSettled: true)
        }
        return await scan(interval, properties: properties, entries: entries)
    }

    /// Day-1 backfill through the WP2 chain's batch API, with progress. WP-L: it streams. Each
    /// item is put in the inbox store as soon as it is classified (on the main actor, in the
    /// order they finish) and handed to `onIngest`, so the Inbox fills in while the scan runs.
    /// Likely and "Not sure" items are both kept (low confidence is shown, never hidden); muted
    /// and no-signal items are dropped. Hours and start stay 1.x's (see type comment).
    /// Cancelled: stops classifying and ingests nothing more; items already streamed stay.
    func scanBackfillBatched(
        chain: ClassifierChain,
        properties: [RentalProperty],
        entries: [TimeEntry],
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void = { _ in },
        onIngest: @escaping @MainActor ([Suggestion]) -> Void = { _ in }
    ) async -> CalendarScanResult {
        await scanBatched(
            interval: detector.backfillInterval(now: clock(), calendar: calendar),
            chain: chain, properties: properties, entries: entries, progress: progress, onIngest: onIngest
        )
    }

    /// The chain's batch API over `interval`. `skipSettled`: leave out events the store would
    /// ignore anyway (dismissed or confirmed), so a scan on every launch doesn't ask the model
    /// again about them.
    private func scanBatched(
        interval: DateInterval,
        chain: ClassifierChain,
        properties: [RentalProperty],
        entries: [TimeEntry],
        skipSettled: Bool = false,
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void = { _ in },
        onIngest: @escaping @MainActor ([Suggestion]) -> Void = { _ in }
    ) async -> CalendarScanResult {
        var candidates: [CaptureCandidate]
        do {
            candidates = try await detector.detect(in: interval)
        } catch CalendarCaptureError.noAccess(let access) {
            return .blocked(access)
        } catch {
            return .blocked(detector.access)
        }
        if skipSettled {
            candidates = candidates.filter { store.wouldIngest(sourceKey: $0.sourceKey) }
        }

        enum Event: Sendable {
            case result(Int, ClassifierOutcome)
            case progress(ClassifierBatchProgress)
        }
        let (events, continuation) = AsyncStream.makeStream(of: Event.self)
        // Created on the main actor and cancelled below before this function first suspends,
        // so a scan cancelled at once never classifies anything.
        let batch = Task { () throws -> [ClassifierOutcome] in
            defer { continuation.finish() }
            return try await chain.classifyBatch(
                candidates,
                properties: properties,
                onResult: { continuation.yield(.result($0, $1)) },
                progress: { continuation.yield(.progress($0)) }
            )
        }
        var added: [Suggestion] = []
        await withTaskCancellationHandler {
            for await event in events {
                switch event {
                case .result(let index, let outcome):
                    guard !Task.isCancelled, candidates.indices.contains(index),
                          let classification = CalendarVisibility.shown(outcome, title: candidates[index].title) else { continue }
                    let candidate = candidates[index]
                    let suggestion = prepared(Suggestion(candidate: candidate, classification: classification), candidate: candidate, properties: properties)
                    let new = store.ingest([suggestion], existingEntries: entries, calendar: calendar)
                    if !new.isEmpty {
                        added.append(contentsOf: new)
                        onIngest(new)
                    }
                case .progress(let value):
                    guard !Task.isCancelled else { continue }
                    progress(value)
                }
            }
        } onCancel: {
            batch.cancel()
        }
        // classifyBatch throws only on cancellation.
        guard (try? await batch.value) != nil, !Task.isCancelled else {
            return CalendarScanResult(access: .fullAccess, added: added, skipped: detector.lastSkipCounts, cancelled: true)
        }
        return CalendarScanResult(access: .fullAccess, added: added, skipped: detector.lastSkipCounts)
    }

    /// The 2.2 one-time cleanup. Re-reads the calendar events behind every PENDING calendar
    /// suggestion (the old scanner let in team meetings, salon visits and the like), classifies
    /// them with the current chain, and:
    /// - removes the ones that now score hidden AND have no landlord word in the title, as a system call (never "dismissed by user");
    /// - lowers the confidence, tier and evidence of the ones now below their old score.
    /// Confirmed, dismissed and manual records are never read or changed, and a pending item
    /// whose event can't be found is left as it is. Returns nil when it already ran, or when it
    /// couldn't run yet (no calendar access, cancelled): the flag stays unset then, so it runs
    /// later. Idempotent: once the flag is set a second call does nothing.
    func cleanUpPendingOnce(chain: ClassifierChain, properties: [RentalProperty], entries: [TimeEntry]) async -> InboxCleanupResult? {
        guard !store.hasRunPendingCleanup, detector.access.canReadEvents else { return nil }
        let pending = store.pending.filter { $0.kind == .calendar }
        guard let first = pending.map(\.start).min(), let last = pending.map(\.start).max() else {
            store.markPendingCleanupDone()
            return InboxCleanupResult()
        }
        let keys = Set(pending.map(\.sourceKey))
        guard let found = try? await detector.detect(in: DateInterval(start: first, end: last.addingTimeInterval(1))) else { return nil }
        let candidates = found.filter { keys.contains($0.sourceKey) }
        guard let outcomes = try? await chain.classifyBatch(candidates, properties: properties), !Task.isCancelled else { return nil }

        var result = InboxCleanupResult()
        var hidden = Set<String>()
        for (candidate, outcome) in zip(candidates, outcomes) {
            if case .muted = outcome { continue }   // a mute is the user's rule: left to the normal flow
            if let shown = CalendarVisibility.shown(outcome, title: candidate.title, keepKeywordTitles: true) {
                if let current = store.suggestion(forKey: candidate.sourceKey), shown.confidence < current.confidence {
                    store.lowerConfidence(forKey: candidate.sourceKey, to: shown)
                    result.updated += 1
                }
            } else {
                hidden.insert(candidate.sourceKey)
            }
        }
        result.removed = store.removeHiddenBySystem(keys: hidden)
        store.markPendingCleanupDone()
        return result
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
            // "Not sure" items are kept too (landlord evidence below the likely line).
            guard classification.isLandlordWork || classification.hasLandlordEvidence else { continue }
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
