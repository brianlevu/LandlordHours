import SwiftUI
import AuthenticationServices
import Combine
import LucideIcons
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "Auth")

@available(iOS 16.0, *)
struct AppleSignInButton: View {
    let onCompletion: (_ isNewUser: Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                if let appleIdCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    let userId = appleIdCredential.user
                    // "New" means this Apple ID has never finished setup on this device — not
                    // merely "not the currently stored ID" (a returning user who switched
                    // profiles must not be sent through onboarding again).
                    let isNewUser = !UserDefaults.standard.bool(
                        forKey: UserScope.key("hasCompletedOnboarding", userId: userId)
                    )
                    UserDefaults.standard.set(userId, forKey: "appleUserId")

                    AppleSignInManager.shared.userId = userId
                    AppleSignInManager.shared.isSignedIn = true
                    AppleSignInManager.shared.loginType = .apple

                    if let fullName = appleIdCredential.fullName {
                        let name = [fullName.givenName, fullName.familyName]
                            .compactMap { $0 }
                            .joined(separator: " ")
                        if !name.isEmpty {
                            AppleSignInManager.shared.fullName = name
                            UserDefaults.standard.set(name, forKey: "appleUserName")
                        }
                    }

                    if let email = appleIdCredential.email {
                        AppleSignInManager.shared.email = email
                        UserDefaults.standard.set(email, forKey: "appleUserEmail")
                    } else if let existingEmail = UserDefaults.standard.string(forKey: "appleUserEmail") {
                        AppleSignInManager.shared.email = existingEmail
                    }

                    onCompletion(isNewUser)
                }
            case .failure(let error):
                let nsError = error as NSError
                // Code 1001 = user cancelled — don't show an error
                if nsError.code != 1001 {
                    errorMessage = "Sign in with Apple isn't available right now. You can continue without an account, or check that you're signed in to your Apple Account in Settings."
                    showError = true
                }
                logger.error("Apple Sign-In failed: \(error.localizedDescription)")
            }
        }
        // Black on light, white on dark: a black button on the dark canvas measured 1.11:1.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .id(colorScheme)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }
}

enum LoginType: String, Codable {
    case apple
    /// Legacy ≤1.0.6 email "account". Still decodes; migrated to `.local` at launch.
    case email
    /// 1.1 local profile (no account): `local-<UUID>` or a migrated `email-…` ID.
    case local
}

enum AdminAccess {
    static let adminEmails: Set<String> = ["brianlevu@gmail.com"]

    static var currentEmail: String? {
        UserDefaults.standard.string(forKey: ProfileKeys.appleUserEmail)
        ?? UserDefaults.standard.string(forKey: ProfileKeys.localProfileEmail)
        ?? UserDefaults.standard.string(forKey: ProfileKeys.emailUserEmail)
        ?? AppleSignInManager.shared.email
    }

    static var isCurrentUserAdmin: Bool {
        guard let email = currentEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return adminEmails.contains(email)
    }
}

class AppleSignInManager: ObservableObject {
    static let shared = AppleSignInManager()
    
    @Published var isSignedIn = false
    @Published var userId: String?
    @Published var fullName: String?
    @Published var email: String?
    @Published var profileImageData: Data?
    @Published var loginType: LoginType = .apple
    
    private init() {
        checkExistingSignIn()
    }
    
    func checkExistingSignIn() {
        let defaults = UserDefaults.standard
        if let userId = defaults.string(forKey: ProfileKeys.appleUserId) {
            self.userId = userId
            self.isSignedIn = true
            self.fullName = defaults.string(forKey: ProfileKeys.appleUserName)
            self.email = defaults.string(forKey: ProfileKeys.appleUserEmail)
            self.loginType = .apple
        } else if let localId = defaults.string(forKey: ProfileKeys.localProfileId) {
            self.userId = localId
            self.isSignedIn = true
            self.fullName = defaults.string(forKey: ProfileKeys.localProfileName)
            self.email = defaults.string(forKey: ProfileKeys.localProfileEmail)
            self.loginType = .local
        } else if let emailUserId = defaults.string(forKey: ProfileKeys.emailUserId) {
            // Legacy fallback: only seen before `ProfileMigration` has run.
            self.userId = emailUserId
            self.isSignedIn = true
            self.fullName = defaults.string(forKey: ProfileKeys.emailUserName)
            self.email = defaults.string(forKey: ProfileKeys.emailUserEmail)
            self.loginType = .email
        } else {
            userId = nil
            fullName = nil
            email = nil
            profileImageData = nil
            isSignedIn = false
            return
        }
        self.profileImageData = defaults.data(forKey: UserScope.key("profileImageData"))
    }

