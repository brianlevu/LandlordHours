import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var goalManager: GoalManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var totalHours: Double { viewModel.totalHoursAllParticipants(year: currentYear) }
    private var targetHours: Double { goalManager.globalGoalType.hoursRequired }
    private var progress: Double { min(totalHours / targetHours, 1.0) }
    private var remainingHours: Double { max(targetHours - totalHours, 0) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    progressRingCard
                    quickStatsRow
                    recentEntriesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(colors.background)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                Text(formattedDate)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            LHCircleBadge(
                icon: .home,
                bgColor: AppColors.primary,
                fgColor: .white,
                size: 46,
                iconScale: 0.45
            )
        }
        .padding(.top, 4)
    }

    // MARK: - Progress Ring Card
    private var progressRingCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(colors.primarySurface, lineWidth: 22)
                    .frame(width: 190, height: 190)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 22, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 190, height: 190)
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: progress)

                VStack(spacing: 4) {
                    Text(String(format: "%.0f", totalHours))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("of \(Int(targetHours))h")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.textSecondary)
                    Text(goalManager.globalGoalType.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(AppColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colors.primarySurface)
                        .clipShape(Capsule())
                }
            }

            if totalHours >= targetHours {
                HStack(spacing: 6) {
                    LHIconView(icon: .seal, size: 18, color: AppColors.success)
                    Text("Goal reached!")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.success)
                }
            } else {
                Text(String(format: "%.0f hours remaining this year", remainingHours))
                    .font(.system(size: 14))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 16, x: 0, y: 4)
    }

    // MARK: - Quick Stats
    private var quickStatsRow: some View {
        HStack(spacing: 12) {
            DashStatCard(
                icon: .bolt,
                title: "This Week",
                value: String(format: "%.1f", weeklyHours),
                unit: "hrs"
            )
            DashStatCard(
                icon: .calendar,
                title: "This Month",
                value: String(format: "%.1f", monthlyHours),
                unit: "hrs"
            )
        }
    }

    // MARK: - Recent Entries
    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionPill(icon: .clock, label: "RECENT ENTRIES")
                Spacer()
            }
            if recentEntries.isEmpty {
                emptyRecentCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentEntries.enumerated()), id: \.element.id) { index, entry in
                        EntryListRow(
                            entry: entry,
                            propertyName: viewModel.properties.first { $0.id == entry.propertyId }?.name ?? "Unknown"
                        )
                        if index < recentEntries.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)
            }
        }
    }

    private var emptyRecentCard: some View {
        VStack(spacing: 12) {
            LHSoftBadge(icon: .home, color: AppColors.primary, size: 64, iconScale: 0.45)
            Text("No entries yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            Text("Tap Track to log your first hours")
                .font(.system(size: 14))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func sectionPill(icon: LHIcon, label: String) -> some View {
        HStack(spacing: 5) {
            LHIconView(icon: icon, size: 13, color: colors.textSecondary)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
        }
        .foregroundStyle(colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.backgroundTertiary)
        .clipShape(Capsule())
    }

    // MARK: - Computed
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning" }
        if h < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var weeklyHours: Double {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return 0 }
        return viewModel.timeEntries.filter { $0.date >= start && $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    private var monthlyHours: Double {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return 0 }
        return viewModel.timeEntries.filter { $0.date >= start && $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    private var recentEntries: [TimeEntry] {
        Array(viewModel.timeEntries.sorted { $0.date > $1.date }.prefix(5))
    }
}

// MARK: - Dash Stat Card (Tiimo-style — clean white, no border)
struct DashStatCard: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let icon: LHIcon
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LHSoftBadge(icon: icon, color: AppColors.primary, size: 36, iconScale: 0.45)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Shared Entry Row (used in Dashboard & History)
struct EntryListRow: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let entry: TimeEntry
    let propertyName: String

    private var categoryIcon: LHIcon {
        LHIcon.from(sfSymbol: entry.category.icon) ?? .repairs
    }

    var body: some View {
        HStack(spacing: 14) {
            LHIconBadge(
                icon: categoryIcon,
                bgColor: categoryColor,
                fgColor: .white,
                size: 44,
                iconScale: 0.45
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
                Text(propertyName)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if !entry.countsForREPS {
                        Text("Non-REPS")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    Text(String(format: "%.1fh", entry.hours))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                }
                Text(entry.date, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    var categoryColor: Color {
        LHIcon.categoryColor(for: entry.category.rawValue)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppViewModel())
        .environmentObject(GoalManager.shared)
}
