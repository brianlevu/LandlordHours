import SwiftUI
import AuthenticationServices
import Combine
import LucideIcons
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "Auth")

@available(iOS 16.0, *)
struct AppleSignInButton: View {
    let onCompletion: (_ isNewUser: Bool) -> Void
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
                    let isNewUser = UserDefaults.standard.string(forKey: "appleUserId") != userId
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
                    errorMessage = "Apple Sign In isn't available right now. Please use email sign-up or make sure you're signed into your Apple ID in Settings."
                    showError = true
                }
                logger.error("Apple Sign-In failed: \(error.localizedDescription)")
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
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
    case email
}

enum AdminAccess {
    static let adminEmails: Set<String> = ["brianlevu@gmail.com"]

    static var currentEmail: String? {
        UserDefaults.standard.string(forKey: "appleUserEmail")
        ?? UserDefaults.standard.string(forKey: "emailUserEmail")
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
        if let userId = UserDefaults.standard.string(forKey: "appleUserId") {
            self.userId = userId
            self.isSignedIn = true
            self.fullName = UserDefaults.standard.string(forKey: "appleUserName")
            self.email = UserDefaults.standard.string(forKey: "appleUserEmail")
            self.profileImageData = UserDefaults.standard.data(forKey: UserScope.key("profileImageData"))
            if let typeRaw = UserDefaults.standard.string(forKey: "loginType"),
               let type = LoginType(rawValue: typeRaw) {
                self.loginType = type
            }
        } else if let emailUserId = UserDefaults.standard.string(forKey: "emailUserId") {
            self.userId = emailUserId
            self.isSignedIn = true
            self.fullName = UserDefaults.standard.string(forKey: "emailUserName")
            self.email = UserDefaults.standard.string(forKey: "emailUserEmail")
            self.profileImageData = UserDefaults.standard.data(forKey: UserScope.key("profileImageData"))
            self.loginType = .email
        }
    }
    
    func signInWithEmail(email: String, password: String, name: String) {
        // Use a deterministic userId based on email so the same account always
        // maps to the same data scope (no random UUID that changes every login)
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let userId = "email-" + normalizedEmail
        UserDefaults.standard.set(userId, forKey: "emailUserId")
        UserDefaults.standard.set(email, forKey: "emailUserEmail")
        if !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "emailUserName")
        }
        UserDefaults.standard.set(LoginType.email.rawValue, forKey: "loginType")

        self.userId = userId
        self.email = email
        if !name.isEmpty {
            self.fullName = name
        }
        self.isSignedIn = true
        self.loginType = .email
    }
    
    func updateProfile(name: String?, email: String?, imageData: Data?) {
        if let name = name {
            fullName = name
            if loginType == .apple {
                UserDefaults.standard.set(name, forKey: "appleUserName")
            } else {
                UserDefaults.standard.set(name, forKey: "emailUserName")
            }
        }
        
        if let email = email {
            self.email = email
            if loginType == .apple {
                UserDefaults.standard.set(email, forKey: "appleUserEmail")
            } else {
                UserDefaults.standard.set(email, forKey: "emailUserEmail")
            }
        }
        
        if let imageData = imageData {
            profileImageData = imageData
            UserDefaults.standard.set(imageData, forKey: UserScope.key("profileImageData"))
        }
    }
    
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
        UserDefaults.standard.removeObject(forKey: "emailUserId")
        UserDefaults.standard.removeObject(forKey: "emailUserName")
        UserDefaults.standard.removeObject(forKey: "emailUserEmail")
        UserDefaults.standard.removeObject(forKey: "loginType")
        
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
    @State private var showCreateAccount = false
    @State private var showEmailLogin = false

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
            .navigationDestination(isPresented: $showCreateAccount) {
                EmailSignUpView()
            }
            .sheet(isPresented: $showEmailLogin) {
                EmailLoginSheetView()
            }
            .onAppear {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.35).delay(0.08)) {
                    appeared = true
                }
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
            .frame(height: 54)

            HStack(spacing: 12) {
                Button {
                    showEmailLogin = true
                } label: {
                    Text("Log in")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(colors.backgroundSecondary)
                        .foregroundStyle(colors.textPrimary)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(colors.border.opacity(0.45), lineWidth: 1)
                        }
                }

                Button {
                    showCreateAccount = true
                } label: {
                    Text("Create account")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(colors.action)
                        .foregroundStyle(AppColors.onAction)
                        .clipShape(Capsule())
                }
            }
        }
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

