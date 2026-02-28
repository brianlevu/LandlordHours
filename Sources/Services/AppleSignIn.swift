import SwiftUI
import AuthenticationServices
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
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var appeared = false
    @State private var showCreateAccount = false
    @State private var showEmailLogin = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // Base background
                    colors.background.ignoresSafeArea()

                    // Top half: lavender gradient + floating glass cards
                    VStack(spacing: 0) {
                        ZStack {
                            // Lavender gradient background — adapts to dark mode
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(hex: "1A1535").opacity(0.6), Color(hex: "1C1A2E").opacity(0.5), colors.background]
                                    : [Color(hex: "C4B5FD").opacity(0.4), Color(hex: "DDD6FE").opacity(0.5), Color(hex: "EDE9FE").opacity(0.6), Color.white.opacity(0.85), Color.white],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            // Decorative blobs
                            Circle()
                                .fill(Color(hex: "7B68EE").opacity(0.12))
                                .frame(width: 200, height: 200)
                                .blur(radius: 50)
                                .offset(x: 60, y: -20)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                            Circle()
                                .fill(Color(hex: "B8AFFE").opacity(0.15))
                                .frame(width: 180, height: 180)
                                .blur(radius: 40)
                                .offset(x: -60, y: 40)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                            // Floating glass cards
                            floatingCards
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                        }
                        .frame(height: geo.size.height * 0.48)

                        Spacer()
                    }

                    // Bottom content: logo, headline, auth buttons
                    VStack(spacing: 0) {
                        Spacer()

                        loginContent
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 30)
                    }
                }
            }
            .navigationDestination(isPresented: $showCreateAccount) {
                EmailSignUpView()
            }
            .sheet(isPresented: $showEmailLogin) {
                EmailLoginSheetView()
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Floating Glass Cards

    private var floatingCards: some View {
        ZStack {
            // Card 1: REPS Progress — top-left, rotated -6deg
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "EDE8FF"))
                            .frame(width: 36, height: 36)
                        LucideIcon(image: Lucide.clock, size: 18)
                            .foregroundStyle(AppColors.primary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("REPS Progress")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.charcoal)
                        Text("262.5 of 750 hours")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AppColors.slate)
                    }
                }
                .padding(.bottom, 14)

                // Progress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.snow)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.primary, Color(hex: "B8AFFE")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 88, height: 6) // ~35%
                }
                .padding(.bottom, 8)

                // Category rows
                HStack(spacing: 8) {
                    Circle().fill(AppColors.coral).frame(width: 8, height: 8)
                    Text("Repairs").font(.system(size: 11, design: .rounded)).foregroundStyle(AppColors.slate)
                    Spacer()
                    Text("105.0h").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(AppColors.charcoal)
                }
                .padding(.bottom, 6)
                HStack(spacing: 8) {
                    Circle().fill(AppColors.sage).frame(width: 8, height: 8)
                    Text("Management").font(.system(size: 11, design: .rounded)).foregroundStyle(AppColors.slate)
                    Spacer()
                    Text("65.5h").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(AppColors.charcoal)
                }
            }
            .padding(24)
            .frame(width: 280)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: AppColors.primary.opacity(0.08), radius: 32, y: 8)
            .rotationEffect(.degrees(-6))
            .offset(x: -40, y: -30)

            // Card 2: Time Entry — top-right, rotated 4deg
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "FFE8E4"))
                            .frame(width: 36, height: 36)
                        LucideIcon(image: Lucide.wrench, size: 18)
                            .foregroundStyle(AppColors.coral)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("2.5h logged")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.charcoal)
                        Text("123 Oak St \u{2022} Today")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(AppColors.slate)
                    }
                }
                .padding(.bottom, 10)

                Text("Fixed leaky faucet and replaced bathroom fixtures")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AppColors.slate)
                    .lineSpacing(2)
            }
            .padding(20)
            .frame(width: 240)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: AppColors.primary.opacity(0.08), radius: 32, y: 8)
            .rotationEffect(.degrees(4))
            .offset(x: 50, y: 60)
        }
        .padding(.top, 40)
    }

    // MARK: - Login Content (bottom half)

    private var loginContent: some View {
        VStack(spacing: 0) {
            // Logo
            WaveHouseIcon(size: 56)
                .shadow(color: AppColors.primary.opacity(0.2), radius: 24, y: 8)
                .padding(.bottom, 20)

            // Headline
            Text("Track your hours.\nQualify with confidence.")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.bottom, 6)

            // Subline
            Text("750 hours to Real Estate Professional Status \u{2014} we make every hour count.")
                .font(.system(size: 15))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 32)

            // Auth buttons
            VStack(spacing: 12) {
                // Sign in with Apple
                if #available(iOS 16.0, *) {
                    AppleSignInButton { isNewUser in
                        if isNewUser {
                            viewModel.signUp()
                        } else {
                            viewModel.signIn()
                        }
                    }
                    .clipShape(Capsule())
                } else {
                    Button {
                        viewModel.signIn()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("Sign in with Apple")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.charcoal)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }

                // Continue with email
                Button {
                    showCreateAccount = true
                } label: {
                    Text("Continue with email")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(AppColors.primary)
                        .overlay(
                            Capsule()
                                .stroke(AppColors.primary, lineWidth: 2)
                        )
                }
            }
            .padding(.bottom, 12)

            // Already have an account link
            HStack(spacing: 0) {
                Text("Already have an account? ")
                    .foregroundStyle(colors.textSecondary)
                Button {
                    showEmailLogin = true
                } label: {
                    Text("Log in here")
                        .foregroundStyle(AppColors.primary)
                        .fontWeight(.semibold)
                        .underline(true, color: AppColors.primary)
                }
            }
            .font(.system(size: 14))
            .padding(.bottom, 60)
        }
        .padding(.horizontal, 28)
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
                            errorMessage = "Please fill in all fields"
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
                        errorMessage = "Please fill in all fields"
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
