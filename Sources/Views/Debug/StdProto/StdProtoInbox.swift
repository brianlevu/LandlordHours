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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    init(seed: StdSeed, launch: StdProtoLaunch) {
        self.seed = seed
        self.launch = launch
        _items = State(initialValue: seed.suggestions)
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
    private var asksCleaner: Bool { seed.id == "brian" || seed.id == "eight" }

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    StdActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
                        .stdMeasure("row.\(item.id)")
                        .modifier(StdCollapse(fading: fading.contains(item.id), collapsed: collapsing.contains(item.id)))
                        .listRowInsets(collapsing.contains(item.id) ? EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
                                                                    : EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
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
                if likely.count >= 2 {
                    Button(StdCanon.confirmLikely(likely.count)) { confirmLikely() }
                        .buttonStyle(StdButtonStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(colors.backgroundSecondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    StdScreenTitle(title: L("Inbox"))
                        .padding(.bottom, 8)
                    if asksCleaner && !typeSize.isAccessibilitySize { questionCard.padding(.top, 16) }
                    StdSectionHeader(title: L("To confirm"), count: items.count).padding(.top, 24)
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
        .listStyle(.insetGrouped)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom } action: { y in
            StdGeom.log(String(format: "STDGEOM fold %.1f 0 0 0", y))
        }
        .listSectionSpacing(24)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 1)
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

    // MARK: The question card

    private var questionCard: some View {
        let rental = seed.rentals.rentals.first { $0.shortStay } ?? seed.rentals.rentals[0]
        return VStack(alignment: .leading, spacing: 10) {
            Label { Text(L("From your calendar · weekly")) } icon: { Image(systemName: "calendar") }
                .font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                .foregroundStyle(colors.draftingInk)
            Text(L("Does the cleaner do more hours at \(rental.name) than you?"))
                .font(.headline).foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { answers; Spacer(minLength: 0); notSure }
                VStack(alignment: .leading, spacing: 8) { answers; notSure }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
        .stdMeasure("card.question")
    }

    @ViewBuilder private var answers: some View {
        Button(L("They do")) { goalCheck = StdGoalCheckStart(step: .result) }
            .buttonStyle(StdButtonStyle(.secondary))
        Button(L("I do")) { goalCheck = StdGoalCheckStart(step: .result, answer: .me) }
            .buttonStyle(StdButtonStyle(.secondary))
    }

    private var notSure: some View {
        Button(L("Not sure")) {}.buttonStyle(StdButtonStyle(.tertiary))
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