    func updateProfile(name: String?, email: String?, imageData: Data?) {
        let defaults = UserDefaults.standard
        let nameKey: String
        let emailKey: String
        switch loginType {
        case .apple:
            nameKey = ProfileKeys.appleUserName
            emailKey = ProfileKeys.appleUserEmail
        case .local:
            nameKey = ProfileKeys.localProfileName
            emailKey = ProfileKeys.localProfileEmail
        case .email:
            nameKey = ProfileKeys.emailUserName
            emailKey = ProfileKeys.emailUserEmail
        }

        if let name = name {
            fullName = name
            defaults.set(name, forKey: nameKey)
        }

        if let email = email {
            self.email = email
            defaults.set(email, forKey: emailKey)
        }

        if let imageData = imageData {
            profileImageData = imageData
            defaults.set(imageData, forKey: UserScope.key("profileImageData"))
        }
    }

    func signOut() {
        for key in ProfileKeys.signOutKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        userId = nil
        fullName = nil
        email = nil
        profileImageData = nil
        isSignedIn = false
    }
}

// MARK: - Login View (Redesigned — matches B. Login from onboarding-full.html)

struct LoginView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var appeared = false
    @State private var restorableProfiles: [DiscoveredProfile] = []
    @State private var showRestoreSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                welcomeBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        welcomeHero
                            .padding(.top, 22)

                        welcomeMoment

                        Spacer(minLength: 18)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 190)
                }
                .opacity(appeared ? 1 : 0)
            }
            .safeAreaInset(edge: .bottom) {
                authActions
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .background {
                        LinearGradient(
                            colors: [
                                colors.background.opacity(0),
                                colors.background.opacity(colorScheme == .dark ? 0.96 : 0.98),
                                colors.background
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    }
            }
            .sheet(isPresented: $showRestoreSheet) {
                ProfileRestoreSheet(profiles: restorableProfiles, context: .welcome) { profile in
                    showRestoreSheet = false
                    viewModel.switchToProfile(profile)
                }
                .environmentObject(viewModel)
            }
            .onAppear {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.35).delay(0.08)) {
                    appeared = true
                }
            }
            .task {
                restorableProfiles = await viewModel.discoverRestorableProfiles()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-LHOpenRestoreSheet"), !restorableProfiles.isEmpty {
                    showRestoreSheet = true
                }
                #endif
            }
        }
    }

    private var welcomeBackground: some View {
        ZStack {
            colors.background

            LinearGradient(
                colors: colorScheme == .dark
                    ? [AppColors.darkPlum.opacity(0.82), AppColors.darkBackground, AppColors.darkInk]
                    : [AppColors.lavenderPale, AppColors.background, Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
            .ignoresSafeArea()
    }

    private var welcomeHero: some View {
        VStack(spacing: 16) {
            WaveHouseIcon(size: 82)
                .shadow(color: colors.primary.opacity(colorScheme == .dark ? 0.30 : 0.22), radius: 22, y: 12)
                .scaleEffect(appeared ? 1 : 0.94)

            VStack(spacing: 10) {
                (
                    Text("Landlord")
                        .foregroundStyle(colors.textPrimary)
                    +
                    Text("Hours")
                        .foregroundStyle(colors.primary)
                )
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .accessibilityLabel("LandlordHours")

                Text("Turn property work into tax-ready hours.")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Speak, type, or tap. LandlordHours keeps the record ready for review.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }

    private var welcomeMoment: some View {
        ZStack {
            WelcomeTrailShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            colors.primary.opacity(colorScheme == .dark ? 0.74 : 0.62),
                            colors.informational.opacity(colorScheme == .dark ? 0.54 : 0.42),
                            colors.positive.opacity(colorScheme == .dark ? 0.52 : 0.38)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 0.2)
                .opacity(0.88)

            WelcomeTrailShape()
                .stroke(
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.32),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                )

            VStack(spacing: 14) {
                HStack {
                    landingProofPill(icon: Lucide.mic, text: "Voice note")
                    Spacer(minLength: 0)
                    landingProofPill(icon: Lucide.sparkles, text: "Auto-filled")
                }

                HStack(alignment: .center, spacing: 15) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Porch repair")
                            .font(.system(size: 21, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text("Oak Street • Today")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("1.0h")
                            .font(.system(size: 33, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            LucideIcon(image: Lucide.check, size: 13)
                                .foregroundStyle(colors.positive)
                            Text("Repairs")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.54 : 0.50))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.34), lineWidth: 1)
                }
                .shadow(color: colors.primary.opacity(colorScheme == .dark ? 0.16 : 0.11), radius: 16, y: 10)
                .landingGlassPanel(colors: colors, colorScheme: colorScheme)

                HStack {
                    landingProofPill(icon: Lucide.building2, text: "Property")
                    Spacer(minLength: 0)
                    landingProofPill(icon: Lucide.fileText, text: "Review-ready")
                }
            }
        }
        .frame(height: 202)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example entry: one hour of Oak Street porch repair captured and ready for review.")
    }

    private func landingProofPill(icon: UIImage, text: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(image: icon, size: 13)
                .foregroundStyle(colors.primary)
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.38), lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: colors.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 10, y: 5)
        .landingGlassCapsule(colors: colors, colorScheme: colorScheme)
    }

    private var authActions: some View {
        VStack(spacing: 11) {
            AppleSignInButton { isNewUser in
                if isNewUser {
                    viewModel.signUp()
                } else {
                    viewModel.signIn()
                }
            }
            .clipShape(Capsule())
            .frame(height: 52)
            .accessibilityIdentifier("welcome.signInWithApple")

            Button {
                viewModel.continueWithoutAccount()
            } label: {
                Text("Continue without an account")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(colors.action)
                    .foregroundStyle(AppColors.onAction)
                    .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("welcome.continueWithoutAccount")

            if !restorableProfiles.isEmpty {
                Button {
                    showRestoreSheet = true
                } label: {
                    HStack(spacing: 10) {
                        LucideIcon(image: Lucide.history, size: 16)
                            .foregroundStyle(colors.action)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Restore earlier data")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                            Text(restoreSummary)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        LucideIcon(image: Lucide.chevronRight, size: 14)
                            .foregroundStyle(colors.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppCornerRadius.large, style: .continuous)
                            .strokeBorder(colors.border.opacity(0.45), lineWidth: 1)
                    }
                }
                .buttonStyle(.lhPressable)
                .accessibilityIdentifier("welcome.restoreEarlierData")
            }

            Text("Hours, properties and settings sync to your iCloud. Photos stay on this iPhone.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var restoreSummary: String {
        let count = restorableProfiles.count
        return count == 1 ? "1 earlier profile found" : "\(count) earlier profiles found"
    }
}

private struct WelcomeTrailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.30))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.26),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.54)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.74),
            control1: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.04),
            control2: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.94)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.76),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.46),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.96)
        )
        return path
    }
}

private extension View {
    @ViewBuilder
    func landingGlassPanel(colors: AdaptiveColors, colorScheme: ColorScheme) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(colors.actionSurface.opacity(colorScheme == .dark ? 0.14 : 0.26)),
                in: .rect(cornerRadius: 26)
            )
        } else {
            self
        }
    }

    @ViewBuilder
    func landingGlassCapsule(colors: AdaptiveColors, colorScheme: ColorScheme) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(colors.actionSurface.opacity(colorScheme == .dark ? 0.12 : 0.20)),
                in: .rect(cornerRadius: 999)
            )
        } else {
            self
        }
    }

}
