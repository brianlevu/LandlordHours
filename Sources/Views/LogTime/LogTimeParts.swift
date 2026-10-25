import SwiftUI

// MARK: - Log time parts kept from 2.0: the mic ring, the timer card, the voice intro flag

/// A 2pt drafting ring that follows the input level; still in silence and under Reduce Motion.
/// It sits around the mic button (`LHButton.icon`, 44 → 52 with the ring).
struct LogMicLevelRing: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .strokeBorder(AdaptiveColors(colorScheme: colorScheme).drafting, lineWidth: 2)
            .padding(-4)
            .scaleEffect(1 + (reduceMotion ? 0 : min(max(level, 0), 1)) * 0.18)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: level)
            .accessibilityHidden(true)
    }
}

/// The running timer, on the sheet: the rental, the clock and what it is for. The Stop button is the
/// sheet's one `.primary`, pinned at the foot (`timer.stop`). The clock reads the rental's name the
/// way the Live Activity does.
struct LiveTimerCard: View {
    let property: RentalProperty?
    let category: ActivityCategory
    let start: Date

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = min(context.date.timeIntervalSince(start), TimerReviewMath.cap)
            VStack(alignment: .leading, spacing: 8) {
                Text(property?.name ?? lt("Timer"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                Text(LogTimeFormat.clock(elapsed))
                    .lhHeroNumberFont()
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(LogSheetDebug.state == nil ? AppAnimation.standard : nil, value: Int(elapsed))
                    .accessibilityLabel(lt("Running for \(LHFormat.spokenHours(elapsed / 3600))"))
                    .accessibilityIdentifier("timer.clock")
                Text(lt("\(category.inboxLabel) \u{00B7}\u{00A0}started \(LogTimeFormat.clockTime(start))"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timer.card")
    }
}

/// "Talk like you'd tell a friend" shows once, before the system asks.
enum LogVoiceIntro {
    private static var key: String { UserScope.key("LandlordHours.voiceIntroSeen") }
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}

extension AppViewModel {
    /// Stops the running timer into a draft the review (and Today's draft card) can log.
    /// The draft is stored before the timer ends, so nothing is lost if the app dies here.
    @discardableResult
    func stopTimerIntoDraft(now: Date = Date()) -> StoppedTimerDraft? {
        guard isTimerRunning, let start = timerStartTime, let propertyId = timerPropertyId else { return nil }
        let draft = StoppedTimerDraft(elapsed: now.timeIntervalSince(start), propertyId: propertyId, category: timerCategory,
                                      startDate: start, participant: .selfParticipant, notes: "")
        StoppedTimerDraftStore.save(draft)
        cancelTimer()
        return draft
    }
}
