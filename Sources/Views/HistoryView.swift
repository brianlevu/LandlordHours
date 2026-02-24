import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedParticipant: Participant?
    @State private var selectedProperty: RentalProperty?

    var filteredEntries: [TimeEntry] {
        var entries = viewModel.entriesForYear(selectedYear)
        if let participant = selectedParticipant {
            entries = entries.filter { $0.participant == participant }
        }
        if let property = selectedProperty {
            entries = entries.filter { $0.propertyId == property.id }
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
                            filterChip(text: String(selectedYear), icon: "calendar", isActive: true)
                        }

                        Menu {
                            Button("All People") { selectedParticipant = nil }
                            ForEach(Participant.allCases, id: \.self) { p in
                                Button(p.rawValue) { selectedParticipant = p }
                            }
                        } label: {
                            filterChip(
                                text: selectedParticipant?.rawValue ?? "All People",
                                icon: "person.fill",
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
                                icon: "house.fill",
                                isActive: selectedProperty != nil
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(colors.background)

                // Summary strip
                HStack(spacing: 12) {
                    summaryChip(label: "REPS Hours", value: String(format: "%.1fh", totalREPSHours), color: AppColors.success)
                    summaryChip(label: "Non-REPS", value: String(format: "%.1fh", totalNonREPSHours), color: AppColors.warning)
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
                        LHSoftBadge(icon: .clock, color: AppColors.primary, size: 64)
                        Text("No Entries")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        Text("No time entries match your filters")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.background)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                EntryListRow(
                                    entry: entry,
                                    propertyName: viewModel.properties.first { $0.id == entry.propertyId }?.name ?? "Unknown"
                                )
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.deleteTimeEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                if index < filteredEntries.count - 1 {
                                    Divider()
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .background(colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 20)
                    }
                    .background(colors.background)
                }
            }
            .background(colors.background)
            .navigationTitle("History")
        }
    }

    private func filterChip(text: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            DynamicIconView(name: icon, size: 11, color: isActive ? AppColors.primary : colors.textSecondary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            LHIconView(icon: .chevronDown, size: 10, color: isActive ? AppColors.primary : colors.textSecondary, strokeStyle: true)
        }
        .foregroundStyle(isActive ? AppColors.primary : colors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? colors.primarySurface : colors.backgroundSecondary)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 4, x: 0, y: 2)
    }

    private func summaryChip(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppViewModel())
}
