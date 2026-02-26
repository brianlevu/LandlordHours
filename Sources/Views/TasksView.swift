import SwiftUI
import LucideIcons

struct TasksView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.properties.isEmpty {
                    EmptyTasksView()
                } else {
                    List {
                        // Today's tasks from time entries
                        Section("Today") {
                            ForEach(todayEntries) { entry in
                                TaskListRow(entry: entry, properties: viewModel.properties)
                            }
                        }
                        
                        Section("Upcoming") {
                            ForEach(upcomingEntries) { entry in
                                TaskListRow(entry: entry, properties: viewModel.properties)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                Button {
                    // Add task
                } label: {
                    LucideIcon(image: Lucide.circlePlus, size: 22)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
    }
    
    var todayEntries: [TimeEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return viewModel.timeEntries
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .sorted { $0.date > $1.date }
    }
    
    var upcomingEntries: [TimeEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return viewModel.timeEntries
            .filter { $0.date > today }
            .sorted { $0.date < $1.date }
            .prefix(10)
            .map { $0 }
    }
}

struct EmptyTasksView: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            JellyBadge(systemName: "clipboard-check", color: AppColors.primary, wash: colors.primarySurface, size: 56)
            Text("No Tasks Yet")
                .font(AppTypography.subheadline)
                .foregroundStyle(colors.textPrimary)
            Text("Log time entries to see your tasks here")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}

struct TaskListRow: View {
    let entry: TimeEntry
    let properties: [RentalProperty]
    
    var property: RentalProperty? {
        properties.first { $0.id == entry.propertyId }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(property?.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(entry.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(String(format: "%.1fh", entry.hours))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TasksView()
        .environmentObject(AppViewModel())
}
