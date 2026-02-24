import SwiftUI

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
                    LHIconView(icon: .plusCircle, size: 24, color: AppColors.primary)
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
            LHSoftBadge(icon: .checklist, color: AppColors.primary, size: 64)
            Text("No Tasks Yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text("Log time entries to see your tasks here")
                .font(.system(size: 14))
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
