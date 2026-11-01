import SwiftUI

// MARK: - Today › Learn (2.3, package C; frame l1, t1)
//
// DashboardView places this under To confirm and above the care slot. One milestone card ("You're at
// 420 of 750. Here's what usually counts.") with "Read · 2 min", a close button, and "See all" in the
// header. It shows only at a milestone the person hasn't read or dismissed, only for the 750-hour
// goal, and only while a lesson is unread. Everything else draws nothing. The slot owns its padding.
struct TodayLearnSlot: View {
    /// The rental Today is focused on (nil with one rental, or "All").
    let rentalID: UUID?

    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var goalManager: GoalManager
    @ObservedObject private var progress = LessonProgressStore.shared
    @ObservedObject private var entitlements = EntitlementStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var open: LessonOpen?
    @State private var showList = false
    /// The milestone to mark handled once the sheet closes. Marking it earlier would clear the card
    /// and take the open sheet's host with it.
    @State private var pendingMilestone: Int?
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var card: LearnMilestone.Card? {
        let hours = Self.debugHours ?? viewModel.houseCountableHours()
        return LearnMilestone.card(hours: hours, goal: Int(goalManager.houseGoal.targetHours),
                                   wantsGoal750: goalManager.goalChoice == .reps750,
                                   handled: progress.handledMilestone, read: progress.readIDs,
                                   lessonIDs: LearnLibrary.lessons.map(\.id))
    }

    var body: some View {
        Group {
            if let card, let lesson = LearnLibrary.lesson(id: card.lessonID) {
                milestone(card, lesson: lesson)
                    .padding(.top, LHMetrics.sectionGap)
                    .padding(.horizontal, LHMetrics.gutter)
            }
        }
        .navigationDestination(isPresented: $showList) { LearningCenterView() }
        .lessonSheet(open: $open)
        .onChange(of: open) { _, now in
            // Reading clears the card, but only after the sheet is gone: an empty slot can't host it.
            if now == nil, let milestone = pendingMilestone {
                pendingMilestone = nil
                progress.handleMilestone(milestone)
            }
        }
    }

    private func milestone(_ card: LearnMilestone.Card, lesson: Lesson) -> some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            HStack(alignment: .firstTextBaseline) {
                Text(LearnLibrary.line("learn.today.header"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(LearnLibrary.line("learn.today.seeAll")) { showList = true }
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("today.learn.seeAll")
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 24)
            HStack(alignment: .top, spacing: 12) {
                LHRowGlyph(systemImage: "book", tint: .action)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(card, lesson: lesson))
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(LearnLibrary.format("lesson.readButton", lesson.minutes)) {
                        pendingMilestone = card.milestone
                        LessonLauncher.open(lesson.id, into: $open)
                        if open == nil { pendingMilestone = nil; progress.handleMilestone(card.milestone) }   // the paywall opened instead
                    }
                    .buttonStyle(LHButton.secondary)
                    .padding(.top, 8)
                    .accessibilityIdentifier("today.learn.read")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { progress.handleMilestone(card.milestone) } label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel(LearnLibrary.line("lesson.notNow"))
                    .accessibilityIdentifier("today.learn.dismiss")
                    .padding(.top, -6)
                    .padding(.trailing, -6)
            }
            .padding(LHMetrics.cardPadding)
            .background(colors.backgroundSecondary, in: shape)
            .overlay { shape.strokeBorder(colors.pageCardEdge, lineWidth: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.learn")
    }

    private func headline(_ card: LearnMilestone.Card, lesson: Lesson) -> String {
        card.isFirstLesson
            ? LearnLibrary.format("lesson.card.title", card.hours, card.goal)
            : LearnLibrary.format("lesson.card.next", lesson.title)
    }

    /// DEBUG: `-LHLearnHours <n>` pretends the house is at n hours (milestone frames and tests).
    private static var debugHours: Double? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHLearnHours"), args.indices.contains(i + 1) { return Double(args[i + 1]) }
        #endif
        return nil
    }
}
