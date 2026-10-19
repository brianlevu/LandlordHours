import SwiftUI

/// WP-L: the Inbox's compact header for the background 90-day look-back. While it runs: the
/// drafting line sketching the house, "Looking through your calendar…", live progress and how
/// many it has found, and Cancel. After a stop: "Run again". If calendar access went away: the
/// Settings path. Suggestions stream into the list below it as they are classified.
struct BackfillProgressHeader: View {
    @ObservedObject var job: BackfillJob
    var onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch job.phase {
            case .scanning(let completed, let total):
                scanning(completed: completed, total: total)
            case .cancelled:
                stopped
            case .blocked:
                blocked
            case .idle, .finished:
                EmptyView()
            }
        }
    }

    // MARK: Scanning

    private func scanning(completed: Int, total: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            DraftingLoader(sketch: .house, surface: .blueprint, lineWidth: 1.6)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Looking through your calendar…")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OnBlueprint.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.detail(completed: completed, total: total, found: job.foundCount))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(OnBlueprint.secondary)
                    .contentTransition(.numericText())
                    .lineLimit(2)
                BackfillProgressLine(fraction: total > 0 ? Double(completed) / Double(total) : 0)
                    .frame(height: 3)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Button("Cancel") { job.cancel() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnBlueprint.primary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("Stops looking back. You can run it again.")
                .accessibilityIdentifier("backfill.cancel")
        }
        .padding(.vertical, 14)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(InboxBlueprintPaper())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: completed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Looking through your calendar. \(Self.detail(completed: completed, total: total, found: job.foundCount))")
        .accessibilityIdentifier("inbox.backfill.header")
    }

    /// "Getting your events" → "12 of 80 events · 5 found so far".
    static func detail(completed: Int, total: Int, found: Int) -> String {
        guard total > 0 else { return "Getting your events" }
        let events = "\(completed) of \(total) events"
        guard found > 0 else { return events }
        return "\(events) · \(found) found so far"
    }

    // MARK: Stopped

    private var stopped: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stopped looking back")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OnBlueprint.primary)
                Text(job.foundCount > 0
                     ? "What we found so far is below. Run it again to finish the last 90 days."
                     : "Run it again any time to check the last 90 days.")
                    .font(.subheadline)
                    .foregroundStyle(OnBlueprint.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Run again", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HouseTokens.blueprint)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white))
                .accessibilityIdentifier("inbox.backfill.retry")
        }
        .padding(14)
        .background(InboxBlueprintPaper())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.backfill.stopped")
    }

    // MARK: Blocked

    private var blocked: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("We can't read your calendar")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OnBlueprint.primary)
                Text("Turn on Full Access for LandlordHours in Settings, then run it again.")
                    .font(.subheadline)
                    .foregroundStyle(OnBlueprint.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HouseTokens.blueprint)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.white))
        }
        .padding(14)
        .background(InboxBlueprintPaper())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.backfill.blocked")
    }
}

/// A thin drafting-cyan progress line on blueprint paper.
struct BackfillProgressLine: View {
    var fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(HouseTokens.drafting)
                    .frame(width: max(3, g.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}
