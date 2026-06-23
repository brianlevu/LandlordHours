import SwiftUI
import PDFKit
import LucideIcons

// MARK: - Goal Mode Enum
enum GoalMode: String, CaseIterable, Identifiable {
    case reps750 = "REPS · 750h"
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
        case .reps750: return [AppColors.reportsAccent, AppColors.reportsAccentSoft]
        case .mp500: return [AppColors.reportsAccent, AppColors.mpAccentSoft]
        case .mp100: return [AppColors.successGreenLight, AppColors.successGreenSoft]
        }
    }

    var innerGradientColors: [Color] {
        [AppColors.successGreenLight, AppColors.successGreenSoft]
    }

    var trackOuterColor: Color {
        switch self {
        case .reps750: return AppColors.reportsAccentWash
        case .mp500: return AppColors.reportsAccentWash
        case .mp100: return AppColors.successGreenWash
        }
    }

    var trackInnerColor: Color {
        switch self {
        case .reps750: return AppColors.successGreenWash
        case .mp500: return AppColors.snow
        case .mp100: return AppColors.successGreenWash
        }
    }

    var accentColor: Color {
        switch self {
        case .reps750: return AppColors.reportsAccent
        case .mp500: return AppColors.mpAccent
        case .mp100: return AppColors.successGreen
        }
    }

    var accentWashColor: Color {
        switch self {
        case .reps750: return AppColors.reportsAccentWash
        case .mp500: return AppColors.mpAccentWash
        case .mp100: return AppColors.successGreenWash
        }
    }

    var glowColor: Color {
        switch self {
        case .reps750: return AppColors.reportsAccent.opacity(0.10)
        case .mp500: return AppColors.mpAccent.opacity(0.10)
        case .mp100: return AppColors.successGreenLight.opacity(0.12)
        }
    }

    var stat3Label: String {
        switch self {
        case .reps750: return "50% Rule"
        case .mp500: return "Complete"
        case .mp100: return ">100h tests"
        }
    }

}

