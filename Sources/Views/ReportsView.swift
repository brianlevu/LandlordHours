import SwiftUI
import PDFKit
import LucideIcons

// MARK: - Goal Mode Enum
enum GoalMode: String, CaseIterable, Identifiable {
    case reps750 = "REPS 750h"
    case mp500 = "500h"
    case mp100 = "100h"

    var id: String { rawValue }

    var pillLabel: String { rawValue }

    var targetHours: Double {
        switch self {
        case .reps750: return 750
        case .mp500: return 500
        case .mp100: return 100
        }
    }

    var showInnerRing: Bool {
        self == .reps750
    }

    var outerGradientColors: [Color] {
        switch self {
        case .reps750: return [Color(hex: "8B5CF6"), Color(hex: "A78BFA")]
        case .mp500: return [Color(hex: "8B5CF6"), Color(hex: "C084FC")]
        case .mp100: return [Color(hex: "34D399"), Color(hex: "6EE7B7")]
        }
    }

    var innerGradientColors: [Color] {
        [Color(hex: "34D399"), Color(hex: "6EE7B7")]
    }

    var trackOuterColor: Color {
        switch self {
        case .reps750: return Color(hex: "EDE9FE")
        case .mp500: return Color(hex: "EDE9FE")
        case .mp100: return Color(hex: "ECFDF5")
        }
    }

    var trackInnerColor: Color {
        switch self {
        case .reps750: return Color(hex: "ECFDF5")
        case .mp500: return Color(hex: "F0EFF4")
        case .mp100: return Color(hex: "ECFDF5")
        }
    }

    var accentColor: Color {
        switch self {
        case .reps750: return Color(hex: "8B5CF6")
        case .mp500: return Color(hex: "A855F7")
        case .mp100: return Color(hex: "059669")
        }
    }

    var accentWashColor: Color {
        switch self {
        case .reps750: return Color(hex: "EDE9FE")
        case .mp500: return Color(hex: "F3E8FF")
        case .mp100: return Color(hex: "ECFDF5")
        }
    }

    var glowColor: Color {
        switch self {
        case .reps750: return Color(hex: "8B5CF6").opacity(0.10)
        case .mp500: return Color(hex: "A855F7").opacity(0.10)
        case .mp100: return Color(hex: "34D399").opacity(0.12)
        }
    }

    var stat3Label: String {
        switch self {
        case .reps750: return "50% Rule"
        case .mp500: return "Complete"
        case .mp100: return "Properties"
        }
    }
}

