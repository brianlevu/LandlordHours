import SwiftUI
import LucideIcons
import UserNotifications

// MARK: - Design System for LandlordHours
// Tiimo-inspired — soft, rounded, friendly, modern
// Source of truth: figma-redesign/design-system.html

// MARK: - Colors
enum AppColors {
    // MARK: - Light Theme (Warm Cream Base)
    static let background = Color(hex: "FAF7F2")        // cream — warm page background
    static let backgroundSecondary = Color.white         // pure white for cards
    static let backgroundTertiary = Color(hex: "F0EFF4") // snow — inputs, tags, subtle surfaces

    // Primary accent — Violet family.
    // Role: brand identity, primary CTAs, selected navigation, focus, links.
    static let primary = Color(hex: "7B68EE")
    static let primaryLight = Color(hex: "B8AFFE")
    static let primarySurface = Color(hex: "EDE8FF")
    static let primaryDark = Color(hex: "5B4BC9")

    // Accent palette
    static let coral = Color(hex: "FF8A7A")              // destructive, repair/maintenance emphasis
    static let coralWash = Color(hex: "FFE8E4")
    static let sage = Color(hex: "7EC8A0")               // success, qualified, complete, healthy progress
    static let sageWash = Color(hex: "E4F5EC")
    static let honey = Color(hex: "F5C563")              // warning, behind pace, needs attention
    static let honeyWash = Color(hex: "FFF4DA")
    static let sky = Color(hex: "6CB4EE")                // info, imports, calendar/sync
    static let skyWash = Color(hex: "E0F0FF")
    static let rose = Color(hex: "E88CA5")               // soft human/spouse emphasis
    static let roseWash = Color(hex: "FFE4EC")
    static let lavenderPanel = Color(hex: "F8F6FF")
    static let lavenderMist = Color(hex: "E8E0FF")
    static let lavenderField = Color(hex: "F0ECFF")
    static let skyMist = Color(hex: "E0F2FE")
    static let aquaMist = Color(hex: "F0FDFA")
    static let blueSoft = Color(hex: "93C5FD")
    static let successDeep = Color(hex: "5BA87E")
    static let indigoMist = Color(hex: "E0E7FF")
    static let lavenderSoft = Color(hex: "C4B5FD")
    static let lavenderPale = Color(hex: "F5F3FF")
    static let darkPlum = Color(hex: "1A1535")
    static let darkInk = Color(hex: "1C1A2E")

    // Semantic
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FBBF24")
    static let error = Color(hex: "F472B6")

    // Intent aliases. New UI should prefer these over raw accent names.
    static let action = primary
    static let actionSurface = primarySurface
    static let actionPressed = primaryDark
    static let onAction = Color.white
    static let positive = sage
    static let positiveSurface = sageWash
    static let caution = honey
    static let cautionSurface = honeyWash
    static let destructive = coral
    static let destructiveSurface = coralWash
    static let informational = sky
    static let informationalSurface = skyWash

    // Reports goal palettes
    static let reportsAccent = Color(hex: "8B5CF6")
    static let reportsAccentSoft = Color(hex: "A78BFA")
    static let reportsAccentWash = Color(hex: "EDE9FE")
    static let mpAccent = Color(hex: "A855F7")
    static let mpAccentSoft = Color(hex: "C084FC")
    static let mpAccentWash = Color(hex: "F3E8FF")
    static let successGreen = Color(hex: "059669")
    static let successGreenLight = Color(hex: "34D399")
    static let successGreenSoft = Color(hex: "6EE7B7")
    static let successGreenWash = Color(hex: "ECFDF5")
    static let cautionText = Color(hex: "D97706")
    static let repairOrange = Color(hex: "F97316")
    static let dataBlue = Color(hex: "60A5FA")
    static let dataBlueDeep = Color(hex: "3B82F6")
    static let dataRed = Color(hex: "EF4444")
    static let dataEmerald = Color(hex: "10B981")
    static let dataPink = Color(hex: "EC4899")

    // Celebration palette
    static let celebrationDeepPurple = Color(hex: "4C3D8F")
    static let celebrationPurple = Color(hex: "5B4BA8")
    static let celebrationIndigo = Color(hex: "6E5DC6")
    static let celebrationLavender = Color(hex: "8B7EC8")
    static let celebrationNightPurple = Color(hex: "3D3270")

