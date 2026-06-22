import SwiftUI
import PhotosUI
import LucideIcons

// MARK: - Hour Goal Type

enum HourGoalType: String, CaseIterable, Codable {
    case reps = "REPS"
    case str = "STR (Short-Term Rental)"
    case both = "Both"

    var description: String {
        switch self {
        case .reps:
            return "750 hours - Full Real Estate Professional Status"
        case .str:
            return "100 hours - STR Material Participation"
        case .both:
            return "Track both REPS and STR goals"
        }
    }

    var hoursRequired: Double {
        switch self {
        case .reps:
            return 750
        case .str:
            return 100
        case .both:
            return 750 // Use higher as primary
        }
    }
}

// MARK: - Property Goal

struct PropertyGoal: Identifiable, Codable {
    var id: UUID
    var propertyId: UUID
    var goalType: HourGoalType
    var modifiedAt: Date

    init(id: UUID = UUID(), propertyId: UUID, goalType: HourGoalType = .both) {
        self.id = id
        self.propertyId = propertyId
        self.goalType = goalType
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        goalType = try c.decode(HourGoalType.self, forKey: .goalType)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

// MARK: - Goal Manager

class GoalManager: ObservableObject {
    static let shared = GoalManager()

    /// Called when goals change, so sync can be triggered
    var onDidChange: (() -> Void)?

    @Published var propertyGoals: [PropertyGoal] = []
    @Published var globalGoalType: HourGoalType = .reps

    private var goalsKey: String { UserScope.key("propertyGoals") }
    private var globalGoalKey: String { UserScope.key("globalGoalType") }

    private init() {
        loadGoals()
    }

    func loadGoals() {
        if let data = UserDefaults.standard.data(forKey: goalsKey),
           let goals = try? JSONDecoder().decode([PropertyGoal].self, from: data) {
            propertyGoals = goals
        } else {
            propertyGoals = []
        }

        if let raw = UserDefaults.standard.string(forKey: globalGoalKey),
           let type = HourGoalType(rawValue: raw) {
            globalGoalType = type
        } else {
            globalGoalType = .reps
        }
    }

    func saveGoals() {
        if let data = try? JSONEncoder().encode(propertyGoals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
        UserDefaults.standard.set(globalGoalType.rawValue, forKey: globalGoalKey)
        onDidChange?()
    }

    func resetForSignOut() {
        propertyGoals = []
        globalGoalType = .reps
    }

    func resetForDataReset() {
        propertyGoals = []
        globalGoalType = .reps
        let ud = UserDefaults.standard
        ud.removeObject(forKey: goalsKey)
        ud.removeObject(forKey: globalGoalKey)
        onDidChange?()
    }

    func setGoal(for propertyId: UUID, type: HourGoalType) {
        if let index = propertyGoals.firstIndex(where: { $0.propertyId == propertyId }) {
            propertyGoals[index].goalType = type
        } else {
            propertyGoals.append(PropertyGoal(propertyId: propertyId, goalType: type))
        }
        saveGoals()
    }

    func getGoal(for propertyId: UUID) -> HourGoalType {
        propertyGoals.first(where: { $0.propertyId == propertyId })?.goalType ?? globalGoalType
    }

    func setGlobalGoal(_ type: HourGoalType) {
        globalGoalType = type
        saveGoals()
    }
}

// MARK: - Filing Status

enum FilingStatus: String, CaseIterable, Codable {
    case single = "Single"
    case marriedJoint = "Married, Joint"
    case marriedSeparate = "Married, Separate"
    case headOfHousehold = "Head of Household"
    case qualifyingWidow = "Qualifying Widow(er)"
}

// MARK: - Tax Profile Manager

final class TaxProfileManager: ObservableObject {
    static let shared = TaxProfileManager()

    /// Called when any field changes, so sync can be triggered
    var onDidChange: (() -> Void)?

    private func scopedKey(_ field: String) -> String {
        UserScope.key("LandlordHours.taxProfile." + field)
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        onDidChange?()
    }

    @Published var filingStatus: FilingStatus {
        didSet { save(scopedKey("filingStatus"), filingStatus.rawValue) }
    }
    @Published var spouseTracking: Bool {
        didSet { save(scopedKey("spouseTracking"), spouseTracking) }
    }
    @Published var taxYear: Int {
        didSet { save(scopedKey("taxYear"), taxYear) }
    }
    @Published var groupingElection: Bool {
        didSet { save(scopedKey("groupingElection"), groupingElection) }
    }
    @Published var nonREWorkHours: Double {
        didSet { save(scopedKey("nonREWorkHours"), nonREWorkHours) }
    }

    private init() {
        // Set defaults first (didSet won't fire during init)
        filingStatus = .marriedJoint
        spouseTracking = true
        taxYear = Calendar.current.component(.year, from: Date())
        groupingElection = false
        nonREWorkHours = 0
        reload()
    }

    func reload() {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: scopedKey("filingStatus")),
           let status = FilingStatus(rawValue: raw) {
            filingStatus = status
        }
        if ud.object(forKey: scopedKey("spouseTracking")) != nil {
            spouseTracking = ud.bool(forKey: scopedKey("spouseTracking"))
        }
        let savedYear = ud.integer(forKey: scopedKey("taxYear"))
        if savedYear > 0 { taxYear = savedYear }
        groupingElection = ud.bool(forKey: scopedKey("groupingElection"))
        nonREWorkHours = ud.double(forKey: scopedKey("nonREWorkHours"))
    }

    func resetForSignOut() {
        filingStatus = .marriedJoint
        spouseTracking = true
        taxYear = Calendar.current.component(.year, from: Date())
        groupingElection = false
        nonREWorkHours = 0
    }

    func resetForDataReset() {
        filingStatus = .marriedJoint
        spouseTracking = true
        taxYear = Calendar.current.component(.year, from: Date())
        groupingElection = false
        nonREWorkHours = 0

        let ud = UserDefaults.standard
        for field in ["filingStatus", "spouseTracking", "taxYear", "groupingElection", "nonREWorkHours"] {
            ud.removeObject(forKey: scopedKey(field))
        }
        onDidChange?()
    }
}

// MARK: - Setting Row Component

private struct SettingRow: View {
    let icon: UIImage
    let iconColor: Color
    var iconWash: Color? = nil
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueColor: Color? = nil
    var showChevron: Bool = true
    var isDanger: Bool = false

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            LucideIcon(image: icon, size: 20)
                .foregroundStyle(isDanger ? AppColors.coral : iconColor)
                .frame(width: 38, height: 38)
                .background(iconWash ?? colors.backgroundTertiary)
                .clipShape(Circle())

            // Text content
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(isDanger ? AppColors.coral : colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textTertiary)
                }
            }

