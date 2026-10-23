import SwiftUI
import LucideIcons

// MARK: - Check my goal (2.1)
//
// From Settings, next to the goal. Per rental, "Who does most of the hands-on work at <name>?"
// (only where each rental can have its own target), then the diff "What the app would track"
// and two buttons of equal weight: Keep (pins what changed) and Switch (targets re-derive).
// When nothing would change there is only Done. Rules decide; nothing here calls a model.

struct GoalCheckView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var store = RentalPlanStore.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var draft: [UUID: WhoDoesMost] = [:]
    @State private var open: UUID?
    @State private var loaded = false

    var body: some View {
        let ctx = viewModel.rentalPlanContext
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Check my goal", tableName: "Home")
                        .lhDisplayFont(.largeTitle)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    if GoalCheck.asksPerRental(ctx) {
                        perRental(ctx)
                    } else {
                        shared(ctx)
                    }
                    Text(RentalPlanWords.cpaLine)
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("goalCheck.cpa")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(colors.background.ignoresSafeArea())
            .onAppear {
                load(ctx)
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-LHGoalCheckScrollDiff") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo("goalCheck.diff", anchor: .top) }
                }
#endif
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Like Tax profile: the floating tab bar would cover the Keep / Switch buttons.
        .hidesAppTabBar()
        .accessibilityIdentifier("goalCheck.screen")
    }

    private func load(_ ctx: RentalPlanContext) {
        guard !loaded else { return }
        loaded = true
        draft = store.whoDoesMost.filter { id, _ in ctx.properties.contains { $0.id == id } }
        open = ctx.properties.first { draft[$0.id] == nil }?.id ?? ctx.properties.first?.id
    }

    // MARK: Per rental

    @ViewBuilder
    private func perRental(_ ctx: RentalPlanContext) -> some View {
        let rows = GoalCheck.rows(ctx, draft: draft)
        Text("Say who does most of the hands-on work at each rental. The app shows what it would track, and you choose.", tableName: "Home")
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(Array(ctx.properties.enumerated()), id: \.element.id) { index, property in
            question(property, index: index)
        }
        diff(rows).id("goalCheck.diff")
        buttons(ctx, rows: rows)
    }

    @ViewBuilder
    private func question(_ property: RentalProperty, index: Int) -> some View {
        let answer = draft[property.id]
        VStack(alignment: .leading, spacing: 10) {
            if open == property.id {
                Text(GoalCheckWords.question(property.name))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 8) {
                    ForEach(WhoDoesMost.allCases, id: \.self) { option in
                        GoalChoiceRow(title: GoalCheckWords.answer(option), selected: answer == option,
                                      identifier: "goalCheck.answer.\(index).\(option.rawValue)") {
                            set(option, for: property.id)
                        }
                    }
                }
            } else {
                Button {
                    if reduceMotion { open = property.id } else { withAnimation(AppAnimation.standard) { open = property.id } }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(property.name)
                                .font(.headline)
                                .foregroundStyle(colors.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(GoalCheckWords.shortAnswer(answer))
                                .font(.subheadline)
                                .foregroundStyle(colors.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Text("Change", tableName: "Home")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.action)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.lhPressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "\(property.name), \(GoalCheckWords.shortAnswer(answer))", table: "Home"))
                .accessibilityHint(String(localized: "Change who does most of the work here", table: "Home"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("goalCheck.change.\(index)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goalCheck.question.\(index)")
    }

    private func set(_ who: WhoDoesMost, for id: UUID) {
        let apply = { draft[id] = who }
        if reduceMotion { apply() } else { withAnimation(AppAnimation.standard) { apply() } }
    }

    // MARK: Diff

    private func diff(_ rows: [GoalCheckRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the app would track", tableName: "Home")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(colors.border) }
                diffRow(row, index: index)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goalCheck.diff")
    }

    private func diffRow(_ row: GoalCheckRow, index: Int) -> some View {
        let from = GoalCheckWords.trackValue(row.current)
        let to = GoalCheckWords.trackValue(row.proposed)
        let why = GoalCheckWords.reason(row)
        let change = row.changes
            ? String(localized: "From \(from) to \(to)", table: "Home")
            : String(localized: "\(from) · no change", table: "Home")
        return VStack(alignment: .leading, spacing: 4) {
            Text(row.name)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
            if row.changes {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { changeParts(from: from, to: to) }
                    VStack(alignment: .leading, spacing: 2) { changeParts(from: from, to: to) }
                }
                .font(.subheadline)
            } else {
                Text(change)
                    .font(.subheadline)
                    .foregroundStyle(colors.textPrimary)
            }
            Text(why)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name). \(change). \(why).")
        .accessibilityIdentifier("goalCheck.diff.\(index)")
    }

    @ViewBuilder
    private func changeParts(from: String, to: String) -> some View {
        Text(from).strikethrough().foregroundStyle(colors.textSecondary)
        LucideIcon(image: Lucide.chevronRight, size: 14).foregroundStyle(colors.textSecondary)
        Text(to).fontWeight(.semibold).foregroundStyle(colors.action)
    }

    // MARK: Buttons

    @ViewBuilder
    private func buttons(_ ctx: RentalPlanContext, rows: [GoalCheckRow]) -> some View {
        if rows.contains(where: \.changes) {
            // Equal weight: same shape, same fill, so neither leans toward an answer.
            VStack(spacing: 10) {
                equalButton(String(localized: "Keep what I have", table: "Home"), identifier: "goalCheck.keep") {
                    GoalCheckActions.keep(ctx, draft: draft, store: store)
                    finish()
                }
                equalButton(GoalCheckWords.switchTitle(rows), identifier: "goalCheck.switch") {
                    GoalCheckActions.switchToProposed(draft: draft, store: store)
                    finish()
                }
            }
        } else {
            equalButton(String(localized: "Done", table: "Home"), identifier: "goalCheck.done") {
                GoalCheckActions.saveAnswers(draft, store: store)
                finish()
            }
        }
    }

    private func finish() {
        RentalPlanAnnouncer.announce(viewModel.rentalPlanContext)
        dismiss()
    }

    private func equalButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.action)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(colors.actionSurface))
                .contentShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier(identifier)
    }

    // MARK: One total (750, grouping, record)

    @ViewBuilder
    private func shared(_ ctx: RentalPlanContext) -> some View {
        let mode = RentalPlanning.mode(ctx)
        VStack(alignment: .leading, spacing: 8) {
            Text("Your goal", tableName: "Home")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
            Text(goalManager.goalChoice.title)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(GoalCheckWords.sharedExplanation(mode))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("goalCheck.shared")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        equalButton(String(localized: "Done", table: "Home"), identifier: "goalCheck.done") { dismiss() }
    }
}
