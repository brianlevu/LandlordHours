import SwiftUI

/// One record, read and edited in place. Same grammar as the Inbox confirm sheet: the tool and
/// what it was on top, the hours large, then the facts as a plain grouped list, then where it came
/// from. Records are tax evidence, so edits are explicit (Edit → Save) and delete asks first.
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
    @FocusState private var isNotesFocused: Bool

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
        viewModel.properties.first { $0.id == propertyId }?.name ?? "No property"
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

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                hoursCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isEditing {
                editSections
            } else {
                readSections
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(isEditing ? "Edit record" : "")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                        .foregroundStyle(hasChanges ? colors.action : colors.textTertiary)
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("entry.save")
                } else {
                    Button("Edit") {
                        animate { isEditing = true }
                    }
                    .foregroundStyle(colors.action)
                    .accessibilityIdentifier("entry.edit")
                }
            }
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancelEditing() }
                        .foregroundStyle(colors.action)
                }
            }
        }
        .alert("Delete this record?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteTimeEntry(entry)
                dismiss()
            }
        } message: {
            Text("It comes off your hours and your export. This can't be undone.")
        }
        .alert("Discard changes?", isPresented: $showingDiscardAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { discardChanges() }
        } message: {
            Text("Your edits to this record will be lost.")
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .navigationBarBackButtonHidden(isEditing)
        .accessibilityIdentifier("entry.detail")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CategoryToolTile(category: category, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(badge.title) · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(AppTypography.drafting)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(colors.draftingInk)
                    .lineLimit(2)
                Text(isEditing ? category.inboxLabel : RecordsLogic.title(for: entry, propertyName: propertyName))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var hoursCard: some View {
        HStack(spacing: 16) {
            if isEditing {
                stepButton(symbol: "minus", label: "Fifteen minutes less", enabled: hours > 0.25) {
                    animate(AppAnimation.quick) { hours = max(0.25, hours - 0.25) }
                }
            }
            Spacer(minLength: 0)
            HoursReadout(hours: hours)
            Spacer(minLength: 0)
            if isEditing {
                stepButton(symbol: "plus", label: "Fifteen minutes more", enabled: hours < 24) {
                    animate(AppAnimation.quick) { hours = min(24, hours + 0.25) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(enabled ? colors.textPrimary : colors.textTertiary)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundTertiary))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border, lineWidth: 1))
        }
        .buttonStyle(.lhPressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Read

    @ViewBuilder
    private var readSections: some View {
        // Photos first: they are the evidence, and the List only builds rows on screen.
        if !entry.attachments.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachments (\(entry.attachments.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entry.attachments) { attachment in
                                if let bytes = attachment.data, let uiImage = UIImage(data: bytes) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .accessibilityLabel("Attached photo")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .accessibilityIdentifier("entry.attachments")
            }
            .listRowBackground(colors.backgroundSecondary)
        }

        Section {
            factRow("Property", value: propertyName)
            factRow("Who", value: participant == .spouse ? "Spouse" : "Me")
            factRow("Category", value: category.inboxLabel)
            factRow("Date", value: entry.formattedDate)
            if !entry.countsForREPS {
                factRow("Counts toward", value: "Not real estate hours", valueColor: colors.caution)
            }
        }
        .listRowBackground(colors.backgroundSecondary)

        if !notes.isEmpty {
            Section {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .textSelection(.enabled)
            } header: {
                BPSectionHeader(title: "Notes")
            }
            .listRowBackground(colors.backgroundSecondary)
        }

        Section {
            factRow("Source", value: badge.title)
            if let detected = entry.detectedAt {
                factRow("Detected", value: detected.formatted(date: .abbreviated, time: .shortened))
            }
            if let confirmed = entry.confirmedAt {
                factRow("Confirmed by you", value: confirmed.formatted(date: .abbreviated, time: .shortened))
            }
            factRow("Added", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            if entry.modifiedAt.timeIntervalSince(entry.createdAt) > 1 {
                factRow("Last changed", value: entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
        } header: {
            BPSectionHeader(title: "Where it came from")
        } footer: {
            Text("Your export shows the same source and dates for every entry.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .listRowBackground(colors.backgroundSecondary)

        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete record", systemImage: "trash")
                    .foregroundStyle(colors.destructive)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("entry.delete")
        }
        .listRowBackground(colors.backgroundSecondary)
    }

    private func factRow(_ label: String, value: String, valueColor: Color? = nil) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline).foregroundStyle(colors.textSecondary)
                    Text(value).font(.body).foregroundStyle(valueColor ?? colors.textPrimary)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.body)
                        .foregroundStyle(valueColor ?? colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    // MARK: Edit

    /// Branded date chip: our capsule is the visual; the system date picker sits invisibly on top
    /// so tapping still opens the native calendar (and VoiceOver still reads a date picker).
    private var dateChip: some View {
        Text(date.formatted(date: .abbreviated, time: .omitted))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(colors.backgroundTertiary))
            .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
            .overlay {
                DatePicker("Date", selection: $date, in: ...Date.distantFuture, displayedComponents: .date)
                    .labelsHidden()
                    .tint(colors.action)
                    .opacity(0.02)
            }
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var editSections: some View {
        Section {
            Picker("Property", selection: $propertyId) {
                ForEach(viewModel.properties) { property in
                    Text(property.name).tag(property.id)
                }
            }
            .tint(colors.action)

            VStack(alignment: .leading, spacing: 8) {
                Text("Who")
                    .foregroundStyle(colors.textPrimary)
                BPSegmentedPicker(
                    options: [Participant.selfParticipant, .spouse],
                    selection: $participant,
                    title: { $0 == .spouse ? "Spouse" : "Me" }
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Who")
            }

            Picker("Category", selection: $category) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    Text(cat.inboxLabel).tag(cat)
                }
            }
            .tint(colors.action)

            HStack {
                Text("Date")
                    .foregroundStyle(colors.textPrimary)
                Spacer(minLength: 12)
                dateChip
            }
        }
        .listRowBackground(colors.backgroundSecondary)

        Section {
            TextField("What did you do?", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .focused($isNotesFocused)
                .foregroundStyle(colors.textPrimary)
        } header: {
            BPSectionHeader(title: "Notes")
        } footer: {
            Text("A short note makes the record stronger if anyone asks later.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
        .listRowBackground(colors.backgroundSecondary)
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
        isNotesFocused = false
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

/// "2h 30m" with small unit letters, SF Pro Rounded tabular (the Inbox sheet's readout).
private struct HoursReadout: View {
    let hours: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let total = Int((hours * 60).rounded())
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(total / 60)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text("h").font(.title3).foregroundStyle(colors.textSecondary)
            Text(String(format: "%02d", total % 60))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
                .padding(.leading, 6)
            Text("m").font(.title3).foregroundStyle(colors.textSecondary)
        }
        .monospacedDigit()
        .foregroundStyle(colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hours")
        .accessibilityValue(BPHours.spoken(hours))
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
