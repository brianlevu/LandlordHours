import SwiftUI
import LucideIcons

struct CalendarImportReviewView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State var detectedEntries: [DetectedCalendarEntry]
    @State private var importCount = 0
    @State private var didImport = false

    private var selectedCount: Int {
        detectedEntries.filter(\.isSelected).count
    }

    private var allSelected: Bool {
        detectedEntries.allSatisfy(\.isSelected)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if didImport {
                    successState
                } else if detectedEntries.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
            .background(colors.background)
            .navigationTitle(didImport ? "Import Complete" : "Review Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(didImport ? "Done" : "Cancel") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(colors.textSecondary)
                }
                if !didImport && !detectedEntries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            let newValue = !allSelected
                            for i in detectedEntries.indices {
                                detectedEntries[i].isSelected = newValue
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                    }
                }
            }
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.calendar, size: 16)
                    .foregroundStyle(AppColors.primary)
                Text("\(detectedEntries.count) events detected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text("\(selectedCount) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(detectedEntries.enumerated()), id: \.element.id) { index, entry in
                        CalendarImportRow(
                            entry: $detectedEntries[index],
                            properties: viewModel.properties,
                            colors: colors
                        )
                        if index < detectedEntries.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            importButton
        }
    }

    // MARK: - Import Button

    private var importButton: some View {
        Button {
            importCount = viewModel.importCalendarEntries(detectedEntries)
            withAnimation(AppAnimation.standard) { didImport = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.download, size: 16)
                    .foregroundStyle(.white)
                Text("Import \(selectedCount) Entries")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedCount > 0 ? AppColors.primary : AppColors.mist)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedCount == 0)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: 20) {
            Spacer()
            JellyBadge(systemName: "circle-check", color: AppColors.sage, wash: colors.sageWash, size: 64)
            Text("\(importCount) Entries Imported")
                .font(AppTypography.title2)
                .foregroundStyle(colors.textPrimary)
            Text("Your calendar events have been added to your time log. You can edit them anytime.")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            JellyBadge(systemName: "calendar", color: AppColors.primary, wash: colors.primarySurface, size: 64)
            Text("No Events Found")
                .font(AppTypography.title2)
                .foregroundStyle(colors.textPrimary)
            Text("No property-related calendar events were found in the last 90 days.")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - Calendar Import Row

struct CalendarImportRow: View {
    @Binding var entry: DetectedCalendarEntry
    let properties: [RentalProperty]
    let colors: AdaptiveColors

    private var propertyName: String {
        guard let id = entry.propertyId else { return "No Property" }
        return properties.first { $0.id == id }?.name ?? "Unknown"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                entry.isSelected.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(entry.isSelected ? AppColors.primary : Color.clear)
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(entry.isSelected ? AppColors.primary : AppColors.cloud, lineWidth: 1.5)
                    )
                    .overlay {
                        if entry.isSelected {
                            LucideIcon(image: Lucide.check, size: 14)
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.eventTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(entry.isSelected ? colors.textPrimary : colors.textTertiary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Date
                    Text(entry.eventDate, style: .date)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)

                    // Category picker
                    Menu {
                        ForEach(ActivityCategory.allCases, id: \.self) { cat in
                            Button {
                                entry.category = cat
                            } label: {
                                HStack {
                                    Text(cat.chipLabel)
                                    if entry.category == cat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(entry.category.color)
                                .frame(width: 6, height: 6)
                            Text(entry.category.chipLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(colors.textSecondary)
                            LucideIcon(image: Lucide.chevronDown, size: 8)
                                .foregroundStyle(colors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.snow)
                        .clipShape(Capsule())
                    }

                    // Property picker
                    if properties.count > 1 {
                        Menu {
                            ForEach(properties) { property in
                                Button {
                                    entry.propertyId = property.id
                                } label: {
                                    HStack {
                                        Text(property.name)
                                        if entry.propertyId == property.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(propertyName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(colors.textSecondary)
                                    .lineLimit(1)
                                LucideIcon(image: Lucide.chevronDown, size: 8)
                                    .foregroundStyle(colors.textTertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.snow)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            // Hours
            Text(String(format: "%.1fh", entry.hours))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(entry.isSelected ? colors.textPrimary : colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(entry.isSelected ? 1.0 : 0.6)
    }
}
