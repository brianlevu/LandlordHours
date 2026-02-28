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
            // Bare icon — no background container
            LucideIcon(image: icon, size: 20)
                .foregroundStyle(isDanger ? AppColors.coral : iconColor)
                .frame(width: 24, height: 24)

            // Text content
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
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
        .padding(.vertical, 13)
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
            // Bare icon — no background container
            LucideIcon(image: icon, size: 20)
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.body)
                    .fontWeight(.medium)
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
                .tint(AppColors.primary)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(AppTypography.label)
            .tracking(1.5)
            .foregroundStyle(AppColors.mist)
            .padding(.top, 28)
            .padding(.bottom, 10)
    }
}

// MARK: - Subscription Card

private struct SubscriptionCard: View {
    let isPro: Bool
    let isTrialActive: Bool
    let trialDaysRemaining: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if isPro && !isTrialActive {
                // Pro member card
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRO PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.white.opacity(0.6))

                    Text("LandlordHours Pro")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text("Active subscription")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.bottom, 6)

                    Text("Manage Subscription")
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [AppColors.primaryDark, AppColors.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            } else {
                // Trial / free card
                VStack(alignment: .leading, spacing: 6) {
                    Text("FREE TRIAL")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(AppColors.warning)

                    Text(isTrialActive ? "\(trialDaysRemaining) days remaining" : "Trial Expired")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)

                    // Trial progress bar
                    if isTrialActive {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(AppColors.warning)
                                    .frame(width: geo.size.width * CGFloat(max(0, 7 - trialDaysRemaining)) / 7.0, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.bottom, 8)
                    }

                    Text("Upgrade to Pro")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [AppColors.charcoal, AppColors.ink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature List (Trial)

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
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.primary, AppColors.primaryLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)

                        // Show initial or person icon
                        if !name.isEmpty && name != "Your Name" {
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                        } else {
                            LucideIcon(image: Lucide.user, size: 20)
                                .foregroundStyle(Color.white)
                        }
                    }
                }

                // Name and email
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
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
            .padding(.vertical, 16)
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
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var showingResetAlert = false
    @State private var showingProfileEdit = false
    @State private var showingPaywall = false
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Data?
    @State private var showingIconPicker = false
    @State private var showingCalendarImport = false
    @State private var calendarDetectedEntries: [DetectedCalendarEntry] = []
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Page title
                    HStack {
                        Text("Settings")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, 20)

                    // ===== Plan & Account =====
                    SectionLabel(text: "Plan & Account")
                        .padding(.top, 0)

                    SubscriptionCard(
                        isPro: subscriptionManager.isPro,
                        isTrialActive: subscriptionManager.isTrialActive,
                        trialDaysRemaining: subscriptionManager.trialDaysRemaining,
                        onTap: { showingPaywall = true }
                    )
                    .padding(.bottom, 4)

                    // Feature list for trial/free users
                    if !subscriptionManager.isPro || subscriptionManager.isTrialActive {
                        FeatureListView()
                    }

                    // Restore purchase row
                    Button {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    } label: {
                        SettingRow(
                            icon: Lucide.badgeCheck,
                            iconColor: AppColors.charcoal,
                            title: "Restore Purchase"
                        )
                    }
                    .buttonStyle(.plain)

                    #if DEBUG
                    // Debug-only: unlock Pro without StoreKit
                    Button {
                        print("[DEBUG] Unlock Pro tapped — calling unlockPro()")
                        Task { await subscriptionManager.unlockPro() }
                    } label: {
                        Text(subscriptionManager.hasPurchased ? "DEBUG: Pro Unlocked ✓" : "DEBUG: Unlock Pro")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(subscriptionManager.hasPurchased ? AppColors.sage : AppColors.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 8)
                    #endif

                    // ===== Profile & Tax =====
                    SectionLabel(text: "Profile & Tax")

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

                    Divider().background(AppColors.snow)

                    // Tax Profile (includes goal, filing status, spouse tracking)
                    NavigationLink {
                        TaxProfileView()
                    } label: {
                        SettingRow(
                            icon: Lucide.fileText,
                            iconColor: AppColors.charcoal,
                            title: "Tax Profile",
                            subtitle: "Filing, goals & spouse tracking"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(AppColors.snow)

                    // Learning Center
                    NavigationLink {
                        LearningCenterView()
                    } label: {
                        SettingRow(
                            icon: Lucide.bookOpen,
                            iconColor: AppColors.charcoal,
                            title: "Learning Center",
                            subtitle: "Guides, tax strategy & tips"
                        )
                    }
                    .buttonStyle(.plain)

                    // ===== Data & Export =====
                    SectionLabel(text: "Data & Export")

                    if subscriptionManager.isPro && !subscriptionManager.isTrialActive {
                        NavigationLink {
                            ExportPDFView(year: Calendar.current.component(.year, from: Date()))
                        } label: {
                            SettingRow(
                                icon: Lucide.download,
                                iconColor: AppColors.charcoal,
                                title: "Export Reports",
                                subtitle: "PDF for your accountant"
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 14) {
                            LucideIcon(image: Lucide.download, size: 20)
                                .foregroundStyle(AppColors.charcoal)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Export Reports")
                                    .font(AppTypography.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(colors.textPrimary)
                                Text("Upgrade to unlock")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(colors.textTertiary)
                            }

                            Spacer()

                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AppColors.primarySurface)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 13)
                        .opacity(0.5)
                    }

                    Divider().background(AppColors.snow)

                    // Backup / Sync
                    Button {
                        viewModel.syncNow()
                    } label: {
                        SettingRow(
                            icon: Lucide.cloudUpload,
                            iconColor: AppColors.charcoal,
                            title: "Sync Now",
                            subtitle: syncSubtitle
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(AppColors.snow)

                    // Import from Calendar
                    Button {
                        Task {
                            isScanning = true
                            let granted = await CalendarImportService.shared.requestAccess()
                            if granted {
                                let calendars = CalendarImportService.shared.availableCalendars()
                                let allIds = Set(calendars.map { $0.calendarIdentifier })
                                calendarDetectedEntries = CalendarImportService.shared.scanCalendars(
                                    allIds,
                                    properties: viewModel.properties
                                )
                                showingCalendarImport = true
                            }
                            isScanning = false
                        }
                    } label: {
                        SettingRow(
                            icon: Lucide.calendar,
                            iconColor: AppColors.charcoal,
                            title: "Import from Calendar",
                            subtitle: isScanning ? "Scanning..." : "Detect property events"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanning)

                    // ===== Preferences =====
                    SectionLabel(text: "Preferences")

                    // Notifications
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingRow(
                            icon: Lucide.bell,
                            iconColor: AppColors.charcoal,
                            title: "Notifications"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(AppColors.snow)

                    // App Icon
                    Button {
                        showingIconPicker = true
                    } label: {
                        SettingRow(
                            icon: Lucide.layoutGrid,
                            iconColor: AppColors.charcoal,
                            title: "App Icon",
                            value: AppIconOption.current.displayName
                        )
                    }
                    .buttonStyle(.plain)

                    // ===== Support =====
                    SectionLabel(text: "Support")

                    // Contact Support
                    NavigationLink {
                        ContactSupportView()
                    } label: {
                        SettingRow(
                            icon: Lucide.mail,
                            iconColor: AppColors.charcoal,
                            title: "Contact Support"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(AppColors.snow)

                    // Terms & Privacy
                    Button {
                        if let url = URL(string: "https://www.openclaw.com/landlord-hours/terms") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingRow(
                            icon: Lucide.scrollText,
                            iconColor: AppColors.charcoal,
                            title: "Terms & Privacy"
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(AppColors.snow)

                    // Sign Out (danger)
                    Button {
                        viewModel.signOut()
                        AppleSignInManager.shared.signOut()
                    } label: {
                        SettingRow(
                            icon: Lucide.logOut,
                            iconColor: AppColors.coral,
                            title: "Sign Out",
                            showChevron: false,
                            isDanger: true
                        )
                    }
                    .buttonStyle(.plain)

                    // Version
                    Text("LandlordHours v1.0.0")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.cloud)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(colors.background)
            .navigationBarHidden(true)
            .alert("Reset All Data?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: UserScope.key("LandlordHours.properties"))
                    UserDefaults.standard.removeObject(forKey: UserScope.key("LandlordHours.entries"))
                }
            } message: {
                Text("This will delete all your properties, time entries, and settings.")
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
            .sheet(isPresented: $showingCalendarImport) {
                CalendarImportReviewView(detectedEntries: calendarDetectedEntries)
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
        (Color(hex: "EDE8FF"), Color(hex: "7B68EE")),
        (Color(hex: "FFE8E4"), Color(hex: "FF8A7A")),
        (Color(hex: "FFF4E0"), Color(hex: "F5C563")),
        (Color(hex: "E0F5E8"), Color(hex: "7EC8A0")),
        (Color(hex: "E0F0FF"), Color(hex: "6CB4EE")),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                filingStatusSection
                qualificationGoalSection
                propertiesSection
                fiftyPercentRuleSection
                Spacer().frame(height: 100)
            }
        }
        .background(colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Tax Profile")
                    .font(.system(size: 22, weight: .regular, design: .serif))
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
                        iconBg: Color(hex: "EDE8FF"),
                        iconFg: Color(hex: "7B68EE"),
                        title: "Filing Status",
                        subtitle: "How you file your tax return",
                        rightText: taxProfile.filingStatus.rawValue
                    )
                }
                .buttonStyle(.plain)

                Divider().background(AppColors.snow).padding(.leading, 68)

                tpToggleRow(
                    icon: Lucide.users,
                    iconBg: Color(hex: "FFE8E4"),
                    iconFg: Color(hex: "FF8A7A"),
                    title: "Track Spouse Hours",
                    subtitle: "Combine for Material Participation",
                    isOn: $taxProfile.spouseTracking
                )
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)

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
                        iconBg: Color(hex: "EDE8FF"),
                        iconFg: Color(hex: "7B68EE"),
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
                        iconBg: Color(hex: "E0F5E8"),
                        iconFg: Color(hex: "7EC8A0"),
                        title: "Tax Year",
                        subtitle: "January 1 \u{2013} December 31",
                        rightText: "\(taxProfile.taxYear)"
                    )
                }
                .buttonStyle(.plain)

                Divider().background(AppColors.snow).padding(.leading, 68)

                tpToggleRow(
                    icon: Lucide.clipboardCheck,
                    iconBg: Color(hex: "FFF4E0"),
                    iconFg: Color(hex: "F5C563"),
                    title: "Grouping Election",
                    subtitle: "Treat all rentals as one activity",
                    isOn: $taxProfile.groupingElection
                )
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)

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
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
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
                        iconBg: Color(hex: "F0EFF4"),
                        iconFg: Color(hex: "6E6E82"),
                        title: "Non-RE Work Hours",
                        subtitle: "W-2 or other job hours this year",
                        rightText: "\(Int(taxProfile.nonREWorkHours))h"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)

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
            ? (Color(hex: "EDE8FF"), Color(hex: "7B68EE"))
            : (Color(hex: "FFF4E0"), Color(hex: "D4870E"))

        return Text(type.rawValue)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Reusable Row Helpers

    private func tpSectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(AppColors.mist)
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
                .fill(Color(hex: "EDE8FF"))
                .frame(width: 20, height: 20)
                .overlay(
                    LucideIcon(image: Lucide.info, size: 10)
                        .foregroundStyle(AppColors.primary)
                )

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "F8F6FF"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "EDE8FF"), lineWidth: 1)
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
                        .background(AppColors.primary)
                        .foregroundStyle(Color.white)
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
                                .background(newPropertyType == type ? Color(hex: "F8F6FF") : Color.clear)
                                .foregroundStyle(newPropertyType == type ? AppColors.primary : AppColors.slate)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(newPropertyType == type ? AppColors.primary : AppColors.snow, lineWidth: 2)
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
                        .background(Color(hex: "FAFAFA"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(newPropertyName.isEmpty ? AppColors.snow : AppColors.primary, lineWidth: 2)
                        )

                    TextField("Address", text: $newPropertyAddress)
                        .font(.system(size: 16))
                        .padding(14)
                        .background(Color(hex: "FAFAFA"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(newPropertyAddress.isEmpty ? AppColors.snow : AppColors.primary, lineWidth: 2)
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
                        .background(newPropertyName.isEmpty ? AppColors.cloud : AppColors.primary)
                        .foregroundStyle(Color.white)
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
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.primary, AppColors.primaryLight],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)

                                LucideIcon(image: Lucide.user, size: 40)
                                    .foregroundStyle(Color.white)
                            }
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Change Photo")
                                .font(AppTypography.buttonSmall)
                                .foregroundStyle(AppColors.primary)
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
                        Text("NAME")
                            .font(AppTypography.label)
                            .tracking(1.5)
                            .foregroundStyle(colors.textTertiary)

                        TextField("Your name", text: $userName)
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                            .padding(AppSpacing.md)
                            .background(colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    }

                    // Email Field
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("EMAIL")
                            .font(AppTypography.label)
                            .tracking(1.5)
                            .foregroundStyle(colors.textTertiary)

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
            .background(colors.background)
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
                                        print("Failed to set app icon: \(error.localizedDescription)")
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
