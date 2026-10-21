import SwiftUI

/// Confirm sheet for one suggestion (Flighty header + status band, Skyscanner stepper, Brick
/// value rows). The only place a not-sure, already-logged or hour-less item can be logged.
struct SuggestionConfirmSheet: View {
    let suggestion: Suggestion
    @ObservedObject var model: InboxViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hours: Double
    @State private var propertyId: UUID?
    @State private var category: ActivityCategory?
    @State private var participant: Participant = .selfParticipant
    @State private var notes: String
    @State private var showMuteOptions = false
    @State private var stepTick = 0
    /// WP-P: the free plan is full and this item is at a new rental.
    @State private var showRentalPicker = false
    @State private var paywall: ProPaywallRequest?
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
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

    /// Free plan full, item at a new rental, and the user hasn't said it was at their rental.
    private var atLimit: Bool { model.needsNewRental(suggestion) && !model.properties.contains { $0.id == propertyId } }
    private var limitedToPicker: Bool { model.needsNewRental(suggestion) }

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
                if limitActionsInline {
                    // Accessibility sizes: the explanation and the two ways out scroll with the
                    // sheet; only "Unlock Pro" stays pinned, so the Property row stays reachable.
                    limitExplanation
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    limitWaysOut
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                secondaryActions
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Log and "Not rental work" stay pinned above the home indicator, so the decline is
        // always visible, however long the sheet is (not-sure items carry an extra band).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedActions
        }
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
        .sheet(isPresented: $showRentalPicker) {
            LimitRentalPicker(
                properties: model.properties,
                selected: propertyId,
                onPick: { id in propertyId = id; showRentalPicker = false },
                onUnlock: { showRentalPicker = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openPaywall() } }
            )
            // Accessibility sizes open full height so the locked row's "Unlock Pro" is reachable.
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationBackground(colors.background)
        }
        .proPaywall($paywall)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirm.sheet")
    }

    // MARK: Free plan at its limit (WP-P)

    /// The paywall about adding a rental. After a purchase the sheet closes and Add Property
    /// opens; the item stays in the inbox, ready to log at the new rental.
    private func openPaywall() {
        paywall = model.paywallForNewRental(onUnlocked: { [model] in
            model.waitList.remove(suggestion.sourceKey)
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
            }
        })
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
                    title: Text("Scheduled \(Text(InboxFormat.hours(scheduled)).fontWeight(.bold))"),
                    body: scheduleSentence,
                    wash: colors.backgroundTertiary
                )
            }
            if badges.notSure {
                band(
                    title: Text("Not sure this is rental work"),
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
                if limitedToPicker {
                    Button { showRentalPicker = true } label: {
                        menuLabel(model.properties.first(where: { $0.id == propertyId })?.name ?? "Choose", isPlaceholder: propertyId == nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("confirm.property")
                } else {
                Menu {
                    ForEach(model.properties) { property in
                        Button(property.name) { propertyId = property.id }
                    }
                } label: {
                    menuLabel(model.properties.first(where: { $0.id == propertyId })?.name ?? "Choose", isPlaceholder: propertyId == nil)
                }
                .accessibilityIdentifier("confirm.property")
                }
            }
            if model.showsSpousePicker {
                divider
                valueRow("Who") {
                    whoPicker
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

    /// Me / Spouse on brand tokens (the system segmented control renders grey on iOS 27).
    private var whoPicker: some View {
        HStack(spacing: 2) {
            ForEach([Participant.selfParticipant, .spouse], id: \.self) { option in
                let selected = participant == option
                Button {
                    if reduceMotion { participant = option } else { withAnimation(AppAnimation.quick) { participant = option } }
                } label: {
                    Text(option == .spouse ? "Spouse" : "Me")
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? colors.onAction : colors.textPrimary)
                        .frame(minWidth: 72, minHeight: 32)
                        .background(Capsule().fill(selected ? colors.action : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .spouse ? "Spouse" : "Me")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(colors.backgroundTertiary))
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var divider: some View {
        Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 16)
    }

    private func valueRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        // Accessibility sizes: the value drops under its label so "Choose" never truncates.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(label).foregroundStyle(colors.textSecondary)
            if !stacked { Spacer(minLength: 8) }
            trailing()
        }
        .padding(.vertical, stacked ? 8 : 0)
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

    private var limitActionsInline: Bool { atLimit && dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder private var pinnedActions: some View {
        if limitActionsInline {
            pinnedFooter { unlockButton }
        } else if atLimit {
            limitActions
        } else {
            regularActions
        }
    }

    /// The free plan is full: say what's locked and what stays, one "Unlock Pro", and two ways
    /// out that lose nothing.
    private var limitActions: some View {
        pinnedFooter {
            VStack(spacing: 10) {
                limitExplanation
                unlockButton
                limitWaysOut
            }
        }
    }

    private var limitExplanation: some View {
        VStack(spacing: 2) {
            Text(InboxProLimit.sheetLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
            Text(ProGate.keepsLine(.inboxLimit, firstPropertyName: model.properties.first?.name))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("confirm.limitLine")
        .onAppear { Analytics.lockPreviewShown(entry: .inboxLimit) }
    }

    private var unlockButton: some View {
        UnlockProButton(entry: .inboxLimit, title: "Unlock Pro to add a rental", fullWidth: true, action: openPaywall)
            .accessibilityIdentifier("confirm.unlockPro")
    }

    private var limitWaysOut: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { keepButton; notWorkButton }
            VStack(spacing: 0) { keepButton; notWorkButton }
        }
        .frame(maxWidth: .infinity)
    }

    private func pinnedFooter<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .background(
                colors.background
                    .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .bottom)
            )
    }

    private var keepButton: some View {
        Button("Keep it in my inbox") {
            model.keepForPro(suggestion)
            dismiss()
        }
        .font(.body)
        .foregroundStyle(colors.action)
        .frame(minHeight: 44)
        .accessibilityIdentifier("confirm.keepForPro")
    }

    private var notWorkButton: some View {
        Button("Not rental work") {
            model.dismiss(suggestion)
            dismiss()
        }
        .font(.body)
        .foregroundStyle(colors.textSecondary)
        .frame(minHeight: 44)
        .accessibilityIdentifier("confirm.dismiss")
    }

    private var regularActions: some View {
        VStack(spacing: 4) {
            if let reason = missingReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("confirm.missing")
            }
            Button {
                let result = model.log(suggestion, edits: edits)
                if result.entryId != nil {
                    dismiss()
                } else if case .needsInput(let missing) = result, missing.contains(.plan) {
                    openPaywall()
                }
            } label: {
                Text(hours > 0 ? "Log \(InboxFormat.hours(hours))" : "Log")
                    .contentTransition(.numericText(value: hours))
            }
            .buttonStyle(InboxPrimaryButtonStyle())
            .disabled(!missing.isEmpty)
            .accessibilityIdentifier("confirm.log")

            Button("Not rental work") {
                model.dismiss(suggestion)
                dismiss()
            }
            .font(.body)
            .foregroundStyle(colors.destructive)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("confirm.dismiss")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            colors.background
                .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var secondaryActions: some View {
        VStack(spacing: 4) {
            if InboxLogic.muteRule(forTitleOf: suggestion) != nil || InboxLogic.muteRule(forCalendarOf: suggestion) != nil {
                Button("Don't suggest events like this") { showMuteOptions = true }
                    .font(.subheadline)
                    .foregroundStyle(colors.action)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("confirm.mute")
            }
            Text("Nothing counts until you log it.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
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

/// "Which rental?" while the free plan is full: the user's rental, then the `.row` lock for a new
/// one. Picking the rental they have logs it there; "Unlock Pro" opens the paywall.
struct LimitRentalPicker: View {
    let properties: [RentalProperty]
    let selected: UUID?
    var onPick: (UUID) -> Void
    var onUnlock: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Which rental?").font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(colors.backgroundSecondary))
                            .overlay(Circle().strokeBorder(colors.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.lhPressable)
                    .accessibilityLabel("Close")
                }
                VStack(spacing: 0) {
                    ForEach(properties) { property in
                        Button { onPick(property.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(colors.action)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(colors.actionSurface))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(property.name).font(.body.weight(.semibold)).foregroundStyle(colors.textPrimary)
                                    if !property.address.isEmpty {
                                        Text(property.address).font(.subheadline).foregroundStyle(colors.textSecondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if property.id == selected {
                                    Image(systemName: "checkmark").foregroundStyle(colors.action).accessibilityHidden(true)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(property.id == selected ? .isSelected : [])
                        .accessibilityIdentifier("limitPicker.property")
                        Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 60)
                    }
                    LockedPreview(
                        size: .row,
                        entry: .inboxLimit,
                        line: ProGate.lockLine(.inboxLimit),
                        keeps: ProGate.keepsLine(.inboxLimit, firstPropertyName: properties.first?.name),
                        onUnlock: onUnlock
                    ) {
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(colors.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 32, height: 32)
                                .overlay(Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.textSecondary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a new rental").font(.body.weight(.semibold)).foregroundStyle(colors.textPrimary)
                                Text("From your calendar").font(.subheadline).foregroundStyle(colors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                    }
                }
                .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .background(colors.background.ignoresSafeArea())
        .accessibilityIdentifier("limitPicker")
    }
}
