import SwiftUI
import PhotosUI

// MARK: - The rows: what Log will record, each one an editor
//
// Each row is an `LHRow.Value` (§1.5): label left, value right, 56 high at default, label above value
// at AX. A tapped row opens its editor in place under it, one at a time. What a row's look says:
//   a 3pt timber bar      the note gave this value
//   a dashed action ring  the value is still missing ("Choose")
//   a caution ring        the value is a guess ("You didn't say how long") or the model just changed it
//   an action ring        this row's editor is open

extension LogTimeSheet {
    /// How a row looks. A 3pt timber bar marks a value the note gave; a dashed ring is a value still missing.
    enum RowLook { case filled(fromNote: Bool), empty, caution, updated }

    var showsWho: Bool { LogParticipantRule.showsPicker(spouseTracking: spouseTracking) && !isRecovery }

    var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isFirstRun { row(.property) }
            row(.category)
            row(.hours)
            row(.date)
            if showsWho { whoRow }
            if form.recordDescription != nil { recordRow }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.rows")
    }

    func label(_ field: LogField) -> String {
        switch field {
        case .property: return lt("Rental")
        case .category: return lt("Kind of work")
        case .hours: return lt("How long")
        case .date: return lt("Date")
        case .participant: return lt("Who")
        case .description: return lt("On the record")
        }
    }

    func identifier(_ field: LogField) -> String {
        switch field {
        case .property: return "log.property"
        case .category: return "log.category"
        case .hours: return "log.hours"
        case .date: return "log.date"
        case .participant: return "log.who"
        case .description: return "log.description"
        }
    }

    /// Whether the note wrote this value (rules or model).
    func fromNote(_ field: LogField) -> Bool {
        let provenance = form.provenance(field)
        return provenance == .rules || provenance == .model
    }

    /// The note was read and never said how long: the 1h is a default, not a fact.
    var hoursQuestionable: Bool {
        form.hoursIsDefault && form.trimmedNote.count >= 6 && !manual && mode == .log && form.fillSource != nil
    }

    func look(_ field: LogField) -> RowLook {
        if form.updatedAfterSeen[field] != nil { return .updated }
        switch field {
        case .property: return form.propertyId == nil ? .empty : .filled(fromNote: fromNote(.property))
        case .category: return form.category == nil ? .empty : .filled(fromNote: fromNote(.category))
        case .hours: return hoursQuestionable ? .caution : .filled(fromNote: fromNote(.hours))
        default: return .filled(fromNote: fromNote(field))
        }
    }

    func valueText(_ field: LogField) -> String {
        switch field {
        case .property: return properties.first { $0.id == form.propertyId }?.name ?? ""
        case .category: return form.category?.inboxLabel ?? ""
        case .hours: return LogTimeFormat.hours(form.hours)
        case .date: return LogTimeFormat.dateRow(form.date)
        case .participant: return form.participant == .spouse ? lt("Spouse") : lt("Me")
        case .description: return form.recordDescription ?? ""
        }
    }

    /// The value as the row shows it: "Choose" when missing, "(last used)" on a remembered kind.
    func shownValue(_ field: LogField, _ look: RowLook) -> String {
        if case .empty = look { return lt("Choose") }
        if field == .category, form.categoryIsRemembered, !isReviewing { return lt("\(valueText(field)) (last used)") }
        return valueText(field)
    }

    /// Row = one element: label, value, where it came from, and a hint.
    func a11y(_ field: LogField, _ look: RowLook) -> String {
        let name = label(field)
        let value = field == .hours ? LHFormat.spokenHours(form.hours) : valueText(field)
        switch look {
        case .empty: return lt("\(name), not chosen")
        case .caution: return lt("\(name), \(value), you didn\u{2019}t say how long")
        case .updated: return lt("\(name), \(value), updated from your note")
        case .filled(let note): return note ? lt("\(name), \(value), filled from your note") : lt("\(name), \(value)")
        }
    }

    func row(_ field: LogField) -> some View {
        let look = look(field)
        let open = expanded == field
        return VStack(alignment: .leading, spacing: 8) {
            LHRow.Value(label(field), value: shownValue(field, look), accessory: .disclosure) { toggle(field) }
                .overlay { rowRing(look, open: open) }
                .overlay(alignment: .leading) { noteBar(look) }
                .overlay { rowWash(field) }
                .accessibilityLabel(a11y(field, look))
                .accessibilityHint(lt("Double-tap to change."))
                .accessibilityAddTraits(open ? .isSelected : [])
                .accessibilityIdentifier(identifier(field))
            if field == .property, form.propertyId == nil, mentioned.count >= 2, let hint = form.propertyHint { twoRentalsHint(hint) }
            if field == .category, !form.countsTowardHours, let category = form.category { notCountedNote(category) }
            if field == .hours, hoursQuestionable { hoursFootnote }
            if case .updated = look { updatedLine(field) }
            if open { editor(field).transition(rowTransition) }
        }
        .id(field.rowID)
    }

    /// `sheetUnfold`: the editor grows from the row (height with a fade); a 0.2 fade under Reduce Motion.
    var rowTransition: AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)) }

    @ViewBuilder func rowRing(_ look: RowLook, open: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
        switch look {
        case .empty:
            shape.strokeBorder(colors.action, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        case .caution, .updated:
            shape.strokeBorder(colors.caution, lineWidth: 1.5)
        case .filled:
            if open { shape.strokeBorder(colors.action, lineWidth: 1.5) }
        }
    }

    /// The one timber accent: a 3pt bar on rows whose value came from the note.
    @ViewBuilder func noteBar(_ look: RowLook) -> some View {
        if case .filled(true) = look {
            Capsule().fill(colors.noteMark).frame(width: 3, height: 26).padding(.leading, 6).accessibilityHidden(true)
        }
    }

    /// The timber wash on a row the last fill wrote: 0 → 16% → 0 over 300 + 300 ms.
    func rowWash(_ field: LogField) -> some View {
        RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
            .fill(colors.timber.opacity(flashing.contains(field) ? 0.16 : 0))
            .allowsHitTesting(false)
    }

    // MARK: Under a row

    func twoRentalsHint(_ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hint).font(.footnote).foregroundStyle(colors.textSecondary)
            LogChipFlow(spacing: 8) {
                ForEach(mentioned) { property in
                    LHChip(property.name, isSelected: false) { pick(property: property.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.propertyHint")
    }

    func notCountedNote(_ category: ActivityCategory) -> some View {
        Text(lt("\(category.inboxLabel) doesn\u{2019}t count toward your hours."))
            .font(.footnote)
            .foregroundStyle(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("log.notCounted")
    }

    /// The model changed this row after the rules' answer had been on screen: say so, offer Undo.
    func updatedLine(_ field: LogField) -> some View {
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            Text(lt("Updated from your note."))
                .font(.footnote.weight(.medium))
                .foregroundStyle(colors.cautionText)
            Button(lt("Undo")) { undoUpdate(field) }
                .buttonStyle(LHButton.tertiary)
                .accessibilityLabel(lt("Undo the update to \(label(field).lowercased())"))
                .accessibilityIdentifier("log.updated.undo")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var hoursFootnote: some View {
        Text(lt("You didn\u{2019}t say how long"))
            .font(.footnote.weight(.medium))
            .foregroundStyle(colors.cautionText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("log.hoursDefault")
    }

    // MARK: Who and the record

    var whoRow: some View {
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(label(.participant)).font(.body).foregroundStyle(colors.textPrimary)
            if !isAX { Spacer(minLength: 8) }
            LogWhoSegmented([.init(Participant.selfParticipant, lt("Me")), .init(Participant.spouse, lt("Spouse"))],
                            selection: Binding(get: { form.participant }, set: { form.setParticipant($0); edited(.participant) }),
                            accessibilityLabel: label(.participant))
                .frame(maxWidth: isAX ? .infinity : 190)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .overlay { rowWash(.participant) }
        .id(LogField.participant.rowID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.who")
    }

    /// The model's sentence for the record. Editable in place; the note stays the user's words.
    var recordRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label(.description)).font(.subheadline).foregroundStyle(colors.textSecondary)
            TextField("", text: Binding(get: { form.recordDescription ?? "" }, set: { form.setDescription($0) }), axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .accessibilityLabel(lt("Description for your record"))
                .accessibilityIdentifier("log.description.field")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            if fromNote(.description) {
                Capsule().fill(colors.noteMark).frame(width: 3, height: 26).padding(.leading, 6).accessibilityHidden(true)
            }
        }
        .overlay { rowWash(.description) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.description")
    }

    // MARK: Under the rows

    var receiptRow: some View {
        PhotosPicker(selection: $photoItems, maxSelectionCount: 3, matching: .images) {
            Label(attachments.isEmpty ? lt("Receipt or photo")
                    : (attachments.count == 1 ? lt("1 photo added") : lt("\(attachments.count) photos added")),
                  systemImage: attachments.isEmpty ? "camera" : "checkmark.circle")
        }
        .buttonStyle(LHButton.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("log.receipt")
    }
}


// MARK: - Who control

/// The Me / Spouse control. It sits on a `backgroundTertiary` row, so `LHSegmented`'s own thumb
/// (`backgroundSecondary` on a `backgroundTertiary` track) reads 1.06:1 here and the selection is
/// invisible. This one fills the selected thumb with the action colour (`onAction` ink), which
/// clears 3:1 against the track in light and dark. Same geometry, motion and haptic as `LHSegmented`.
private struct LogWhoSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
        init(_ value: Value, _ label: String) { self.value = value; self.label = label }
    }

    let options: [Option]
    @Binding var selection: Value
    var accessibilityLabel: String

    @Namespace private var thumb
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(_ options: [Option], selection: Binding<Value>, accessibilityLabel: String) {
        self.options = options
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    withAnimation(reduceMotion ? AppAnimation.quick : AppAnimation.segmentSlide) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? AppColors.onAction : colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: LHSegmented<Value>.height - 4)
                        .frame(minWidth: LHSegmented<Value>.minSegmentWidth)
                        .background {
                            if selected {
                                Capsule().fill(colors.action)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                        .animation(AppAnimation.quick, value: selected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(minHeight: LHSegmented<Value>.height)
        .background(colors.backgroundTertiary, in: Capsule())
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
        .frame(minHeight: LHMetrics.minTap)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}