// MARK: - Reports View
struct ReportsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingExportSheet = false
    @State private var selectedGoal: GoalMode = .reps750
    @State private var ringAppeared = false

    // MARK: - Computed Properties

    private var selfHours: Double {
        viewModel.totalHoursForParticipant(.selfParticipant, year: selectedYear)
    }

    private var spouseHours: Double {
        viewModel.totalHoursForParticipant(.spouse, year: selectedYear)
    }

    private var totalHours: Double {
        selfHours + spouseHours
    }

    private var outerProgress: Double {
        let target = selectedGoal.targetHours
        guard target > 0 else { return 0 }
        return min(totalHours / target, 1.0)
    }

    private var innerProgress: Double {
        guard selectedGoal.showInnerRing else { return 0 }
        let selfRatio = selfHours > 0 ? min(selfHours / max(selfHours + spouseHours, 1), 1.0) : 0
        return selfRatio
    }

    private var meets50Percent: Bool {
        viewModel.meets50PercentRule(year: selectedYear)
    }

    private var isGoalMet: Bool {
        totalHours >= selectedGoal.targetHours
    }

    private var remainingHours: Double {
        max(selectedGoal.targetHours - totalHours, 0)
    }

    private var daysLeftInYear: Int {
        let calendar = Calendar.current
        guard let endOfYear = calendar.date(from: DateComponents(year: selectedYear, month: 12, day: 31)) else { return 0 }
        let today = Date()
        let currentYear = calendar.component(.year, from: today)
        if selectedYear < currentYear { return 0 }
        if selectedYear > currentYear { return 365 }
        return max(calendar.dateComponents([.day], from: today, to: endOfYear).day ?? 0, 0)
    }

    private var stat3Value: String {
        switch selectedGoal {
        case .reps750:
            let total = selfHours + spouseHours
            guard total > 0 else { return "0%" }
            let selfPercent = (selfHours / total) * 100
            return String(format: "%.0f%%", selfPercent)
        case .mp500:
            let pct = (totalHours / 500.0) * 100
            return String(format: "%.0f%%", min(pct, 100))
        case .mp100:
            let count = viewModel.properties.count
            return "\(count)"
        }
    }

    private var propertyAccentColors: [Color] {
        [
            Color(hex: "8B5CF6"),
            Color(hex: "F472B6"),
            Color(hex: "34D399"),
            Color(hex: "FBBF24"),
            Color(hex: "60A5FA"),
            Color(hex: "F97316"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header row
                    headerRow
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.xs)

                    // Goal mode pills
                    goalPillRow
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.md)

                    // Ring hero
                    ringHeroSection
                        .padding(.top, 28)

                    // Legend
                    legendRow
                        .padding(.top, 14)

                    // Stat chips
                    statChipRow
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.md)

                    // Property breakdown
                    PropertyBreakdownSection(
                        properties: viewModel.properties,
                        viewModel: viewModel,
                        selectedYear: selectedYear,
                        selectedGoal: selectedGoal,
                        accentColors: propertyAccentColors
                    )
                    .padding(.top, AppSpacing.xl)

                    // Category breakdown
                    CategoryBreakdownSection(
                        viewModel: viewModel,
                        selectedYear: selectedYear,
                        selectedGoal: selectedGoal
                    )
                    .padding(.top, AppSpacing.xl)
                }
                .padding(.bottom, 40)
            }
            .background {
                AuroraBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingExportSheet = true
                    } label: {
                        LucideIcon(image: Lucide.share2, size: 18)
                            .foregroundStyle(selectedGoal.accentColor)
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportPDFView(year: selectedYear)
            }
            .onAppear {
                withAnimation(AppAnimation.ringProgress.delay(0.3)) {
                    ringAppeared = true
                }
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text("Reports")
                .font(AppTypography.headline)
                .foregroundStyle(colors.textPrimary)

            Spacer()

            YearSelector(
                selectedYear: $selectedYear,
                accentColor: selectedGoal.accentColor,
                accentWash: selectedGoal.accentWashColor
            )
        }
    }

    // MARK: - Goal Pill Row

    private var goalPillRow: some View {
        HStack(spacing: 8) {
            ForEach(GoalMode.allCases) { goal in
                GoalPillButton(
                    goal: goal,
                    isSelected: selectedGoal == goal,
                    action: {
                        withAnimation(AppAnimation.pillPop) {
                            selectedGoal = goal
                        }
                    }
                )
            }
            Spacer()
        }
    }

    // MARK: - Ring Hero Section

    private var ringHeroSection: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [selectedGoal.glowColor, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .animation(AppAnimation.standard, value: selectedGoal)

            // Ring container
            ZStack {
                // Outer track (segmented dashes)
                Circle()
                    .stroke(
                        selectedGoal.trackOuterColor,
                        style: StrokeStyle(lineWidth: 18, lineCap: .round, dash: [3, 5])
                    )
                    .frame(width: 216, height: 216)
                    .animation(AppAnimation.standard, value: selectedGoal)

                // Outer progress
                Circle()
                    .trim(from: 0, to: ringAppeared ? outerProgress : 0)
                    .stroke(
                        LinearGradient(
                            colors: selectedGoal.outerGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .frame(width: 216, height: 216)
                    .rotationEffect(.degrees(-90))
                    .animation(AppAnimation.ringProgress, value: outerProgress)
                    .animation(AppAnimation.standard, value: selectedGoal)

                // Inner track (REPS only)
                if selectedGoal.showInnerRing {
                    Circle()
                        .stroke(
                            selectedGoal.trackInnerColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [3, 5])
                        )
                        .frame(width: 164, height: 164)
                        .transition(.opacity)

                    // Inner progress (50% rule)
                    Circle()
                        .trim(from: 0, to: ringAppeared ? innerProgress : 0)
                        .stroke(
                            LinearGradient(
                                colors: selectedGoal.innerGradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 164, height: 164)
                        .rotationEffect(.degrees(-90))
                        .animation(AppAnimation.ringProgress, value: innerProgress)
                        .transition(.opacity)
                }

                // Center content
                ringCenterContent
            }
            .frame(width: 260, height: 260)
        }
    }

    @ViewBuilder
    private var ringCenterContent: some View {
        if isGoalMet && selectedGoal == .mp100 {
            // Goal met state
            VStack(spacing: 4) {
                LucideIcon(image: Lucide.circleCheck, size: 32)
                    .foregroundStyle(Color(hex: "059669"))
                Text("Goal met!")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "059669"))
                Text("\(Int(totalHours)) of \(Int(selectedGoal.targetHours)) hours")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.mist)
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 4) {
                Text(String(format: "%.0f", totalHours))
                    .font(AppTypography.heroNumber)
                    .foregroundStyle(isGoalMet ? Color(hex: "059669") : colors.textPrimary)

                Text("of \(Int(selectedGoal.targetHours)) hours")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.mist)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Legend Row

    private var legendRow: some View {
        HStack(spacing: 20) {
            legendDot(
                color: selectedGoal.outerGradientColors.first ?? AppColors.primary,
                text: selectedGoal == .mp100 ? "All hours logged" :
                      selectedGoal == .mp500 ? "Your hours + Spouse" : "RE Hours"
            )

            if selectedGoal.showInnerRing {
                legendDot(
                    color: Color(hex: "34D399"),
                    text: "50% Rule"
                )
            }
        }
        .animation(AppAnimation.standard, value: selectedGoal)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.slate)
        }
    }

    // MARK: - Stat Chip Row

    private var statChipRow: some View {
        HStack(spacing: 8) {
            StatChip(
                value: isGoalMet ? String(format: "%.0fh", totalHours) : String(format: "%.0fh", remainingHours),
                label: isGoalMet ? "Total logged" : "Remaining",
                valueColor: isGoalMet ? Color(hex: "059669") : colors.textPrimary,
                colorScheme: colorScheme
            )

            StatChip(
                value: "\(daysLeftInYear)",
                label: "Days left",
                valueColor: colors.textPrimary,
                colorScheme: colorScheme
            )

            StatChip(
                value: stat3Value,
                label: selectedGoal.stat3Label,
                valueColor: selectedGoal == .reps750 && meets50Percent ? Color(hex: "059669") :
                            selectedGoal == .mp100 ? Color(hex: "059669") : colors.textPrimary,
                colorScheme: colorScheme
            )
        }
    }
}

