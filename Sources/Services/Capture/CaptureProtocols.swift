import Foundation

// MARK: - Capture pipeline seams
//
// Detectors → Classifier → SuggestionStore (inbox) → Notifier → confirm().
// WP0 defines only the contracts; implementations arrive in later work packages. Tests use the
// fakes in the test target.

/// What a calendar event says besides its title and place. Read by the classifier for signals
/// that an event is NOT rental work (a video call, a team invite). Local only: never stored,
/// never synced, never sent to the model.
struct CalendarContext: Equatable {
    static let maxNotesLength = 500

    /// People on the invite, the owner included.
    var attendeeCount = 0
    var url: String?
    var notes: String?
    var organizedByOther = false
    var isWorkCalendar = false
    var isRecurring = false

    init(attendeeCount: Int = 0, url: String? = nil, notes: String? = nil, organizedByOther: Bool = false,
         isWorkCalendar: Bool = false, isRecurring: Bool = false) {
        self.attendeeCount = attendeeCount
        self.url = url
        self.notes = notes
        self.organizedByOther = organizedByOther
        self.isWorkCalendar = isWorkCalendar
        self.isRecurring = isRecurring
    }

    static func trimmedNotes(_ notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        return String(notes.prefix(maxNotesLength))
    }
}

/// A raw activity a detector found, before classification.
struct CaptureCandidate: Equatable {
    var sourceKey: String
    var kind: Suggestion.Kind
    var start: Date
    var end: Date?
    /// Local only (calendar title, receipt merchant). Never synced.
    var title: String
    var externalId: String?
    /// Calendar `eventIdentifier` (device-local); kept for 1.1 import dedupe.
    var legacyEventIdentifier: String?
    var containerId: String?
    var location: String?
    var isBackfill: Bool
    /// When the detector first saw it. Calendar items use max(firstSeen, eventEnd).
    var detectedAt: Date
    /// Calendar only: attendees, link, notes, organizer, calendar type, repeat. Empty otherwise.
    var context = CalendarContext()

    init(
        sourceKey: String,
        kind: Suggestion.Kind,
        start: Date,
        end: Date? = nil,
        title: String,
        externalId: String? = nil,
        legacyEventIdentifier: String? = nil,
        containerId: String? = nil,
        location: String? = nil,
        isBackfill: Bool = false,
        detectedAt: Date,
        context: CalendarContext = CalendarContext()
    ) {
        self.context = context
        self.sourceKey = sourceKey
        self.kind = kind
        self.start = start
        self.end = end
        self.title = title
        self.externalId = externalId
        self.legacyEventIdentifier = legacyEventIdentifier
        self.containerId = containerId
        self.location = location
        self.isBackfill = isBackfill
        self.detectedAt = detectedAt
    }
}

/// Finds candidate landlord activities in one source (calendar, receipts, location, Gmail).
protocol CaptureDetector {
    var kind: Suggestion.Kind { get }
    /// Candidates whose activity falls in `interval`. Must be safe to call repeatedly; the
    /// store dedupes by `sourceKey`.
    func detect(in interval: DateInterval) async throws -> [CaptureCandidate]
}

/// What the classifier proposes for a candidate.
struct CaptureClassification: Equatable {
    var isLandlordWork: Bool
    var confidence: Double
    var propertyId: UUID?
    var category: ActivityCategory?
    /// Nil when hours can't be known (receipts never guess hours).
    var hours: Double?
    var hoursBasis: Suggestion.HoursBasis
    var tier: Suggestion.Tier
    var evidence: [String]
}

/// Decides whether a candidate is rental work and proposes property, category and hours.
protocol CaptureClassifier {
    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification
}

/// Tells the user about new suggestions (end-of-event local notifications).
protocol CaptureNotifier {
    /// Schedules notifications for `suggestions` for `profileId`. Implementations enforce the
    /// budget and quiet hours.
    func schedule(_ suggestions: [Suggestion], profileId: String) async
    /// Removes pending/delivered notifications for these keys (confirmed or dismissed elsewhere).
    func cancel(sourceKeys: [String]) async
}

extension Suggestion {
    /// Builds an inbox item from a detector candidate and its classification.
    init(candidate: CaptureCandidate, classification: CaptureClassification) {
        self.init(
            sourceKey: candidate.sourceKey,
            kind: candidate.kind,
            detectedAt: candidate.detectedAt,
            start: candidate.start,
            end: candidate.end,
            title: candidate.title,
            externalId: candidate.externalId,
            legacyEventIdentifier: candidate.legacyEventIdentifier,
            containerId: candidate.containerId,
            proposedPropertyId: classification.propertyId,
            proposedCategory: classification.category,
            proposedHours: classification.hours,
            hoursBasis: classification.hoursBasis,
            confidence: classification.confidence,
            tier: classification.tier,
            evidence: classification.evidence,
            isBackfill: candidate.isBackfill
        )
    }
}
