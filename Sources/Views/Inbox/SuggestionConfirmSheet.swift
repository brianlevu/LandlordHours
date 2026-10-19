import SwiftUI

/// Confirm sheet for one suggestion (Flighty header + status band, Skyscanner stepper, Brick
/// value rows). The only place a not-sure, already-logged or hour-less item can be logged.
struct SuggestionConfirmSheet: View {
    let suggestion: Suggestion
    @ObservedObject var model: InboxViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hours: Double
    @State private var propertyId: UUID?
    @State private var category: ActivityCategory?
    @State private var participant: Participant = .selfParticipant
    @State private var notes: String
    @State private var showMuteOptions = false
    @State private var stepTick = 0
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    /// Hours stepper bounds and step (15 minutes).
    static let step = 0.25
    static let maxHours = 24.0

    init(suggestion: Suggestion, model: InboxViewModel) {
        self.suggestion = suggestion
        self.model = model
        let proposed = suggestion.hoursBasis == .none ? 0 : (suggestion.proposedHours ?? 0)
        _hours = State(initialValue: max(0, proposed))
        _propertyId = State(initialValue: suggestion.proposedPropertyId)
        _category = State(initialValue: suggestion.proposedCategory)
        _notes = State(initialValue: suggestion.kind == .calendar ? suggestion.title : "")
    }

    private var badges: SuggestionBadges { model.badges(for: suggestion) }

    private var edits: SuggestionEdits {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultNotes = suggestion.kind == .calendar ? suggestion.title : ""
        return SuggestionEdits(
            propertyId: propertyId,
            category: category,
            hours: hours > 0 ? hours : nil,
            participant: model.showsSpousePicker ? participant : .selfParticipant,
            // Unchanged calendar notes stay nil so the entry keeps 1.x's title match.
            notes: trimmed == defaultNotes ? nil : trimmed
        )
    }

