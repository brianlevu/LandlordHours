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
        case .reps: return "Track more than 750 hours for REPS tax benefits"
        case .materialParticipation: return "Track the 100-hour material participation test"
        case .generalTracking: return "Keep organized property work records"
        case .notSure: return "Start with guided tracking. You can choose a goal later."
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

    @State private var currentStep: OnboardingStep = .goalSelection
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
        Button {
            animate(AppAnimation.quick) {
                selectedGoal = goal
            }
        } label: {
            HStack(spacing: 16) {
                // Icon badge
                JellyBadge(
                    systemName: goal.iconName,
                    color: goal.iconColor,
                    wash: goal.iconWash,
                    size: 48
                )

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    Text(goal.subtitle)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.slate)
                        .lineSpacing(2)
                }

                Spacer()

                // Radio button
                radioButton(isSelected: selectedGoal == goal)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedGoal == goal ? AppColors.lavenderPanel.opacity(colorScheme == .dark ? 0.15 : 1) : colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        selectedGoal == goal ? AppColors.primary : AppColors.snow,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen D: Add Property

    private var addPropertyScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your first\nproperty")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(2)

                Text("We'll tailor your tracking based on property type and who manages it. You can add this later from Properties.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.slate)
                    .lineSpacing(4)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 0) {
                    // Property type label
                    sectionLabel("Property Type")
                        .padding(.top, 24)

                    // Property type toggle
                    HStack(spacing: 10) {
                        propertyTypeChip("Long-Term Rental", type: .ltr)
                        propertyTypeChip("Short-Term Rental", type: .str)
                    }
                    .padding(.top, 8)

                    // Management label
                    sectionLabel("Who manages this property?")
                        .padding(.top, 20)

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
                        .padding(.vertical, 14)

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
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedPropertyType == type ? AppColors.lavenderPanel : Color.clear)
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
                        .frame(width: 36, height: 36)

                    LucideIcon(image: UIImage(lucideId: option.iconName) ?? UIImage(), size: 16)
                        .foregroundStyle(option.iconColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    Text(option.subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(AppColors.mist)
                }

                Spacer()

                // Radio
                smallRadioButton(isSelected: selectedManagement == option)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(text.wrappedValue.isEmpty ? colors.backgroundTertiary : colors.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            text.wrappedValue.isEmpty ? colors.border.opacity(0.35) : AppColors.sage,
                            lineWidth: 2
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
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(streetAddress.isEmpty ? colors.backgroundTertiary : colors.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    streetAddress.isEmpty ? colors.border.opacity(0.35) : AppColors.sage,
                                    lineWidth: 2
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
            // Pastel gradient background
            LinearGradient(
                colors: [
                    AppColors.indigoMist,
                    AppColors.reportsAccentWash,
                    AppColors.lavenderPale,
                    AppColors.skyMist,
                    AppColors.aquaMist
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Organic blur blobs
            Circle()
                .fill(AppColors.lavenderSoft.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -60, y: -280)

            Circle()
                .fill(AppColors.blueSoft.opacity(0.3))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 100, y: -80)

            Circle()
                .fill(AppColors.lavenderSoft.opacity(0.2))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: -40, y: 200)

            // Content
            VStack(spacing: 0) {
                Spacer().frame(height: 20)

                // Headline
                Text("Choose your path,\nthen start tracking")
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.bottom, 16)

                // Value props
                VStack(spacing: 10) {
                    paywallProp("AI-assisted logging with review before save")
                    paywallProp("CPA-ready PDF exports")
                    paywallProp("Unlimited properties and PDF exports")
                }
                .padding(.bottom, 24)

                // One-time purchase card
                VStack(spacing: 8) {
                    if let product = SubscriptionManager.shared.proProduct {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(product.displayPrice)
                                .font(.system(size: 42, weight: .heavy))
                                .foregroundStyle(colors.textPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("one-time")
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.textSecondary)
                                Text("lifetime access")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.sage)
                            }
                        }
                        Text("Use the App Store price shown here")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.textSecondary)
                    } else {
                        VStack(spacing: 8) {
                            LucideIcon(image: Lucide.store, size: 22)
                                .foregroundStyle(AppColors.primary)
                            Text("Pro availability check")
                                .font(AppTypography.title3)
                                .foregroundStyle(colors.textPrimary)
                            Text("Start free now. We will check the App Store before showing a Pro price.")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 28)
                .padding(.bottom, 20)

                // Social proof
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.caution)
                        }
                    }
                    Text("Built for rental owners tracking tax-year hours")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.slate)
                }
                .padding(.bottom, 16)

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
                        .background(AppColors.charcoal)
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
                        .background(Color.white.opacity(0.65))
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

    private func paywallProp(_ text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                LucideIcon(image: Lucide.check, size: 12)
                    .foregroundStyle(AppColors.primary)
            }
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    // MARK: - Screen F: Notifications

    private var notificationsScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                Text("Never miss a task!")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(2)

                Text("Smart reminders so you stay on track for qualification.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.slate)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer()

            // Notification mockup
            notificationMockup
                .padding(.horizontal, 28)

            Spacer()

            // CTA
            ctaSection(primaryLabel: "Enable Notifications", showSkip: true) {
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
            // Header
            VStack(alignment: .leading, spacing: 10) {
                Text("Import your calendar\nfor a quick start")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(2)

                Text("We'll auto-detect property appointments and pre-fill your hours.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.slate)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer()

            // Calendar mockup
            calendarMockup
                .padding(.horizontal, 28)

            Spacer()

            // CTA
            ctaSection(primaryLabel: "Import Calendar", showSkip: false) {
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
                .background(AppColors.charcoal)
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
