import SwiftUI

// MARK: - Backfill scanning seam

struct BackfillScanOutcome: Equatable {
    var access: CalendarAccess
    /// Newly found pending items (for the count; the list reads the store).
    var foundCount: Int
}

/// Runs the day-1 90-day scan. Production: WP1's coordinator + WP2's `classifyBatch`.
protocol BackfillScanning {
    @MainActor func scan(progress: @escaping @Sendable (ClassifierBatchProgress) -> Void) async -> BackfillScanOutcome
}

/// The real scan: calendar → classifier chain (batch, with progress) → the profile's inbox.
struct CalendarBackfillScanner: BackfillScanning {
    let store: SuggestionStore
    let properties: [RentalProperty]
    let entries: [TimeEntry]

    @MainActor func scan(progress: @escaping @Sendable (ClassifierBatchProgress) -> Void) async -> BackfillScanOutcome {
        let coordinator = CalendarCaptureCoordinator(
            detector: CalendarDetector(source: EventKitCalendarSource()),
            store: store
        )
        let result = await coordinator.scanBackfillBatched(
            chain: .forStore(store),
            properties: properties,
            entries: entries,
            progress: progress
        )
        return BackfillScanOutcome(access: result.access, foundCount: result.added.count)
    }
}

/// WP-H's `BackfillRevealView` (the house building in hatched hours) shows before the list when
/// anything was found. Set `makeView` to nil to skip it. Arguments: found hours, suggestion
/// count, and the action that continues to the list.
enum BackfillRevealHook {
    @MainActor static var makeView: ((Double, Int, @escaping () -> Void) -> AnyView)? = { hours, count, next in
        AnyView(BackfillRevealView(foundHours: hours, suggestionCount: count, onReview: next, onSkip: next))
    }
}

// MARK: - Model

@MainActor
final class BackfillIntroModel: ObservableObject {
    enum Phase: Equatable {
        case scanning(completed: Int, total: Int)
        case reveal
        case results
        case blocked(CalendarAccess)
    }

    @Published private(set) var phase: Phase = .scanning(completed: 0, total: 0)
    @Published var showAll = false
    @Published private(set) var foundCount = 0

    /// The ranked list the intro shows: top 15 until "Show more".
    func items(from pending: [Suggestion]) -> [Suggestion] {
        let ranked = InboxLogic.ranked(pending.filter(\.isBackfill))
        return showAll ? ranked : Array(ranked.prefix(InboxLogic.backfillPreviewLimit))
    }

    func hiddenCount(from pending: [Suggestion]) -> Int {
        guard !showAll else { return 0 }
        return max(0, pending.filter(\.isBackfill).count - InboxLogic.backfillPreviewLimit)
    }

    func run(_ scanner: BackfillScanning, revealAvailable: Bool? = nil) async {
        let revealAvailable = revealAvailable ?? (BackfillRevealHook.makeView != nil)
        phase = .scanning(completed: 0, total: 0)
        let outcome = await scanner.scan { [weak self] progress in
            Task { @MainActor in
                guard let self, case .scanning = self.phase else { return }
                self.phase = .scanning(completed: progress.completed, total: progress.total)
            }
        }
        guard outcome.access == .fullAccess else {
            phase = .blocked(outcome.access)
            return
        }
        foundCount = outcome.foundCount
        CaptureOptIn.markBackfillCompleted()
        phase = revealAvailable && outcome.foundCount > 0 ? .reveal : .results
    }

    func finishReveal() { phase = .results }
}

// MARK: - View

/// Day-1 backfill intro: scan with progress, then "We found N visits that look like landlord
/// work", ranked by confidence, top 15 + "Show more". Nothing is saved until confirmed.
struct BackfillIntroView: View {
    let scanner: BackfillScanning
    var onDone: (_ openInbox: Bool) -> Void

    @EnvironmentObject private var viewModel: AppViewModel
    @StateObject private var model = BackfillIntroModel()
    @StateObject private var inbox: InboxViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(scanner: BackfillScanning, inbox: @autoclosure @escaping () -> InboxViewModel, onDone: @escaping (Bool) -> Void) {
        self.scanner = scanner
        self.onDone = onDone
        _inbox = StateObject(wrappedValue: inbox())
    }

