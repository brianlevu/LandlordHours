import SwiftUI

// MARK: - Design System for LandlordHours
// Following iOS Human Interface Guidelines

// MARK: - Colors
enum AppColors {
    // MARK: - Light Theme (Default)
    static let background = Color(hex: "F5F5F5")       // clean cool light gray (Tiimo-style)
    static let backgroundSecondary = Color.white        // pure white for cards
    static let backgroundTertiary = Color(hex: "EBEBEB") // cool light gray for inputs/tags

    static let primary = Color(hex: "7C6FF7")
    static let primaryLight = Color(hex: "A78BFA")
    static let primarySurface = Color(hex: "EDE9FE")   // lavender tint for surfaces
    static let primaryDark = Color(hex: "6355E8")
    
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FBBF24")
    static let error = Color(hex: "F472B6")
    static let info = Color(hex: "60A5FA")
    
    static let textPrimary = Color(hex: "0D0D0D")
    static let textSecondary = Color(hex: "6B7280")
    static let textTertiary = Color(hex: "9CA3AF")
    
    static let border = Color(hex: "D1D5DB")
    static let borderLight = Color(hex: "E5E7EB")
    
    // MARK: - Dark Theme Colors
    static let darkBackground = Color(hex: "0D0D0D")
    static let darkBackgroundSecondary = Color(hex: "1C1C1C")
    static let darkBackgroundTertiary = Color(hex: "2A2A2A")
    static let darkPrimarySurface = Color(hex: "2D2A4A")

    static let darkPrimary = Color(hex: "9D8FF5")
    static let darkSuccess = Color(hex: "4ADE80")
    static let darkWarning = Color(hex: "FCD34D")
    static let darkError = Color(hex: "F472B6")
    static let darkInfo = Color(hex: "60A5FA")
    
    static let darkTextPrimary = Color.white
    static let darkTextSecondary = Color(red: 0.68, green: 0.70, blue: 0.74)
    static let darkTextTertiary = Color(red: 0.48, green: 0.50, blue: 0.54)
    
    static let darkBorder = Color(red: 0.28, green: 0.28, blue: 0.30)
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
    var info: Color { colorScheme == .dark ? AppColors.darkInfo : AppColors.info }
    
    var textPrimary: Color { colorScheme == .dark ? AppColors.darkTextPrimary : AppColors.textPrimary }
    var textSecondary: Color { colorScheme == .dark ? AppColors.darkTextSecondary : AppColors.textSecondary }
    var textTertiary: Color { colorScheme == .dark ? AppColors.darkTextTertiary : AppColors.textTertiary }
    
    var border: Color { colorScheme == .dark ? AppColors.darkBorder : AppColors.border }
}

// MARK: - Typography
enum AppTypography {
    static let largeTitle = Font.system(size: 34, weight: .bold)
    static let title1 = Font.system(size: 28, weight: .bold)
    static let title2 = Font.system(size: 22, weight: .bold)
    static let title3 = Font.system(size: 20, weight: .semibold)
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let footnote = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let buttonLarge = Font.system(size: 17, weight: .semibold)
    static let button = Font.system(size: 15, weight: .semibold)
    static let buttonSmall = Font.system(size: 13, weight: .semibold)
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
}

// MARK: - Corner Radius
enum AppCornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
}

// MARK: - Animation
enum AppAnimation {
    static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
    static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
    static let smooth = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let bouncy = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.7)
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
    
    init(id: UUID = UUID(), name: String, iconName: String, colorHex: String, countsForREPS: Bool = true) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.countsForREPS = countsForREPS
    }
}

// MARK: - Category Manager
class CategoryManager: ObservableObject {
    static let shared = CategoryManager()
    
    @Published var customCategories: [CustomCategory] = []
    
    private let userDefaultsKey = "customCategories"
    
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

@main
struct LandlordHoursApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var categoryManager = CategoryManager.shared

    init() {
        // Tab bar
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor.systemBackground
        tabBar.shadowImage = UIImage()
        tabBar.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        UITabBar.appearance().tintColor = UIColor(AppColors.primary)

        // Navigation bar
        let navBar = UINavigationBarAppearance()
        navBar.configureWithTransparentBackground()
        navBar.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(categoryManager)
        }
    }
}

// MARK: - View Modifier for Adaptive Colors
struct AdaptiveColorModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var isBackground: Bool = false
    var isSecondary: Bool = false
    var isTertiary: Bool = false
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(
                colorScheme == .dark ? 
                    (isTertiary ? AppColors.darkTextTertiary : 
                     isSecondary ? AppColors.darkTextSecondary : 
                     AppColors.darkTextPrimary) :
                    (isTertiary ? AppColors.textTertiary : 
                     isSecondary ? AppColors.textSecondary : 
                     AppColors.textPrimary)
            )
    }
}

extension View {
    func adaptiveText(isSecondary: Bool = false, isTertiary: Bool = false) -> some View {
        modifier(AdaptiveColorModifier(isSecondary: isSecondary, isTertiary: isTertiary))
    }
}

// Use this in views instead of hardcoded colors
extension View {
    func adaptiveBackground(_ colorScheme: ColorScheme) -> some View {
        self.background(colorScheme == .dark ? AppColors.darkBackground : AppColors.background)
    }
}

// MARK: - Adaptive Card Modifier
private struct AdaptiveCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark ? AppColors.darkBackgroundSecondary : AppColors.backgroundSecondary)
    }
}

extension View {
    func adaptiveCard() -> some View {
        modifier(AdaptiveCardModifier())
    }
}
