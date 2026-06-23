import SwiftUI
import UserNotifications
import EventKit
import MapKit
import LucideIcons

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    case goalSelection = 0   // Screen C
    case addProperty = 1     // Screen D
    case paywall = 2         // Screen E
    case notifications = 3   // Screen F
    case calendar = 4        // Screen G

    var progressIndex: Int {
        switch self {
        case .goalSelection: return 0
        case .addProperty: return 1
        case .paywall: return 2
        case .notifications: return 3
        case .calendar: return 4
        }
    }
    static var totalSegments: Int { 5 }

    static func fromLaunchArgument(_ value: String) -> OnboardingStep? {
        if let index = Int(value) {
            return OnboardingStep(rawValue: index)
        }

        switch value.lowercased() {
        case "goal", "goalselection":
            return .goalSelection
        case "property", "addproperty":
            return .addProperty
        case "paywall", "pro":
            return .paywall
        case "notifications", "notification":
            return .notifications
        case "calendar":
            return .calendar
        default:
            return nil
        }
    }
}

// MARK: - Goal Option for Screen C

enum OnboardingGoal: String, CaseIterable, Identifiable {
    case reps = "reps"
    case materialParticipation = "materialParticipation"
    case generalTracking = "generalTracking"
    case notSure = "notSure"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reps: return "Real Estate Professional Status"
        case .materialParticipation: return "Short-term rental participation"
        case .generalTracking: return "General Hour Tracking"
        case .notSure: return "Not sure yet"
        }
    }

    var subtitle: String {
        switch self {
        case .reps: return "For owners working toward the 750-hour REPS test."
        case .materialParticipation: return "For STR owners proving active participation."
        case .generalTracking: return "For clean property work records and exports."
        case .notSure: return "Start guided now. You can change this later."
        }
    }

    var decisionLabel: String {
        switch self {
        case .reps: return "750h + 50% rule"
        case .materialParticipation: return "100h STR test"
        case .generalTracking: return "Records first"
        case .notSure: return "Guided setup"
        }
    }

    var setupHint: String {
        switch self {
        case .reps: return "Reports emphasize pace, spouse hours, and work split."
        case .materialParticipation: return "Reports focus on STR participation evidence."
        case .generalTracking: return "Logging stays flexible without qualification pressure."
        case .notSure: return "We'll keep the basics on and explain goals as you go."
        }
    }

    var iconName: String {
        switch self {
        case .reps: return "target"
        case .materialParticipation: return "clock"
        case .generalTracking: return "medal"
        case .notSure: return "info"
        }
    }

    var iconColor: Color {
        switch self {
        case .reps: return AppColors.primary
        case .materialParticipation: return AppColors.coral
        case .generalTracking: return AppColors.sage
        case .notSure: return AppColors.honey
        }
    }

    var iconWash: Color {
        switch self {
        case .reps: return AppColors.primarySurface
        case .materialParticipation: return AppColors.coralWash
        case .generalTracking: return AppColors.sageWash
        case .notSure: return AppColors.honeyWash
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .reps: return AppColors.sage
        case .materialParticipation: return AppColors.honey
        case .generalTracking: return AppColors.sky
        case .notSure: return AppColors.rose
        }
    }

    /// Map onboarding goal to the existing HourGoalType for persistence
    var hourGoalType: HourGoalType {
        switch self {
        case .reps: return .reps
        case .materialParticipation: return .str
        case .generalTracking: return .both
        case .notSure: return .both
        }
    }
}

