import SwiftUI
import LucideIcons

struct TimeEntryDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        viewModel.properties.first { $0.id == propertyId }?.name ?? "Unknown"
    }

    private var hasChanges: Bool {
        notes != entry.notes ||
        category != entry.category ||
        propertyId != entry.propertyId ||
        hours != entry.hours ||
        date != entry.date ||
        participant != entry.participant
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header card with icon + category + hours
                headerCard

                // Details sections
                if isEditing {
                    editForm
                } else {
                    readOnlyDetails
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(colors.background)
        .navigationTitle("Entry Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") { saveChanges() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hasChanges ? AppColors.primary : colors.textTertiary)
                        .disabled(!hasChanges)
                } else {
                    Button {
                        animate(AppAnimation.standard) { isEditing = true }
                    } label: {
                        HStack(spacing: 4) {
                            LucideIcon(image: Lucide.pencil, size: 14)
                            Text("Edit")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancelEditing() }
                        .font(.system(size: 15))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
        .alert("Delete Entry?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteTimeEntry(entry)
                dismiss()
            }
        } message: {
            Text("This time entry will be permanently deleted.")
        }
        .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) { discardChanges() }
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
        .navigationBarBackButtonHidden(isEditing && hasChanges)
        .onTapGesture { isNotesFocused = false }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            // Category badge
            JellyBadge(
                systemName: categoryIconName,
                color: categoryColor,
                wash: categoryWash,
                size: 56
            )

            // Category name
            Text(category.rawValue)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            // Hours + date
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    LucideIcon(image: Lucide.clock, size: 14)
                        .foregroundStyle(categoryColor)
                    Text(String(format: "%.1fh", hours))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }

                Circle()
                    .fill(colors.border)
                    .frame(width: 4, height: 4)

                HStack(spacing: 4) {
                    LucideIcon(image: Lucide.calendar, size: 14)
                        .foregroundStyle(colors.textSecondary)
                    Text(date, style: .date)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            // REPS badge
            if !entry.countsForREPS {
                Text("Not REPS")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.coralWash)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    // MARK: - Read-Only Details

    @ViewBuilder
    private var readOnlyDetails: some View {
        VStack(spacing: 0) {
            detailRow(icon: Lucide.house, label: "Property", value: propertyName)
            divider
            detailRow(icon: Lucide.user, label: "Participant", value: participant.rawValue)
            divider
            detailRow(icon: Lucide.clock, label: "Hours", value: String(format: "%.1fh", hours))
            divider
            detailRow(icon: Lucide.calendar, label: "Date", value: entry.formattedDate)

            if !notes.isEmpty {
                divider
                notesSection
            }

            if !entry.attachments.isEmpty {
                divider
                attachmentsSection
            }

            if entry.importSource != nil {
                divider
                detailRow(icon: Lucide.calendar, label: "Source", value: "Calendar Import")
            }
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }

        // Delete button
        Button {
            showingDeleteConfirmation = true
        } label: {
            HStack(spacing: 6) {
                LucideIcon(image: Lucide.trash2, size: 14)
                Text("Delete Entry")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(AppColors.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.error.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)

        // Metadata
        VStack(spacing: 4) {
            Text("Created \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(AppTypography.caption)
                .foregroundStyle(colors.textTertiary)
            if entry.modifiedAt != entry.createdAt {
                Text("Modified \(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private func detailRow(icon: UIImage, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            LucideIcon(image: icon, size: 16)
                .foregroundStyle(colors.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.fileText, size: 16)
                    .foregroundStyle(colors.textSecondary)
                Text("Notes")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.textSecondary)
            }
            Text(notes)
                .font(.system(size: 14))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.paperclip, size: 16)
                    .foregroundStyle(colors.textSecondary)
                Text("Attachments (\(entry.attachments.count))")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entry.attachments) { attachment in
                        if let uiImage = UIImage(data: attachment.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 48)
    }

    // MARK: - Edit Form

    private var editForm: some View {
        VStack(spacing: 16) {
            // Notes
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Notes")
                TextEditor(text: $notes)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.textPrimary)
                    .focused($isNotesFocused)
                    .frame(minHeight: 80)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isNotesFocused ? AppColors.primary.opacity(0.4) : AppColors.snow, lineWidth: 1.5)
                    )
            }

            // Category
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Category")
                categoryChips
            }

            // Property
            if viewModel.properties.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Property")
                    propertyPicker
                }
            }

            // Hours
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Hours")
                hoursStepper
            }

            // Date
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Date")
                datePicker
            }

            // Participant
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Participant")
                participantSegment
            }

            // Save button
            Button { saveChanges() } label: {
                Text("Save Changes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.onAction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasChanges ? AppColors.primary : AppColors.mist)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!hasChanges)
            .padding(.top, 8)
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(colors.textSecondary)
    }

    // MARK: - Edit Form Components

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    Button {
                        animate(AppAnimation.quick) { category = cat }
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(category == cat
                                      ? Color.white.opacity(0.5)
                                      : categoryDotColor(for: cat))
                                .frame(width: 8, height: 8)
                            Text(categoryChipLabel(for: cat))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(category == cat ? .white : AppColors.slate)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(category == cat ? AppColors.primary : AppColors.snow)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var propertyPicker: some View {
        Menu {
            ForEach(viewModel.properties) { property in
                Button {
                    propertyId = property.id
                } label: {
                    HStack {
                        Text(property.name)
                        if propertyId == property.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(colors.primarySurface)
                    .frame(width: 28, height: 28)
                    .overlay(
                        LucideIcon(image: Lucide.house, size: 14)
                            .foregroundStyle(AppColors.primary)
                    )
                Text(propertyName)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                LucideIcon(image: Lucide.chevronRight, size: 18)
                    .foregroundStyle(AppColors.cloud)
            }
            .padding(14)
            .padding(.horizontal, 2)
            .background(colors.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppColors.snow, lineWidth: 1.5)
            )
        }
    }

    private var hoursStepper: some View {
        HStack(spacing: 24) {
            Spacer()

            Button {
                if hours > 0.25 {
                    animate(AppAnimation.quick) { hours -= 0.25 }
                }
            } label: {
                LucideIcon(image: Lucide.minus, size: 16)
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(colors.background)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(hours.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText())
                Text("h")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.mist)
            }
            .frame(minWidth: 80, alignment: .center)

            Button {
                if hours < 24 {
                    animate(AppAnimation.quick) { hours += 0.25 }
                }
            } label: {
                LucideIcon(image: Lucide.plus, size: 16)
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(colors.background)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var datePicker: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(colors.primarySurface)
                .frame(width: 28, height: 28)
                .overlay(
                    LucideIcon(image: Lucide.calendar, size: 14)
                        .foregroundStyle(AppColors.primary)
                )
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .tint(AppColors.primary)
            Spacer()
        }
        .padding(14)
        .padding(.horizontal, 2)
        .background(colors.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColors.snow, lineWidth: 1.5)
        )
    }

    private var participantSegment: some View {
        HStack(spacing: 0) {
            segmentButton("Self", isSelected: participant == .selfParticipant) {
                animate(AppAnimation.quick) { participant = .selfParticipant }
            }
            segmentButton("Spouse", isSelected: participant == .spouse) {
                animate(AppAnimation.quick) { participant = .spouse }
            }
        }
        .padding(3)
        .background(AppColors.snow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func segmentButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? colors.textPrimary : AppColors.slate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? colors.backgroundSecondary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? colors.border.opacity(0.35) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

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
        animate(AppAnimation.standard) { isEditing = false }
    }

    private func cancelEditing() {
        if hasChanges {
            showingDiscardAlert = true
        } else {
            animate(AppAnimation.standard) { isEditing = false }
        }
    }

    private func discardChanges() {
        notes = entry.notes
        category = entry.category
        propertyId = entry.propertyId
        hours = entry.hours
        date = entry.date
        participant = entry.participant
        animate(AppAnimation.standard) { isEditing = false }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    // MARK: - Helpers

    private var categoryIconName: String {
        switch category {
        case .repairs: return "wrench"
        case .management: return "folder"
        case .leasing: return "key"
        case .bookkeeping: return "file-text"
        case .legal: return "landmark"
        case .insurance: return "shield"
        case .travel: return "car"
        case .renovations: return "hammer"
        case .investing: return "trending-up"
        case .financing: return "dollar-sign"
        case .contractNegotiation: return "file-cog"
        }
    }

    private var categoryColor: Color {
        category.color
    }

    private var categoryWash: Color {
        switch category {
        case .repairs, .renovations: return colors.coralWash
        case .management, .investing: return colors.sageWash
        case .leasing, .travel: return colors.skyWash
        case .bookkeeping, .financing: return colors.honeyWash
        case .legal: return colors.roseWash
        case .insurance, .contractNegotiation: return colors.primarySurface
        }
    }

    private func categoryChipLabel(for cat: ActivityCategory) -> String {
        cat.chipLabel
    }

    private func categoryDotColor(for cat: ActivityCategory) -> Color {
        cat.color
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
