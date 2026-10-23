import SwiftUI
import PhotosUI
import LucideIcons

// MARK: - The rows: what Log will record, each one an editor

extension LogTimeSheet {
    /// How a row looks. A 3pt timber bar marks a value the note gave; a dashed slot is a value still missing.
    enum RowLook { case filled(fromNote: Bool), empty, caution, updated }

    var rows: some View {
        VStack(spacing: 0) {
            if !isFirstRun {
                row(.property)
                rowDivider
            }
            row(.category)
            rowDivider
            row(.hours)
            rowDivider
            row(.date)
            if LogParticipantRule.showsPicker(spouseTracking: spouseTracking), !isRecovery {
                rowDivider
                whoRow
            }
            if form.recordDescription != nil {
                rowDivider
                recordRow
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.sheetCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.sheetStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.rows")
    }

    var rowDivider: some View {
        Rectangle().fill(colors.sheetStroke).frame(height: 1).padding(.horizontal, 12)
    }

    func label(_ field: LogField) -> String {
        switch field {
        case .property: return String(localized: "Rental")
        case .category: return String(localized: "Kind of work")
        case .hours: return String(localized: "How long")
        case .date: return String(localized: "Date")
        case .participant: return String(localized: "Who")
        case .description: return String(localized: "On the record")
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
        case .participant: return form.participant == .spouse ? String(localized: "Spouse") : String(localized: "Me")
        case .description: return form.recordDescription ?? ""
        }
    }

    /// Row = one element: label, value, where it came from, and a hint.
    func a11y(_ field: LogField, _ look: RowLook) -> String {
        let name = label(field)
        let value = valueText(field)
        switch look {
        case .empty: return String(localized: "\(name), not chosen")
        case .caution: return String(localized: "\(name), \(value), you didn\u{2019}t say how long")
        case .updated: return String(localized: "\(name), \(value), updated from your note")
        case .filled(let note): return note ? String(localized: "\(name), \(value), filled from your note") : String(localized: "\(name), \(value)")
        }
    }

    func row(_ field: LogField) -> some View {
        let look = look(field)
        let open = expanded == field
        return VStack(spacing: 0) {
            Button { toggle(field) } label: { rowLabel(field, look, open: open) }
                .buttonStyle(.lhPressable)
                .accessibilityLabel(a11y(field, look))
                .accessibilityHint("Double-tap to change.")
                .accessibilityAddTraits(open ? .isSelected : [])
                .accessibilityIdentifier(identifier(field))
            if field == .property, form.propertyId == nil, mentioned.count >= 2, let hint = form.propertyHint { twoRentalsHint(hint) }
            if field == .category, !form.countsTowardHours, let category = form.category { notCountedNote(category) }
            if case .updated = look { updatedLine(field) }
            if open { editor(field).transition(.opacity) }
        }
        .id("log.row.\(field)")
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.timber.opacity(flashing.contains(field) ? 0.16 : 0)))
    }

    func rowLabel(_ field: LogField, _ look: RowLook, open: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            accentBar(look)
            if isAX {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: label(field)).font(.subheadline).foregroundStyle(colors.textSecondary)
                    valueView(field, look, trailing: false).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(verbatim: label(field)).font(.subheadline).foregroundStyle(colors.textSecondary)
                    .frame(minWidth: 96, alignment: .leading)
                Spacer(minLength: 4)
                valueView(field, look, trailing: true)
            }
            LucideIcon(image: Lucide.chevronRight, size: chevronSize)
                .foregroundStyle(colors.textSecondary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The one timber accent: a 3pt bar on rows whose value came from the note.
    @ViewBuilder func accentBar(_ look: RowLook) -> some View {
        if case .filled(true) = look {
            Capsule().fill(colors.noteMark).frame(width: 3, height: 26).accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 3, height: 26)
        }
    }