    // Logo artwork palette
    static let logoCanvas = Color(hex: "F4F1FF")
    static let logoWaveLightStart = Color(hex: "D8D0FF")
    static let logoWaveMidStart = Color(hex: "A899F7")
    static let logoWaveMidEnd = Color(hex: "9485F0")
    static let logoWaveStrongStart = Color(hex: "8B78F0")
    static let logoWaveDeepStart = Color(hex: "6B58DE")
    static let logoWaveDeepEnd = Color(hex: "4A38B0")

    // Neutrals
    static let charcoal = Color(hex: "1A1A2E")           // headlines, primary text
    static let ink = Color(hex: "2D2D3F")                // secondary text
    static let slate = Color(hex: "6E6E82")              // captions, inactive labels
    static let mist = Color(hex: "A8A8BC")               // placeholders, tertiary
    static let cloud = Color(hex: "D4D4E0")              // borders, dividers
    static let snow = Color(hex: "F0EFF4")               // inputs, subtle surfaces

    // Legacy aliases for backward compatibility
    static let textPrimary = charcoal
    static let textSecondary = slate
    static let textTertiary = mist
    static let border = cloud
    static let borderLight = Color(hex: "E8E8F0")
    static let info = sky

    // MARK: - Dark Theme Colors
    static let darkBackground = Color(hex: "0C0C18")
    static let darkBackgroundSecondary = Color(hex: "161626")
    static let darkBackgroundTertiary = Color(hex: "1E1E32")
    static let darkPrimarySurface = Color(hex: "2D2A4A")

    static let darkPrimary = Color(hex: "9D8FF5")
    static let darkSuccess = Color(hex: "4ADE80")
    static let darkWarning = Color(hex: "FCD34D")
    static let darkError = Color(hex: "F472B6")

    // Dark accent washes (for jelly icon containers)
    static let darkCoralWash = Color(hex: "3A2020")
    static let darkSageWash = Color(hex: "1A2E22")
    static let darkHoneyWash = Color(hex: "2E2818")
    static let darkSkyWash = Color(hex: "1A2230")
    static let darkRoseWash = Color(hex: "2E1A22")

    static let darkTextPrimary = Color(hex: "E8E8F0")
    static let darkTextSecondary = Color(hex: "A8A8BC")
    static let darkTextTertiary = Color(hex: "6E6E82")

    static let darkBorder = Color.white.opacity(0.08)
}

// MARK: - Color Scheme Aware Colors
struct AdaptiveColors {
    let colorScheme: ColorScheme

    var background: Color { colorScheme == .dark ? AppColors.darkBackground : AppColors.background }
    var backgroundSecondary: Color { colorScheme == .dark ? AppColors.darkBackgroundSecondary : AppColors.backgroundSecondary }
    var backgroundTertiary: Color { colorScheme == .dark ? AppColors.darkBackgroundTertiary : AppColors.backgroundTertiary }
    var primarySurface: Color { colorScheme == .dark ? AppColors.darkPrimarySurface : AppColors.primarySurface }

    var primary: Color { colorScheme == .dark ? AppColors.darkPrimary : AppColors.primary }
    var success: Color { colorScheme == .dark ? AppColors.darkSuccess : AppColors.success }
    var warning: Color { colorScheme == .dark ? AppColors.darkWarning : AppColors.warning }
    var error: Color { colorScheme == .dark ? AppColors.darkError : AppColors.error }

    var action: Color { primary }
    var actionSurface: Color { primarySurface }
    var positive: Color { sage }
    var positiveSurface: Color { sageWash }
    var caution: Color { honey }
    var cautionSurface: Color { honeyWash }
    var destructive: Color { coral }
    var destructiveSurface: Color { coralWash }
    var informational: Color { sky }
    var informationalSurface: Color { skyWash }

    var coral: Color { AppColors.coral }
    var sage: Color { AppColors.sage }
    var honey: Color { AppColors.honey }
    var sky: Color { AppColors.sky }
    var rose: Color { AppColors.rose }

