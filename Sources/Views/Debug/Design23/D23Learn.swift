import SwiftUI

#if DEBUG
// MARK: - Learning: card A plus B's list (2.3 design sandbox)
//
// Today: a "Learn" section with one milestone card ("You're at 420 of 750. Here's what counts."),
// shown at milestones only and dismissable. Read opens a 3-card sheet; every lesson ends on
// "Talk to your CPA". See all pushes the lesson list with progress (the Learning center, grown).
// Lesson text is general learning for a CPA-style review before it ships.

struct D23Lesson: Identifiable {
    let id: Int
    let title: String
    let minutes: Int
    let cards: [D23LessonCard]
}

struct D23LessonCard: Identifiable {
    enum Body {
        /// Two lists: what usually counts and what usually doesn't.
        case counts(yes: [String], no: [String])
        /// Short labelled lines in one group (a sample log line, a rule).
        case lines([(label: String, value: String)])
        /// Numbered questions to take to your CPA.
        case questions([String])
        case none
    }

    let id: Int
    let title: String
    let text: String
    let body: Body
    /// One inset note under the body, tied to the person's own log where it can be.
    var note: String? = nil
    var noteSymbol: String = "chart.bar"
}

enum D23Lessons {
    static let all: [D23Lesson] = [
        D23Lesson(id: 0, title: "What counts toward the 750", minutes: 2, cards: [
            D23LessonCard(
                id: 0,
                title: "Work you do yourself usually counts",
                text: "Hours count when you do the work yourself. Owning the rental isn’t enough.",
                body: .counts(yes: ["Repairs and upkeep you do",
                                    "Showings, leases and tenant calls",
                                    "Hiring and managing contractors"],
                              no: ["Reading statements as an investor",
                                   "Learning about real estate in general",
                                   "Hours a manager puts in for you"]),
                note: "Most of your 420 hours are repairs and showings."),
            D23LessonCard(
                id: 1,
                title: "It has to be more than half your work",
                text: "The 750 has a second part. Your rental hours need to be more than half of all the hours you work. Your day job counts in that total.",
                body: .lines([("Day job", "1,800h"), ("Rental work", "more than 1,800h")]),
                note: "A full-time job makes this part hard to reach.",
                noteSymbol: "briefcase"),
            D23LessonCard(
                id: 2,
                title: "Talk to your CPA",
                text: "Your CPA decides what the numbers mean. Take these questions:",
                body: .questions(["Which of my hours count toward the 750?",
                                  "Do I pass the more-than-half part?",
                                  "Should I count my rentals together?"])),
        ]),
        D23Lesson(id: 1, title: "You and your spouse", minutes: 2, cards: [
            D23LessonCard(
                id: 0,
                title: "For the 750, one of you gets there alone",
                text: "One spouse has to pass both parts alone. Your hours don’t add together for the 750.",
                body: .lines([("Your hours", "520h"), ("Your spouse’s", "310h"), ("For the 750", "520h, not 830h")]),
                note: "Dormer keeps your hours and your spouse’s apart.",
                noteSymbol: "person.2"),
            D23LessonCard(
                id: 1,
                title: "For the 500-hour test, your hours add up",
                text: "Here your hours and your spouse’s add up, on each rental.",
                body: .lines([("Your hours", "320h"), ("Your spouse’s", "210h"), ("For the 500", "530h together")]),
                note: "Say who did the work each time you log.",
                noteSymbol: "person.2"),
            D23LessonCard(
                id: 2,
                title: "Talk to your CPA",
                text: "Ask which test fits your return. Take these questions:",
                body: .questions(["Which test matters for us, the 750 or the 500?",
                                  "Whose hours should we count?",
                                  "Does my spouse’s job change anything?"])),
        ]),
        D23Lesson(id: 2, title: "What a good log looks like", minutes: 2, cards: [
            D23LessonCard(
                id: 0,
                title: "Four things in every line",
                text: "A good line says when, where, what you did and for how long.",
                body: .lines([("When", "Oct 12"), ("Where", "Pine Cabin"), ("What", "Cleared the gutters"), ("How long", "2h")]),
                note: "Dormer fills most of this when you type a note.",
                noteSymbol: "text.cursor"),
            D23LessonCard(
                id: 1,
                title: "Log it the same week",
                text: "Notes from the same week are easier to stand behind than a guess in December. Log the hours you worked, not a round number.",
                body: .none,
                note: "Calendar suggestions help you catch the days you missed.",
                noteSymbol: "calendar"),
            D23LessonCard(
                id: 2,
                title: "Talk to your CPA",
                text: "Ask what your CPA wants to see. Take these questions:",
                body: .questions(["Is the PDF of my hours enough?",
                                  "Do you want my receipts too?",
                                  "How long should I keep these records?"])),
        ]),
    ]