private struct GoalDecisionVisual: View {
    let goal: OnboardingGoal
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            goal.iconColor.opacity(colorScheme == .dark ? 0.34 : 0.18),
                            goal.secondaryAccent.opacity(colorScheme == .dark ? 0.20 : 0.12),
                            colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.30 : 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.70), lineWidth: 1)

            visualContent
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Circle()
                    .fill(colors.action)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(colors.backgroundSecondary, lineWidth: 2))
                    .offset(x: 4, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .lhMotion(AppAnimation.smooth, value: isSelected)
    }

    @ViewBuilder
    private var visualContent: some View {
        switch goal {
        case .reps:
            repsVisual
        case .materialParticipation:
            materialParticipationVisual
        case .generalTracking:
            generalTrackingVisual
        case .notSure:
            guidedVisual
        }
    }

    private var repsVisual: some View {
        ZStack {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: 21))
                        path.addLine(to: CGPoint(x: 24, y: 8))
                        path.addLine(to: CGPoint(x: 40, y: 21))
                        path.addLine(to: CGPoint(x: 40, y: 43))
                        path.addLine(to: CGPoint(x: 8, y: 43))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [goal.iconColor.opacity(0.95), goal.secondaryAccent.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.84 : 0.92))
                        .frame(width: 34, height: 18)
                        .overlay {
                            HStack(spacing: 2) {
                                Text("750")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                Circle()
                                    .fill(goal.secondaryAccent)
                                    .frame(width: 5, height: 5)
                            }
                            .foregroundStyle(colors.textPrimary)
                        }
                        .offset(y: -4)
                }

                Capsule()
                    .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.52 : 0.78))
                    .frame(width: 44, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(goal.secondaryAccent)
                            .frame(width: 26, height: 5)
                    }
            }
        }
    }

    private var materialParticipationVisual: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.62 : 0.88))
                .frame(width: 48, height: 48)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(goal.iconColor.opacity(0.86))
                        .frame(height: 13)
                        .overlay {
                            Text("STR")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppColors.onAction)
                        }
                }
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach([0.78, 0.56, 0.36], id: \.self) { width in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(goal.secondaryAccent)
                                    .frame(width: 5, height: 5)
                                Capsule()
                                    .fill(goal.iconColor.opacity(width > 0.5 ? 0.60 : 0.28))
                                    .frame(width: 24 * width, height: 5)
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.top, 14)
                }

            Circle()
                .fill(goal.secondaryAccent)
                .frame(width: 24, height: 24)
                .overlay {
                    Text("100")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }
                .shadow(color: goal.secondaryAccent.opacity(0.20), radius: 6, y: 3)
        }
    }

    private var generalTrackingVisual: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.36 : 0.68))
                .frame(width: 38, height: 44)
                .offset(x: -6, y: -4)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.78 : 0.94))
                .frame(width: 42, height: 48)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Capsule().fill(goal.iconColor).frame(width: 16, height: 4)
                            Circle().fill(goal.secondaryAccent).frame(width: 4, height: 4)
                        }
                        Capsule().fill(colors.border).frame(width: 25, height: 4)
                        Capsule().fill(colors.border).frame(width: 20, height: 4)
                        Capsule().fill(colors.border.opacity(0.58)).frame(width: 28, height: 4)
                    }
                    .padding(8)
                }

            Circle()
                .fill(goal.secondaryAccent)
                .frame(width: 23, height: 23)
                .overlay {
                    LucideIcon(image: Lucide.check, size: 12)
                        .foregroundStyle(AppColors.onAction)
                }
                .shadow(color: goal.secondaryAccent.opacity(0.24), radius: 7, y: 3)
        }
    }

    private var guidedVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.42 : 0.70))
                .frame(width: 50, height: 42)

            Path { path in
                path.move(to: CGPoint(x: 11, y: 35))
                path.addCurve(to: CGPoint(x: 25, y: 22), control1: CGPoint(x: 14, y: 28), control2: CGPoint(x: 20, y: 28))
                path.addCurve(to: CGPoint(x: 40, y: 11), control1: CGPoint(x: 30, y: 16), control2: CGPoint(x: 35, y: 16))
            }
            .stroke(goal.iconColor.opacity(0.76), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            ForEach([
                CGPoint(x: 11, y: 35),
                CGPoint(x: 25, y: 22),
                CGPoint(x: 40, y: 11)
            ], id: \.x) { point in
                ZStack {
                    Circle()
                        .fill(colors.backgroundSecondary)
                        .frame(width: 15, height: 15)
                    Circle()
                        .fill(goal.secondaryAccent)
                        .frame(width: 7, height: 7)
                }
                .position(point)
            }
        }
        .frame(width: 58, height: 52)
    }
}

// MARK: - Management Option for Screen D