    var coralWash: Color { colorScheme == .dark ? AppColors.darkCoralWash : AppColors.coralWash }
    var sageWash: Color { colorScheme == .dark ? AppColors.darkSageWash : AppColors.sageWash }
    var honeyWash: Color { colorScheme == .dark ? AppColors.darkHoneyWash : AppColors.honeyWash }
    var skyWash: Color { colorScheme == .dark ? AppColors.darkSkyWash : AppColors.skyWash }
    var roseWash: Color { colorScheme == .dark ? AppColors.darkRoseWash : AppColors.roseWash }

    var textPrimary: Color { colorScheme == .dark ? AppColors.darkTextPrimary : AppColors.charcoal }
    var textSecondary: Color { colorScheme == .dark ? AppColors.darkTextSecondary : AppColors.slate }
    var textTertiary: Color { colorScheme == .dark ? AppColors.darkTextTertiary : AppColors.mist }

    var border: Color { colorScheme == .dark ? AppColors.darkBorder : AppColors.cloud }

    /// Glass effect background for tab bar, overlays
    var glass: Color { colorScheme == .dark ? AppColors.darkBackground.opacity(0.85) : Color.white.opacity(0.85) }
}

// MARK: - Appearance Preference
enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "Match device"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }

    var confirmationText: String {
        switch self {
        case .system: return "Saved - following device"
        case .light: return "Saved - light mode"
        case .dark: return "Saved - dark mode"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private let storageKey = "LandlordHours.appearancePreference"

    @Published var preference: AppAppearancePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: storageKey)
        }
    }

    var preferredColorScheme: ColorScheme? {
        preference.preferredColorScheme
    }

    static var forcedColorSchemeFromLaunchArguments: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHColorScheme"),
              args.indices.contains(index + 1) else {
            return nil
        }

        switch args[index + 1].lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHResetAppearancePreference") {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        #endif
        let raw = UserDefaults.standard.string(forKey: storageKey)
        preference = raw.flatMap(AppAppearancePreference.init(rawValue:)) ?? .system
    }
}

// MARK: - Typography
// SF Pro Rounded for UI, Serif (New York) for editorial headlines
enum AppTypography {
    // Serif headlines — maps to DM Serif Display in HTML mockups
    static let headline = Font.system(size: 28, weight: .regular, design: .serif)
    static let headlineLarge = Font.system(size: 34, weight: .regular, design: .serif)

    // Rounded body — maps to DM Sans in HTML mockups
    static let subheadline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular, design: .rounded)
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .rounded)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    static let label = Font.system(size: 11, weight: .bold, design: .rounded)
    static let heroNumber = Font.system(size: 52, weight: .heavy, design: .rounded)
    static let ringNumber = Font.system(size: 46, weight: .bold, design: .rounded)

    // Buttons
    static let buttonLarge = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let button = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let buttonSmall = Font.system(size: 13, weight: .semibold, design: .rounded)

    // Legacy aliases
    static let largeTitle = headlineLarge
    static let title1 = headline
    static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let footnote = Font.system(size: 13, weight: .regular, design: .rounded)
}

// MARK: - Spacing
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    static let tabContentBottomInset: CGFloat = 176
    static let floatingTabBarReservedHeight: CGFloat = 132
}

// MARK: - Corner Radius
enum AppCornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Animation
enum AppAnimation {
    static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
    static let standard = SwiftUI.Animation.easeInOut(duration: 0.24)
    static let smooth = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let feedback = SwiftUI.Animation.easeOut(duration: 0.12)
    static let reveal = SwiftUI.Animation.easeOut(duration: 0.22)
    static let flow = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let bouncy = SwiftUI.Animation.spring(response: 0.32, dampingFraction: 0.86)

    // Specific presets from design system
    static let ringProgress = SwiftUI.Animation.spring(response: 0.7, dampingFraction: 0.82)
    static let pillPop = SwiftUI.Animation.spring(response: 0.26, dampingFraction: 0.82)
    static let logoEntrance = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.86)
}

// MARK: - Hours Formatting
enum AppFormat {
    /// Consistent hours display across the app: "1.5h", "10.0h"
    static func hours(_ value: Double) -> String {
        String(format: "%.1f", value) + "h"
    }

    /// Whole hours for large ring displays: "142"
    static func hoursWhole(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Custom Category Model
struct CustomCategory: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var countsForREPS: Bool
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, iconName: String, colorHex: String, countsForREPS: Bool = true) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.countsForREPS = countsForREPS
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        iconName = try c.decode(String.self, forKey: .iconName)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        countsForREPS = try c.decode(Bool.self, forKey: .countsForREPS)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

// MARK: - Category Manager
class CategoryManager: ObservableObject {
    static let shared = CategoryManager()

