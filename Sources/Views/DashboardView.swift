import SwiftUI
import LucideIcons

struct DashboardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var goalManager: GoalManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var repsStatus: TaxQualificationEngine.REPSResult {
        viewModel.repsStatus(participant: .selfParticipant, year: currentYear)
    }
    private var materialParticipationStatus: TaxQualificationEngine.MaterialParticipationResult {
        viewModel.materialParticipationOverview(year: currentYear)
    }
    private var totalHours: Double {
        switch goalManager.globalGoalType {
        case .reps, .both:
            return repsStatus.realEstateHours
        case .str:
            return materialParticipationStatus.ownerAndSpouseHours
        }
    }
    private var targetHours: Double { goalManager.globalGoalType.hoursRequired }
    private var progress: Double { min(totalHours / targetHours, 1.0) }
    private var remainingHours: Double { max(targetHours - totalHours, 0) }
    private var isGoalMet: Bool {
        switch goalManager.globalGoalType {
        case .reps, .both:
            return repsStatus.isQualified
        case .str:
            return materialParticipationStatus.isMateriallyParticipating
        }
    }

    private var isREPS: Bool { goalManager.globalGoalType == .reps || goalManager.globalGoalType == .both }

    // 50% rule compliance: ratio of RE hours to total working hours (incl. non-RE employment)
    private var fiftyPercentCompliance: Double {
        min(repsStatus.realEstateWorkPercentage, 1.0)
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
    @State private var isReady = false
    @State private var showLearningCenter = Self.shouldOpenLearningCenterFromLaunchArguments
    @State private var showHistory = false
    @State private var scrollOffset: CGFloat = 0

    private static var shouldOpenLearningCenterFromLaunchArguments: Bool {
        ProcessInfo.processInfo.arguments.contains("-LHOpenLearningCenter")
    }

    private var shouldShowActivationCard: Bool {
        viewModel.properties.isEmpty || viewModel.timeEntries.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LHMobileCanvas()

                if isReady {
                    ScrollView(showsIndicators: false) {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: DashboardScrollOffsetPreferenceKey.self,
                                    value: proxy.frame(in: .named("dashboardScroll")).minY
                                )
                        }
                        .frame(height: 0)

                        VStack(spacing: 22) {
                            headerSection
                            if shouldShowActivationCard {
                                homeActivationCard
                                progressRingCard
                            } else {
                                progressRingCard
                                learningShortcutCard
                            }
                            recentEntriesSection
                            thisWeekCard
                            trialStatusNudge
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, AppSpacing.tabContentBottomInset)
                    }
                    .coordinateSpace(name: "dashboardScroll")
                    .onPreferenceChange(DashboardScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
                    .overlay(alignment: .top) {
                        if isCompactHeaderVisible {
                            compactDashboardBar
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .transition(.opacity)
                } else {
                    ScrollView(showsIndicators: false) {
                        DashboardSkeleton()
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPaywall) {
                PaywallView(showPaywall: $showPaywall)
            }
            .navigationDestination(isPresented: $showLearningCenter) {
                LearningCenterView()
            }
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .onAppear {
                // Brief skeleton then reveal — lets SwiftUI layout settle
                if !isReady {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        animate(.easeOut(duration: 0.35)) {
                            isReady = true
                        }
                    }
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

    private var isCompactHeaderVisible: Bool {
        scrollOffset < -70
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Button {
                    NotificationCenter.default.post(name: .switchToTab, object: 4)
                } label: {
                    Circle()
                        .fill(colors.backgroundTertiary)
                        .frame(width: 54, height: 54)
                        .overlay {
                            Text(userInitials)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(colors.backgroundSecondary)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    LucideIcon(image: Lucide.settings, size: 12)
                                        .foregroundStyle(colors.textSecondary)
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(colors.border.opacity(0.38), lineWidth: 1)
                                }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open profile and settings")

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .switchToTab, object: 3)
                } label: {
                    LucideIcon(image: Lucide.chartColumnIncreasing, size: 22)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open reports")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(dashboardTitle)
                    .font(.system(size: dashboardTitleSize, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(-1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(dashboardSubtitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            quickActionsRow
        }
    }

    private var compactDashboardBar: some View {
        HStack(spacing: 12) {
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: 4)
            } label: {
                Text(userInitials)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile and settings")

            VStack(alignment: .leading, spacing: 1) {
                Text(compactHeaderTitle)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(compactHeaderSubtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                NotificationCenter.default.post(name: .switchToTab, object: 2)
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(image: Lucide.plus, size: 14)
                    Text("Log")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(AppColors.onAction)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(colors.action)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log time")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.88 : 0.94))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: colors.textPrimary.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 12, y: 6)
        .lhMotion(AppAnimation.reveal, value: isCompactHeaderVisible)
    }

    private var displayName: String {
        let name = viewModel.userName
        if name.isEmpty || name == "User" { return "Dashboard" }
        // Use first name only
        return name.components(separatedBy: " ").first ?? name
    }

    private var dashboardTitle: String {
        if viewModel.properties.isEmpty {
            return "Add your first property"
        }
        if viewModel.timeEntries.isEmpty {
            return "Log your first hour"
        }
        return "Today's work"
    }

    private var dashboardTitleSize: CGFloat {
        shouldShowActivationCard ? 31 : 32
    }

    private var dashboardSubtitle: String {
        if viewModel.properties.isEmpty {
            return "Start with a property so every hour has a clean record."
        }
        if viewModel.timeEntries.isEmpty {
            return "\(viewModel.properties.count) property ready. Capture the first activity while details are fresh."
        }
        return "\(AppFormat.hours(totalHours)) logged toward \(Int(targetHours)) hours. \(isOnTrack ? "You're on pace." : "\(Int(hoursPerWeekNeeded))h per week gets you back on pace.")"
    }

    private var compactHeaderTitle: String {
        if shouldShowActivationCard { return "Finish setup" }
        return "\(AppFormat.hours(totalHours)) logged"
    }

    private var compactHeaderSubtitle: String {
        if shouldShowActivationCard {
            return "\(completedActivationSteps)/2 essentials complete"
        }
        return "\(Int(progress * 100))% of \(Int(targetHours))h target"
    }

    private var userInitials: String {
        let source = displayName == "Dashboard" ? "LH" : displayName
        let pieces = source.split(separator: " ")
        if pieces.count >= 2 {
            return pieces.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    // MARK: - Home Commands
    @ViewBuilder
    private var quickActionsRow: some View {
        if viewModel.properties.isEmpty {
            HStack(spacing: 10) {
                dashboardPrimaryPill("Add property", icon: Lucide.building2) {
                    openAddPropertyFromHome()
                }
                dashboardSecondaryPill("What counts", icon: Lucide.bookOpenText, width: 138) {
                    showLearningCenter = true
                }
            }
        } else if viewModel.timeEntries.isEmpty {
            HStack(spacing: 10) {
                dashboardPrimaryPill("Log time", icon: Lucide.clock) {
                    NotificationCenter.default.post(name: .switchToTab, object: 2)
                }
                dashboardSecondaryPill("Learn", icon: Lucide.bookOpenText, width: 92) {
                    showLearningCenter = true
                }
                dashboardSecondaryPill("Property", icon: Lucide.building2, width: 104) {
                    NotificationCenter.default.post(name: .switchToTab, object: 1)
                }
            }
        } else {
            HStack(spacing: 10) {
                dashboardPrimaryPill("Log time", icon: Lucide.clock) {
                    NotificationCenter.default.post(name: .switchToTab, object: 2)
                }
                dashboardSecondaryPill("Entries", icon: Lucide.list, width: 98) {
                    showHistory = true
                }
                dashboardSecondaryPill("Reports", icon: Lucide.chartColumnIncreasing, width: 100) {
                    NotificationCenter.default.post(name: .switchToTab, object: 3)
                }
            }
        }
    }

    private func dashboardPrimaryPill(_ title: String, icon: UIImage, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIcon(image: icon, size: 17)
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(AppColors.onAction)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(colors.action)
            .clipShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title)
    }

    private func dashboardSecondaryPill(_ title: String, icon: UIImage, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(image: icon, size: 15)
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(colors.textPrimary)
            .frame(width: width)
            .frame(height: 50)
            .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.72 : 1))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title)
    }

    // MARK: - Pro Status Nudge
    @ViewBuilder
    private var trialStatusNudge: some View {
        if !subscriptionManager.isPro && shouldShowProNudge {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    LHIconTile(icon: Lucide.sparkles, color: AppColors.primary, wash: colors.primarySurface, size: 44, isActive: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Pro")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text("Buy lifetime access for exports and unlimited properties.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                    }
                    Spacer()
                    Text("Upgrade")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.onAction)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.action)
                        .clipShape(Capsule())
                }
                .padding(14)
                .lhSurfaceCard(cornerRadius: 20)
            }
            .buttonStyle(.plain)
        }
    }

    private var shouldShowProNudge: Bool {
        !viewModel.properties.isEmpty &&
        (!viewModel.timeEntries.isEmpty || GuidedOnboardingStore.isCompleted || GuidedOnboardingStore.isSkipped)
    }

    // MARK: - Progress Ring Card
    private var progressRingCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goalCardTitle)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(goalCardSubtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 16)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colors.textPrimary.opacity(colorScheme == .dark ? 0.16 : 0.08))
                            .frame(height: 10)
                        Capsule()
                            .fill(colors.textPrimary)
                            .frame(width: proxy.size.width * progress, height: 10)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(AppFormat.hours(totalHours)) logged")
                    Spacer()
                    Text("\(Int(remainingHours))h left")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
            }

            HStack(spacing: 12) {
                dashboardMiniMetric(title: "Pace", value: isOnTrack ? "On track" : "Behind")
                if isREPS {
                    dashboardMiniMetric(title: "50% rule", value: "\(Int(fiftyPercentCompliance * 100))%")
                } else {
                    dashboardMiniMetric(title: "Days left", value: "\(daysLeftInYear)")
                }
            }
        }
        .padding(24)
        .background(isGoalMet ? AppColors.sage : colors.sageWash)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isGoalMet
            ? "Goal met. \(AppFormat.hours(totalHours)) logged"
            : "\(AppFormat.hours(totalHours)) of \(Int(targetHours)) hours, \(Int(progress * 100)) percent complete")
    }

    private var goalCardTitle: String {
        isGoalMet ? "Goal met" : "\(Int(targetHours)) hour target"
    }

    private var goalCardSubtitle: String {
        if isGoalMet { return "Your tracked work has reached the current goal." }
        return "\(Int(hoursPerWeekNeeded))h per week \(isOnTrack ? "keeps you on pace" : "gets you back on pace") for \(currentYear)."
    }

    private func dashboardMiniMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.62 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Activation
    private var homeActivationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                LHIconTile(
                    icon: Lucide.listChecks,
                    color: colors.action,
                    wash: colors.actionSurface,
                    size: 42,
                    isActive: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish your tax-ready setup")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("A few quick steps make every hour easier to review later.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                }

                Spacer(minLength: 8)

                Text("\(completedActivationSteps)/2")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.backgroundTertiary)
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                activationActionTile(
                    title: "Property",
                    subtitle: viewModel.properties.isEmpty ? "Add first" : "\(viewModel.properties.count) ready",
                    icon: Lucide.building2,
                    isComplete: !viewModel.properties.isEmpty,
                    accessibilityIdentifier: "home.activation.property",
                    action: {
                        openAddPropertyFromHome()
                    }
                )

                activationActionTile(
                    title: "First hour",
                    subtitle: viewModel.timeEntries.isEmpty ? "Log now" : AppFormat.hours(totalHours),
                    icon: Lucide.clock,
                    isComplete: !viewModel.timeEntries.isEmpty,
                    accessibilityIdentifier: "home.activation.firstHour",
                    action: {
                        NotificationCenter.default.post(name: .switchToTab, object: 2)
                    }
                )

                activationActionTile(
                    title: "Learn",
                    subtitle: "What counts",
                    icon: Lucide.bookOpenText,
                    isComplete: false,
                    accessibilityIdentifier: "home.activation.learn",
                    action: {
                        showLearningCenter = true
                    }
                )

                activationActionTile(
                    title: "Report",
                    subtitle: "Check pace",
                    icon: Lucide.chartColumnIncreasing,
                    isComplete: false,
                    accessibilityIdentifier: "home.activation.report",
                    action: {
                        NotificationCenter.default.post(name: .switchToTab, object: 3)
                    }
                )
            }
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var completedActivationSteps: Int {
        (viewModel.properties.isEmpty ? 0 : 1) + (viewModel.timeEntries.isEmpty ? 0 : 1)
    }

    private func openAddPropertyFromHome() {
        if viewModel.properties.isEmpty {
            NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
        } else {
            NotificationCenter.default.post(name: .switchToTab, object: 1)
        }
    }

    private func activationActionTile(
        title: String,
        subtitle: String,
        icon: UIImage,
        isComplete: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isComplete ? colors.positiveSurface : colors.backgroundTertiary)
                        .frame(width: 40, height: 40)

                    LucideIcon(image: isComplete ? Lucide.circleCheck : icon, size: 19)
                        .foregroundStyle(isComplete ? colors.positive : colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 92)
            .padding(12)
            .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.72 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(colors.border.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityIdentifier(accessibilityIdentifier)
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
            .background(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colors.border.opacity(colorScheme == .dark ? 0.8 : 0.55), lineWidth: 1)
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
            .background(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colors.border.opacity(colorScheme == .dark ? 0.8 : 0.55), lineWidth: 1)
            )
        }
    }

    // MARK: - This Week Card
    private var thisWeekCard: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text("This Week")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text(String(format: "%.1fh", thisWeekTotal))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
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
                                    isToday ? AppColors.sage :
                                    hours > 0 ? AppColors.sageWash :
                                    colors.backgroundTertiary
                                )
                                .frame(width: 30, height: 30)

                            if hours > 0 {
                                Text(String(format: "%.0f", hours))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? AppColors.charcoal : colors.textPrimary)
                            } else {
                                Text("\u{2013}")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? AppColors.charcoal : colors.textTertiary)
                            }
                        }
                        Text(dayLabels[i])
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
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
                        NavigationLink {
                            TimeEntryDetailView(entry: entry)
                        } label: {
                            EntryListRow(
                                entry: entry,
                                propertyName: viewModel.properties.first { $0.id == entry.propertyId }?.name ?? "Unknown"
                            )
                        }
                        .buttonStyle(.plain)
                        if index < recentEntries.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(colors.border.opacity(0.28), lineWidth: 1)
                }
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

    // MARK: - Learning Shortcut
    private var learningShortcutCard: some View {
        NavigationLink {
            LearningCenterView()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                LHIconTile(
                    icon: Lucide.bookOpenText,
                    color: AppColors.primary,
                    wash: colors.primarySurface,
                    size: 46,
                    isActive: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Learn what counts")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    Text("REPS, STR rules, and audit-ready logs.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                LucideIcon(image: Lucide.chevronRight, size: 18)
                    .foregroundStyle(colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .padding(18)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open learning center. Learn what counts for rental tax tracking.")
    }

    // MARK: - Computed
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

    private var categoryIconName: String {
        entry.category.lucideIconName
    }

    private var categoryColor: Color {
        entry.category.color
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
                systemName: categoryIconName,
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
                    if entry.importSource != nil {
                        HStack(spacing: 2) {
                            LucideIcon(image: Lucide.calendar, size: 9)
                            Text("Cal")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(AppColors.sky)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(colors.skyWash)
                        .clipShape(Capsule())
                    }
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

private struct DashboardScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppViewModel())
        .environmentObject(GoalManager.shared)
}
