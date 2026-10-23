import SwiftUI

#if DEBUG
// MARK: - Inbox: the same LHRow.Action, the question card (§1.1 card: question + answers)

struct StdInboxScreen: View {
    let seed: StdSeed
    let launch: StdProtoLaunch
    @State private var items: [StdSuggestion]
    @State private var confirmed: Set<String> = []
    /// rowConfirm phase 2/3: faded, then collapsed to zero height (our spring), then removed without animation.
    @State private var fading: Set<String> = []
    @State private var collapsing: Set<String> = []
    @State private var toast: LHToastSpec?
    @State private var successTick = 0
    @State private var dismissTick = 0
    @State private var goalCheck: StdGoalCheckStart?
    @State private var overflow = false
    @State private var picked: StdGoalCheckStart.Answer?
    @State private var cardAnswer: StdGoalCheckStart.Answer?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(seed: StdSeed, launch: StdProtoLaunch) {
        self.seed = seed
        self.launch = launch
        _items = State(initialValue: launch.screen == .inbox && launch.state == "empty" ? [] : seed.suggestions)
        if launch.state == "answered" {
            _picked = State(initialValue: .cleaner)
            _cardAnswer = State(initialValue: .cleaner)
        }
        if launch.screen == .goalcheck {
            let step: StdGoalCheckStart.Step
            switch launch.state {
            case "result": step = .result
            case "summary": step = .summary
            default: step = .question
            }
            _goalCheck = State(initialValue: StdGoalCheckStart(step: step))
        }
    }

    private var likely: [StdSuggestion] { items.filter { $0.isLikely && !confirmed.contains($0.id) } }
    private var asksCleaner: Bool { (seed.id == "brian" || seed.id == "eight") && !items.isEmpty }

    private var groups: [(name: String, items: [StdSuggestion])] { stdDayGroups(items) }

    /// The batch action pins above the tab bar while the list overflows (critique #4).
    private var pinned: Bool { overflow && likely.count >= 2 }