    @Published var customCategories: [CustomCategory] = []

    private var userDefaultsKey: String { UserScope.key("customCategories") }
    
    let defaultCategories: [(name: String, icon: String, color: String, countsForREPS: Bool)] = [
        ("Repairs & Maintenance", "wrench.fill", "8B5CF6", true),
        ("Property Management", "building.2.fill", "34D399", true),
        ("Leasing & Tenant Relations", "key.fill", "60A5FA", true),
        ("Bookkeeping & Financial", "calculator", "FBBF24", true),
        ("Legal & Compliance", "doc.badge.gearshape", "F472B6", true),
        ("Insurance & Claims", "shield.fill", "A78BFA", true),
        ("Travel to Property", "car.fill", "3B82F6", true),
        ("Renovations & Improvements", "hammer.fill", "EF4444", true),
    ]
    
    var allCategories: [CustomCategory] {
        let defaults = defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) }
        return defaults + customCategories
    }
    
    init() {
        loadCategories()
    }
    
    func loadCategories() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let categories = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            customCategories = categories
        }
    }
    
    func saveCategories() {
        if let data = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        saveCategories()
    }
    
    func deleteCategory(_ category: CustomCategory) {
        customCategories.removeAll { $0.id == category.id }
        saveCategories()
    }
    
    func updateCategory(_ category: CustomCategory) {
        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
            saveCategories()
        }
    }

    func resetForSignOut() {
        customCategories = []
    }

    func resetForDataReset() {
        customCategories = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Available Icons and Colors
let availableCategoryIcons = [
    "house.fill", "building.2.fill", "building.fill", "key.fill",
    "wrench.fill", "hammer.fill", "paintbrush.fill", "drop.fill",
    "car.fill", "bus.fill", "airplane", "tram.fill",
    "doc.text.fill", "doc.badge.gearshape", "folder.fill",
    "phone.fill", "bubble.left.fill", "envelope.fill",
    "dollarsign.circle.fill", "creditcard.fill", "banknote.fill",
    "chart.bar.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill",
    "shield.fill", "lock.fill", "eye.fill", "camera.fill",
    "person.fill", "person.2.fill", "calendar", "clock.fill",
    "star.fill", "heart.fill", "flag.fill", "tag.fill",
    "megaphone.fill", "lightbulb.fill", "gearshape.fill"
]

let availableCategoryColors = [
    "8B5CF6", "A78BFA", "7C3AED",
    "34D399", "10B981", "059669",
    "60A5FA", "3B82F6", "1D4ED8",
    "FBBF24", "F59E0B", "D97706",
    "F472B6", "EC4899", "DB2777",
    "EF4444", "DC2626", "B91C1C",
    "F97316", "EA580C", "C2410C",
    "6B7280", "4B5563", "374151"
]

// MARK: - App Delegate (CloudKit remote notifications)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        registerEngagementNotificationCategories(center: notificationCenter)
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit subscription notification — pull changes
        Task { @MainActor in
            guard let viewModel = AppDelegate.sharedViewModel else {
                completionHandler(.noData)
                return
            }
            await viewModel.syncService.pullChanges()
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let rawDestination = response.notification.request.content.userInfo["destination"] as? String,
           let destination = notificationDestination(for: rawDestination) {
            UserDefaults.standard.set(destination.rawValue, forKey: AppIntentNavigationRequest.pendingDestinationKey)

            Task { @MainActor in
                NotificationCenter.default.post(name: .switchToTab, object: destination.tabIndex)
            }
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        #if DEBUG
        completionHandler([.banner, .list])
        #else
        completionHandler([.list])
        #endif
    }

    private func notificationDestination(for rawDestination: String) -> LandlordHoursIntentDestination? {
        if let directDestination = LandlordHoursIntentDestination(rawValue: rawDestination) {
            return directDestination
        }

        guard let engagementDestination = EngagementDestination(rawValue: rawDestination) else {
            return nil
        }

        switch engagementDestination {
        case .addProperty:
            return .properties
        case .track, .timerReview:
            return .track
        case .reports, .calendarReview, .export:
            return .reports
        case .none:
            return .home
        }
    }

    private func registerEngagementNotificationCategories(center: UNUserNotificationCenter) {
        let foreground: UNNotificationActionOptions = [.foreground]
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_TRACK",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_TRACK", title: "Log Time", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_REVIEW_CALENDAR",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_REVIEW_CALENDAR", title: "Review Drafts", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_EXPORT",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_EXPORT", title: "Prepare Export", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_REPORTS",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_REPORTS", title: "Open Reports", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_ADD_PROPERTY",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_ADD_PROPERTY", title: "Add Property", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_TIMER",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_TIMER", title: "Review Timer", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            )
        ]

        center.setNotificationCategories(categories)
    }

    @MainActor static var sharedViewModel: AppViewModel?
}

