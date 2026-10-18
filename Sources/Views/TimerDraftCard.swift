import SwiftUI
import LucideIcons

/// Track card for a timer draft awaiting review (forgotten >24 h, or paused at a profile
/// switch). The elapsed time is always shown; capped drafts must be reviewed, never saved
/// with one tap; a draft whose property was deleted names the property it will save to.
struct TimerDraftCard: View {
    let recovery: StaleTimerRecovery

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var chosenPropertyId: UUID?
    @State private var showReview = false

    private var needsProperty: Bool { viewModel.staleTimerRecoveryNeedsProperty(recovery) }
    private var remaining: Int { max(viewModel.staleTimerRecoveries.count - 1, 0) }
    /// Where the hours will be saved: the draft's property, or the one the user picked.
    private var targetProperty: RentalProperty? {
        if !needsProperty { return viewModel.properties.first { $0.id == recovery.propertyId } }
        let id = chosenPropertyId ?? viewModel.properties.first?.id
        return viewModel.properties.first { $0.id == id }
    }
    private var isCaution: Bool { recovery.requiresReview || recovery.reason == .forgotten }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            if needsProperty, !viewModel.properties.isEmpty {
                propertyPicker
            }
            actions
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .strokeBorder(colors.border.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showReview) {
            TimerDraftReviewSheet(
                recovery: recovery,
                propertyName: targetProperty?.name ?? "this property"
            ) { hours in
                showReview = false
                if viewModel.saveRecoveredStaleTimer(id: recovery.id, hours: hours, propertyId: targetProperty?.id) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(image: isCaution ? Lucide.timerReset : Lucide.timer, size: 20)
                .foregroundStyle(isCaution ? colors.cautionText : colors.informationalText)
                .frame(width: 42, height: 42)
                .background(isCaution ? colors.cautionSurface : colors.informationalSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Finish your saved timer")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if remaining > 0 {
                        Text("\(remaining) more")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.informationalText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(colors.informationalSurface)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("timerDraft.queueChip")
                    }
                }
                Text(recovery.cardHeadline)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .monospacedDigit()
                    .accessibilityIdentifier("timerDraft.ran")
                Text(message)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("timerDraft.summary")
    }

    private var message: String {
        recovery.cardMessage(
            propertyName: needsProperty ? nil : targetProperty?.name,
            hasAnyProperty: !viewModel.properties.isEmpty
        )
    }

    private var accessibilitySummary: String {
        let more = remaining > 0 ? " \(remaining) more timer drafts after this one." : ""
        return "\(recovery.accessibilityTitle) \(recovery.cardHeadline). \(message)\(more)"
    }

    // MARK: Property picker (deleted property)

    private var propertyPicker: some View {
        Menu {
            ForEach(viewModel.properties) { property in
                Button(property.name) { chosenPropertyId = property.id }
            }
        } label: {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.building2, size: 15)
                    .foregroundStyle(colors.actionText)
                Text("Save to")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                Text(targetProperty?.name ?? "Choose property")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                LucideIcon(image: Lucide.chevronsUpDown, size: 14)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
        }
        .accessibilityLabel("Save to \(targetProperty?.name ?? "a property")")
        .accessibilityIdentifier("timerDraft.pickProperty")
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 10) {
            primaryAction
            Button {
                viewModel.discardRecoveredStaleTimer(id: recovery.id)
            } label: {
                buttonLabel("Discard")
                    .foregroundStyle(colors.destructive)
                    .background(colors.backgroundTertiary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("timerDraft.discard")
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if viewModel.properties.isEmpty {
            Button {
                NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
            } label: {
                primaryLabel("Add property")
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("timerDraft.addProperty")
        } else if recovery.requiresReview {
            Button {
                showReview = true
            } label: {
                primaryLabel("Review hours")
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("timerDraft.review")
        } else {
            Button {
                if viewModel.saveRecoveredStaleTimer(id: recovery.id, propertyId: needsProperty ? targetProperty?.id : nil) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                primaryLabel("Save \(recovery.durationLabel)")
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("timerDraft.save")
        }
    }

    private func primaryLabel(_ text: String) -> some View {
        buttonLabel(text)
            .foregroundStyle(colors.onAction)
            .background(colors.action)
            .clipShape(Capsule())
    }

    private func buttonLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.buttonSmall)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
    }
}

/// Entry editor for a capped draft: the hours start at the 24 h cap and the user sets the
/// real figure before anything is saved.
struct TimerDraftReviewSheet: View {
    let recovery: StaleTimerRecovery
    let propertyName: String
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var hours: Double
    @State private var confirmed = false

    private var canSave: Bool { recovery.canSaveReview(hours: hours, confirmed: confirmed) }

    init(recovery: StaleTimerRecovery, propertyName: String, onSave: @escaping (Double) -> Void) {
        self.recovery = recovery
        self.propertyName = propertyName
        self.onSave = onSave
        _hours = State(initialValue: recovery.suggestedHours)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("How long did you actually work?")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(recovery.ranLabel) at \(propertyName), so we stopped it at 24 hours. Change the hours to the time you really worked, or confirm 24 hours is right.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Text(AppFormat.hours(hours))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .monospacedDigit()
                        .accessibilityIdentifier("timerDraftReview.hours")
                    Spacer(minLength: 0)
                    stepButton(icon: Lucide.minus, label: "Fewer hours", id: "timerDraftReview.decrement",
                               enabled: hours > 0.25) { hours = max(hours - 0.25, 0.25) }
                    stepButton(icon: Lucide.plus, label: "More hours", id: "timerDraftReview.increment",
                               enabled: hours < 24) { hours = min(hours + 0.25, 24) }
                }
                .accessibilityElement(children: .contain)

                confirmRow

                Spacer(minLength: 0)

                Button {
                    guard canSave else { return }
                    onSave(hours)
                } label: {
                    Text("Save \(AppFormat.hours(hours))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canSave ? colors.action : colors.backgroundTertiary)
                        .foregroundStyle(canSave ? colors.onAction : colors.textSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)
                .disabled(!canSave)
                .accessibilityIdentifier("timerDraftReview.save")
                .accessibilityHint(canSave ? "" : "Change the hours or confirm them first.")
            }
            .padding(20)
            .background(colors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.actionText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 44 pt round step button (the stock Stepper's segments measured 30.7 pt).
    private func stepButton(icon: UIImage, label: String, id: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(image: icon, size: 18)
                .foregroundStyle(enabled ? colors.textPrimary : colors.textSecondary)
                .frame(width: 44, height: 44)
                .background(colors.backgroundTertiary)
                .clipShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// An explicit "these hours are right" check. A drawn box, not a stock Toggle: on
    /// iOS 27 the stock off track is close to invisible on a light card.
    private var confirmRow: some View {
        Button {
            confirmed.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(confirmed ? colors.action : colors.backgroundSecondary)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(confirmed ? colors.action : colors.textSecondary, lineWidth: 2)
                    if confirmed {
                        LucideIcon(image: Lucide.check, size: 16)
                            .foregroundStyle(colors.onAction)
                    }
                }
                .frame(width: 32, height: 32)
                Text("These hours are right")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("These hours are right")
        .accessibilityValue(confirmed ? "Checked" : "Not checked")
        .accessibilityAddTraits(confirmed ? [.isSelected] : [])
        .accessibilityIdentifier("timerDraftReview.confirm")
    }
}