// MARK: - Reports View
struct ReportsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @StateObject private var goalManager = GoalManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingExportSheet = false
    @State private var showingPaywall = false
    @State private var selectedGoal: GoalMode = .reps750
    @State private var ringAppeared = false

    private var reportsBottomContentInset: CGFloat {
        AppSpacing.tabContentBottomInset + AppSpacing.xxl
    }

    // MARK: - Computed Properties

    private var selfHours: Double {
        viewModel.totalHoursForParticipant(.selfParticipant, year: selectedYear)
    }

    private var spouseHours: Double {
        viewModel.totalHoursForParticipant(.spouse, year: selectedYear)
    }

    private var totalHours: Double {
        switch selectedGoal {
        case .reps750:
            return repsStatus.realEstateHours
        case .mp500, .mp100:
            return materialParticipationStatus.ownerAndSpouseHours
        }
    }

    private var repsStatus: TaxQualificationEngine.REPSResult {
        viewModel.repsStatus(participant: .selfParticipant, year: selectedYear)
    }

    private var materialParticipationStatus: TaxQualificationEngine.MaterialParticipationResult {
        viewModel.materialParticipationOverview(year: selectedYear)
    }

    private var outerProgress: Double {
        let target = selectedGoal.targetHours
        guard target > 0 else { return 0 }
        return min(totalHours / target, 1.0)
    }

    private var innerProgress: Double {
        guard selectedGoal.showInnerRing else { return 0 }
        return min(repsStatus.realEstateWorkPercentage, 1.0)
    }

    private var meets50Percent: Bool {
        viewModel.meets50PercentRule(year: selectedYear)
    }

    private var isGoalMet: Bool {
        switch selectedGoal {
        case .reps750:
            return repsStatus.isQualified
        case .mp500:
            return materialParticipationStatus.meets500HourTest
        case .mp100:
            return materialParticipationStatus.meets100HourTest
        }
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
            return String(format: "%.0f%%", repsStatus.realEstateWorkPercentage * 100)
        case .mp500:
            let pct = (totalHours / 500.0) * 100
            return String(format: "%.0f%%", min(pct, 100))
        case .mp100:
            let count = viewModel.properties.filter { property in
                viewModel.materialParticipationStatus(year: selectedYear, propertyId: property.id).meets100HourTest
            }.count
            return "\(count)"
        }
    }

    private var weeklyPaceNeeded: Double {
        guard daysLeftInYear > 0 else { return 0 }
        let weeksLeft = Double(daysLeftInYear) / 7.0
        guard weeksLeft > 0 else { return 0 }
        return remainingHours / weeksLeft
    }

    private var paceStatus: (label: String, detail: String, isOnTrack: Bool) {
        if isGoalMet {
            let over = totalHours - selectedGoal.targetHours
            if selectedGoal == .reps750 && !meets50Percent {
                return ("Hours target met", "50% rule still needed", false)
            }
            return (selectedGoal == .reps750 ? "Qualified" : "Goal met", "\(String(format: "%.0f", over))h over target", true)
        }
        let pace = weeklyPaceNeeded
        if pace <= 20 {
            return ("On track", "~\(String(format: "%.1f", pace))h/week needed", true)
        } else {
            return ("Behind pace", "~\(String(format: "%.1f", pace))h/week needed", false)
        }
    }

    private var propertyAccentColors: [Color] {
        [
            AppColors.reportsAccent,
            AppColors.error,
            AppColors.successGreenLight,
            AppColors.warning,
            AppColors.dataBlue,
            AppColors.repairOrange,
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    headerRow

                    goalPillRow

                    ringHeroSection

                    legendRow

                    paceIndicator

                    statChipRow

                    PropertyBreakdownSection(
                        properties: viewModel.properties,
                        viewModel: viewModel,
                        selectedYear: selectedYear,
                        selectedGoal: selectedGoal,
                        accentColors: propertyAccentColors
                    )
                    .padding(.top, AppSpacing.xl)

                    CategoryBreakdownSection(
                        viewModel: viewModel,
                        selectedYear: selectedYear,
                        selectedGoal: selectedGoal
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, reportsBottomContentInset)
            }
            .background {
                goalBackground
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingExportSheet) {
                ExportPDFView(year: selectedYear)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(showPaywall: $showingPaywall)
            }
            .onAppear {
                // Sync selected goal from GoalManager settings
                switch goalManager.globalGoalType {
                case .reps, .both:
                    selectedGoal = .reps750
                case .str:
                    selectedGoal = .mp100
                }
                animate(AppAnimation.ringProgress.delay(0.3)) {
                    ringAppeared = true
                }
            }
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    // MARK: - Goal-Specific Background
    private var goalBackground: some View {
        ZStack {
            LHMobileCanvas()

            Circle()
                .fill(selectedGoal.glowColor)
                .frame(width: 240, height: 240)
                .blur(radius: 58)
                .offset(x: selectedGoal == .mp500 ? -150 : 150, y: -230)
                .allowsHitTesting(false)

            Circle()
                .fill(selectedGoal.accentWashColor.opacity(colorScheme == .dark ? 0.08 : 0.42))
                .frame(width: 180, height: 180)
                .blur(radius: 52)
                .offset(x: selectedGoal == .mp100 ? -130 : 130, y: 260)
                .allowsHitTesting(false)
        }
        .lhMotion(AppAnimation.standard, value: selectedGoal)
    }

    // MARK: - Header Row
    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text("Reports")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .minimumScaleFactor(0.82)

                Spacer()

                Button {
                    exportAction()
                } label: {
                    LucideIcon(image: subscriptionManager.isPro && !subscriptionManager.isTrialActive ? Lucide.share2 : Lucide.lock, size: 20)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subscriptionManager.isPro && !subscriptionManager.isTrialActive ? "Export report" : "Unlock export")
            }

            Text("Check pace, gaps, and export-ready evidence.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(2)

            YearSelector(
                selectedYear: $selectedYear,
                accentColor: colors.textPrimary,
                accentWash: colors.backgroundTertiary
            )
        }
    }

    private func exportAction() {
        if subscriptionManager.isPro && !subscriptionManager.isTrialActive {
            showingExportSheet = true
        } else {
            showingPaywall = true
        }
    }

    // MARK: - Goal Pill Row
    private var goalPillRow: some View {
        HStack(spacing: 8) {
            ForEach(GoalMode.allCases) { goal in
                GoalPillButton(
                    goal: goal,
                    isSelected: selectedGoal == goal,
                    accentColor: goal.accentColor,
                    accentWash: goal.accentWashColor,
                    action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        animate(AppAnimation.pillPop) {
                            selectedGoal = goal
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .lhMotion(AppAnimation.standard, value: selectedGoal)

            ZStack {
                // Outer track (segmented dashes)
                Circle()
                    .stroke(
                        selectedGoal.trackOuterColor,
                        style: StrokeStyle(lineWidth: 18, lineCap: .round, dash: [3, 5])
                    )
                    .frame(width: 216, height: 216)
                    .lhMotion(AppAnimation.standard, value: selectedGoal)

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
                    .lhMotion(AppAnimation.ringProgress, value: outerProgress)
                    .lhMotion(AppAnimation.standard, value: selectedGoal)

                // Inner track (REPS only)
                if selectedGoal.showInnerRing {
                    Circle()
                        .stroke(
                            selectedGoal.trackInnerColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [3, 5])
                        )
                        .frame(width: 164, height: 164)
                        .transition(.opacity)

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
                        .lhMotion(AppAnimation.ringProgress, value: innerProgress)
                        .transition(.opacity)
                }

                ringCenterContent
            }
            .frame(width: 260, height: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selectedGoal.pillLabel) progress. \(AppFormat.hours(totalHours)) logged out of \(Int(selectedGoal.targetHours)) hours.")
    }

    @ViewBuilder
    private var ringCenterContent: some View {
        if isGoalMet && selectedGoal == .mp100 {
            VStack(spacing: 4) {
                LucideIcon(image: Lucide.circleCheck, size: 32)
                    .foregroundStyle(AppColors.successGreen)
                Text("Goal met!")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.successGreen)
                Text("\(Int(totalHours)) of \(Int(selectedGoal.targetHours)) hours")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.mist)
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 4) {
                Text(String(format: "%.0f", totalHours))
                    .font(AppTypography.heroNumber)
                    .foregroundStyle(isGoalMet ? AppColors.successGreen : colors.textPrimary)

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
                    color: AppColors.successGreenLight,
                    text: "50% Rule"
                )
            }
        }
        .lhMotion(AppAnimation.standard, value: selectedGoal)
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

    // MARK: - Pace Indicator
    private var paceIndicator: some View {
        let pace = paceStatus
        return HStack(spacing: 8) {
            // Pace badge
            HStack(spacing: 6) {
                Circle()
                    .fill(pace.isOnTrack ? AppColors.successGreenLight : colors.caution)
                    .frame(width: 6, height: 6)
                Text(pace.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(pace.isOnTrack ? AppColors.successGreen : AppColors.cautionText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(pace.isOnTrack ? AppColors.successGreenWash : colors.cautionSurface)
            .clipShape(Capsule())

            // Detail text
            Text(pace.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.mist)
        }
        .lhMotion(AppAnimation.standard, value: selectedGoal)
    }

    // MARK: - Stat Chip Row
    private var statChipRow: some View {
        HStack(spacing: 8) {
            StatChip(
                value: isGoalMet ? AppFormat.hours(totalHours) : AppFormat.hours(remainingHours),
                label: isGoalMet ? "Total logged" : "Remaining",
                valueColor: isGoalMet ? AppColors.successGreen : colors.textPrimary,
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
                valueColor: selectedGoal == .reps750 && meets50Percent ? AppColors.successGreen :
                            selectedGoal == .mp100 ? AppColors.successGreen : colors.textPrimary,
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
            .accessibilityLabel("Previous year")

            Text(String(selectedYear))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)

            Button {
                if selectedYear < 2030 { selectedYear += 1 }
            } label: {
                LucideIcon(image: Lucide.chevronRight, size: 11)
                    .foregroundStyle(accentColor)
            }
            .accessibilityLabel("Next year")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(accentWash)
        .clipShape(Capsule())
        .lhMotion(AppAnimation.standard, value: accentColor)
    }
}

// MARK: - Goal Pill Button
struct GoalPillButton: View {
    let goal: GoalMode
    let isSelected: Bool
    var accentColor: Color = AppColors.action
    var accentWash: Color = AppColors.actionSurface
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            Text(goal.pillLabel)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? AppColors.onAction : colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? accentColor : inactiveFill)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? accentWash.opacity(colorScheme == .dark ? 0.72 : 0.9) : colors.border.opacity(colorScheme == .dark ? 0.85 : 0.28),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .lhMotion(AppAnimation.pillPop, value: isSelected)
    }

    private var inactiveFill: Color {
        colors.backgroundTertiary
    }
}

// MARK: - Stat Chip
struct StatChip: View {
    let value: String
    let label: String
    var valueColor: Color = AppColors.charcoal
    var colorScheme: ColorScheme = .light
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
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
            HStack {
                Text("Properties")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)

                Spacer()
            }

            if properties.isEmpty {
                EmptySectionCard(
                    systemIcon: "building-2",
                    message: "No properties added",
                    actionLabel: "Add Property",
                    action: {
                        // Switch to Properties tab (index 1)
                        NotificationCenter.default.post(name: .switchToTab, object: 1)
                    }
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                        let hours = viewModel.hoursForProperty(property, year: selectedYear)
                        let barColor = accentColors[index % max(accentColors.count, 1)]
                        PropertyBreakdownRow(
                            property: property,
                            hours: hours,
                            barColor: barColor,
                            selectedGoal: selectedGoal
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Property Breakdown Row
struct PropertyBreakdownRow: View {
    let property: RentalProperty
    let hours: Double
    var barColor: Color = AppColors.primary
    var selectedGoal: GoalMode = .reps750

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var progress: Double {
        guard selectedGoal.targetHours > 0 else { return 0 }
        return min(hours / selectedGoal.targetHours, 1.0)
    }

    var barGradient: LinearGradient {
        LinearGradient(
            colors: [barColor, barColor.opacity(0.6)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var metaText: String {
        switch selectedGoal {
        case .reps750:
            return "\(property.propertyType.rawValue) \u{00B7} \(property.address)"
        case .mp500:
            return "\(property.propertyType.rawValue) \u{00B7} \(AppFormat.hours(hours)) of \(Int(selectedGoal.targetHours))h"
        case .mp100:
            if hours > selectedGoal.targetHours {
                return "\(property.propertyType.rawValue) \u{00B7} \(AppFormat.hours(hours)), met"
            } else if hours == selectedGoal.targetHours {
                return "\(property.propertyType.rawValue) \u{00B7} \(AppFormat.hours(hours)), add any more time"
            } else {
                let left = selectedGoal.targetHours - hours
                return "\(property.propertyType.rawValue) \u{00B7} \(AppFormat.hours(hours)), \(AppFormat.hours(left)) left"
            }
        }
    }

    private var hoursDisplayText: String {
        switch selectedGoal {
        case .reps750:
            return AppFormat.hours(hours)
        case .mp500:
            let pct = (hours / selectedGoal.targetHours) * 100
            return String(format: "%.0f%%", pct)
        case .mp100:
            return AppFormat.hours(hours)
        }
    }

    private var hoursColor: Color {
        switch selectedGoal {
        case .reps750:
            return colors.textPrimary
        case .mp500:
            return barColor
        case .mp100:
            return hours > selectedGoal.targetHours ? AppColors.successGreen : colors.textPrimary
        }
    }

    private var subText: String {
        switch selectedGoal {
        case .reps750:
            return String(format: "%.0f%%", progress * 100)
        case .mp500:
            return "complete"
        case .mp100:
            return "logged"
        }
    }

    private var effectiveBarColor: Color {
        if selectedGoal == .mp100 && hours > selectedGoal.targetHours {
            return AppColors.successGreenLight
        }
        return barColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(effectiveBarColor.opacity(colorScheme == .dark ? 0.28 : 0.18))
                .frame(width: 44, height: 44)
                .overlay {
                    LucideIcon(image: property.propertyType == .str ? Lucide.bedDouble : Lucide.house, size: 20)
                        .foregroundStyle(effectiveBarColor)
                }

            // Property info
            VStack(alignment: .leading, spacing: 2) {
                Text(property.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)

                Text(metaText)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors.border.opacity(colorScheme == .dark ? 0.35 : 0.35))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [effectiveBarColor, effectiveBarColor.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geometry.size.width * progress, 0), height: 4)
                            .lhMotion(AppAnimation.ringProgress, value: progress)
                    }
                }
                .frame(height: 4)
                .padding(.top, 6)
            }

            Spacer(minLength: 4)

            // Hours
            VStack(alignment: .trailing, spacing: 2) {
                Text(hoursDisplayText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(hoursColor)

                Text(subText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
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
        AppColors.reportsAccent,
        AppColors.error,
        AppColors.successGreenLight,
        AppColors.warning,
        AppColors.dataBlue,
        AppColors.repairOrange,
        AppColors.reportsAccentSoft,
        AppColors.dataBlueDeep,
        AppColors.dataRed,
        AppColors.dataEmerald,
        AppColors.dataPink,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories")
                    .font(.system(size: 17, weight: .bold))
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
                        let catColor = categoryColors[index % max(categoryColors.count, 1)]
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
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [barColor, barColor.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    LucideIcon(image: category.lucideIcon, size: 12)
                        .foregroundStyle(barColor)

                    Text(category.rawValue)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors.border.opacity(colorScheme == .dark ? 0.35 : 0.35))
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
                            .lhMotion(AppAnimation.ringProgress, value: progress)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(AppFormat.hours(hours))
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
                    ? colors.backgroundSecondary.opacity(0.9)
                    : Color.white.opacity(0.65)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .strokeBorder(colors.border.opacity(colorScheme == .dark ? 0.75 : 0.22), lineWidth: 1)
        )
    }
}

// MARK: - Empty Section Card
struct EmptySectionCard: View {
    let systemIcon: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

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

                if let actionLabel, let action {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                }
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

    var lucideIconName: String {
        switch self {
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

    var color: Color {
        switch self {
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

    var chipLabel: String {
        switch self {
        case .repairs: return "Repairs"
        case .management: return "Management"
        case .leasing: return "Leasing"
        case .bookkeeping: return "Bookkeeping"
        case .legal: return "Legal"
        case .insurance: return "Insurance"
        case .travel: return "Travel"
        case .renovations: return "Renovations"
        case .investing: return "Investing"
        case .financing: return "Financing"
        case .contractNegotiation: return "Contracts"
        }
    }
}

// MARK: - Preview
#Preview {
    ReportsView()
        .environmentObject(AppViewModel())
}