enum ManagementOption: String, CaseIterable, Identifiable {
    case justMe = "justMe"
    case meAndSpouse = "meAndSpouse"
    case propertyManager = "propertyManager"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .justMe: return "Just me"
        case .meAndSpouse: return "Me & my spouse"
        case .propertyManager: return "Property manager"
        }
    }

    var subtitle: String {
        switch self {
        case .justMe: return "I self-manage this property"
        case .meAndSpouse: return "We both manage and log hours"
        case .propertyManager: return "A third party handles day-to-day"
        }
    }

    var iconName: String {
        switch self {
        case .justMe: return "user"
        case .meAndSpouse: return "users"
        case .propertyManager: return "building-2"
        }
    }

    var iconColor: Color {
        switch self {
        case .justMe: return AppColors.primary
        case .meAndSpouse: return AppColors.coral
        case .propertyManager: return AppColors.honey
        }
    }

    var iconWash: Color {
        switch self {
        case .justMe: return AppColors.primarySurface
        case .meAndSpouse: return AppColors.coralWash
        case .propertyManager: return AppColors.honeyWash
        }
    }
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var currentStep: OnboardingStep = Self.initialStepFromLaunchArguments()
    @State private var appeared = false

    // Screen C state
    @State private var selectedGoal: OnboardingGoal = .reps

    // Screen D state
    @State private var selectedPropertyType: PropertyType = .ltr
    @State private var selectedManagement: ManagementOption = .justMe
    @State private var propertyName = ""
    @State private var streetAddress = ""
    @State private var addressResults: [MKMapItem] = []
    @State private var isSearchingAddress = false
    @FocusState private var isAddressFocused: Bool

    private static func initialStepFromLaunchArguments() -> OnboardingStep {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHOnboardingStep"),
              args.indices.contains(index + 1),
              let step = OnboardingStep.fromLaunchArgument(args[index + 1]) else {
            return .goalSelection
        }
        return step
    }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar + progress
                navigationBar
                progressSegments
                    .padding(.top, 4)

                // Screen content
                Group {
                    switch currentStep {
                    case .goalSelection:
                        goalSelectionScreen
                    case .addProperty:
                        addPropertyScreen
                    case .paywall:
                        paywallScreen
                    case .notifications:
                        notificationsScreen
                    case .calendar:
                        calendarScreen
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            viewModel.suppressCelebrations = true
            animate(.easeOut(duration: 0.5).delay(0.15)) {
                appeared = true
            }
        }
        .onDisappear {
            viewModel.suppressCelebrations = false
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep != .goalSelection {
                Button {
                    animate(AppAnimation.smooth) {
                        goBack()
                    }
                } label: {
                    LucideIcon(image: Lucide.chevronLeft, size: 18)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.top, 4)
    }

    // MARK: - Progress Segments

    private var progressSegments: some View {
        HStack(spacing: 4) {
            ForEach(0..<OnboardingStep.totalSegments, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep.progressIndex ? AppColors.primary : AppColors.snow)
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    .lhMotion(AppAnimation.standard, value: currentStep)
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Navigation Helpers

    private func advance() {
        animate(AppAnimation.smooth) {
            switch currentStep {
            case .goalSelection:
                // Save goal selection
                goalManager.setGlobalGoal(selectedGoal.hourGoalType)
                currentStep = .addProperty
            case .addProperty:
                // Save property if user filled it in
                savePropertyIfNeeded()
                currentStep = .paywall
            case .paywall:
                currentStep = .notifications
            case .notifications:
                currentStep = .calendar
            case .calendar:
                completeOnboarding()
            }
        }
    }

    private func goBack() {
        switch currentStep {
        case .goalSelection:
            break
        case .addProperty:
            currentStep = .goalSelection
        case .paywall:
            currentStep = .addProperty
        case .notifications:
            currentStep = .paywall
        case .calendar:
            currentStep = .notifications
        }
    }

    private func skip() {
        advance()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
        showOnboarding = false
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    private func savePropertyIfNeeded() {
        let trimmedName = propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = streetAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else { return }
        viewModel.addProperty(
            name: trimmedName,
            address: trimmedAddress,
            type: selectedPropertyType
        )
    }

    // MARK: - Screen C: Goal Selection

    private var goalSelectionScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                Text("What's your\nmain goal?")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(2)

                Text("We'll customize your experience based on what you're tracking toward.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.slate)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            // Goal cards
            VStack(spacing: 12) {
                ForEach(OnboardingGoal.allCases) { goal in
                    goalCard(goal)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Spacer()

            // CTA
            ctaSection(
                primaryLabel: "Continue",
                primaryIdentifier: "onboarding.goalPrimaryCTA",
                showSkip: false
            ) {
                advance()
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .lhMotion(.easeOut(duration: 0.45).delay(0.1), value: appeared)
    }

    private func goalCard(_ goal: OnboardingGoal) -> some View {
        let isSelected = selectedGoal == goal

        return Button {
            animate(AppAnimation.quick) {
                selectedGoal = goal
            }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                GoalDecisionVisual(goal: goal, isSelected: isSelected)
                    .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(goal.decisionLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? colors.action : colors.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(isSelected ? colors.actionSurface : colors.backgroundTertiary)
                            )

                        Spacer(minLength: 8)

                        radioButton(isSelected: isSelected)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(goal.subtitle)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(colors.textSecondary)
                            .lineSpacing(2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isSelected {
                        Text(goal.setupHint)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .accessibilityIdentifier("onboarding.goalSetupHint")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                    .fill(isSelected ? colors.actionSurface.opacity(colorScheme == .dark ? 0.32 : 0.78) : colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                    .stroke(
                        isSelected ? colors.action : colors.border.opacity(colorScheme == .dark ? 0.8 : 0.55),
                        lineWidth: 2
                    )
            )
            .shadow(color: isSelected ? colors.action.opacity(colorScheme == .dark ? 0.18 : 0.16) : .clear, radius: 12, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.title). \(goal.decisionLabel). \(goal.subtitle)")
    }

    // MARK: - Screen D: Add Property

    private var addPropertyScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your first\nproperty")
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(0)

                Text("We'll tailor your tracking based on property type and who manages it. You can add this later from Properties.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColors.slate)
                    .lineSpacing(3)
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 0) {
                    // Property type label
                    sectionLabel("Property Type")
                        .padding(.top, 18)

                    // Property type toggle
                    HStack(spacing: 10) {
                        propertyTypeChip("Long-Term Rental", type: .ltr)
                        propertyTypeChip("Short-Term Rental", type: .str)
                    }
                    .padding(.top, 8)

                    // Management label
                    sectionLabel("Who manages this property?")
                        .padding(.top, 16)

                    // Management cards
                    VStack(spacing: 8) {
                        ForEach(ManagementOption.allCases) { option in
                            managementCard(option)
                        }
                    }
                    .padding(.top, 8)

                    // Divider
                    Rectangle()
                        .fill(AppColors.snow)
                        .frame(height: 1)
                        .padding(.vertical, 10)

                    // Property Name
                    formField(
                        label: "Property Name",
                        placeholder: "e.g. Oak Street Duplex",
                        text: $propertyName,
                        accessibilityIdentifier: "onboarding.propertyName"
                    )

                    // Street Address with autocomplete
                    addressAutocompleteField
                        .padding(.top, 14)
                }
                .padding(.horizontal, 28)

                // CTA
                ctaSection(
                    primaryLabel: propertySetupPrimaryLabel,
                    primaryIdentifier: "onboarding.propertyPrimaryCTA",
                    showSkip: hasPartialPropertySetup
                ) {
                    advance()
                }
                .padding(.top, 24)
            }
        }
    }

    private var hasCompletePropertySetup: Bool {
        !propertyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !streetAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasPartialPropertySetup: Bool {
        !propertyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !streetAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var propertySetupPrimaryLabel: String {
        hasCompletePropertySetup ? "Save property" : "Continue without property"
    }

    private func propertyTypeChip(_ label: String, type: PropertyType) -> some View {
        Button {
            animate(AppAnimation.quick) {
                selectedPropertyType = type
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedPropertyType == type ? AppColors.primary : AppColors.slate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedPropertyType == type ? AppColors.lavenderPanel.opacity(colorScheme == .dark ? 0.16 : 1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            selectedPropertyType == type ? AppColors.primary : AppColors.snow,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func managementCard(_ option: ManagementOption) -> some View {
        Button {
            animate(AppAnimation.quick) {
                selectedManagement = option
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(option.iconWash)
                        .frame(width: 32, height: 32)

                    LucideIcon(image: UIImage(lucideId: option.iconName) ?? UIImage(), size: 15)
                        .foregroundStyle(option.iconColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    Text(option.subtitle)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }

                Spacer()

                // Radio
                smallRadioButton(isSelected: selectedManagement == option)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selectedManagement == option ? AppColors.lavenderPanel.opacity(colorScheme == .dark ? 0.15 : 1) : colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        selectedManagement == option ? AppColors.primary : AppColors.snow,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func formField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textSecondary)

            TextField(placeholder, text: text)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .accessibilityIdentifier(accessibilityIdentifier ?? placeholder)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(text.wrappedValue.isEmpty ? colors.backgroundTertiary : colors.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            text.wrappedValue.isEmpty ? colors.border.opacity(0.35) : AppColors.sage,
                            lineWidth: 1.5
                        )
                )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.slate)
    }

    // MARK: - Address Autocomplete

    private var addressAutocompleteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Street address")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textSecondary)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    TextField("123 Main Street", text: $streetAddress)
                        .focused($isAddressFocused)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityIdentifier("onboarding.streetAddress")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(streetAddress.isEmpty ? colors.backgroundTertiary : colors.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    streetAddress.isEmpty ? colors.border.opacity(0.35) : AppColors.sage,
                                    lineWidth: 1.5
                                )
                        )
                        .onChange(of: streetAddress) { _, newValue in
                            if newValue.count > 2 && isAddressFocused {
                                searchAddress(query: newValue)
                            } else {
                                addressResults = []
                            }
                        }

                    // Autocomplete results dropdown
                    if !addressResults.isEmpty && isAddressFocused {
                        VStack(spacing: 0) {
                            ForEach(addressResults.prefix(4), id: \.self) { item in
                                Button {
                                    selectAddress(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(colors.textPrimary)
                                        if let addr = item.placemark.title {
                                            Text(addr)
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundStyle(AppColors.mist)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                }
                                .buttonStyle(.plain)

                                if item != addressResults.prefix(4).last {
                                    Rectangle()
                                        .fill(AppColors.snow)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colors.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colors.border.opacity(0.35), lineWidth: 1)
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func searchAddress(query: String) {
        isSearchingAddress = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            isSearchingAddress = false
            if let response = response {
                addressResults = response.mapItems
            }
        }
    }

    private func selectAddress(_ item: MKMapItem) {
        let placemark = item.placemark
        var parts: [String] = []

        if let streetNumber = placemark.subThoroughfare,
           let street = placemark.thoroughfare {
            parts.append("\(streetNumber) \(street)")
        } else if let street = placemark.thoroughfare {
            parts.append(street)
        }
        if let city = placemark.locality {
            parts.append(city)
        }
        if let state = placemark.administrativeArea {
            if let zip = placemark.postalCode {
                parts.append("\(state) \(zip)")
            } else {
                parts.append(state)
            }
        }

        streetAddress = parts.joined(separator: ", ")
        addressResults = []
        isAddressFocused = false
    }

    // MARK: - Screen E: Paywall

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    private var paywallScreen: some View {
        ZStack {
            onboardingSoftBackground(accent: AppColors.primary)

            // Content
            VStack(spacing: 0) {
                onboardingHeader(
                    title: "Upgrade when your\nrecords matter",
                    subtitle: "Start free today. Pro is for export-ready reporting and growing rental portfolios.",
                    centered: true
                )
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        onboardingMiniBadge(icon: Lucide.badgeCheck, color: AppColors.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LandlordHours Pro")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                            Text("One purchase for export-ready records.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                        }
                    }

                    VStack(spacing: 10) {
                        paywallBenefitRow(
                            icon: Lucide.fileText,
                            title: "Export audit-ready PDFs",
                            subtitle: "Package hours by property, category, and year.",
                            color: AppColors.primary
                        )
                        paywallBenefitRow(
                            icon: Lucide.building2,
                            title: "Track unlimited properties",
                            subtitle: "Keep each rental's evidence clean and separate.",
                            color: AppColors.sky
                        )
                        paywallBenefitRow(
                            icon: Lucide.sparkles,
                            title: "Faster review before save",
                            subtitle: "Use assisted logging while keeping final control.",
                            color: AppColors.sage
                        )
                    }

                    Divider()
                        .overlay(colors.border.opacity(0.4))

                    if let product = SubscriptionManager.shared.proProduct {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayPrice)
                                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)
                                Text("One-time lifetime access")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppColors.sage)
                            }
                            Spacer()
                            Text("No subscription")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppColors.primarySurface)
                                .clipShape(Capsule())
                        }
                        Text("Final App Store pricing is shown before purchase.")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textSecondary)
                    } else {
                        HStack(spacing: 12) {
                            onboardingMiniBadge(icon: Lucide.store, color: AppColors.sky)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pro availability check")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(colors.textPrimary)
                                Text("You can continue free while the App Store price loads.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.textSecondary)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(onboardingCardFill)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.large)
                        .stroke(colors.border.opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.top, 22)

                Spacer()

                // CTA
                VStack(spacing: 8) {
                    Button {
                        Task {
                            await subscriptionManager.purchasePro()
                            if subscriptionManager.hasPurchased { advance() }
                        }
                    } label: {
                        Group {
                            if subscriptionManager.isLoading {
                                ProgressView()
                                    .tint(AppColors.onAction)
                            } else if let product = subscriptionManager.proProduct {
                                Text("Buy lifetime Pro \u{00B7} \(product.displayPrice)")
                            } else {
                                Text(subscriptionManager.purchaseError == nil ? "Check Pro availability" : "Try Pro purchase again")
                            }
                        }
                        .font(AppTypography.buttonLarge)
                        .foregroundStyle(AppColors.onAction)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(colors.action)
                        .overlay(
                            Capsule()
                                .stroke(Color.clear, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }

                    if let error = subscriptionManager.purchaseError {
                        VStack(spacing: 10) {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.coral)
                                .multilineTextAlignment(.center)

                            #if DEBUG
                            if AdminAccess.isCurrentUserAdmin {
                                Button {
                                    subscriptionManager.unlockPro()
                                    advance()
                                } label: {
                                    Text("Use local Pro for testing")
                                        .font(AppTypography.buttonSmall)
                                        .foregroundStyle(AppColors.primary)
                                }
                            }
                            #endif
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(onboardingCardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text(subscriptionManager.proProduct == nil ? "You can keep using the free plan while Pro is unavailable." : "One-time purchase. No subscription. No automatic renewal.")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        animate(AppAnimation.smooth) { skip() }
                    } label: {
                        Text("Continue free")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColors.mist)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
    }

    private func paywallBenefitRow(icon: UIImage, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            onboardingMiniBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingCardFill: some ShapeStyle {
        colorScheme == .dark ? colors.backgroundSecondary : Color.white.opacity(0.82)
    }

    private func onboardingSoftBackground(accent: Color) -> some View {
        LinearGradient(
            colors: colorScheme == .dark
            ? [
                colors.background,
                colors.backgroundSecondary,
                colors.background
            ]
            : [
                AppColors.lavenderPale,
                AppColors.skyMist,
                AppColors.aquaMist
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 80, y: -90)
        }
        .ignoresSafeArea()
    }

    private func onboardingHeader(title: String, subtitle: String, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 27, weight: .regular, design: .serif))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.horizontal, 28)
    }

    private func onboardingMiniBadge(icon: UIImage, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(colorScheme == .dark ? 0.22 : 0.14))
                .frame(width: 36, height: 36)
            LucideIcon(image: icon, size: 17)
                .foregroundStyle(color)
        }
    }

    private func permissionBenefitCard(icon: UIImage, title: String, subtitle: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            onboardingMiniBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.55 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func calendarDetectionRow(title: String, detail: String, hours: String, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            Text(hours)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColors.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.55 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func onboardingFlowStep(number: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.onAction)
                .frame(width: 26, height: 26)
                .background(colors.action)
                .clipShape(Circle())
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingFlowConnector: some View {
        Rectangle()
            .fill(colors.border.opacity(0.45))
            .frame(width: 12, height: 1)
            .padding(.bottom, 34)
    }

    // MARK: - Screen F: Notifications

    private var notificationsScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            onboardingHeader(
                title: "Get reminded when\nhours are easy to forget",
                subtitle: "Use reminders for the moments that become hard to reconstruct later.",
                centered: false
            )
            .padding(.top, 20)

            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    onboardingMiniBadge(icon: Lucide.bellRing, color: AppColors.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminder plan")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text("Quiet nudges tied to evidence, not noise.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                    }
                }

                permissionBenefitCard(
                    icon: Lucide.mapPin,
                    title: "After property visits",
                    subtitle: "A same-day prompt helps you log while the details are still fresh.",
                    color: AppColors.primary
                )
                permissionBenefitCard(
                    icon: Lucide.calendarClock,
                    title: "Before tax-year drift",
                    subtitle: "Weekly summaries show whether your pace needs attention.",
                    color: AppColors.honey
                )
                permissionBenefitCard(
                    icon: Lucide.shieldCheck,
                    title: "Only useful reminders",
                    subtitle: "You stay in control and can change notification settings anytime.",
                    color: AppColors.sage
                )
            }
            .padding(18)
            .background(onboardingCardFill)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .stroke(colors.border.opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 1)
            )
            .padding(.horizontal, 28)

            Spacer()

            // CTA
            ctaSection(primaryLabel: "Allow reminders", showSkip: true) {
                requestNotifications()
            }
        }
    }

    private var notificationMockup: some View {
        ZStack {
            // Ambient glows
            Circle()
                .fill(AppColors.primary.opacity(0.08))
                .frame(width: 120, height: 120)
                .blur(radius: 30)
                .offset(x: 80, y: -60)

            Circle()
                .fill(AppColors.coral.opacity(0.06))
                .frame(width: 80, height: 80)
                .blur(radius: 20)
                .offset(x: -60, y: 60)

            // Phone mockup
            VStack(spacing: 0) {
                // Lock screen header
                VStack(spacing: 2) {
                    Text("Monday, February 24")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.slate)

                    Text("9:41")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }
                .padding(.top, 40)

                // Notification card 1
                HStack(alignment: .top, spacing: 12) {
                    WaveHouseIcon(size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("LandlordHours")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.primary)

                        Text("Don't forget to log today!")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        Text("You visited 123 Oak St earlier. Tap to log your hours.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(AppColors.slate)
                            .lineSpacing(2)
                    }

                    Spacer()

                    Text("now")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.85))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                }
                .padding(.horizontal, 14)
                .padding(.top, 24)

                // Notification card 2
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.sage, AppColors.successDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)

                        LucideIcon(image: Lucide.circleCheck, size: 18)
                            .foregroundStyle(AppColors.onAction)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly summary")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.sage)

                        Text("Great week! 18.5h logged")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        Text("You're on track for REPS. Keep it up!")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(AppColors.slate)
                            .lineSpacing(2)
                    }

                    Spacer()

                    Text("2h")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                Spacer()
            }
            .frame(width: 240)
            .frame(maxHeight: 340)
            .background(
                LinearGradient(
                    colors: [
                        AppColors.lavenderMist,
                        AppColors.lavenderPale,
                        AppColors.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                    .stroke(Color.white.opacity(0.6), lineWidth: 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                    .strokeBorder(colors.border.opacity(0.2), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            DispatchQueue.main.async {
                advance()
            }
        }
    }

    // MARK: - Screen G: Calendar

    @State private var calendarAccessGranted = false
    @State private var showCalendarPicker = false
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarIds: Set<String> = []
    @State private var importedEventCount = 0
    @State private var isImporting = false

    private var calendarScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            onboardingHeader(
                title: "Calendar can start\nyour draft logs",
                subtitle: "Find likely property work from Calendar. You review before anything becomes part of your records.",
                centered: false
            )
            .padding(.top, 20)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    onboardingMiniBadge(icon: Lucide.calendarPlus, color: AppColors.sky)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import preview")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text("Calendar finds candidates. You decide what counts.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    calendarDetectionRow(
                        title: "Plumber at Oak St",
                        detail: "10:00 AM - 12:00 PM",
                        hours: "2h",
                        color: AppColors.coral
                    )
                    calendarDetectionRow(
                        title: "Tenant meeting",
                        detail: "2:00 PM - 3:00 PM",
                        hours: "1h",
                        color: AppColors.primary
                    )
                }

                HStack(spacing: 8) {
                    onboardingFlowStep(number: "1", title: "Scan", detail: "Find events")
                    onboardingFlowConnector
                    onboardingFlowStep(number: "2", title: "Review", detail: "Check details")
                    onboardingFlowConnector
                    onboardingFlowStep(number: "3", title: "Save", detail: "Draft entries")
                }

                HStack(spacing: 10) {
                    onboardingMiniBadge(icon: Lucide.listChecks, color: AppColors.sage)
                    Text("Calendar import never replaces your review. It only starts the draft.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.actionSurface.opacity(colorScheme == .dark ? 0.22 : 0.75))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(18)
            .background(onboardingCardFill)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .stroke(colors.border.opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 1)
            )
            .padding(.horizontal, 28)

            Spacer()

            // CTA
            ctaSection(primaryLabel: "Connect Calendar", showSkip: true) {
                requestCalendarAccess()
            }
        }
        .sheet(isPresented: $showCalendarPicker) {
            calendarPickerSheet
        }
    }

    private var calendarMockup: some View {
        ZStack {
            // Ambient glows
            Circle()
                .fill(AppColors.sage.opacity(0.08))
                .frame(width: 100, height: 100)
                .blur(radius: 25)
                .offset(x: 70, y: -50)

            Circle()
                .fill(AppColors.honey.opacity(0.06))
                .frame(width: 70, height: 70)
                .blur(radius: 18)
                .offset(x: -50, y: 50)

            VStack(spacing: 0) {
                // Calendar header
                VStack(spacing: 4) {
                    Text("February 2026")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    // Day headers
                    calendarDayHeaders

                    // Calendar grid
                    calendarGrid
                }
                .padding(.horizontal, 6)
                .padding(.top, 40)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(
                        colors: [AppColors.lavenderMist, AppColors.lavenderField],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Entries
                VStack(spacing: 6) {
                    calendarEntry(
                        title: "Plumber at Oak St",
                        time: "10:00 AM - 12:00 PM",
                        hours: "2h",
                        barColor: AppColors.coral
                    )
                    calendarEntry(
                        title: "Tenant meeting",
                        time: "2:00 PM - 3:00 PM",
                        hours: "1h",
                        barColor: AppColors.primary
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Stat row
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.primary.opacity(0.15))
                            .frame(width: 28, height: 28)
                        LucideIcon(image: Lucide.sparkles, size: 14)
                            .foregroundStyle(AppColors.primary)
                    }

                    HStack(spacing: 0) {
                        Text("3 hours")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.primary)
                        Text(" detected today")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.lavenderPanel, AppColors.primarySurface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .frame(width: 240)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                    .stroke(Color.white.opacity(0.6), lineWidth: 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                    .strokeBorder(colors.border.opacity(0.2), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var calendarDayHeaders: some View {
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.mist)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
    }

    private var calendarGrid: some View {
        // February 2026 starts on Sunday
        let daysInMonth = 28
        let hoursOnDays: Set<Int> = [2, 3, 5, 9, 10, 12, 16, 17, 19, 23]
        let todayDay = 24

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            ForEach(1...daysInMonth, id: \.self) { day in
                Text("\(day)")
                    .font(.system(size: 10, weight: day == todayDay ? .bold : .regular, design: .rounded))
                    .foregroundStyle(day == todayDay ? .white : AppColors.slate)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        Group {
                            if day == todayDay {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.primary)
                            }
                        }
                    )
                    .overlay(alignment: .bottom) {
                        if hoursOnDays.contains(day) && day != todayDay {
                            Circle()
                                .fill(AppColors.primary)
                                .frame(width: 4, height: 4)
                                .offset(y: -1)
                        }
                    }
            }
        }
    }

    private func calendarEntry(title: String, time: String, hours: String, barColor: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(time)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColors.mist)
            }

            Spacer()

            Text(hours)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.background)
        )
    }

    private func requestCalendarAccess() {
        let store = EKEventStore()

        let handlePermission: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                if granted {
                    calendarAccessGranted = true
                    let calendars = store.calendars(for: .event)
                    availableCalendars = calendars.sorted { $0.title < $1.title }
                    // Pre-select all calendars
                    selectedCalendarIds = Set(calendars.map { $0.calendarIdentifier })
                    showCalendarPicker = true
                } else {
                    // Permission denied — complete onboarding without import
                    completeOnboarding()
                }
            }
        }

        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                handlePermission(granted)
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                handlePermission(granted)
            }
        }
    }

    private var calendarPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("Select calendars to import")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                    Text("We'll scan the last 90 days for property-related events.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.slate)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)
                .padding(.bottom, 16)
                .padding(.horizontal, 24)

                if availableCalendars.isEmpty {
                    VStack(spacing: 12) {
                        LucideIcon(image: Lucide.calendarX, size: 32)
                            .foregroundStyle(AppColors.mist)
                        Text("No calendars found")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.slate)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                                calendarRow(calendar)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()

                // Import button
                VStack(spacing: 8) {
                    if isImporting {
                        ProgressView("Scanning events...")
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else if importedEventCount > 0 {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                LucideIcon(image: Lucide.circleCheck, size: 16)
                                    .foregroundStyle(AppColors.sage)
                                Text("\(importedEventCount) events imported")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.sage)
                            }

                            Button {
                                showCalendarPicker = false
                                completeOnboarding()
                            } label: {
                                Text("Continue")
                                    .font(AppTypography.buttonLarge)
                                    .foregroundStyle(AppColors.onAction)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(AppColors.charcoal)
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        Button {
                            importSelectedCalendars()
                        } label: {
                            HStack(spacing: 8) {
                                LucideIcon(image: Lucide.download, size: 16)
                                Text("Import \(selectedCalendarIds.count) calendar\(selectedCalendarIds.count == 1 ? "" : "s")")
                            }
                            .font(AppTypography.buttonLarge)
                            .foregroundStyle(AppColors.onAction)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(selectedCalendarIds.isEmpty ? AppColors.mist : AppColors.charcoal)
                            .clipShape(Capsule())
                        }
                        .disabled(selectedCalendarIds.isEmpty)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        showCalendarPicker = false
                        completeOnboarding()
                    }
                    .foregroundStyle(AppColors.mist)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let isSelected = selectedCalendarIds.contains(calendar.calendarIdentifier)
        return Button {
            animate(AppAnimation.quick) {
                if isSelected {
                    selectedCalendarIds.remove(calendar.calendarIdentifier)
                } else {
                    selectedCalendarIds.insert(calendar.calendarIdentifier)
                }
            }
        } label: {
            HStack(spacing: 14) {
                // Calendar color dot
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 14, height: 14)

                // Calendar name
                VStack(alignment: .leading, spacing: 1) {
                    Text(calendar.title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(calendar.source.title)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }

                Spacer()

                // Checkmark
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? AppColors.primary : AppColors.cloud, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppColors.primary)
                            .frame(width: 22, height: 22)
                        LucideIcon(image: Lucide.check, size: 12)
                            .foregroundStyle(AppColors.onAction)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppColors.lavenderPanel.opacity(colorScheme == .dark ? 0.15 : 1) : colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.primary : AppColors.snow, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func importSelectedCalendars() {
        guard !selectedCalendarIds.isEmpty else { return }
        isImporting = true

        let detected = CalendarImportService.shared.scanCalendars(
            selectedCalendarIds,
            properties: viewModel.properties
        )

        // During onboarding, import all detected entries directly (no review step)
        let count = viewModel.importCalendarEntries(detected)

        DispatchQueue.main.async {
            isImporting = false
            importedEventCount = count
            if count == 0 {
                showCalendarPicker = false
                completeOnboarding()
            }
        }
    }

    // MARK: - Shared Components

    private func ctaSection(
        primaryLabel: String,
        primaryIdentifier: String? = nil,
        showSkip: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            // Primary CTA
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(primaryLabel)
                        .font(AppTypography.buttonLarge)
                    LucideIcon(image: Lucide.arrowRight, size: 14)
                }
                .foregroundStyle(AppColors.onAction)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(colors.action)
                .clipShape(Capsule())
            }
            .accessibilityIdentifier(primaryIdentifier ?? "")

            // Skip button
            if showSkip {
                Button {
                    animate(AppAnimation.smooth) {
                        skip()
                    }
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 48)
    }

    private func radioButton(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppColors.primary : AppColors.cloud, lineWidth: 2)
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 22, height: 22)

                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func smallRadioButton(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppColors.primary : AppColors.cloud, lineWidth: 2)
                .frame(width: 18, height: 18)

            if isSelected {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 18, height: 18)

                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    OnboardingView(showOnboarding: .constant(true))
        .environmentObject(AppViewModel())
}