    private var missing: Set<CaptureConfirmField> { model.missingFields(suggestion, edits: edits) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                statusBand
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                hoursCard
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                valueRows
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                notesField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(colors.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: stepTick)
        .confirmationDialog("Don't suggest events like this", isPresented: $showMuteOptions, titleVisibility: .visible) {
            if let rule = InboxLogic.muteRule(forTitleOf: suggestion) {
                Button("Events named \u{201C}\(suggestion.title)\u{201D}") { mute(rule) }
            }
            if let rule = InboxLogic.muteRule(forCalendarOf: suggestion) {
                Button("Everything from this calendar") { mute(rule) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We stop suggesting them. Hours you already logged stay.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirm.sheet")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: InboxFormat.kindSymbol(suggestion.kind))
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(colors.informational)
                .frame(width: 44, height: 44)
                .background(colors.informationalSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(InboxFormat.kindLabel(suggestion.kind)) · \(InboxFormat.longDay(suggestion.start))")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(colors.textSecondary)
                titleText
                    .font(.title2)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(colors.backgroundSecondary))
                    .overlay(Circle().strokeBorder(colors.border, lineWidth: 0.5))
            }
            .buttonStyle(.lhPressable)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("confirm.close")
        }
    }

    private var titleText: Text {
        let noun = Text(suggestion.title).fontWeight(.semibold)
        guard let name = model.properties.first(where: { $0.id == propertyId })?.name else { return noun }
        return Text("\(noun) at \(Text(name).fontWeight(.semibold))")
    }

    // MARK: Status band

    @ViewBuilder private var statusBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            if badges.needsHours {
                band(
                    title: Text("How long did it take?"),
                    body: "We can't tell the hours from this, so add them below.",
                    wash: colors.cautionSurface
                )
            } else if let scheduled = suggestion.proposedHours {
                band(
                    title: Text("Scheduled \(Text(InboxFormat.hours(scheduled)).foregroundStyle(colors.positive))"),
                    body: scheduleSentence,
                    wash: colors.backgroundTertiary
                )
            }
            if badges.notSure {
                band(
                    title: Text("Not sure this is landlord work"),
                    body: "Log it only if it was work on a rental.",
                    wash: colors.cautionSurface
                )
                .accessibilityIdentifier("confirm.notSure")
            }
            if badges.mightAlreadyBeLogged {
                band(
                    title: Text("Might already be logged"),
                    body: "You have hours around this time. Check Records so it isn't counted twice.",
                    wash: colors.informationalSurface
                )
                .accessibilityIdentifier("confirm.mightAlreadyBeLogged")
            }
        }
    }

    private var scheduleSentence: String {
        guard let end = suggestion.end else { return "Change it if the work ran long or short." }
        return "Your calendar had this from \(InboxFormat.clockTime(suggestion.start)) to \(InboxFormat.clockTime(end)). Change it if the work ran long or short."
    }

    private func band(title: Text, body: String, wash: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Hours

    private var hoursCard: some View {
        let minutes = Int((hours * 60).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            Text("How long were you working?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colors.textSecondary)
            HStack(spacing: 12) {
                stepButton(symbol: "minus", enabled: hours > 0) {
                    hours = max(0, hours - Self.step)
                }
                .accessibilityLabel("Less time")
                .accessibilityIdentifier("confirm.hours.minus")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(minutes / 60)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(minutes / 60)))
                    Text("h").font(.title3).foregroundStyle(colors.textSecondary)
                    Text(String(format: "%02d", minutes % 60))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(minutes % 60)))
                        .padding(.leading, 6)
                    Text("m").font(.title3).foregroundStyle(colors.textSecondary)
                }
                .monospacedDigit()
                .foregroundStyle(hours > 0 ? colors.textPrimary : colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hours")
                .accessibilityValue(InboxFormat.spokenHours(hours))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: hours = min(Self.maxHours, hours + Self.step)
                    case .decrement: hours = max(0, hours - Self.step)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("confirm.hours.value")
                Spacer(minLength: 0)
                stepButton(symbol: "plus", enabled: hours < Self.maxHours) {
                    hours = min(Self.maxHours, hours + Self.step)
                }
                .accessibilityLabel("More time")
                .accessibilityIdentifier("confirm.hours.plus")
            }
            .padding(16)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func stepButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion { action() } else { withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { action() } }
            stepTick += 1
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? colors.textPrimary : colors.textTertiary)
                .frame(width: 44, height: 44)
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
        .disabled(!enabled)
    }

    // MARK: Values

    private var valueRows: some View {
        VStack(spacing: 0) {
            valueRow("Property") {
                Menu {
                    ForEach(model.properties) { property in
                        Button(property.name) { propertyId = property.id }
                    }
                } label: {
                    menuLabel(model.properties.first(where: { $0.id == propertyId })?.name ?? "Choose", isPlaceholder: propertyId == nil)
                }
                .accessibilityIdentifier("confirm.property")
            }
            if model.showsSpousePicker {
                divider
                valueRow("Who") {
                    Picker("Who", selection: $participant) {
                        Text("Me").tag(Participant.selfParticipant)
                        Text("Spouse").tag(Participant.spouse)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    .accessibilityIdentifier("confirm.who")
                }
            }
            divider
            valueRow("Category") {
                Menu {
                    ForEach(ActivityCategory.allCases, id: \.self) { option in
                        Button {
                            category = option
                        } label: {
                            Label(option.inboxLabel, image: "bp_tool_\(option.blueprintToolName)_36")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if category != nil { CategoryToolTile(category: category, size: 28) }
                        menuLabel(category?.inboxLabel ?? "Choose", isPlaceholder: category == nil)
                    }
                }
                .accessibilityIdentifier("confirm.category")
            }
            divider
            valueRow("Date") {
                Text(InboxFormat.longDay(suggestion.start))
                    .foregroundStyle(colors.textPrimary)
            }
        }
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 16)
    }

    private func valueRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(colors.textSecondary)
            Spacer(minLength: 8)
            trailing()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func menuLabel(_ text: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .foregroundStyle(isPlaceholder ? colors.caution : colors.action)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(minHeight: 44)
    }

    private var notesField: some View {
        TextField("Add a note (optional)", text: $notes, axis: .vertical)
            .lineLimit(1...4)
            .font(.body)
            .foregroundStyle(colors.textPrimary)
            .padding(16)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Notes")
            .accessibilityIdentifier("confirm.notes")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            if let reason = missingReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("confirm.missing")
            }
            Button {
                if model.log(suggestion, edits: edits) == nil { dismiss() }
            } label: {
                Text(hours > 0 ? "Log \(InboxFormat.hours(hours))" : "Log")
                    .contentTransition(.numericText(value: hours))
            }
            .buttonStyle(InboxPrimaryButtonStyle())
            .disabled(!missing.isEmpty)
            .accessibilityIdentifier("confirm.log")

            Button("Not landlord work") {
                model.dismiss(suggestion)
                dismiss()
            }
            .font(.body)
            .foregroundStyle(colors.destructive)
            .frame(minHeight: 44)
            .accessibilityIdentifier("confirm.dismiss")

            if InboxLogic.muteRule(forTitleOf: suggestion) != nil || InboxLogic.muteRule(forCalendarOf: suggestion) != nil {
                Button("Don't suggest events like this") { showMuteOptions = true }
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("confirm.mute")
            }
            Text("Nothing counts until you log it.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, 4)
        }
    }

    private var missingReason: String? {
        let missing = missing
        guard !missing.isEmpty else { return nil }
        var parts: [String] = []
        if missing.contains(.hours) { parts.append("the hours") }
        if missing.contains(.property) { parts.append(model.properties.isEmpty ? "a property (add one in Properties)" : "a property") }
        if missing.contains(.category) { parts.append("a category") }
        return "Add \(ListFormatter.localizedString(byJoining: parts)) to log this."
    }

    private func mute(_ rule: CaptureMuteRule) {
        model.mute(suggestion, rule: rule)
        dismiss()
    }
}