    /// The list behind "See all": the three written lessons, then the next three (titles only).
    static let list: [(title: String, minutes: Int, done: Bool)] = [
        ("What counts toward the 750", 2, true),
        ("You and your spouse", 2, false),
        ("What a good log looks like", 2, false),
        ("Short stays and long stays", 3, false),
        ("Counting your rentals together", 2, false),
        ("Getting ready for tax season", 3, false),
    ]
}

// MARK: Today card

struct D23MilestoneCard: View {
    let hours: Double
    let goal: Double
    var onRead: () -> Void
    var onSeeAll: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            D23TodayHeader(title: "Learn", trailing: "See all", action: onSeeAll)
            HStack(alignment: .top, spacing: 12) {
                LHRowGlyph(systemImage: "book", tint: .action)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re at \(Int(hours)) of \(Int(goal)). Here’s what usually counts.")
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                    Button("Read · 2 min", action: onRead)
                        .buttonStyle(LHButton.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { } label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel("Not now")
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
}

// MARK: Lesson sheet

struct D23LessonSheet: View {
    let lessonIndex: Int
    let startCard: Int
    @State private var card = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lesson: D23Lesson { D23Lessons.all[min(lessonIndex, D23Lessons.all.count - 1)] }
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(lessonIndex: Int, startCard: Int) {
        self.lessonIndex = lessonIndex
        self.startCard = startCard
        _card = State(initialValue: startCard)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Cards page sideways in a paging scroll view: swipe or Next.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(lesson.cards) { item in
                        ScrollView {
                            D23LessonCardView(card: item, isLast: item.id == lesson.cards.count - 1)
                                .padding(.horizontal, LHMetrics.gutter)
                                .padding(.top, 20)
                                .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: Binding(get: { Optional(card) }, set: { if let v = $0 { card = v } }))
            .defaultScrollAnchor(.leading)
            .onAppear {
                // Opens on the requested card (captures open cards 2 and 3 directly).
                let start = startCard
                card = 0
                DispatchQueue.main.async { card = start }
            }
            .animation(reduceMotion ? AppAnimation.quick : AppAnimation.flow, value: card)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let last = card == lesson.cards.count - 1
            Button(last ? "Done" : "Next") {
                if last { dismiss() } else { card += 1 }
            }
            .buttonStyle(LHButton.primary)
            .contentTransition(.opacity)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background { D23FootFade(color: colors.background) }
        }
        .background { LHCanvas() }
        .presentationBackground(colors.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: card)
        .accessibilityIdentifier("lesson.sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                    Text("Card \(card + 1) of \(lesson.cards.count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(colors.textSecondary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel("Close")
            }
            HStack(spacing: 6) {
                ForEach(0..<lesson.cards.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= card ? colors.action : colors.actionSurface)
                        .frame(height: 4)
                }
            }
            .animation(AppAnimation.standard, value: card)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 24)
    }
}

struct D23LessonCardView: View {
    let card: D23LessonCard
    let isLast: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(LHFont.screenTitle(size: 28))
                .foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(card.text)
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .lineSpacing(2)
                .padding(.top, 12)
            bodyContent
                .padding(.top, LHMetrics.sectionGap)
            if let note = card.note {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: card.noteSymbol)
                        .font(.body)
                        .foregroundStyle(colors.action)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(LHMetrics.cardPadding)
                .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .padding(.top, 16)
            }
            if isLast {
                LHFootnote("General learning, not tax advice.")
                    .padding(.top, LHMetrics.sectionGap)
            }
        }
        .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var bodyContent: some View {
        switch card.body {
        case .counts(let yes, let no):
            VStack(alignment: .leading, spacing: 16) {
                list("Usually counts", items: yes, symbol: "checkmark", tint: .positive)
                list("Usually doesn’t", items: no, symbol: "xmark", tint: .neutral)
            }
        case .lines(let lines):
            LHRowGroup {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { LHDivider(leadingInset: 16) }
                    HStack(spacing: 12) {
                        Text(line.label)
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                        Spacer(minLength: 8)
                        Text(line.value)
                            .font(.body.weight(.semibold))
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .foregroundStyle(colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(LHRow.insets)
                    .frame(minHeight: LHMetrics.rowMinHeight)
                    .accessibilityElement(children: .combine)
                }
            }
        case .questions(let questions):
            LHRowGroup {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.body.weight(.semibold))
                            .fontDesign(.rounded)
                            .foregroundStyle(colors.action)
                            .frame(width: 36, height: 36)
                            .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                            .accessibilityHidden(true)
                        Text(question)
                            .font(.body)
                            .foregroundStyle(colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(LHRow.insets)
                    .frame(minHeight: LHMetrics.rowMinHeight)
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func list(_ title: String, items: [String], symbol: String, tint: LHRowGlyph.Tint) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            Text(title)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            // A read-only list of lines in one card, not rows to act on: no dividers, an inline
            // glyph per line (Monzo, Lloyds).
            LHRowGroup {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tint == .positive ? colors.positive : colors.textSecondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.body)
                            .foregroundStyle(colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, index == 0 ? 14 : 6)
                    .padding(.bottom, index == items.count - 1 ? 14 : 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: Lesson list (See all)

struct D23LessonListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var open: D23LessonOpen?
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        let read = D23Lessons.list.filter(\.done).count
        let total = D23Lessons.list.count
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                progressCard(read: read, total: total)
                D23Section(title: "Lessons") {
                    LHRowGroup {
                        ForEach(Array(D23Lessons.list.enumerated()), id: \.offset) { index, lesson in
                            if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                            let upNext = index == read
                            LHRow.Browse(title: lesson.title,
                                         meta: lesson.done ? "Read" : (upNext ? "Up next · " : "") + "3 cards · \(lesson.minutes) min",
                                         action: { if index < 3 { open = D23LessonOpen(lesson: index, card: 0) } }) {
                                if lesson.done {
                                    D23DoneTile()
                                } else {
                                    D23NumberTile(number: index + 1, emphasised: upNext)
                                }
                            }
                        }
                    }
                }
                D23Section(title: "Short reads") {
                    LHRowGroup {
                        ForEach(Array(["The more-than-half rule", "Spouse hours", "Keeping receipts"].enumerated()), id: \.offset) { index, title in
                            if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                            LHRow.Browse(title: title, systemImage: "book", tint: .neutral, action: {})
                        }
                    }
                }
                LHFootnote("General learning, not tax advice.")
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhTabScreen("Learning center", back: LHBackAction(label: "Back", identifier: "learn.back") { dismiss() })
        .hidesAppTabBar()
        .sheet(item: $open) { D23LessonSheet(lessonIndex: $0.lesson, startCard: $0.card) }
        .accessibilityIdentifier("learn.list")
    }

    private func progressCard(read: Int, total: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(read) of \(total)")
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
            Text("lessons read · about 2 minutes each")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            D23ProgressBar(value: Double(read) / Double(total))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(read) of \(total) lessons read")
    }
}

/// The reading order tile (Learning center's number tile): action wash when it's up next,
/// neutral otherwise.
struct D23NumberTile: View {
    let number: Int
    var emphasised = false
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Text(String(number))
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(emphasised ? colors.action : colors.textSecondary)
            .frame(width: side, height: side)
            .background(emphasised ? colors.actionSurface : colors.backgroundTertiary,
                        in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
#endif