@main
struct LandlordHoursApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var categoryManager = CategoryManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared

    init() {
        // Tab bar: soft but legible. Keep content from visually bleeding through the controls.
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundEffect = nil
        tabBar.backgroundColor = UIColor.systemBackground
        tabBar.shadowImage = UIImage()
        tabBar.shadowColor = UIColor.separator.withAlphaComponent(0.18)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        UITabBar.appearance().tintColor = UIColor(AppColors.primary)

        // Navigation bar — transparent with rounded font
        let navBar = UINavigationBarAppearance()
        navBar.configureWithTransparentBackground()
        navBar.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold).rounded()
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(categoryManager)
                .environmentObject(appearanceManager)
                .preferredColorScheme(AppearanceManager.forcedColorSchemeFromLaunchArguments ?? appearanceManager.preferredColorScheme)
                .onAppear {
                    AppDelegate.sharedViewModel = viewModel
                }
        }
    }

}

// MARK: - UIFont Rounded Extension
extension UIFont {
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

// MARK: - View Modifier for Adaptive Colors
struct AdaptiveColorModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var isSecondary: Bool = false
    var isTertiary: Bool = false

    func body(content: Content) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        content
            .foregroundColor(
                isTertiary ? colors.textTertiary :
                isSecondary ? colors.textSecondary :
                colors.textPrimary
            )
    }
}

extension View {
    func adaptiveText(isSecondary: Bool = false, isTertiary: Bool = false) -> some View {
        modifier(AdaptiveColorModifier(isSecondary: isSecondary, isTertiary: isTertiary))
    }

    func adaptiveBackground(_ colorScheme: ColorScheme) -> some View {
        self.background(AdaptiveColors(colorScheme: colorScheme).background)
    }

    func adaptiveCard() -> some View {
        modifier(AdaptiveCardModifier())
    }
}

// MARK: - Adaptive Card Modifier
private struct AdaptiveCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        content
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
    }
}

// MARK: - Aurora Background
/// Atmospheric floating gradient blobs — the signature LandlordHours background effect
struct AuroraBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ZStack {
            colors.background.ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.primary.opacity(colorScheme == .dark ? 0.08 : 0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -100, y: -200)
                .blur(radius: 50)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.sage.opacity(colorScheme == .dark ? 0.06 : 0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 120, y: 100)
                .blur(radius: 50)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.coral.opacity(colorScheme == .dark ? 0.04 : 0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
                .offset(x: 80, y: -120)
                .blur(radius: 55)
        }
    }
}

// MARK: - Jelly Icon Badge
/// Squircle icon container with glass highlight and colored shadow — the "jelly-glass" system
struct JellyBadge: View {
    let systemName: String
    let color: Color
    var wash: Color? = nil
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            // Jelly-glass squircle container
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(color.opacity(0.8))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.30), location: 0),
                                    .init(color: Color.white.opacity(0.06), location: 0.4),
                                    .init(color: Color.black.opacity(0.04), location: 1.0)
                                ],
                                startPoint: UnitPoint(x: 0.15, y: 0),
                                endPoint: UnitPoint(x: 0.85, y: 1)
                            )
                        )
                )

            // Icon — try Lucide first, fall back to SF Symbol
            if let uiImage = UIImage(lucideId: systemName) {
                Image(uiImage: uiImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.45, height: size * 0.45)
                    .foregroundStyle(AppColors.onAction)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(AppColors.onAction)
            }
        }
        .shadow(color: color.opacity(0.35), radius: size * 0.25, y: size * 0.1)
    }
}