    @ViewBuilder func valueView(_ field: LogField, _ look: RowLook, trailing: Bool) -> some View {
        let alignment: TextAlignment = trailing ? .trailing : .leading
        switch look {
        case .empty:
            Text("Choose")
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.actionText)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .overlay(Capsule().strokeBorder(colors.action, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        case .caution, .updated:
            HStack(spacing: 8) {
                Circle().fill(colors.cautionText).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(verbatim: valueText(field)).font(.body.weight(.semibold)).foregroundStyle(colors.cautionText).multilineTextAlignment(alignment)
            }
        case .filled:
            VStack(alignment: isAX || !trailing ? .leading : .trailing, spacing: 2) {
                Text(verbatim: valueText(field)).font(.body.weight(.semibold)).foregroundStyle(colors.textPrimary).multilineTextAlignment(alignment)
                if field == .category, form.categoryIsRemembered, !isReviewing {
                    Text("Last used").font(.caption).foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    // MARK: Under a row

    func twoRentalsHint(_ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: hint).font(.footnote).foregroundStyle(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            LogChipFlow(spacing: 8) {
                ForEach(mentioned) { property in
                    LogChip(title: property.name) { pick(property: property.id) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.propertyHint")
    }

    func notCountedNote(_ category: ActivityCategory) -> some View {
        Text("\(category.inboxLabel) doesn\u{2019}t count toward your hours.")
            .font(.footnote)
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("log.notCounted")
    }

    /// The model changed this row after the rules' answer had been on screen: say so, offer Undo.
    func updatedLine(_ field: LogField) -> some View {
        HStack(spacing: 4) {
            Text("Updated from your note.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(colors.cautionText)
            Button { undoUpdate(field) } label: {
                Text("Undo")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.cautionText)
                    .underline()
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.lhPressable)
            .accessibilityLabel(String(localized: "Undo the update to \(label(field).lowercased())"))
            .accessibilityIdentifier("log.updated.undo")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 25)
        .padding(.bottom, 2)
    }

    // MARK: Who and the record

    var whoRow: some View {
        let stack = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return stack {
            Text("Who").font(.subheadline).foregroundStyle(colors.textSecondary)
                .frame(minWidth: isAX ? nil : 96, alignment: .leading)
            if !isAX { Spacer(minLength: 4) }
            LogWhoPicker(participant: Binding(get: { form.participant }, set: { form.setParticipant($0); edited(.participant) }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.leading, 13)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.timber.opacity(flashing.contains(.participant) ? 0.16 : 0)))
        .id("log.row.participant")
    }

    /// The model's sentence for the record. Editable in place; the note stays the user's words.
    var recordRow: some View {
        HStack(alignment: .top, spacing: 10) {
            accentBar(.filled(fromNote: fromNote(.description))).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: label(.description)).font(.subheadline).foregroundStyle(colors.textSecondary)
                TextField("", text: Binding(get: { form.recordDescription ?? "" }, set: { form.setDescription($0) }), axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .tint(colors.action)
                    .accessibilityLabel("Description for your record")
                    .accessibilityIdentifier("log.description.field")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.timber.opacity(flashing.contains(.description) ? 0.16 : 0)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.description")
    }

    // MARK: Under the card

    var hoursFootnote: some View {
        HStack(spacing: 8) {
            Circle().fill(colors.cautionText).frame(width: 6, height: 6).accessibilityHidden(true)
            Text("You didn\u{2019}t say how long").font(.footnote.weight(.medium)).foregroundStyle(colors.cautionText)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("log.hoursDefault")
    }

    var receiptRow: some View {
        PhotosPicker(selection: $photoItems, maxSelectionCount: 3, matching: .images) {
            HStack(spacing: 10) {
                LucideIcon(image: attachments.isEmpty ? Lucide.camera : Lucide.circleCheck, size: 18)
                    .foregroundStyle(attachments.isEmpty ? colors.actionText : colors.positive)
                    .accessibilityHidden(true)
                Text(verbatim: attachments.isEmpty ? String(localized: "Receipt or photo")
                        : (attachments.count == 1 ? String(localized: "1 photo added") : String(localized: "\(attachments.count) photos added")))
                    .font(.body)
                    .foregroundStyle(attachments.isEmpty ? colors.actionText : colors.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("log.receipt")
    }
}
