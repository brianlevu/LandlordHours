import SwiftUI
import LucideIcons

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

    private var isREPS: Bool { goalManager.globalGoalType == .reps || goalManager.globalGoalType == .both }

    // 50% rule compliance: ratio of RE hours to total working hours
    private var fiftyPercentCompliance: Double {
        let selfHours = viewModel.totalHoursForParticipant(.selfParticipant, year: currentYear)
        let spouseHours = viewModel.totalHoursForParticipant(.spouse, year: currentYear)
        let total = selfHours + spouseHours
        guard total > 0 else { return 0 }
        return min(selfHours / total, 1.0)
    }

    // Pace calculations
    private var daysLeftInYear: Int {
        let cal = Calendar.current
        guard let endOfYear = cal.date(from: DateComponents(year: currentYear, month: 12, day: 31)) else { return 0 }
        let remaining = cal.dateComponents([.day], from: Date(), to: endOfYear).day ?? 0
        return max(remaining, 1)
    }

    private var weeksLeftInYear: Double {
        max(Double(daysLeftInYear) / 7.0, 1.0)
    }

    private var hoursPerWeekNeeded: Double {
        remainingHours / weeksLeftInYear
    }

    private var isOnTrack: Bool {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let expectedProgress = Double(dayOfYear) / 365.0
        return progress >= expectedProgress * 0.85
    }

    // This week hours by day
    private var thisWeekHours: [Double] {
        let cal = Calendar.current
        let today = Date()
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return Array(repeating: 0, count: 7)
        }
        var result: [Double] = []
        for dayOffset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                result.append(0)
                continue
            }
            let dayHours = viewModel.timeEntries
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.hours }
            result.append(dayHours)
        }
        return result
    }

    private var thisWeekTotal: Double {
        thisWeekHours.reduce(0, +)
    }

    private var todayWeekdayIndex: Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        // Convert Sunday=1 to Monday-first: Mon=0, Tue=1, ... Sun=6
        return weekday == 1 ? 6 : weekday - 2
    }

    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    trialStatusNudge
                    progressRingCard
                    thisWeekCard
                    recentEntriesSection
                    learnCarouselSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background {
                AuroraBackground()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPaywall) {
                PaywallView(showPaywall: $showPaywall)
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingLine)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
                HStack(spacing: 6) {
                    Text("Track your hours")
                        .font(AppTypography.headline)
                        .foregroundStyle(colors.textPrimary)
                    if subscriptionManager.isPro && !subscriptionManager.isTrialActive {
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button(action: {}) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(colors.border, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    LucideIcon(image: Lucide.bell, size: 18)
                        .foregroundStyle(AppColors.charcoal)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Trial Status Nudge
    @ViewBuilder
    private var trialStatusNudge: some View {
        if subscriptionManager.isTrialActive {
            // Trial active
            Button { showPaywall = true } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.primarySurface)
                            .frame(width: 32, height: 32)
                        LucideIcon(image: Lucide.sparkles, size: 16)
                            .foregroundStyle(AppColors.primary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pro Trial \u{00B7} \(subscriptionManager.trialDaysRemaining) days left")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text("All features unlocked")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                    }
                    Spacer()
                    Text("Upgrade")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.primarySurface)
                        .clipShape(Capsule())
                }
                .padding(10)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(colors.border.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else if !subscriptionManager.isPro {
            // Trial expired
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "5B4BC9"), AppColors.primary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        LucideIcon(image: Lucide.sparkles, size: 20)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your trial has ended")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text("Upgrade to keep all your data and unlock exports.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                    }
                    Spacer()
                    Text("Upgrade")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
                .padding(14)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(colors.border.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress Ring Card
    private var progressRingCard: some View {
        VStack(spacing: 16) {
            // Dual-ring progress
            ZStack {
                // Ambient glow
                RadialGradient(
                    colors: [AppColors.primary.opacity(0.08), AppColors.primary.opacity(0.02), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 120
                )
                .frame(width: 240, height: 240)

                // Ring container
                ZStack {
                    // Outer track (segmented dashes)
                    Circle()
                        .stroke(
                            AppColors.primarySurface,
                            style: StrokeStyle(lineWidth: 18, dash: [3, 5])
                        )
                        .frame(width: 216, height: 216)

                    // Outer progress fill
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "8B5CF6"), Color(hex: "A78BFA")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round, dash: [3, 5])
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 216, height: 216)
                        .animation(AppAnimation.ringProgress, value: progress)

                    // Inner ring (50% rule) — only for REPS
                    if isREPS {
                        // Inner track
                        Circle()
                            .stroke(
                                AppColors.sageWash,
                                style: StrokeStyle(lineWidth: 10, dash: [3, 5])
                            )
                            .frame(width: 164, height: 164)

                        // Inner progress fill
                        Circle()
                            .trim(from: 0, to: fiftyPercentCompliance)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "34D399"), Color(hex: "6EE7B7")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [3, 5])
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 164, height: 164)
                            .animation(AppAnimation.ringProgress, value: fiftyPercentCompliance)
                    }

                    // Center content
                    VStack(spacing: 4) {
                        if totalHours >= targetHours {
                            LucideIcon(image: Lucide.check, size: 32)
                                .foregroundStyle(AppColors.success)
                            Text("Goal met!")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.success)
                        } else {
                            Text(String(format: "%.0f", totalHours))
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                            Text("of \(Int(targetHours)) hours")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.textTertiary)
                        }
                    }
                }
                .frame(width: 260, height: 260)
            }

            // Hero message
            if totalHours < targetHours {
                VStack(spacing: 4) {
                    Text("You\u{2019}re building momentum")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("\(Int(remainingHours)) hours to go \u{2014} about \(Int(hoursPerWeekNeeded))h per week. You\u{2019}ve got this.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Pace chips
            paceChipsRow
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(colors.border.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.045), radius: 16, x: 0, y: 2)
    }

    // MARK: - Pace Chips
    private var paceChipsRow: some View {
        HStack(spacing: 12) {
            // Pace chip
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.sage)
                    .frame(width: 6, height: 6)
                Text("Pace")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text(isOnTrack ? "On track" : "Behind")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.sage)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "F0F0F0").opacity(0.6), lineWidth: 1)
            )

            // 50% Rule chip
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 6, height: 6)
                Text("50% Rule")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text("\(Int(fiftyPercentCompliance * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "F0F0F0").opacity(0.6), lineWidth: 1)
            )
        }
    }

    // MARK: - This Week Card
    private var thisWeekCard: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text("This Week")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text(String(format: "%.1fh", thisWeekTotal))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primary)
                    .tracking(-0.5)
            }

            // Day grid
            let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        let hours = thisWeekHours[i]
                        let isToday = i == todayWeekdayIndex
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    isToday ? AppColors.primary :
                                    hours > 0 ? AppColors.primarySurface :
                                    AppColors.snow
                                )
                                .frame(width: 32, height: 32)
                                .shadow(color: isToday ? AppColors.primary.opacity(0.3) : .clear, radius: 4, y: 2)

                            if hours > 0 {
                                Text(String(format: "%.0f", hours))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? .white : AppColors.primary)
                            } else {
                                Text("\u{2013}")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? .white : AppColors.cloud)
                            }
                        }
                        Text(dayLabels[i])
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(AppColors.mist)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(22)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(hex: "F0F0F0").opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 12, x: 0, y: 2)
    }

    // MARK: - Recent Entries
    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                if !recentEntries.isEmpty {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        HStack(spacing: 2) {
                            Text("See all")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.primary)
                            LucideIcon(image: Lucide.chevronRight, size: 14)
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                }
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
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 2)
            }
        }
    }

    private var emptyRecentCard: some View {
        VStack(spacing: 12) {
            JellyBadge(systemName: "clock", color: AppColors.primary, wash: colors.primarySurface, size: 56)
            Text("No entries yet")
                .font(AppTypography.subheadline)
                .foregroundStyle(colors.textPrimary)
            Text("Tap Track to log your first hours")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
    }

    // MARK: - Learn Carousel
    private var learnCarouselSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Kicker + headline
            VStack(alignment: .leading, spacing: 4) {
                Text("LEARN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.mist)
                Text("Tax Essentials")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
            }

            // Horizontal card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink {
                        LearningCenterView()
                    } label: {
                        learnCard(
                            category: "IRS BASICS",
                            title: "What Counts as REPS Hours?",
                            readTime: "3 min",
                            categoryColor: AppColors.primary,
                            washColor: AppColors.primarySurface,
                            iconImage: Lucide.bookOpen
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LearningCenterView()
                    } label: {
                        learnCard(
                            category: "TAX STRATEGY",
                            title: "The 50% Rule Explained",
                            readTime: "5 min",
                            categoryColor: AppColors.sage,
                            washColor: AppColors.sageWash,
                            iconImage: Lucide.lightbulb
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LearningCenterView()
                    } label: {
                        learnCard(
                            category: "RECORD KEEPING",
                            title: "Audit-Proof Your Logs",
                            readTime: "4 min",
                            categoryColor: AppColors.coral,
                            washColor: AppColors.coralWash,
                            iconImage: Lucide.shieldCheck
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
            .padding(.horizontal, -2)
        }
    }

    private func learnCard(category: String, title: String, readTime: String, categoryColor: Color, washColor: Color, iconImage: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Illustration area
            ZStack {
                washColor
                ZStack {
                    Circle()
                        .fill(AppColors.charcoal)
                        .frame(width: 24, height: 24)
                    LucideIcon(image: Lucide.bookOpen, size: 12)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)

                LucideIcon(image: iconImage, size: 32)
                    .foregroundStyle(categoryColor.opacity(0.5))
            }
            .frame(height: 100)

            // Body
            VStack(alignment: .leading, spacing: 6) {
                Text(category)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(categoryColor)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(2)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    LucideIcon(image: Lucide.clock, size: 10)
                        .foregroundStyle(AppColors.mist)
                    Text(readTime)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .frame(width: 165)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(colors.border.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Computed
    private var greetingLine: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning," }
        if h < 17 { return "Good afternoon," }
        return "Good evening,"
    }

    private var recentEntries: [TimeEntry] {
        Array(viewModel.timeEntries.sorted { $0.date > $1.date }.prefix(5))
    }
}

// MARK: - Shared Entry Row (used in Dashboard & History)
struct EntryListRow: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let entry: TimeEntry
    let propertyName: String

    private var categorySystemIcon: String {
        switch entry.category {
        case .repairs: return "wrench"
        case .management: return "clipboard"
        case .leasing: return "key"
        case .bookkeeping: return "calculator"
        case .legal: return "landmark"
        case .insurance: return "shield"
        case .travel: return "car"
        case .renovations: return "hammer"
        case .investing: return "trending-up"
        case .financing: return "banknote"
        case .contractNegotiation: return "file-cog"
        }
    }

    private var categoryColor: Color {
        switch entry.category {
        case .repairs: return AppColors.coral
        case .management: return AppColors.sage
        case .leasing: return AppColors.sky
        case .bookkeeping: return AppColors.honey
        case .legal: return AppColors.rose
        case .insurance: return AppColors.primaryLight
        case .travel: return AppColors.sky
        case .renovations: return AppColors.coral
        case .investing: return AppColors.sage
        case .financing: return AppColors.honey
        case .contractNegotiation: return AppColors.primary
        }
    }

    private var categoryWash: Color {
        let c = AdaptiveColors(colorScheme: colorScheme)
        switch entry.category {
        case .repairs, .renovations: return c.coralWash
        case .management, .investing: return c.sageWash
        case .leasing, .travel: return c.skyWash
        case .bookkeeping, .financing: return c.honeyWash
        case .legal: return c.roseWash
        case .insurance, .contractNegotiation: return c.primarySurface
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            JellyBadge(
                systemName: categorySystemIcon,
                color: categoryColor,
                wash: categoryWash,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category.rawValue)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(propertyName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if !entry.countsForREPS {
                        Text("Non-REPS")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColors.coral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.coralWash)
                            .clipShape(Capsule())
                    }
                    Text(String(format: "%.1fh", entry.hours))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }
                Text(entry.date, style: .date)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppViewModel())
        .environmentObject(GoalManager.shared)
}