// MARK: - Year Selector (Pill Style)
struct YearSelector: View {
    @Binding var selectedYear: Int
    var accentColor: Color = AppColors.primary
    var accentWash: Color = AppColors.primarySurface

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if selectedYear > 2020 { selectedYear -= 1 }
            } label: {
                LucideIcon(image: Lucide.chevronLeft, size: 11)
                    .foregroundStyle(accentColor)
            }

            Text(String(selectedYear))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)

            Button {
                if selectedYear < 2030 { selectedYear += 1 }
            } label: {
                LucideIcon(image: Lucide.chevronRight, size: 11)
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(accentWash)
        .clipShape(Capsule())
        .animation(AppAnimation.standard, value: accentColor)
    }
}

// MARK: - Goal Pill Button
struct GoalPillButton: View {
    let goal: GoalMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(goal.pillLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : AppColors.slate)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? goal.accentColor : Color.white.opacity(0.7))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.black.opacity(0.06),
                            lineWidth: 1.5
                        )
                )
                .scaleEffect(isSelected ? 1.0 : 0.97)
                .shadow(
                    color: isSelected ? goal.accentColor.opacity(0.3) : .clear,
                    radius: 8,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .animation(AppAnimation.pillPop, value: isSelected)
    }
}

// MARK: - Stat Chip
struct StatChip: View {
    let value: String
    let label: String
    var valueColor: Color = AppColors.charcoal
    var colorScheme: ColorScheme = .light

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.mist)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(
                    colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.white.opacity(0.65)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        )
    }
}

// MARK: - Property Breakdown Section
struct PropertyBreakdownSection: View {
    let properties: [RentalProperty]
    let viewModel: AppViewModel
    let selectedYear: Int
    var selectedGoal: GoalMode = .reps750
    var accentColors: [Color] = []

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("By Property")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(colors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)

            if properties.isEmpty {
                EmptySectionCard(
                    systemIcon: "building-2",
                    message: "No properties added"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                        let hours = viewModel.hoursForProperty(property, year: selectedYear)
                        let totalHrs = viewModel.totalHoursAllParticipants(year: selectedYear)
                        let barColor = accentColors.indices.contains(index)
                            ? accentColors[index]
                            : accentColors[index % max(accentColors.count, 1)]
                        PropertyBreakdownRow(
                            property: property,
                            hours: hours,
                            totalHours: totalHrs,
                            barColor: barColor,
                            selectedGoal: selectedGoal
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
            }
        }
    }
}

// MARK: - Property Breakdown Row
struct PropertyBreakdownRow: View {
    let property: RentalProperty
    let hours: Double
    let totalHours: Double
    var barColor: Color = AppColors.primary
    var selectedGoal: GoalMode = .reps750

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var progress: Double {
        guard totalHours > 0 else { return 0 }
        return hours / totalHours
    }