            Spacer()

            // Optional value
            if let value {
                Text(value)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(valueColor ?? colors.textTertiary)
            }

            // Chevron
            if showChevron && !isDanger {
                LucideIcon(image: Lucide.chevronRight, size: 12)
                    .foregroundStyle(AppColors.cloud)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Setting Toggle Row

private struct SettingToggleRow: View {
    let icon: UIImage
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            LucideIcon(image: icon, size: 20)
                .foregroundStyle(iconColor)
                .frame(width: 38, height: 38)
                .background(colors.backgroundTertiary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.sage)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .black, design: .rounded))
            .foregroundStyle(colors.textPrimary)
            .padding(.top, 28)
            .padding(.bottom, 8)
    }
}

// MARK: - Subscription Card

private struct SubscriptionCard: View {
    let isPro: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isPro ? AppColors.positiveSurface : AppColors.actionSurface)
                            .frame(width: 54, height: 54)
                        LucideIcon(image: isPro ? Lucide.badgeCheck : Lucide.sparkles, size: 24)
                            .foregroundStyle(isPro ? AppColors.successGreen : AppColors.action)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isPro ? "Pro is active" : "Upgrade to Pro")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text(isPro ? "Lifetime access is unlocked for this account." : "Unlock the audit-ready tools that make this app worth trusting at tax time.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    LucideIcon(image: Lucide.chevronRight, size: 14)
                        .foregroundStyle(colors.textTertiary)
                        .padding(.top, 6)
                }

                HStack(spacing: 8) {
                    planBenefit("PDF exports", icon: Lucide.fileText)
                    planBenefit("Unlimited properties", icon: Lucide.building2)
                }

                HStack {
                    Text(isPro ? "Manage Pro" : "One-time lifetime purchase")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(isPro ? AppColors.successGreen : AppColors.onAction)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isPro ? AppColors.positiveSurface : AppColors.action)
                        .clipShape(Capsule())

                    Spacer()

                    Text(isPro ? "ACTIVE" : "PRO")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(isPro ? AppColors.successGreen : AppColors.action)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isPro ? AppColors.positiveSurface : AppColors.actionSurface)
                        .clipShape(Capsule())
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [colors.backgroundSecondary, AppColors.darkPlum.opacity(0.72)]
                        : [Color.white, AppColors.lavenderPale, isPro ? AppColors.successGreenWash : AppColors.reportsAccentWash],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isPro ? AppColors.positive.opacity(0.28) : AppColors.action.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(isPro ? "Manage Pro. Lifetime access is active." : "Upgrade to Pro. One-time lifetime purchase.")
    }

    private func planBenefit(_ text: String, icon: UIImage) -> some View {
        HStack(spacing: 6) {
            LucideIcon(image: icon, size: 13)
                .foregroundStyle(isPro ? AppColors.successGreen : AppColors.action)
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.5 : 0.72))
        .clipShape(Capsule())
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(colors.border.opacity(colorScheme == .dark ? 0.42 : 0.28), lineWidth: 1)
            }
        }
    }
}

// MARK: - Feature List

