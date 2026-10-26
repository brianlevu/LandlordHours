import SwiftUI

/// One record, read and edited in place. The tool and what it was on top, the hours large, then the
/// facts as one grouped container, then where it came from. Edits are explicit (Edit, then Save)
/// and delete asks first. Standard §1.4, §1.7, §1.8, §1.9, §1.14 (`.detail` title), §1.17 (the 56pt
/// tool header stays), §H.5 (no house on a record).
struct TimeEntryDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let entry: TimeEntry

    // Edit state
    @State private var notes: String
    @State private var category: ActivityCategory
    @State private var propertyId: UUID
    @State private var hours: Double
    @State private var date: Date
    @State private var participant: Participant

    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDiscardAlert = false
    @State private var savedTick = 0

    init(entry: TimeEntry) {
        self.entry = entry
        _notes = State(initialValue: entry.notes)
        _category = State(initialValue: entry.category)
        _propertyId = State(initialValue: entry.propertyId)
        _hours = State(initialValue: entry.hours)
        _date = State(initialValue: entry.date)
        _participant = State(initialValue: entry.participant)
    }

    private var propertyName: String {
        viewModel.properties.first { $0.id == propertyId }?.name ?? RR.t("record.noRental", "No rental")
    }

    private var badge: RecordSourceBadge { RecordSourceBadge(entry: entry) }

    private var hasChanges: Bool {
        notes != entry.notes ||
        category != entry.category ||
        propertyId != entry.propertyId ||
        hours != entry.hours ||
        date != entry.date ||
        participant != entry.participant
    }

    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                header
                hoursCard
                if isEditing { editSections } else { readSections }
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, LHMetrics.sectionGap)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { LHCanvas() }
        .navigationTitle(isEditing ? RR.t("record.editTitle", "Edit record") : "")
        .navigationBarTitleDisplayMode(.inline)
        // The title lives in the content, so the floating back and Edit controls need their own
        // material or scrolled text runs under them (gate B1, AX3).
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.bar, for: .navigationBar)
        .hidesAppTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button(RR.t("record.save", "Save")) { saveChanges() }
                        .fontWeight(.semibold)
                        .foregroundStyle(hasChanges ? colors.action : colors.textSecondary)
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("entry.save")
                } else {
                    Button(RR.t("record.edit", "Edit")) {
                        animate { isEditing = true }
                    }
                    .foregroundStyle(colors.action)
                    .accessibilityIdentifier("entry.edit")
                }
            }
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button(RR.t("record.cancel", "Cancel")) { cancelEditing() }
                        .foregroundStyle(colors.action)
                }
            }
        }
        .alert(RR.t("record.delete.title", "Delete this record?"), isPresented: $showingDeleteConfirmation) {
            Button(RR.t("record.delete.cancel", "Cancel"), role: .cancel) {}
            Button(RR.t("record.delete.confirm", "Delete"), role: .destructive) {
                viewModel.deleteTimeEntry(entry)
                dismiss()
            }
        } message: {
            Text(RR.t("record.delete.message", "It comes off your hours and your export. This can\u{2019}t be undone."))
        }
        .confirmationDialog(RR.t("record.discard.title", "Discard changes?"), isPresented: $showingDiscardAlert, titleVisibility: .visible) {
            Button(RR.t("record.discard.confirm", "Discard"), role: .destructive) { discardChanges() }
            Button(RR.t("record.discard.keep", "Keep editing"), role: .cancel) {}
        } message: {
            Text(RR.t("record.discard.message", "Your edits to this record will be lost."))
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .navigationBarBackButtonHidden(isEditing)
        .accessibilityIdentifier("entry.detail")
    }

    // MARK: Header

    private var headerSubtitle: String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return RR.t("record.header.subtitle", "\(badge.title) \u{00B7} \(day)")
    }

    private var header: some View {
        let title = LHScreenTitle(
            isEditing ? category.inboxLabel : RecordsLogic.title(for: entry, propertyName: propertyName),
            subtitle: headerSubtitle,
            style: .detail
        )
        .padding(.bottom, -LHMetrics.headerToContent)
        return Group {
            if ax {
                // Tile above the title so the title keeps the full width (no mid-word breaks).
                VStack(alignment: .leading, spacing: 12) {
                    CategoryToolTile(category: category, size: 56)
                    title
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    CategoryToolTile(category: category, size: 56)
                    title
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var hoursCard: some View {
        Group {
            if isEditing {
                LHStepper(hours: $hours, step: 0.25, range: 0.25...24, label: RR.t("record.hours", "Hours"))
                    .frame(maxWidth: .infinity)
            } else {
                HoursReadout(hours: hours)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, isEditing ? 0 : LHMetrics.cardPadding)
        .padding(.vertical, isEditing ? 0 : 14)
        .background {
            // The stepper sits bare on the page: a card around a single 44pt control reads as empty.
            if !isEditing {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .fill(colors.backgroundSecondary)
            }
        }
        .overlay {
            if colorScheme == .dark && !isEditing {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Read

    @ViewBuilder
    private var readSections: some View {
        if !entry.attachments.isEmpty {
            VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                LHSectionHeader(RR.t("record.attachments", "Attachments"), count: entry.attachments.count)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(entry.attachments) { attachment in
                            if let bytes = attachment.data, let uiImage = UIImage(data: bytes) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                                    .accessibilityLabel(RR.t("record.attachment.photo", "Attached photo"))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .accessibilityIdentifier("entry.attachments")
        }

        LHRowGroup {
            FactRow(label: RR.t("record.fact.rental", "Rental"), value: propertyName)
            LHDivider(leadingInset: LHMetrics.cardPadding)
            FactRow(label: RR.t("record.fact.who", "Who"),
                    value: participant == .spouse ? RR.t("record.who.spouse", "Spouse") : RR.t("record.who.me", "Me"))
            LHDivider(leadingInset: LHMetrics.cardPadding)
            FactRow(label: RR.t("record.fact.kind", "Kind of work"), value: category.inboxLabel)
            LHDivider(leadingInset: LHMetrics.cardPadding)
            FactRow(label: RR.t("record.fact.date", "Date"), value: entry.formattedDate)
            if !entry.countsForREPS {
                LHDivider(leadingInset: LHMetrics.cardPadding)
                FactRow(label: RR.t("record.fact.counts", "Counts toward your goal"),
                        value: RR.t("record.fact.counts.no", "No, not rental work"), valueColor: colors.caution)
            }
        }

        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                LHSectionHeader(RR.t("record.notes", "Notes"))
                Text(notes)
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LHMetrics.cardPadding)
                    .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
                    .textSelection(.enabled)
            }
        }

        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(RR.t("record.source.header", "Where it came from"))
            LHRowGroup {
                FactRow(label: RR.t("record.fact.source", "Source"), value: badge.title)
                if let detected = entry.detectedAt {
                    LHDivider(leadingInset: LHMetrics.cardPadding)
                    FactRow(label: RR.t("record.fact.found", "Found"), value: detected.formatted(date: .abbreviated, time: .shortened))
                }
                if let confirmed = entry.confirmedAt {
                    LHDivider(leadingInset: LHMetrics.cardPadding)
                    FactRow(label: RR.t("record.fact.confirmed", "Confirmed by you"), value: confirmed.formatted(date: .abbreviated, time: .shortened))
                }
                LHDivider(leadingInset: LHMetrics.cardPadding)
                FactRow(label: RR.t("record.fact.added", "Added"), value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                if entry.modifiedAt.timeIntervalSince(entry.createdAt) > 1 {
                    LHDivider(leadingInset: LHMetrics.cardPadding)
                    FactRow(label: RR.t("record.fact.changed", "Last changed"), value: entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Text(RR.t("record.source.footer", "Your PDF shows the same source and dates for every record."))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
        }

        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label(RR.t("record.delete.button", "Delete record"), systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LHButton.destructiveTertiary)
        .accessibilityIdentifier("entry.delete")
    }

    // MARK: Edit

    @ViewBuilder
    private var editSections: some View {
        VStack(spacing: 12) {
            Menu {
                Picker(RR.t("record.fact.rental", "Rental"), selection: $propertyId) {
                    ForEach(viewModel.properties) { property in
                        Text(property.name).tag(property.id)
                    }
                }
            } label: {
                EditMenuFace(label: RR.t("record.fact.rental", "Rental"), value: propertyName, colors: colors)
            }
            .accessibilityIdentifier("entry.edit.rental")

            Menu {
                Picker(RR.t("record.fact.kind", "Kind of work"), selection: $category) {
                    ForEach(ActivityCategory.allCases, id: \.self) { cat in
                        Text(cat.inboxLabel).tag(cat)
                    }
                }
            } label: {
                EditMenuFace(label: RR.t("record.fact.kind", "Kind of work"), value: category.inboxLabel, colors: colors)
            }
            .accessibilityIdentifier("entry.edit.kind")

            dateRow

            VStack(alignment: .leading, spacing: 8) {
                Text(RR.t("record.fact.who", "Who"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                LHSegmented([
                    .init(Participant.selfParticipant, RR.t("record.who.me", "Me")),
                    .init(Participant.spouse, RR.t("record.who.spouse", "Spouse"))
                ], selection: $participant, accessibilityLabel: RR.t("record.fact.who", "Who"))
            }
        }

        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(RR.t("record.notes", "Notes"))
            if dynamicTypeSize.isAccessibilitySize {
                axNotesField
            } else {
                LHField(RR.t("record.notes.placeholder", "What did you do?"), text: $notes, multiline: true,
                        identifier: "entry.edit.notes")
            }
            Text(RR.t("record.notes.footer", "A short note helps if anyone asks later."))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    /// The date as a value row with the system date picker on top, so tapping opens the calendar.
    private var dateRow: some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            if ax {
                Text(RR.t("record.fact.date", "Date"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker(RR.t("record.fact.date", "Date"), selection: $date, in: ...Date.distantFuture, displayedComponents: .date)
                    .labelsHidden()
                    .tint(colors.action)
            } else {
                DatePicker(RR.t("record.fact.date", "Date"), selection: $date, in: ...Date.distantFuture, displayedComponents: .date)
                    .tint(colors.action)
                    .foregroundStyle(colors.textPrimary)
            }
        }
        .padding(.horizontal, LHMetrics.cardPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entry.edit.date")
    }

    /// Notes at accessibility sizes: the foundation field clamps to three lines, which clips a
    /// long note. This grows with the text instead.
    private var axNotesField: some View {
        SwiftUI.TextField(text: $notes, prompt: Text(RR.t("record.notes.placeholder", "What did you do?")).foregroundStyle(colors.textTertiary), axis: .vertical) {
            Text(RR.t("record.notes.placeholder", "What did you do?"))
        }
        .font(.body)
        .foregroundStyle(colors.textPrimary)
        .tint(colors.action)
        .lineLimit(1...)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: LHField.multilineMinHeight, alignment: .topLeading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .accessibilityIdentifier("entry.edit.notes")
    }

    // MARK: Actions

    private func saveChanges() {
        var updated = entry
        updated.notes = notes
        updated.category = category
        updated.propertyId = propertyId
        updated.hours = hours
        updated.date = date
        updated.participant = participant
        updated.modifiedAt = Date()
        viewModel.updateTimeEntry(updated)
        savedTick += 1
        animate { isEditing = false }
    }

    private func cancelEditing() {
        if hasChanges {
            showingDiscardAlert = true
        } else {
            animate { isEditing = false }
        }
    }

    private func discardChanges() {
        notes = entry.notes
        category = entry.category
        propertyId = entry.propertyId
        hours = entry.hours
        date = entry.date
        participant = entry.participant
        animate { isEditing = false }
    }

    private func animate(_ animation: Animation = AppAnimation.standard, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

/// One read-only fact: the label left, the value right (stacked at accessibility sizes), 56pt
/// minimum like every row.
private struct FactRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(label)
                .font(typeSize.isAccessibilitySize ? .subheadline : .body)
                .foregroundStyle(colors.textSecondary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Text(value)
                .font(.body)
                .foregroundStyle(valueColor ?? colors.textPrimary)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .padding(LHRow.insets)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A menu row's face for the edit form. Takes the parent's resolved colours: a `Menu` label is
/// rendered outside the parent's environment, so reading `colorScheme` here put the light
/// tertiary fill on a dark canvas.
private struct EditMenuFace: View {
    let label: String
    let value: String
    let colors: AdaptiveColors
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(label)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            HStack(spacing: 6) {
                Text(value)
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// "2h 30m" with small unit letters, SF Pro Rounded tabular.
private struct HoursReadout: View {
    let hours: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let total = LHFormat.minutes(hours) ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(total / 60)")
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .contentTransition(.numericText())
            Text(RR.t("record.unit.h", "h")).font(.title3).foregroundStyle(colors.textSecondary)
            Text(String(format: "%02d", total % 60))
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .contentTransition(.numericText())
                .padding(.leading, 6)
            Text(RR.t("record.unit.m", "m")).font(.title3).foregroundStyle(colors.textSecondary)
        }
        .monospacedDigit()
        .foregroundStyle(colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RR.t("record.hours", "Hours"))
        .accessibilityValue(LHFormat.spokenHours(hours))
    }
}

#Preview {
    NavigationStack {
        TimeEntryDetailView(
            entry: TimeEntry(
                propertyId: UUID(),
                participant: .selfParticipant,
                category: .repairs,
                hours: 2.5,
                date: Date(),
                notes: "Fixed the leaking faucet in the kitchen"
            )
        )
        .environmentObject(AppViewModel())
    }
}
