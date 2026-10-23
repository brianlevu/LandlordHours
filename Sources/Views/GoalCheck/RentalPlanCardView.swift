import SwiftUI

// MARK: - The rental page's first card: how this rental is tracked (2.1)
//
// Two choices where each rental can have its own target ("Track a goal for this rental" /
// "Record only"), one tap, no confirm sheet. Under 750, grouping or a record goal the card is
// read-only and links to the goal. The CPA line sits under every goal decision.

struct RentalPlanCardView: View {
    let property: RentalProperty

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var store = RentalPlanStore.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        let ctx = viewModel.rentalPlanContext
        let plan = RentalPlanning.plan(for: property, ctx)
        VStack(alignment: .leading, spacing: 10) {
            PropertySectionHeader(String(localized: "This rental’s goal", table: "Home"))
            VStack(alignment: .leading, spacing: 12) {
                if RentalPlanCard.isEditable(ctx) {
                    VStack(spacing: 8) {
                        GoalChoiceRow(title: RentalPlanWords.trackAGoal, selected: plan.track.hasOwnTarget,
                                      identifier: "plan.track") { choose(track: true, ctx) }
                        GoalChoiceRow(title: RentalPlanWords.recordOnly, selected: plan.track.isRecordOnly,
                                      identifier: "plan.record") { choose(track: false, ctx) }
                    }
                    Text(RentalPlanCard.explanation(for: property, ctx))
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(RentalPlanStore.describe(plan.track))
                        .transition(.opacity)
                        .accessibilityIdentifier("plan.explanation")
                } else {
                    Text(RentalPlanCard.readOnlyLine(ctx))
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan.readOnly")
                    NavigationLink {
                        TaxProfileView()
                    } label: {
                        Text("Change goal", tableName: "Home")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.action)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.lhPressable)
                    .accessibilityIdentifier("plan.changeGoal")
                }
                Text(RentalPlanWords.cpaLine)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .propertyCard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property.plan")
    }

    private func choose(track: Bool, _ ctx: RentalPlanContext) {
        guard RentalPlanning.plan(for: property, ctx).track.hasOwnTarget != track else { return }
        let apply = { RentalPlanCard.choose(track: track, for: property, ctx, store: store) }
        if reduceMotion { apply() } else { withAnimation(AppAnimation.standard) { apply() } }
        RentalPlanAnnouncer.announce(viewModel.rentalPlanContext)
    }
}

/// A radio row of equal weight: a ring, the title, a soft fill when selected.
struct GoalChoiceRow: View {
    let title: String
    let selected: Bool
    var identifier: String? = nil
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.body)
                    .foregroundStyle(selected ? colors.action : colors.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(selected ? colors.actionSurface : colors.backgroundTertiary,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier ?? "")
    }
}
