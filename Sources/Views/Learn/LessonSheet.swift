import SwiftUI

// MARK: - The lesson sheet (2.3, package C)
//
// Three cards that page sideways (`flow` motion, a `.selection` haptic), a segmented progress bar and
// "Card n of 3" on top, and a pinned Next / Done. The sheet sits on the canvas (standard §1.20, grouped
// cards) with an `LHFootFade` over the pinned button. A free person gets card 1 of the first lesson;
// Next then opens the paywall. Reduce Motion swaps the flow for a quick fade. Frames l2–l4, l6–l11.

struct LessonOpen: Identifiable, Equatable {
    let lessonID: String
    var card = 0
    let access: LessonAccess
    var id: String { "\(lessonID)-\(card)" }
}

struct LessonSheet: View {
    let lesson: Lesson
    let access: LessonAccess
    /// Called when a free person taps Next on the preview card.
    var onUpgrade: () -> Void = {}
    /// The note for the "Work you do yourself" card, from the person's log.
    var personalNote: String? = nil

    @State private var card: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(lesson: Lesson, startCard: Int = 0, access: LessonAccess, personalNote: String? = nil, onUpgrade: @escaping () -> Void = {}) {
        self.lesson = lesson
        self.access = access
        self.personalNote = personalNote
        self.onUpgrade = onUpgrade
        _card = State(initialValue: access == .full ? min(max(0, startCard), max(0, lesson.cards.count - 1)) : 0)
    }

    private var isLast: Bool { card == lesson.cards.count - 1 }
    private var isPreview: Bool { access == .preview }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    // A free person's preview holds card 1 only: the other cards aren't built at all.
                    ForEach(isPreview ? Array(lesson.cards.prefix(1)) : lesson.cards) { item in
                        ScrollView {
                            LessonCardView(card: item, isLast: item.index == lesson.cards.count - 1, personalNote: personalNote)
                                .padding(.horizontal, LHMetrics.gutter)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .containerRelativeFrame(.horizontal)
                        .id(item.index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollDisabled(isPreview)
            .scrollPosition(id: Binding(get: { Optional(card) }, set: { if let value = $0 { card = value } }))
            .defaultScrollAnchor(.leading)
            .animation(reduceMotion ? nil : AppAnimation.flow, value: card)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(isLast ? LearnLibrary.line("lesson.done") : LearnLibrary.line("lesson.next")) { advance() }
                .buttonStyle(LHButton.primary)
                .contentTransition(.opacity)
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background { LHFootFade(color: colors.background) }
                .accessibilityIdentifier("lesson.next")
        }
        .background { LHCanvas() }
        .presentationBackground(colors.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: card)
        .onChange(of: card) { _, _ in markIfFinished() }
        .onAppear { markIfFinished() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson.sheet")
    }

    private func advance() {
        if isLast { dismiss(); return }
        if isPreview { onUpgrade(); return }
        card += 1
    }

    /// Reaching the last card counts as read.
    private func markIfFinished() {
        if access == .full, isLast { LessonProgressStore.shared.markRead(lesson.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                    Text(LearnLibrary.format("lesson.cardOf", card + 1, lesson.cards.count))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(colors.textSecondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("lesson.cardOf")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel(LearnLibrary.line("lesson.close"))
                    .accessibilityIdentifier("lesson.close")
            }
            LHSegmentedProgress(count: lesson.cards.count, current: card)
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 24)
    }
}

// MARK: - Presenting a lesson (shared by Today and the list)

/// Presents the lesson sheet for `open`, or the paywall when the person's plan doesn't cover it.
/// The paywall entry is `.settingsPro` until package A adds `LockEntry.learning`.
struct LessonSheetHost: ViewModifier {
    @Binding var open: LessonOpen?
    @EnvironmentObject private var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.sheet(item: $open) { item in
            if let lesson = LearnLibrary.lesson(id: item.lessonID) {
                LessonSheet(lesson: lesson, startCard: item.card, access: item.access,
                            personalNote: note(for: lesson), onUpgrade: { upgrade(lesson.id) })
            }
        }
    }

    private func note(for lesson: Lesson) -> String? {
        let year = Calendar.current.component(.year, from: Date())
        // The same person the Today number counts (REPS is one spouse alone).
        let participant = GoalManager.shared.repsParticipant
        let entries = viewModel.timeEntries
            .filter { Calendar.current.component(.year, from: $0.date) == year && $0.participant == participant }
            .map { (category: $0.category, hours: $0.hours) }
        guard let share = LessonInsights.share(entries: entries) else { return nil }
        return LearnLibrary.format("lesson.counts.c1.note", share.hours, share.phrase)
    }

    private func upgrade(_ lessonID: String) {
        open = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            // After a purchase the lesson opens in full.
            ProPaywallPresenter.shared.present(entry: .settingsPro, onUnlocked: { open = LessonOpen(lessonID: lessonID, access: .full) })
        }
    }
}

extension View {
    func lessonSheet(open: Binding<LessonOpen?>) -> some View { modifier(LessonSheetHost(open: open)) }
}

enum LessonLauncher {
    /// DEBUG: `-LHLearnFree` treats the plan as free for lessons (the mock's Pro seed stays for the rest).
    private static var debugFree: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-LHLearnFree")
        #else
        return false
        #endif
    }

    /// Where a lesson opens for the current plan.
    @MainActor
    static func open(_ lessonID: String, card: Int = 0, into binding: Binding<LessonOpen?>) {
        let allowed = EntitlementStore.shared.plan.allows(.learning) && !debugFree
        switch LessonAccess.route(lessonID: lessonID, firstLessonID: LearnLibrary.lessons.first?.id, allowed: allowed) {
        case .paywall: ProPaywallPresenter.shared.present(entry: .settingsPro)
        case let access: binding.wrappedValue = LessonOpen(lessonID: lessonID, card: card, access: access)
        }
    }
}