    var body: some View {
        Group {
            switch model.phase {
            case .scanning(let completed, let total):
                scanning(completed: completed, total: total)
            case .reveal:
                if let make = BackfillRevealHook.makeView {
                    make(foundHours, model.foundCount) { model.finishReveal() }
                } else {
                    results
                }
            case .results:
                results
            case .blocked:
                blocked
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : AppAnimation.smooth, value: model.phase)
        .task {
            inbox.undoWindow = 0
            await model.run(scanner)
            inbox.reload()
        }
        .sheet(item: $inbox.sheetSuggestion, onDismiss: { inbox.commitPending() }) { suggestion in
            SuggestionConfirmSheet(suggestion: suggestion, model: inbox)
        }
        .onDisappear { inbox.commitPending() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backfill.intro")
    }

    private var foundHours: Double {
        inbox.visible.filter(\.isBackfill).reduce(0) { $0 + ($1.proposedHours ?? 0) }
    }

    // MARK: Scanning

    private func scanning(completed: Int, total: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                InboxBlueprintPaper(cornerRadius: 28)
                    .frame(width: 168, height: 168)
                Image("bp_house_k18_finished_lines")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .accessibilityHidden(true)
            }
            Text("Looking back 90 days")
                .font(AppTypography.drafting)
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(colors.draftingInk)
            Text("Reading your calendar on this iPhone")
                .font(.title3.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
            ProgressView(value: total > 0 ? Double(completed) : 0, total: Double(max(total, 1)))
                .tint(colors.action)
                .frame(maxWidth: 240)
                .accessibilityLabel("Scanning")
                .accessibilityValue(total > 0 ? "\(completed) of \(total) events" : "Starting")
                .accessibilityIdentifier("backfill.progress")
            Text(total > 0 ? "\(completed) of \(total) events" : "Getting your events")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(colors.textSecondary)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }

    // MARK: Results

    private var results: some View {
        let pending = inbox.visible
        let items = model.items(from: pending)
        let total = pending.filter(\.isBackfill).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(total == 0
                         ? "Nothing from the last 90 days looked like rental work"
                         : (total == 1 ? "We found 1 visit that looks like landlord work"
                                       : "We found \(total) visits that look like landlord work"))
                        .font(.title.weight(.bold))
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("backfill.headline")
                    Text(total == 0
                         ? "We'll keep an eye on new events and ask you when one looks like work."
                         : "Most likely first. Nothing counts until you confirm it. Tap one to check it, or review them all in your Inbox.")
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)

                if !items.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, suggestion in
                            Button {
                                inbox.sheetSuggestion = suggestion
                            } label: {
                                SuggestionRowView(
                                    suggestion: suggestion,
                                    propertyName: inbox.propertyName(for: suggestion),
                                    badges: inbox.badges(for: suggestion)
                                )
                                .padding(.leading, 12)
                                .padding(.trailing, 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(SuggestionRowView.accessibilityLabel(
                                for: suggestion, propertyName: inbox.propertyName(for: suggestion),
                                badges: inbox.badges(for: suggestion), now: Date()))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("backfill.row.\(index)")
                            if index < items.count - 1 {
                                Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 74)
                            }
                        }
                    }
                    .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 24)

                    let hidden = model.hiddenCount(from: pending)
                    if hidden > 0 {
                        Button("Show \(hidden) more") {
                            if reduceMotion { model.showAll = true } else { withAnimation(AppAnimation.flow) { model.showAll = true } }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 8)
                        .accessibilityIdentifier("backfill.showMore")
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(total == 0 ? "Done" : "Review in Inbox") {
                    inbox.commitPending()
                    onDone(total > 0)
                }
                .buttonStyle(InboxPrimaryButtonStyle())
                .accessibilityIdentifier("backfill.done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(colors.background)
        }
        .background(colors.background)
    }

    // MARK: Blocked

    private var blocked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We can't read your calendar")
                .font(.title.weight(.bold))
                .foregroundStyle(colors.textPrimary)
            Text("Calendar access is off for LandlordHours. Turn on Full Access in Settings, then come back to the Inbox.")
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(InboxPrimaryButtonStyle())
            Button("Not now") { onDone(false) }
                .font(.body)
                .foregroundStyle(colors.action)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .background(colors.background)
    }
}