    var body: some View {
        List {
            if items.isEmpty {
                Section {} header: { emptyState.stdHeaderInsets() }
            }
            if !groups.isEmpty {
                Section {
                    ForEach(Array(groups.enumerated()), id: \.element.name) { gi, g in
                        StdDayHeader(title: g.name).stdDayRow(first: gi == 0, colors: colors)
                        ForEach(Array(g.items.enumerated()), id: \.element.id) { ii, item in
                            row(item)
                        }
                    }
                    if !pinned && likely.count >= 2 {
                        Button(StdCanon.confirmLikely(likely.count)) { confirmLikely() }
                            .buttonStyle(StdButtonStyle(.tertiary))
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(colors.backgroundSecondary)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        StdScreenTitle(title: L("Inbox"), subtitle: L("\(items.count) to confirm"))
                            .padding(.bottom, 8)
                        if asksCleaner && !typeSize.isAccessibilitySize { questionCard.padding(.top, 16) }
                    }
                    .stdHeaderInsets()
                } footer: {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(StdCanon.nothingCounts)
                            .font(.footnote).foregroundStyle(colors.textSecondary)
                            .padding(.top, 4)
                        // Large text: the question waits under the list so rows lead (D2/D3).
                        if asksCleaner && typeSize.isAccessibilitySize { questionCard }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom } action: { y in
            StdGeom.log(String(format: "STDGEOM fold %.1f 0 0 0", y))
        }
        .modifier(StdOverflowReader(overflow: $overflow))
        .listSectionSpacing(24)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 1)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinned {
                // §1.3b pinned batch bar: material capsule, hairline, 12pt above the tab bar, inset 20.
                Button { confirmLikely() } label: {
                    Text(StdCanon.confirmLikely(likely.count))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                        .contentTransition(.numericText(value: Double(likely.count)))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(.regularMaterial))
                        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(StdPressStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
                    .accessibilityIdentifier("inbox.confirmLikely.pinned")
            }
        }
        .animation(StdMotion.reveal, value: pinned)
        .overlay(alignment: .bottom) {
            if let toast {
                LHToast(spec: toast).padding(.horizontal, 16).padding(.bottom, 12).id(toast.id)
                    .transition(.asymmetric(insertion: .offset(y: reduceMotion ? 0 : 24).combined(with: .opacity),
                                            removal: .offset(y: reduceMotion ? 0 : 12).combined(with: .opacity)))
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
        .sheet(item: $goalCheck) { start in
            StdGoalCheckSheet(seed: seed, start: start, demo: launch.demo == "goalcheck") { goalCheck = nil }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func row(_ item: StdSuggestion) -> some View {
        StdActionRow(item: item, confirmed: confirmed.contains(item.id), onConfirm: { confirm(item) }, showDay: false)
            .stdMeasure("row.\(item.id)")
            .listRowInsets(EdgeInsets(top: typeSize.isAccessibilitySize ? 4 : 10, leading: 16,
                                      bottom: typeSize.isAccessibilitySize ? 4 : 10, trailing: 16))
            .listRowBackground(colors.backgroundSecondary)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 34 }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 16 }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { confirm(item) } label: { Label(StdCanon.confirm, systemImage: "checkmark") }
                    .tint(colors.positive)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { decline(item) } label: { Label(StdCanon.notRentalWork, systemImage: "xmark") }
                    .tint(colors.textSecondary)
            }
    }

    // MARK: Empty (§1.18 full screen): blueprint art, one headline, one line, one primary

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            StdScreenTitle(title: L("Inbox"))
                .padding(.bottom, 24)
            ZStack {
                HouseBlueprintPaper()
                HouseLineworkImage(name: HouseKeyframe.k00_lot.linesImageName)
                    .foregroundStyle(HouseTokens.drafting)
                    .padding(16)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(L("Nothing to confirm"))
                .font(.title3.weight(.semibold)).foregroundStyle(colors.textPrimary)
                .padding(.top, 24)
            Text(L("Calendar events and reminders that look like rental work show up here."))
                .font(.subheadline).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button(L("Log time")) {}
                .buttonStyle(StdButtonStyle(.primary))
                .padding(.top, 24)
        }
        .textCase(nil)
        .accessibilityElement(children: .contain)
    }

    // MARK: The question card (critique #3): short eyebrow, three equal chips, collapses once answered

    private var questionCard: some View {
        let rental = seed.rentals.rentals.first { $0.shortStay } ?? seed.rentals.rentals[0]
        return Group {
            if let answer = cardAnswer {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(colors.positive)
                    Text(answeredLine(answer, rental.name))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L("Undo")) { withAnimation(StdMotion.collapse) { cardAnswer = nil; picked = nil } }
                        .buttonStyle(StdButtonStyle(.tertiary))
                }
                .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 4)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label { Text(L("From your calendar")) } icon: { Image(systemName: "calendar") }
                        .font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                        .foregroundStyle(colors.draftingInk)
                    Text(L("Who does more of the work at \(rental.name)?"))
                        .font(.headline).foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        chip(L("Cleaner"), .cleaner)
                        chip(L("Me"), .me)
                        chip(L("Not sure"), .notSure)
                    }
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
        .stdMeasure("card.question")
    }

    private func chip(_ text: String, _ answer: StdGoalCheckStart.Answer) -> some View {
        StdChip(text: text, selected: picked == answer, fill: true) {
            withAnimation(StdMotion.quick) { picked = answer }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.collapse) { cardAnswer = answer }
            }
        }
    }

    private func answeredLine(_ a: StdGoalCheckStart.Answer, _ name: String) -> String {
        switch a {
        case .cleaner: return L("Noted. \(name) tracks 500 now.")
        case .me, .spouse: return L("Noted. \(name) keeps 100.")
        case .notSure: return L("Noted. We'll ask again later.")
        }
    }

    // MARK: Actions

    private func confirm(_ item: StdSuggestion) {
        guard item.canQuickLog, !confirmed.contains(item.id) else { return }
        successTick += 1
        collapseRows([item.id], fill: true)
        show(LHToastSpec(kind: .success, message: L("Logged \(StdFormat.hours(item.hours))."), actionTitle: L("Undo")))
    }

    private func decline(_ item: StdSuggestion) {
        dismissTick += 1
        collapseRows([item.id], fill: false)
        show(LHToastSpec(kind: .neutral, message: L("Marked not rental work."), actionTitle: L("Undo")))
    }

    private func confirmLikely() {
        let batch = likely
        successTick += 1
        collapseRows(batch.map(\.id), fill: true)
        show(LHToastSpec(kind: .success, message: L("Logged \(batch.count)."), actionTitle: L("Undo")))
    }

    private func collapseRows(_ ids: [String], fill: Bool) {
        let set = Set(ids)
        StdRowConfirm.run(id: ids.first ?? "", reduceMotion: reduceMotion,
                          fill: { if fill { confirmed.formUnion(set) } },
                          fade: { fading.formUnion(set) },
                          collapse: { collapsing.formUnion(set) },
                          remove: { items.removeAll { set.contains($0.id) }; fading.subtract(set); collapsing.subtract(set) })
    }

    private func show(_ spec: LHToastSpec) {
        withAnimation(StdMotion.reveal) { toast = spec }
        let id = spec.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard toast?.id == id else { return }
            withAnimation(StdMotion.quick) { toast = nil }
        }
    }
}
#endif

#if DEBUG
/// Reports whether the list's content is taller than its viewport (iOS 18+; earlier: never pins).
struct StdOverflowReader: ViewModifier {
    @Binding var overflow: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in
                g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom > g.containerSize.height + 1
            } action: { _, v in overflow = v }
        } else {
            content
        }
    }
}
#endif