private struct FeatureListView: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            FeatureItem(icon: Lucide.lock, text: "PDF Export Reports", badge: "PRO", isLocked: true)
            FeatureItem(icon: Lucide.lock, text: "Multi-Year Tracking", badge: "PRO", isLocked: true)
            FeatureItem(icon: Lucide.lock, text: "Unlimited Properties", badge: "PRO", isLocked: true)

            Divider()
                .background(AppColors.snow)
                .padding(.vertical, 6)

            FeatureItem(icon: Lucide.check, text: "Basic hour tracking", badge: "FREE", isLocked: false)
            FeatureItem(icon: Lucide.check, text: "1 property", badge: "FREE", isLocked: false)
            FeatureItem(icon: Lucide.check, text: "Learning center", badge: "FREE", isLocked: false)
        }
        .padding(.vertical, 8)
    }
}

private struct FeatureItem: View {
    let icon: UIImage
    let text: String
    let badge: String
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            LucideIcon(image: icon, size: 14)
                .foregroundStyle(isLocked ? AppColors.mist : AppColors.sage)
                .frame(width: 18, height: 18)

            Text(text)
                .font(AppTypography.bodySmall)
                .foregroundStyle(isLocked ? AppColors.slate : AppColors.ink)

            Spacer()

            Text(badge)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isLocked ? AppColors.primary : AppColors.sage)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(isLocked ? AppColors.primarySurface : AppColors.sageWash)
                .clipShape(Capsule())
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Profile Row

private struct ProfileRow: View {
    let name: String
    let email: String?
    let imageData: Data?
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(AppColors.sage)
                            .frame(width: 48, height: 48)

