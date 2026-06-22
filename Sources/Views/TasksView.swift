import SwiftUI
import LucideIcons

struct TasksView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.properties.isEmpty {
                    EmptyTasksView()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            taskSection(title: "Today", entries: todayEntries)
                            taskSection(title: "Upcoming", entries: upcomingEntries)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                    .background { LHMobileCanvas() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tasks")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text("Review work that came from logged property activity.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func taskSection(title: String, entries: [TimeEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            if entries.isEmpty {
                Text(title == "Today" ? "No time logged today." : "No upcoming logged work.")
                    .font(AppTypography.body)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TaskListRow(entry: entry, properties: viewModel.properties)
                        if index < entries.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
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
            Text("No tasks yet")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text("Log time entries to see property work here.")
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
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    
    var property: RentalProperty? {
        properties.first { $0.id == entry.propertyId }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            LHIconTile(icon: Lucide.clipboardCheck, color: AppColors.sage, wash: colors.sageWash, size: 34, isActive: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(property?.name ?? "Unknown")
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.textPrimary)
                Text(entry.category.rawValue)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            Text(String(format: "%.1fh", entry.hours))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    TasksView()
        .environmentObject(AppViewModel())
}
