import SwiftUI
import UserNotifications
import MapKit
import LucideIcons

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    // 1.1: the onboarding paywall step was removed. Pro is offered only at the moment of need
    // (PaywallView(context:)), never before the user has seen any value.
    case goalSelection = 0   // Screen C
    case addProperty = 1     // Screen D
    case notifications = 2   // Screen F
    case calendar = 3        // Screen G

    var progressIndex: Int { rawValue }
    static var totalSegments: Int { allCases.count }

    static func fromLaunchArgument(_ value: String) -> OnboardingStep? {
        if let index = Int(value) {
            return OnboardingStep(rawValue: index)
        }

        switch value.lowercased() {
        case "goal", "goalselection":
            return .goalSelection
        case "property", "addproperty":
            return .addProperty
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
                    case .notifications:
                        notificationsScreen
                    case .calendar:
                        // 2.0 (WP3): confirm-first capture opt-in replaces the 1.x bulk import.
                        // Calendar and end-of-event prompts stay off unless chosen here.
                        CaptureSetupFlow(mode: .onboarding, environment: .current) { openInbox in
                            CaptureSetupHandoff.openInboxAfterOnboarding = openInbox
                            completeOnboarding()
                        }
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
                    .fill(i <= currentStep.progressIndex ? colors.action : colors.backgroundTertiary)
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
        case .notifications:
            currentStep = .addProperty
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
        Analytics.onboardingCompleted()
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
                    .foregroundStyle(colors.textSecondary)
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
                    .foregroundStyle(colors.textSecondary)
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
                .foregroundStyle(selectedPropertyType == type ? colors.actionText : colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedPropertyType == type ? AppColors.lavenderPanel.opacity(colorScheme == .dark ? 0.16 : 1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            selectedPropertyType == type ? colors.action : colors.border,
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
                        .foregroundStyle(colors.textSecondary)
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
                        selectedManagement == option ? colors.action : colors.border,
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
                            text.wrappedValue.isEmpty ? colors.border.opacity(0.35) : colors.action,
                            lineWidth: 1.5
                        )
                )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(colors.textSecondary)
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
                                    streetAddress.isEmpty ? colors.border.opacity(0.35) : colors.action,
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
                                                .foregroundStyle(colors.textSecondary)
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
                        .foregroundStyle(colors.textSecondary)

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
                            .foregroundStyle(colors.actionText)

                        Text("Don't forget to log today!")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        Text("You visited 123 Oak St earlier. Tap to log your hours.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineSpacing(2)
                    }

                    Spacer()

                    Text("now")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
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

                        Text("You're on pace for 750 hours. Keep it up!")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineSpacing(2)
                    }

                    Spacer()

                    Text("2h")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
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
                        .foregroundStyle(colors.textSecondary)
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
                .stroke(isSelected ? colors.action : colors.border, lineWidth: 2)
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(colors.action)
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
                .stroke(isSelected ? colors.action : colors.border, lineWidth: 2)
                .frame(width: 18, height: 18)

            if isSelected {
                Circle()
                    .fill(colors.action)
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