// MARK: - Email Login Sheet (for "Already have an account?")

struct EmailLoginSheetView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WaveHouseIcon(size: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: AppColors.primary.opacity(0.25), radius: 8, y: 3)
                        .padding(.top, 8)

                    Text("Welcome back")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(AppColors.charcoal)

                    VStack(spacing: 16) {
                        loginFormField(label: "Email", placeholder: "your@email.com", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                        loginSecureField(label: "Password", placeholder: "Password", text: $password)
                    }

                    if !errorMessage.isEmpty {
                        HStack(spacing: 6) {
                            LucideIcon(image: Lucide.circleAlert, size: 14)
                                .foregroundStyle(AppColors.error)
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.error)
                        }
                    }

                    Button {
                        guard !email.isEmpty, !password.isEmpty else {
                            errorMessage = "Enter both email and password."
                            return
                        }
                        guard email.contains("@") && email.contains(".") else {
                            errorMessage = "Please enter a valid email address"
                            return
                        }
                        guard password.count >= 6 else {
                            errorMessage = "Password must be at least 6 characters"
                            return
                        }
                        AppleSignInManager.shared.signInWithEmail(email: email, password: password, name: "")
                        viewModel.signIn()
                        dismiss()
                    } label: {
                        Text("Log In")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.primary)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: AppColors.primary.opacity(0.3), radius: 8, y: 3)
                    }
                    .padding(.top, 8)
                }
                .padding(AppSpacing.xl)
            }
            .background(AppColors.background)
            .navigationTitle("Log In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
    }

    private func loginFormField(label: String, placeholder: String, text: Binding<String>, contentType: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.slate)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .emailAddress ? .none : .words)
                .font(.system(size: 16, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppColors.snow)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
    }

    private func loginSecureField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.slate)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(.password)
                .font(.system(size: 16, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppColors.snow)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
    }
}

// MARK: - Email Sign Up View (Redesigned)

struct EmailSignUpView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                WaveHouseIcon(size: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: AppColors.primary.opacity(0.25), radius: 8, y: 3)
                    .padding(.top, 8)

                Text("Create Account")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(AppColors.charcoal)

                // Form fields
                VStack(spacing: 16) {
                    formField(label: "Name", placeholder: "Your name", text: $name, contentType: .name)
                    formField(label: "Email", placeholder: "your@email.com", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                    secureFormField(label: "Password", placeholder: "Password", text: $password)
                    secureFormField(label: "Confirm Password", placeholder: "Confirm password", text: $confirmPassword)
                }

                if !errorMessage.isEmpty {
                    HStack(spacing: 6) {
                        LucideIcon(image: Lucide.circleAlert, size: 14)
                            .foregroundStyle(AppColors.error)
                        Text(errorMessage)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.error)
                    }
                }

                Button {
                    if password != confirmPassword {
                        errorMessage = "Passwords don't match"
                        return
                    }
                    if password.count < 6 {
                        errorMessage = "Password must be at least 6 characters"
                        return
                    }
                    if name.isEmpty || email.isEmpty {
                        errorMessage = "Enter your name and email."
                        return
                    }
                    guard email.contains("@") && email.contains(".") else {
                        errorMessage = "Please enter a valid email address"
                        return
                    }

                    AppleSignInManager.shared.signInWithEmail(email: email, password: password, name: name)
                    viewModel.signUp()
                } label: {
                    Text("Create Account")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColors.primary)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: AppColors.primary.opacity(0.3), radius: 8, y: 3)
                }
                .padding(.top, 8)
            }
            .padding(AppSpacing.xl)
        }
        .background(colors.background)
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formField(label: String, placeholder: String, text: Binding<String>, contentType: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .emailAddress ? .none : .words)
                .font(.system(size: 16, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
    }

    private func secureFormField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(colors.textSecondary)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(.newPassword)
                .font(.system(size: 16, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
    }
}
