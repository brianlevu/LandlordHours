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
    @State private var selectedSlide = 0

    private let carouselTimer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                wiseBackground

                VStack(spacing: 0) {
                    progressBar
                        .padding(.top, 56)

                    TabView(selection: $selectedSlide) {
                        ForEach(Array(LandlordWelcomeSlide.allCases.enumerated()), id: \.offset) { index, slide in
                            welcomeSlide(slide)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(AppAnimation.standard, value: selectedSlide)

                    authActions
                        .padding(.horizontal, 24)
                        .padding(.bottom, 34)
                }
                .opacity(appeared ? 1 : 0)
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
            .onReceive(carouselTimer) { _ in
                guard !reduceMotion else { return }
                withAnimation(AppAnimation.standard) {
                    selectedSlide = (selectedSlide + 1) % LandlordWelcomeSlide.allCases.count
                }
            }
        }
    }

    private var wiseBackground: some View {
        Color.white
            .ignoresSafeArea()
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.cloud.opacity(0.35))
                    .frame(height: 5)

                Capsule()
                    .fill(AppColors.charcoal)
                    .frame(width: proxy.size.width * progressFraction, height: 5)
                    .animation(AppAnimation.standard, value: selectedSlide)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 32)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(selectedSlide + 1) of \(LandlordWelcomeSlide.allCases.count)")
    }

    private var progressFraction: CGFloat {
        CGFloat(selectedSlide + 1) / CGFloat(LandlordWelcomeSlide.allCases.count)
    }

    private func welcomeSlide(_ slide: LandlordWelcomeSlide) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 22)

            Image(slide.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 278)
                .frame(height: 342)
                .accessibilityHidden(true)

            Spacer(minLength: 20)

            VStack(spacing: 14) {
                Text(slide.title)
                    .font(.system(size: 43, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.charcoal)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-4)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 18)

                Text(slide.subtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.slate)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
            }

            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slide.title). \(slide.subtitle)")
    }

    private var authActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    showEmailLogin = true
                } label: {
                    Text("Log in")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(colors.primary)
                        .foregroundStyle(AppColors.charcoal)
                        .clipShape(Capsule())
                }

                Button {
                    showCreateAccount = true
                } label: {
                    Text("Register")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(colors.primary)
                        .foregroundStyle(AppColors.charcoal)
                        .clipShape(Capsule())
                }
            }

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
                            .font(.system(size: 19))
                        Text("Sign in with Apple")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
        }
    }
}

private enum LandlordWelcomeSlide: CaseIterable {
    case qualification
    case logging
    case records

    var title: String {
        switch self {
        case .qualification: return "KNOW WHAT HOURS COUNT"
        case .logging: return "TRACK RENTAL WORK FAST"
        case .records: return "KEEP TAX RECORDS READY"
        }
    }

    var subtitle: String {
        switch self {
        case .qualification: return "Track REPS, material participation, and the 50% rule without decoding the tax tests every time."
        case .logging: return "Save the property, category, participant, date, and notes while the work is still fresh."
        case .records: return "Build a clean year-end history your CPA can review."
        }
    }

    var imageName: String {
        switch self {
        case .qualification: return "OnboardingHeroQualification"
        case .logging: return "OnboardingHeroLogging"
        case .records: return "OnboardingHeroRecords"
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
