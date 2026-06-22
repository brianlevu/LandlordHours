import SwiftUI
import LucideIcons

struct HistoryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedParticipant: Participant?
    @State private var selectedProperty: RentalProperty?
    @State private var entryToDelete: TimeEntry?
    @State private var showingDeleteConfirmation = false
    @State private var filterImportedOnly = false

    var filteredEntries: [TimeEntry] {
        var entries = viewModel.entriesForYear(selectedYear)
        if let participant = selectedParticipant {
            entries = entries.filter { $0.participant == participant }
        }
        if let property = selectedProperty {
            entries = entries.filter { $0.propertyId == property.id }
        }
        if filterImportedOnly {
            entries = entries.filter { $0.importSource != nil }
        }
        return entries.sorted { $0.date > $1.date }
    }

    var totalREPSHours: Double {
        filteredEntries.filter { $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    var totalNonREPSHours: Double {
        filteredEntries.filter { !$0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach((2020...2030), id: \.self) { year in
                                Button(String(year)) { selectedYear = year }
                            }
                        } label: {
                            filterChip(text: String(selectedYear), icon: Lucide.calendar, isActive: true)
                        }

                        Menu {
                            Button("All People") { selectedParticipant = nil }
                            ForEach(Participant.allCases, id: \.self) { p in
                                Button(p.rawValue) { selectedParticipant = p }
                            }
                        } label: {
                            filterChip(
                                text: selectedParticipant?.rawValue ?? "All People",
                                icon: Lucide.user,
                                isActive: selectedParticipant != nil
                            )
                        }

                        Menu {
                            Button("All Properties") { selectedProperty = nil }
                            ForEach(viewModel.properties) { property in
                                Button(property.name) { selectedProperty = property }
                            }
                        } label: {
                            filterChip(
                                text: selectedProperty?.name ?? "All Properties",
                                icon: Lucide.house,
                                isActive: selectedProperty != nil
                            )
                        }

                        Button {
                            filterImportedOnly.toggle()
                        } label: {
                            filterChip(
                                text: "Imported",
                                icon: Lucide.calendar,
                                isActive: filterImportedOnly
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(colors.background)

                // Summary strip
                HStack(spacing: 12) {
                    summaryChip(label: "REPS Hours", value: String(format: "%.1fh", totalREPSHours), color: AppColors.sage)
                    summaryChip(label: "Non-REPS", value: String(format: "%.1fh", totalNonREPSHours), color: AppColors.honey)
                    summaryChip(label: "Entries", value: "\(filteredEntries.count)", color: AppColors.primary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .background(colors.background)

                Rectangle()
                    .fill(colors.border.opacity(0.4))
                    .frame(height: 1)

                // Entries
                if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        JellyBadge(systemName: "clock", color: AppColors.primary, wash: colors.primarySurface, size: 64)
                        Text("No Entries")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                        Text("No time entries match your filters")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.background)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                NavigationLink {
                                    TimeEntryDetailView(entry: entry)
                                } label: {
                                    EntryListRow(
                                        entry: entry,
                                        propertyName: viewModel.properties.first { $0.id == entry.propertyId }?.name ?? "Unknown"
                                    )
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        entryToDelete = entry
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", image: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        entryToDelete = entry
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label { Text("Delete") } icon: { lucideImage(Lucide.trash2) }
                                    }
                                }
                                if index < filteredEntries.count - 1 {
                                    Divider()
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .background(colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 20)
                    }
                    .background(colors.background)
                }
            }
            .background(colors.background)
            .navigationTitle("History")
            .alert("Delete Entry?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { entryToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        viewModel.deleteTimeEntry(entry)
                    }
                    entryToDelete = nil
                }
            } message: {
                Text("This time entry will be permanently deleted.")
            }
        }
    }

    private func filterChip(text: String, icon: UIImage, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            LucideIcon(image: icon, size: 11)
                .foregroundStyle(isActive ? AppColors.primary : colors.textSecondary)
            Text(text)
                .font(AppTypography.caption)
                .lineLimit(1)
            LucideIcon(image: Lucide.chevronDown, size: 10)
                .foregroundStyle(isActive ? AppColors.primary : colors.textSecondary)
        }
        .foregroundStyle(isActive ? AppColors.primary : colors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? colors.primarySurface : colors.backgroundSecondary)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(isActive ? colors.primary.opacity(0.35) : colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private func summaryChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(AppTypography.label)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppViewModel())
}