    var barGradient: LinearGradient {
        LinearGradient(
            colors: [barColor, barColor.opacity(0.6)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Color bar accent
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [barColor, barColor.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 40)

            // Property info
            VStack(alignment: .leading, spacing: 2) {
                Text(property.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Text("\(property.propertyType.rawValue) \u{00B7} \(property.address)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.mist)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(barGradient)
                            .frame(width: max(geometry.size.width * progress, 0), height: 4)
                            .animation(AppAnimation.ringProgress, value: progress)
                    }
                }
                .frame(height: 4)
                .padding(.top, 6)
            }

            Spacer(minLength: 4)

            // Hours
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0fh", hours))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        selectedGoal == .mp100 && hours >= 100 ? Color(hex: "059669") : colors.textPrimary
                    )

                Text(String(format: "%.0f%%", progress * 100))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.mist)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(
                    colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.white.opacity(0.65)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        )
    }
}

// MARK: - Category Breakdown Section
struct CategoryBreakdownSection: View {
    let viewModel: AppViewModel
    let selectedYear: Int
    var selectedGoal: GoalMode = .reps750

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var categoryBreakdown: [(ActivityCategory, Double)] {
        let entries = viewModel.entriesForYear(selectedYear)
        var breakdown: [ActivityCategory: Double] = [:]

        for entry in entries where entry.countsForREPS {
            breakdown[entry.category, default: 0] += entry.hours
        }

        return breakdown.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private let categoryColors: [Color] = [
        Color(hex: "8B5CF6"),
        Color(hex: "F472B6"),
        Color(hex: "34D399"),
        Color(hex: "FBBF24"),
        Color(hex: "60A5FA"),
        Color(hex: "F97316"),
        Color(hex: "A78BFA"),
        Color(hex: "3B82F6"),
        Color(hex: "EF4444"),
        Color(hex: "10B981"),
        Color(hex: "EC4899"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("By Category")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(colors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)

            if categoryBreakdown.isEmpty {
                EmptySectionCard(
                    systemIcon: "tag",
                    message: "No time entries yet"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(categoryBreakdown.enumerated()), id: \.element.0) { index, item in
                        let (category, hours) = item
                        let catColor = categoryColors.indices.contains(index)
                            ? categoryColors[index]
                            : categoryColors[index % max(categoryColors.count, 1)]
                        CategoryBreakdownRow(
                            category: category,
                            hours: hours,
                            totalHours: viewModel.totalHoursAllParticipants(year: selectedYear),
                            barColor: catColor
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
            }
        }
    }
}

// MARK: - Category Breakdown Row
struct CategoryBreakdownRow: View {
    let category: ActivityCategory
    let hours: Double
    let totalHours: Double
    var barColor: Color = AppColors.primary

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var progress: Double {
        guard totalHours > 0 else { return 0 }
        return hours / totalHours
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Color bar accent
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [barColor, barColor.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 40)

            // Category info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    LucideIcon(image: category.lucideIcon, size: 12)
                        .foregroundStyle(barColor)

                    Text(category.rawValue)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [barColor, barColor.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geometry.size.width * progress, 0), height: 4)
                            .animation(AppAnimation.ringProgress, value: progress)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }

            Spacer(minLength: 4)

            // Hours
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1fh", hours))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)

                Text(String(format: "%.0f%%", progress * 100))
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.mist)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(
                    colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.white.opacity(0.65)
                )
        )
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        )
    }
}

// MARK: - Empty Section Card
struct EmptySectionCard: View {
    let systemIcon: String
    let message: String

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                JellyBadge(
                    systemName: systemIcon,
                    color: AppColors.mist,
                    wash: AppColors.snow,
                    size: 40
                )

                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.vertical, AppSpacing.xl)
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(
                    colorScheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.white.opacity(0.5)
                )
        )
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - ActivityCategory Lucide Mapping
extension ActivityCategory {
    var lucideIcon: UIImage {
        switch self {
        case .repairs: return Lucide.wrench
        case .management: return Lucide.folder
        case .leasing: return Lucide.key
        case .bookkeeping: return Lucide.fileText
        case .legal: return Lucide.landmark
        case .insurance: return Lucide.shield
        case .travel: return Lucide.car
        case .renovations: return Lucide.hammer
        case .investing: return Lucide.trendingUp
        case .financing: return Lucide.dollarSign
        case .contractNegotiation: return Lucide.fileCog
        }
    }
}

// MARK: - Preview
#Preview {
    ReportsView()
        .environmentObject(AppViewModel())
}
