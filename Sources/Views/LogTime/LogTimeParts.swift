import SwiftUI

// MARK: - Log time parts kept from 2.0: Me / Spouse, the mic ring, the timer card, the voice intro flag

/// Me / Spouse on brand tokens (the system segmented control renders grey on iOS 27).
struct LogWhoPicker: View {
    @Binding var participant: Participant
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 2) {
            ForEach([Participant.selfParticipant, .spouse], id: \.self) { option in
                let selected = participant == option
                Button {
                    if reduceMotion { participant = option } else { withAnimation(AppAnimation.quick) { participant = option } }
                } label: {
                    Text(verbatim: option == .spouse ? String(localized: "Spouse") : String(localized: "Me"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? colors.onAction : colors.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 64, minHeight: 44)
                        .background(Capsule().fill(selected ? colors.action : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .spouse ? String(localized: "Spouse") : String(localized: "Me"))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier(option == .spouse ? "log.who.spouse" : "log.who.me")
            }
        }
        .padding(3)
        .background(Capsule().fill(colors.backgroundTertiary))
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// A 2pt drafting ring that follows the input level; still in silence and under Reduce Motion.
struct LogMicLevelRing: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .strokeBorder(AdaptiveColors(colorScheme: colorScheme).drafting, lineWidth: 2)
            .scaleEffect(1 + (reduceMotion ? 0 : min(max(level, 0), 1)) * 0.18)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
            .accessibilityHidden(true)
    }
}

/// The Live Activity layout at full size, on theme-fixed blueprint. No dial, ring or pulse.
struct LiveTimerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let property: RentalProperty?
    let properties: [RentalProperty]
    let category: ActivityCategory
    let start: Date
    var onStop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = min(context.date.timeIntervalSince(start), TimerReviewMath.cap)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let property {
                        PropertySeal(property, in: properties, size: 24)
                            .environment(\.colorScheme, .dark)
                    }
                    Text(property?.name ?? "Timer")
                        .font(.headline)
                        .foregroundStyle(OnBlueprint.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                    Text("LandlordHours")
                        .font(.caption2.monospaced().weight(.medium))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(HouseTokens.drafting)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                    }
                }
                Text(LogTimeFormat.clock(elapsed))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OnBlueprint.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeOut(duration: 0.2), value: Int(elapsed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(String(localized: "Running for \(InboxFormat.spokenHours(elapsed / 3600))"))
                    .accessibilityIdentifier("timer.clock")
                Text(String(localized: "\(category.inboxLabel)\(LogTimeFormat.dot)started \(InboxFormat.clockTime(start))"))
                    .font(.subheadline)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Stop", action: onStop)
                    .buttonStyle(OnBlueprintButtonStyle())
                    .accessibilityIdentifier("timer.stop")
            }
            .padding(20)
            .background(InboxBlueprintPaper(cornerRadius: 24))
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