                        // Show initial or person icon
                        if !name.isEmpty && name != "Your Name" {
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.charcoal)
                        } else {
                            LucideIcon(image: Lucide.user, size: 20)
                                .foregroundStyle(AppColors.charcoal)
                        }
                    }
                }

                // Name and email
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    if let email, !email.isEmpty {
                        Text(email)
                            .font(AppTypography.caption)
                            .foregroundStyle(colors.textTertiary)
                    }
                }

                Spacer()

                LucideIcon(image: Lucide.chevronRight, size: 12)
                    .foregroundStyle(AppColors.cloud)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var appleSignIn = AppleSignInManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showingResetAlert = false
    @State private var showingProfileEdit = false
    @State private var showingPaywall = false
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Data?
    @State private var showingIconPicker = false
    @State private var restoreStatusMessage: String?
    @State private var showingDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showDeveloperTools = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .minimumScaleFactor(0.82)
                        Text("Account, tax profile, exports, and support.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SubscriptionCard(
                        isPro: subscriptionManager.isPro,
                        onTap: { showingPaywall = true }
                    )

                    if !subscriptionManager.isPro {
                        SettingsGroup(title: "What Pro unlocks", subtitle: "The features that matter when records need to leave the app.") {
                            FeatureListView()
                        }
                    }

                    SettingsGroup(title: "Account", subtitle: "Profile, purchase status, and identity.") {
                        ProfileRow(
                            name: appleSignIn.fullName ?? (viewModel.userName.isEmpty ? "Your Name" : viewModel.userName),
                            email: appleSignIn.email,
                            imageData: profileImage ?? appleSignIn.profileImageData,
                            onTap: {
                                userName = appleSignIn.fullName ?? viewModel.userName
                                userEmail = appleSignIn.email ?? ""
                                profileImage = appleSignIn.profileImageData
                                showingProfileEdit = true
                            }
                        )

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            Task {
                                await subscriptionManager.restorePurchases()
                                restoreStatusMessage = subscriptionManager.hasPurchased
                                    ? "Your Pro purchase has been restored."
                                    : (subscriptionManager.purchaseError ?? "No previous purchase was found.")
                            }
                        } label: {
                            SettingRow(
                                icon: Lucide.badgeCheck,
                                iconColor: AppColors.action,
                                iconWash: colors.actionSurface,
                                title: subscriptionManager.isLoading ? "Restoring Purchase..." : "Restore Purchase",
                                subtitle: "Recover a previous Pro purchase"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(subscriptionManager.isLoading)
                    }

                    SettingsGroup(title: "Tax Setup", subtitle: "The assumptions that drive qualification math.") {
                        NavigationLink {
                            TaxProfileView()
                        } label: {
                            SettingRow(
                                icon: Lucide.fileText,
                                iconColor: AppColors.action,
                                iconWash: colors.actionSurface,
                                title: "Tax Profile",
                                subtitle: "Filing, goals, spouse tracking, and 50% rule inputs"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.taxProfile")

                        Divider().background(colors.border.opacity(0.35))

                        NavigationLink {
                            LearningCenterView()
                        } label: {
                            SettingRow(
                                icon: Lucide.bookOpen,
                                iconColor: AppColors.informational,
                                iconWash: colors.informationalSurface,
                                title: "Learning Center",
                                subtitle: "REPS, STR rules, and audit-ready logs"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.learningCenter")
                    }

                    SettingsGroup(title: "Records", subtitle: "Import, sync, and export your tracking evidence.") {
                        if subscriptionManager.isPro && !subscriptionManager.isTrialActive {
                            NavigationLink {
                                ExportPDFView(year: Calendar.current.component(.year, from: Date()))
                            } label: {
                                SettingRow(
                                    icon: Lucide.download,
                                    iconColor: AppColors.action,
                                    iconWash: colors.actionSurface,
                                    title: "Export Reports",
                                    subtitle: "PDF package for your accountant"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.exportReports")
                        } else {
                            Button {
                                showingPaywall = true
                            } label: {
                                SettingRow(
                                    icon: Lucide.download,
                                    iconColor: AppColors.action,
                                    iconWash: colors.actionSurface,
                                    title: "Export Reports",
                                    subtitle: "Unlock accountant-ready PDF exports with Pro",
                                    value: "PRO",
                                    valueColor: AppColors.action
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            viewModel.syncNow()
                        } label: {
                            SettingRow(
                                icon: Lucide.cloudUpload,
                                iconColor: AppColors.informational,
                                iconWash: colors.informationalSurface,
                                title: "Sync Now",
                                subtitle: syncSubtitle ?? "Back up latest records to iCloud"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().background(colors.border.opacity(0.35))

                        NavigationLink {
                            CalendarImportView()
                                .environmentObject(viewModel)
                        } label: {
                            SettingRow(
                                icon: Lucide.calendar,
                                iconColor: AppColors.informational,
                                iconWash: colors.informationalSurface,
                                title: "Import from Calendar",
                                subtitle: "Detect property events and draft time entries"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.importCalendar")
                    }

                    SettingsGroup(title: "App Preferences", subtitle: "Personalize reminders, icon, and setup guidance.") {
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            SettingRow(
                                icon: Lucide.bell,
                                iconColor: AppColors.caution,
                                iconWash: colors.cautionSurface,
                                title: "Notifications",
                                subtitle: "Manage reminder permissions in iOS Settings"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            showingIconPicker = true
                        } label: {
                            SettingRow(
                                icon: Lucide.layoutGrid,
                                iconColor: AppColors.action,
                                iconWash: colors.actionSurface,
                                title: "App Icon",
                                value: AppIconOption.current.displayName
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.appIcon")

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            NotificationCenter.default.post(name: .restartGuidedOnboarding, object: nil)
                        } label: {
                            SettingRow(
                                icon: Lucide.route,
                                iconColor: AppColors.action,
                                iconWash: colors.actionSurface,
                                title: "Restart Guided Setup",
                                subtitle: "Show the first property and first activity walkthrough again"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.restartGuidedSetup")

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            NotificationCenter.default.post(name: .skipGuidedOnboarding, object: nil)
                        } label: {
                            SettingRow(
                                icon: Lucide.circleSlash,
                                iconColor: AppColors.textSecondary,
                                title: "Skip Guided Setup",
                                subtitle: "Hide first-run prompts on this account"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.skipGuidedSetup")
                    }

                    SettingsGroup(title: "Support & Legal", subtitle: "Help, policies, and account exits.") {
                        NavigationLink {
                            ContactSupportView()
                        } label: {
                            SettingRow(
                                icon: Lucide.mail,
                                iconColor: AppColors.informational,
                                iconWash: colors.informationalSurface,
                                title: "Contact Support",
                                subtitle: "Questions about tracking, exports, or setup"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.contactSupport")

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            if let url = URL(string: "https://www.openclaw.com/landlord-hours/terms") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            SettingRow(
                                icon: Lucide.scrollText,
                                iconColor: AppColors.textSecondary,
                                title: "Terms & Privacy"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            viewModel.signOut()
                            AppleSignInManager.shared.signOut()
                        } label: {
                            SettingRow(
                                icon: Lucide.logOut,
                                iconColor: AppColors.coral,
                                iconWash: colors.destructiveSurface,
                                title: "Sign Out",
                                showChevron: false,
                                isDanger: true
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().background(colors.border.opacity(0.35))

                        Button {
                            showingDeleteAccountAlert = true
                        } label: {
                            SettingRow(
                                icon: Lucide.trash2,
                                iconColor: AppColors.coral,
                                iconWash: colors.destructiveSurface,
                                title: isDeletingAccount ? "Deleting Account..." : "Delete Account and Data",
                                subtitle: "Permanently remove this account and records",
                                showChevron: false,
                                isDanger: true
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingAccount)
                    }

                    #if DEBUG
                    if AdminAccess.isCurrentUserAdmin {
                        developerToolsSection
                    }
                    #endif

                    // Version
                    Text("LandlordHours v1.0.0")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.cloud)
                        .padding(.bottom, AppSpacing.tabContentBottomInset)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }
            .background {
                LHMobileCanvas()
            }
            .navigationBarHidden(true)
            .alert("Reset All Data?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    viewModel.resetCurrentUserLocalData()
                }
            } message: {
                Text("This will delete your local properties, time entries, goals, tax profile, categories, and setup state for this account. Your sign-in and Pro purchase status stay intact.")
            }
            .alert("Delete Account and Data?", isPresented: $showingDeleteAccountAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Account", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        do {
                            try await viewModel.deleteAccountAndData()
                            AppleSignInManager.shared.signOut()
                        } catch {
                            deleteAccountError = error.localizedDescription
                        }
                        isDeletingAccount = false
                    }
                }
            } message: {
                Text("This permanently deletes your LandlordHours account data on this device and any LandlordHours iCloud backup records for this app account, including properties, time entries, categories, goals, and tax profile. This cannot be undone.")
            }
            .alert("Account Deletion Failed", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteAccountError = nil }
            } message: {
                Text(deleteAccountError ?? "")
            }
            .alert("Restore Purchase", isPresented: Binding(
                get: { restoreStatusMessage != nil },
                set: { if !$0 { restoreStatusMessage = nil } }
            )) {
                Button("OK", role: .cancel) { restoreStatusMessage = nil }
            } message: {
                Text(restoreStatusMessage ?? "")
            }
            .sheet(isPresented: $showingProfileEdit) {
                ProfileEditView(userName: $userName, userEmail: $userEmail, profileImage: $profileImage)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(showPaywall: $showingPaywall)
            }
            .sheet(isPresented: $showingIconPicker) {
                AppIconPickerView()
            }
        }
    }

    private var syncSubtitle: String? {
        if viewModel.syncService.isSyncing { return "Syncing..." }
        if let error = viewModel.syncService.syncError { return "Error: \(error)" }
        if let date = viewModel.syncService.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last sync: \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        if !viewModel.syncService.accountAvailable { return "iCloud unavailable" }
        return nil
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    #if DEBUG
    private var developerToolsSection: some View {
        DisclosureGroup(isExpanded: $showDeveloperTools) {
            VStack(spacing: 12) {
                Button {
                    subscriptionManager.unlockPro()
                } label: {
                    HStack {
                        LucideIcon(image: Lucide.badgeCheck, size: 18)
                        Text(subscriptionManager.hasPurchased ? "Pro unlocked for this build" : "Unlock Pro for testing")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(subscriptionManager.hasPurchased ? AppColors.successGreen : AppColors.onAction)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(subscriptionManager.hasPurchased ? AppColors.successGreenWash : AppColors.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                ForEach(AppViewModel.MockDataScenario.allCases) { scenario in
                    Button {
                        animate(AppAnimation.smooth) {
                            viewModel.applyMockScenario(scenario)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            LHIconTile(
                                icon: debugScenarioIcon(for: scenario),
                                color: debugScenarioColor(for: scenario),
                                wash: debugScenarioWash(for: scenario),
                                size: 38,
                                isActive: true
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(scenario.title)
                                    .font(AppTypography.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(colors.textPrimary)
                                Text(scenario.subtitle)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(colors.textSecondary)
                            }

                            Spacer()

                            Text("Seed")
                                .font(AppTypography.buttonSmall)
                                .foregroundStyle(debugScenarioColor(for: scenario))
                        }
                        .padding(12)
                        .background(colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                LHIconTile(
                    icon: Lucide.code,
                    color: AppColors.textSecondary,
                    wash: colors.backgroundTertiary,
                    size: 38,
                    isActive: true
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer Tools")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("Mock data and debug-only Pro controls")
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
        .padding(14)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(colors.border.opacity(0.28), lineWidth: 1)
        }
    }

    private func debugScenarioIcon(for scenario: AppViewModel.MockDataScenario) -> UIImage {
        switch scenario {
        case .firstTime: return Lucide.userPlus
        case .emptyMainTabs: return Lucide.panelTop
        case .occasional: return Lucide.calendarClock
        case .frequent: return Lucide.chartNoAxesCombined
        }
    }

    private func debugScenarioColor(for scenario: AppViewModel.MockDataScenario) -> Color {
        switch scenario {
        case .firstTime: return AppColors.sky
        case .emptyMainTabs: return AppColors.primary
        case .occasional: return AppColors.honey
        case .frequent: return AppColors.primary
        }
    }

    private func debugScenarioWash(for scenario: AppViewModel.MockDataScenario) -> Color {
        switch scenario {
        case .firstTime: return colors.skyWash
        case .emptyMainTabs: return colors.primarySurface
        case .occasional: return colors.honeyWash
        case .frequent: return colors.primarySurface
        }
    }
    #endif
}

// MARK: - Tax Profile View

struct TaxProfileView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var taxProfile = TaxProfileManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showFilingStatusPicker = false
    @State private var showGoalPicker = false
    @State private var showYearPicker = false
    @State private var showWorkHoursInput = false
    @State private var showAddProperty = false
    @State private var workHoursText = ""
    @State private var newPropertyName = ""
    @State private var newPropertyAddress = ""
    @State private var newPropertyType: PropertyType = .ltr

    private let propertyIconStyles: [(bg: Color, fg: Color)] = [
        (AppColors.sageWash, AppColors.charcoal),
        (AppColors.coralWash, AppColors.charcoal),
        (AppColors.honeyWash, AppColors.charcoal),
        (AppColors.skyWash, AppColors.charcoal),
        (AppColors.primarySurface, AppColors.charcoal),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tax profile")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .minimumScaleFactor(0.82)
                    Text("Set the filing assumptions that drive your reports.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 18)

                filingStatusSection
                qualificationGoalSection
                propertiesSection
                fiftyPercentRuleSection
                Spacer().frame(height: 100)
            }
        }
        .background {
            LHMobileCanvas()
        }
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .font(.system(size: 1))
                    .foregroundStyle(colors.textPrimary)
            }
        }
        .confirmationDialog("Filing Status", isPresented: $showFilingStatusPicker) {
            ForEach(FilingStatus.allCases, id: \.self) { status in
                Button(status.rawValue) {
                    taxProfile.filingStatus = status
                }
            }
        }
        .confirmationDialog("Primary Goal", isPresented: $showGoalPicker) {
            ForEach(HourGoalType.allCases, id: \.self) { type in
                Button("\(type.rawValue) (\(Int(type.hoursRequired))h)") {
                    goalManager.setGlobalGoal(type)
                }
            }
        }
        .sheet(isPresented: $showYearPicker) {
            taxYearSheet
        }
        .sheet(isPresented: $showWorkHoursInput) {
            workHoursSheet
        }
        .sheet(isPresented: $showAddProperty) {
            addPropertySheet
        }
    }

    // MARK: - Filing Status Section

    private var filingStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            tpSectionTitle("Filing Status")

            VStack(spacing: 0) {
                Button { showFilingStatusPicker = true } label: {
                    tpRow(
                        icon: Lucide.fileText,
                        iconBg: colors.backgroundTertiary,
                        iconFg: AppColors.charcoal,
                        title: "Filing Status",
                        subtitle: "How you file your tax return",
                        rightText: taxProfile.filingStatus.rawValue
                    )
                }
                .buttonStyle(.plain)

                Divider().background(AppColors.snow).padding(.leading, 68)

                tpToggleRow(
                    icon: Lucide.users,
                    iconBg: AppColors.coralWash,
                    iconFg: AppColors.charcoal,
                    title: "Track Spouse Hours",
                    subtitle: "Combine for Material Participation",
                    isOn: $taxProfile.spouseTracking
                )
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: 1)
            }

            tpInfoTip {
                (Text("Spouse hours ").fontWeight(.semibold).foregroundStyle(colors.textPrimary) +
                 Text("combine for Material Participation tests but NOT for REPS qualification. Only one spouse needs to meet the 750h + 50% rule.").foregroundStyle(AppColors.slate))
                    .font(.system(size: 12))
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Qualification Goal Section

    private var qualificationGoalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            tpSectionTitle("Qualification Goal")

            VStack(spacing: 0) {
                Button { showGoalPicker = true } label: {
                    tpRow(
                        icon: Lucide.layers,
                        iconBg: colors.backgroundTertiary,
                        iconFg: AppColors.charcoal,
                        title: "Primary Goal",
                        subtitle: "Determines your Reports dashboard",
                        rightText: "\(goalManager.globalGoalType.rawValue) (\(Int(goalManager.globalGoalType.hoursRequired))h)"
                    )
                }
                .buttonStyle(.plain)

                Divider().background(AppColors.snow).padding(.leading, 68)

                Button { showYearPicker = true } label: {
                    tpRow(
                        icon: Lucide.calendar,
                        iconBg: AppColors.sageWash,
                        iconFg: AppColors.charcoal,
                        title: "Tax Year",
                        subtitle: "January 1 \u{2013} December 31",
                        rightText: "\(taxProfile.taxYear)"
                    )
                }
                .buttonStyle(.plain)

                Divider().background(AppColors.snow).padding(.leading, 68)

                tpToggleRow(
                    icon: Lucide.clipboardCheck,
                    iconBg: AppColors.honeyWash,
                    iconFg: AppColors.charcoal,
                    title: "Grouping Election",
                    subtitle: "Treat all rentals as one activity",
                    isOn: $taxProfile.groupingElection
                )
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: 1)
            }

            tpInfoTip {
                (Text("Grouping Election (1.469-9g): ").fontWeight(.semibold).foregroundStyle(colors.textPrimary) +
                 Text("If you qualify as REP, you can test Material Participation across all properties combined instead of individually.").foregroundStyle(AppColors.slate))
                    .font(.system(size: 12))
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Properties Section

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            tpSectionTitle("Properties")

            VStack(spacing: 0) {
                if viewModel.properties.isEmpty {
                    Text("No properties yet")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.mist)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(viewModel.properties.enumerated()), id: \.element.id) { index, property in
                        if index > 0 {
                            Divider().background(AppColors.snow).padding(.leading, 66)
                        }
                        propertyRow(property: property, index: index)
                    }
                }

                if !viewModel.properties.isEmpty {
                    Divider().background(AppColors.snow)
                }

                Button { showAddProperty = true } label: {
                    HStack(spacing: 8) {
                        LucideIcon(image: Lucide.plus, size: 18)
                            .foregroundStyle(AppColors.primary)
                        Text("Add Property")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - 50% Rule Section

    private var fiftyPercentRuleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            tpSectionTitle("50% Rule Tracking")

            VStack(spacing: 0) {
                Button {
                    workHoursText = taxProfile.nonREWorkHours > 0 ? String(Int(taxProfile.nonREWorkHours)) : ""
                    showWorkHoursInput = true
                } label: {
                    tpRow(
                        icon: Lucide.briefcase,
                        iconBg: colors.backgroundTertiary,
                        iconFg: AppColors.charcoal,
                        title: "Non-RE Work Hours",
                        subtitle: "W-2 or other job hours this year",
                        rightText: "\(Int(taxProfile.nonREWorkHours))h"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: 1)
            }

            tpInfoTip {
                (Text("For REPS, your RE hours must be ").foregroundStyle(AppColors.slate) +
                 Text("more than 50%").fontWeight(.semibold).foregroundStyle(colors.textPrimary) +
                 Text(" of all personal services. Enter your non-RE work hours so we can track this.").foregroundStyle(AppColors.slate))
                    .font(.system(size: 12))
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Property Row

    private func propertyRow(property: RentalProperty, index: Int) -> some View {
        let style = propertyIconStyles[index % propertyIconStyles.count]
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(style.bg)
                .frame(width: 36, height: 36)
                .overlay(
                    LucideIcon(image: Lucide.house, size: 18)
                        .foregroundStyle(style.fg)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(property.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(property.shortAddress)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.mist)
            }

            Spacer()

            propertyBadge(property.propertyType)

            LucideIcon(image: Lucide.chevronRight, size: 16)
                .foregroundStyle(AppColors.cloud)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func propertyBadge(_ type: PropertyType) -> some View {
        let (bg, fg): (Color, Color) = type == .ltr
            ? (colors.sageWash, colors.textPrimary)
            : (colors.honeyWash, colors.textPrimary)

        return Text(type.rawValue)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Reusable Row Helpers

    private func tpSectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .black, design: .rounded))
            .foregroundStyle(colors.textPrimary)
            .padding(.leading, 4)
    }

    private func tpRow(icon: UIImage, iconBg: Color, iconFg: Color, title: String, subtitle: String, rightText: String? = nil) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(iconBg)
                .frame(width: 36, height: 36)
                .overlay(
                    LucideIcon(image: icon, size: 18)
                        .foregroundStyle(iconFg)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.mist)
            }

            Spacer()

            if let rightText {
                Text(rightText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }

            LucideIcon(image: Lucide.chevronRight, size: 16)
                .foregroundStyle(AppColors.cloud)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func tpToggleRow(icon: UIImage, iconBg: Color, iconFg: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(iconBg)
                .frame(width: 36, height: 36)
                .overlay(
                    LucideIcon(image: icon, size: 18)
                        .foregroundStyle(iconFg)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.mist)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppColors.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func tpInfoTip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.sageWash)
                .frame(width: 20, height: 20)
                .overlay(
                    LucideIcon(image: Lucide.info, size: 10)
                        .foregroundStyle(AppColors.charcoal)
                )

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.sageWash.opacity(colorScheme == .dark ? 0.18 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.sage.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Sheets

    private var taxYearSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Tax Year", selection: $taxProfile.taxYear) {
                    ForEach(2024...2030, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding()
            .navigationTitle("Tax Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showYearPicker = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .presentationDetents([.height(300)])
    }

    private var workHoursSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter your non-real estate work hours for this tax year.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.slate)
                    .multilineTextAlignment(.center)

                TextField("Hours", text: $workHoursText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(AppColors.snow)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    if let hours = Double(workHoursText) {
                        taxProfile.nonREWorkHours = hours
                    }
                    showWorkHoursInput = false
                } label: {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.action)
                        .foregroundStyle(AppColors.onAction)
                        .clipShape(Capsule())
                }
            }
            .padding(24)
            .navigationTitle("Non-RE Work Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showWorkHoursInput = false }
                        .foregroundStyle(AppColors.slate)
                }
            }
        }
        .presentationDetents([.height(340)])
    }

    private var addPropertySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    ForEach([PropertyType.ltr, PropertyType.str], id: \.self) { type in
                        Button {
                            newPropertyType = type
                        } label: {
                            Text(type.fullName)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(newPropertyType == type ? AppColors.sageWash : Color.clear)
                                .foregroundStyle(newPropertyType == type ? AppColors.charcoal : AppColors.slate)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(newPropertyType == type ? AppColors.sage : AppColors.snow, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 14) {
                    TextField("Property Name", text: $newPropertyName)
                        .font(.system(size: 16))
                        .padding(14)
                        .background(colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(newPropertyName.isEmpty ? colors.border.opacity(0.2) : AppColors.sage, lineWidth: 1)
                        )

                    TextField("Address", text: $newPropertyAddress)
                        .font(.system(size: 16))
                        .padding(14)
                        .background(colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(newPropertyAddress.isEmpty ? colors.border.opacity(0.2) : AppColors.sage, lineWidth: 1)
                        )
                }

                Button {
                    guard !newPropertyName.isEmpty else { return }
                    viewModel.addProperty(
                        name: newPropertyName,
                        address: newPropertyAddress,
                        type: newPropertyType
                    )
                    newPropertyName = ""
                    newPropertyAddress = ""
                    newPropertyType = .ltr
                    showAddProperty = false
                } label: {
                    Text("Add Property")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(newPropertyName.isEmpty ? AppColors.cloud : AppColors.sage)
                        .foregroundStyle(newPropertyName.isEmpty ? Color.white : AppColors.charcoal)
                        .clipShape(Capsule())
                }
                .disabled(newPropertyName.isEmpty)
            }
            .padding(24)
            .navigationTitle("Add Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddProperty = false
                    }
                    .foregroundStyle(AppColors.slate)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Profile Edit View

struct ProfileEditView: View {
    @Binding var userName: String
    @Binding var userEmail: String
    @Binding var profileImage: Data?
    @StateObject private var appleSignIn = AppleSignInManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    // Profile Photo Section
                    VStack(spacing: AppSpacing.md) {
                        if let imageData = profileImage ?? appleSignIn.profileImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle()
                                    .fill(AppColors.sage)
                                    .frame(width: 100, height: 100)

                                LucideIcon(image: Lucide.user, size: 40)
                                    .foregroundStyle(AppColors.charcoal)
                            }
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Change Photo")
                                .font(AppTypography.buttonSmall)
                                .foregroundStyle(AppColors.charcoal)
                        }
                        .onChange(of: selectedPhotoItem) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    profileImage = data
                                }
                            }
                        }
                    }
                    .padding(.top, AppSpacing.xl)

                    // Name Field
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Name")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        TextField("Your name", text: $userName)
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                            .padding(AppSpacing.md)
                            .background(colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    }

                    // Email Field
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Email")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        TextField("your@email.com", text: $userEmail)
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding(AppSpacing.md)
                            .background(colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .background {
                LHMobileCanvas()
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        AppleSignInManager.shared.updateProfile(
                            name: userName.isEmpty ? nil : userName,
                            email: userEmail.isEmpty ? nil : userEmail,
                            imageData: profileImage
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
    }
}

// MARK: - App Icon Option

enum AppIconOption: String, CaseIterable {
    case `default` = "AppIcon"
    case violet = "AppIcon-Violet"
    case sunset = "AppIcon-Sunset"
    case clock = "AppIcon-Clock"
    case aurora = "AppIcon-Aurora"

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .violet: return "Violet Waves"
        case .sunset: return "Warm Sunset"
        case .clock: return "House + Clock"
        case .aurora: return "Full Spectrum"
        }
    }

    var subtitle: String {
        switch self {
        case .default: return "Original brand icon"
        case .violet: return "Violet Soft to Violet Deep"
        case .sunset: return "Coral through Rose to Violet"
        case .clock: return "Sage-to-Violet with clock face"
        case .aurora: return "Honey through Coral to Violet"
        }
    }

    var previewImageName: String {
        switch self {
        case .default: return "AppIconPreview-Default"
        case .violet: return "AppIconPreview-Violet"
        case .sunset: return "AppIconPreview-Sunset"
        case .clock: return "AppIconPreview-Clock"
        case .aurora: return "AppIconPreview-Aurora"
        }
    }

    var alternateIconName: String? {
        self == .default ? nil : rawValue
    }

    static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .default }
        return AppIconOption(rawValue: name) ?? .default
    }
}

// MARK: - App Icon Picker View

struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var selectedIcon: AppIconOption = AppIconOption.current
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("Choose an icon that fits your style.")
                        .font(AppTypography.body)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    ForEach(AppIconOption.allCases, id: \.rawValue) { option in
                        AppIconRow(
                            option: option,
                            isSelected: selectedIcon == option,
                            colors: colors
                        ) {
                            let actualCurrent = AppIconOption.current
                            guard actualCurrent != option else {
                                selectedIcon = option
                                return
                            }
                            selectedIcon = option
                            UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
                                DispatchQueue.main.async {
                                    if let error {
                                        iconError = error.localizedDescription
                                        selectedIcon = AppIconOption.current
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(colors.background)
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .hidesAppTabBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
            .onAppear {
                selectedIcon = AppIconOption.current
            }
            .alert("Could not change icon", isPresented: Binding(
                get: { iconError != nil },
                set: { if !$0 { iconError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(iconError ?? "Try again later.")
            }
        }
    }
}

private struct AppIconRow: View {
    let option: AppIconOption
    let isSelected: Bool
    let colors: AdaptiveColors
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon preview
                Image(option.previewImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? AppColors.primary : colors.border.opacity(0.5), lineWidth: isSelected ? 2.5 : 0.5)
                    )

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(option.subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.primary)
                }
            }
            .padding(14)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .stroke(isSelected ? AppColors.primary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppViewModel())
        .environmentObject(CategoryManager.shared)
}
