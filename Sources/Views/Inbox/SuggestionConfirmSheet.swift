import SwiftUI

// MARK: - The confirm sheet (standard §1.20 focused sheet, §1.5, §1.8, §1.9; plan package D)
//
// The only place a not-sure, already-logged or hour-less item can be logged. An opaque `.large`
// sheet on `backgroundSecondary` (Brian, 2026-10-23), no house. Header: the 56 category tool, the
// title ("Plumber at Pine Cabin"), "Calendar · Thu Oct 22", one `.icon` close. Then at most one
// notice (not sure / might be logged / needs hours), the hours in an `LHStepper`, `LHRow.Value`
// rows (Property, Category, Date), `LHSegmented` for Me / Spouse, the note in an `LHField`. The
// `.primary` "Log 2h" is pinned (Liquid Glass on iOS 26+) under one `.tertiary` "Not rental work".
// At the free plan's limit the footer says what is locked and offers "Unlock Pro".

struct SuggestionConfirmSheet: View {
    let suggestion: Suggestion
    @ObservedObject var model: InboxViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hours: Double
    @State private var propertyId: UUID?
    @State private var category: ActivityCategory?
    @State private var participant: Participant = .selfParticipant
    @State private var notes: String
    @State private var showMuteOptions = false
    /// The free plan is full and this item is at a new rental.
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
    private var propertyName: String? { model.properties.first(where: { $0.id == propertyId })?.name }
    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Accessibility sizes: the header is too tall to pin, so it scrolls with the sheet.
                if ax { header.padding(.horizontal, -LHMetrics.gutter) }
                notice
                hoursBlock
                valueRows
                if model.showsSpousePicker { whoBlock }
                LHField(confirmText(.notePlaceholder), text: $notes, multiline: true,
                        accessibilityLabel: confirmText(.noteLabel), identifier: "confirm.notes")
                if ax && atLimit { limitExplanation; limitWaysOut }
                secondaryActions
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { if !ax { header } }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(colors.backgroundSecondary)
        .lhSheetPresentation(.focused)
        .confirmationDialog(confirmText(.muteTitle), isPresented: $showMuteOptions, titleVisibility: .visible) {
            if let rule = InboxLogic.muteRule(forTitleOf: suggestion) {
                Button(String(localized: "confirm.mute.named", defaultValue: "Events named \u{201C}\(suggestion.title)\u{201D}", table: "Inbox")) { mute(rule) }
            }
            if let rule = InboxLogic.muteRule(forCalendarOf: suggestion) {
                Button(confirmText(.muteCalendar)) { mute(rule) }
            }
            Button(confirmText(.cancel), role: .cancel) {}
        } message: {
            Text(confirmText(.muteMessage))
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
            .presentationDragIndicator(.visible)
        }
        .proPaywall($paywall)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("confirm.sheet")
    }

    // MARK: Free plan at its limit

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
        let title = VStack(alignment: .leading, spacing: 2) {
            Text(InboxFormat.rowTitle(suggestion, propertyName: propertyName))
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(ax ? nil : 2)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "confirm.subtitle", defaultValue: "\(InboxFormat.kindLabel(suggestion.kind)) · \(InboxFormat.longDay(suggestion.start))", table: "Inbox"))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .lineLimit(ax ? nil : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let close = Button { dismiss() } label: { Image(systemName: "xmark") }
            .buttonStyle(LHButton.icon)
            .accessibilityLabel(String(localized: "sheet.close", defaultValue: "Close", table: "Foundations"))
            .accessibilityIdentifier("confirm.close")
        return Group {
            if ax {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        CategoryToolTile(category: category, size: 56)
                        Spacer(minLength: 0)
                        close
                    }
                    title
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    CategoryToolTile(category: category, size: 56)
                    title
                    close
                }
            }
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
        .background(colors.backgroundSecondary)
    }

    // MARK: Notice

    /// At most one: the most important thing to know before logging.
    @ViewBuilder private var notice: some View {
        if badges.mightAlreadyBeLogged {
            ConfirmNotice(symbol: "exclamationmark.circle", tone: .informational,
                          title: confirmText(.mightTitle), message: confirmText(.mightBody))
                .accessibilityIdentifier("confirm.mightAlreadyBeLogged")
        } else if badges.notSure {
            ConfirmNotice(symbol: "questionmark.circle", tone: .caution,
                          title: confirmText(.notSureTitle), message: confirmText(.notSureBody))
                .accessibilityIdentifier("confirm.notSure")
        } else if badges.needsHours {
            ConfirmNotice(symbol: "clock", tone: .caution, title: confirmText(.needsHoursTitle), message: confirmText(.needsHoursBody))
                .accessibilityIdentifier("confirm.needsHours")
        }
    }

    // MARK: Hours

    private var hoursBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(confirmText(.hoursLabel))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            HStack {
                Spacer(minLength: 0)
                LHStepper(hours: $hours, step: Self.step, range: 0...Self.maxHours, label: confirmText(.hoursA11y))
                    .accessibilityIdentifier("confirm.hours.value")
                Spacer(minLength: 0)
            }
            if !badges.needsHours, let scheduled = scheduleSentence {
                Text(scheduled)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scheduleSentence: String? {
        guard suggestion.proposedHours != nil, let end = suggestion.end else { return nil }
        return String(localized: "confirm.schedule",
                      defaultValue: "Your calendar had this from \(InboxFormat.clockTime(suggestion.start)) to \(InboxFormat.clockTime(end)). Change it if the work ran long or short.",
                      table: "Inbox")
    }

    // MARK: Values

    private var valueRows: some View {
        VStack(spacing: 8) {
            if limitedToPicker {
                LHRow.Value(confirmText(.property), value: propertyName ?? confirmText(.choose)) { showRentalPicker = true }
                    .accessibilityIdentifier("confirm.property")
            } else {
                Menu {
                    ForEach(model.properties) { property in
                        Button(property.name) { propertyId = property.id }
                    }
                } label: {
                    LHRow.Value(confirmText(.property), value: propertyName ?? confirmText(.choose), accessory: .menu).content
                }
                .accessibilityIdentifier("confirm.property")
            }
            Menu {
                ForEach(ActivityCategory.allCases, id: \.self) { option in
                    Button {
                        category = option
                    } label: {
                        Label(option.inboxLabel, image: "bp_tool_\(option.blueprintToolName)_36")
                    }
                }
            } label: {
                LHRow.Value(confirmText(.category), value: category?.inboxLabel ?? confirmText(.choose), accessory: .menu).content
            }
            .accessibilityIdentifier("confirm.category")
            LHRow.Value(confirmText(.date), value: InboxFormat.longDay(suggestion.start), accessory: .none)
        }
    }

    private var whoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(confirmText(.who))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            LHSegmented(
                [.init(Participant.selfParticipant, confirmText(.me)), .init(Participant.spouse, confirmText(.spouse))],
                selection: $participant,
                accessibilityLabel: confirmText(.who)
            )
            .accessibilityIdentifier("confirm.who")
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        VStack(spacing: 4) {
            if atLimit {
                if !ax { limitExplanation; unlockButton; limitWaysOut } else { unlockButton }
            } else {
                regularActions
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            colors.backgroundSecondary
                .overlay(alignment: .top) { Rectangle().fill(colors.border).frame(height: LHMetrics.hairline) }
                .ignoresSafeArea(edges: .bottom)
        )
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
        UnlockProButton(entry: .inboxLimit, title: confirmText(.unlockRental), fullWidth: true, action: openPaywall)
            .accessibilityIdentifier("confirm.unlockPro")
    }

    private var limitWaysOut: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { keepButton; notWorkButton }
            VStack(spacing: 0) { keepButton; notWorkButton }
        }
        .frame(maxWidth: .infinity)
    }

    private var keepButton: some View {
        Button(confirmText(.keep)) {
            model.keepForPro(suggestion)
            dismiss()
        }
        .buttonStyle(LHButton.tertiary)
        .accessibilityIdentifier("confirm.keepForPro")
    }

    private var notWorkButton: some View {
        Button(confirmText(.notWork)) {
            model.dismiss(suggestion)
            dismiss()
        }
        .buttonStyle(LHButton.tertiary)
        .foregroundStyle(colors.textSecondary)
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
                    .accessibilityIdentifier("confirm.missing")
            }
            Button(confirmText(.notWork)) {
                model.dismiss(suggestion)
                dismiss()
            }
            .buttonStyle(LHButton.destructiveTertiary)
            .accessibilityIdentifier("confirm.dismiss")

            Button {
                let result = model.log(suggestion, edits: edits)
                if result.entryId != nil {
                    dismiss()
                } else if case .needsInput(let missing) = result, missing.contains(.plan) {
                    openPaywall()
                }
            } label: {
                Text(hours > 0
                     ? String(localized: "confirm.log.hours", defaultValue: "Log \(InboxFormat.hours(hours))", table: "Inbox")
                     : String(localized: "confirm.log", defaultValue: "Log", table: "Inbox"))
                    .contentTransition(.numericText(value: hours))
            }
            .buttonStyle(LHButton.primaryGlass)
            .disabled(!missing.isEmpty)
            .accessibilityIdentifier("confirm.log")
        }
    }

    private var secondaryActions: some View {
        VStack(spacing: 0) {
            if InboxLogic.muteRule(forTitleOf: suggestion) != nil || InboxLogic.muteRule(forCalendarOf: suggestion) != nil {
                Button(confirmText(.muteTitle)) { showMuteOptions = true }
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityIdentifier("confirm.mute")
            }
            Text(confirmText(.nothingCounts))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var missingReason: String? {
        let missing = missing
        guard !missing.isEmpty else { return nil }
        var parts: [String] = []
        if missing.contains(.hours) { parts.append(confirmText(.partHours)) }
        if missing.contains(.property) { parts.append(model.properties.isEmpty ? confirmText(.partPropertyAdd) : confirmText(.partProperty)) }
        if missing.contains(.category) { parts.append(confirmText(.partCategory)) }
        return String(localized: "confirm.missing", defaultValue: "Add \(ListFormatter.localizedString(byJoining: parts)) to log this.", table: "Inbox")
    }

    private func mute(_ rule: CaptureMuteRule) {
        model.mute(suggestion, rule: rule)
        dismiss()
    }
}

// MARK: - Notice

/// One line of "know this before you log it": a glyph in the intent ink, a `.subheadline.semibold`
/// title in `textPrimary` (intent inks fail AA as small text on their own wash), and one sentence.
/// Inner surface (radius 12) on the intent's wash.
private struct ConfirmNotice: View {
    enum Tone { case caution, informational }

    let symbol: String
    let tone: Tone
    let title: String
    let message: String

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tone == .caution ? colors.caution : colors.informational)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LHMetrics.cardPadding)
        .background(tone == .caution ? colors.cautionSurface : colors.informationalSurface,
                    in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Strings

private enum ConfirmText {
    case notePlaceholder, noteLabel, muteTitle, muteCalendar, cancel, muteMessage
    case mightTitle, mightBody, notSureTitle, notSureBody, needsHoursTitle, needsHoursBody
    case hoursLabel, hoursA11y, property, category, date, choose, who, me, spouse
    case unlockRental, keep, notWork, nothingCounts, partHours, partProperty, partPropertyAdd, partCategory
}

private func confirmText(_ key: ConfirmText) -> String {
    switch key {
    case .notePlaceholder: return String(localized: "confirm.note.placeholder", defaultValue: "Add a note (optional)", table: "Inbox")
    case .noteLabel: return String(localized: "confirm.note.label", defaultValue: "Notes", table: "Inbox")
    case .muteTitle: return String(localized: "confirm.mute", defaultValue: "Don’t suggest events like this", table: "Inbox")
    case .muteCalendar: return String(localized: "confirm.mute.calendar", defaultValue: "Everything from this calendar", table: "Inbox")
    case .cancel: return String(localized: "confirm.cancel", defaultValue: "Cancel", table: "Inbox")
    case .muteMessage: return String(localized: "confirm.mute.message", defaultValue: "We stop suggesting them. Hours you already logged stay.", table: "Inbox")
    case .mightTitle: return String(localized: "confirm.might.title", defaultValue: "Might already be logged", table: "Inbox")
    case .mightBody: return String(localized: "confirm.might.body", defaultValue: "You have hours around this time. Check Records so it isn’t counted twice.", table: "Inbox")
    case .notSureTitle: return String(localized: "confirm.notSure.title", defaultValue: "Not sure this is rental work", table: "Inbox")
    case .notSureBody: return String(localized: "confirm.notSure.body", defaultValue: "Log it only if it was work on a rental.", table: "Inbox")
    case .needsHoursTitle: return String(localized: "confirm.needsHours.title", defaultValue: "How long did it take?", table: "Inbox")
    case .needsHoursBody: return String(localized: "confirm.needsHours.body", defaultValue: "We can’t tell the hours from this, so add them below.", table: "Inbox")
    case .hoursLabel: return String(localized: "confirm.hours.label", defaultValue: "How long were you working?", table: "Inbox")
    case .hoursA11y: return String(localized: "confirm.hours.a11y", defaultValue: "Hours", table: "Inbox")
    case .property: return String(localized: "confirm.property", defaultValue: "Property", table: "Inbox")
    case .category: return String(localized: "confirm.category", defaultValue: "Category", table: "Inbox")
    case .date: return String(localized: "confirm.date", defaultValue: "Date", table: "Inbox")
    case .choose: return String(localized: "confirm.choose", defaultValue: "Choose", table: "Inbox")
    case .who: return String(localized: "confirm.who", defaultValue: "Who did the work", table: "Inbox")
    case .me: return String(localized: "confirm.me", defaultValue: "Me", table: "Inbox")
    case .spouse: return String(localized: "confirm.spouse", defaultValue: "Spouse", table: "Inbox")
    case .unlockRental: return String(localized: "confirm.unlockRental", defaultValue: "Unlock Pro to add a rental", table: "Inbox")
    case .keep: return String(localized: "confirm.keep", defaultValue: "Keep it in my inbox", table: "Inbox")
    case .notWork: return String(localized: "inbox.row.notWork", defaultValue: "Not rental work", table: "Inbox")
    case .nothingCounts: return String(localized: "confirm.nothingCounts", defaultValue: "Nothing counts until you log it.", table: "Inbox")
    case .partHours: return String(localized: "confirm.part.hours", defaultValue: "the hours", table: "Inbox")
    case .partProperty: return String(localized: "confirm.part.property", defaultValue: "a property", table: "Inbox")
    case .partPropertyAdd: return String(localized: "confirm.part.propertyAdd", defaultValue: "a property (add one in Rentals)", table: "Inbox")
    case .partCategory: return String(localized: "confirm.part.category", defaultValue: "a category", table: "Inbox")
    }
}

// MARK: - Which rental?

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
        LHSheet(String(localized: "limitPicker.title", defaultValue: "Which rental?", table: "Inbox"), onClose: { dismiss() }) {
            LHRowGroup {
                ForEach(properties) { property in
                    Button { onPick(property.id) } label: {
                        LHRow.Browse(title: property.name, meta: property.address.isEmpty ? nil : property.address,
                                     showsChevron: false, leading: { LHRowGlyph(systemImage: "house", tint: .action) })
                            .overlay(alignment: .trailing) {
                                if property.id == selected {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(colors.action)
                                        .padding(.trailing, 16)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .buttonStyle(LHButton.press)
                    .accessibilityAddTraits(property.id == selected ? .isSelected : [])
                    .accessibilityIdentifier("limitPicker.property")
                    LHDivider(leadingInset: LHRow.browseDividerInset)
                }
                LockedPreview(
                    size: .row,
                    entry: .inboxLimit,
                    line: ProGate.lockLine(.inboxLimit),
                    keeps: ProGate.keepsLine(.inboxLimit, firstPropertyName: properties.first?.name),
                    onUnlock: onUnlock
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "limitPicker.new", defaultValue: "Add a new rental", table: "Inbox"))
                                .font(.body)
                                .foregroundStyle(colors.textPrimary)
                            Text(String(localized: "limitPicker.newMeta", defaultValue: "From your calendar", table: "Inbox"))
                                .font(.subheadline)
                                .foregroundStyle(colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(LHRow.insets)
                    .frame(minHeight: LHMetrics.rowMinHeight)
                }
            }
        }
        .background(colors.backgroundSecondary)
        .accessibilityIdentifier("limitPicker")
    }
}
