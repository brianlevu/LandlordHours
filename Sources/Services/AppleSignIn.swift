import SwiftUI
import AuthenticationServices

@available(iOS 16.0, *)
struct AppleSignInButton: View {
    let onCompletion: () -> Void
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

                    onCompletion()
                }
            case .failure(let error):
                let nsError = error as NSError
                // Code 1001 = user cancelled — don't show an error
                if nsError.code != 1001 {
                    errorMessage = "Apple Sign In isn't available right now. Please use email sign-up or make sure you're signed into your Apple ID in Settings."
                    showError = true
                }
                print("Apple Sign-In failed: \(error.localizedDescription)")
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
            self.profileImageData = UserDefaults.standard.data(forKey: "profileImageData")
            if let typeRaw = UserDefaults.standard.string(forKey: "loginType"),
               let type = LoginType(rawValue: typeRaw) {
                self.loginType = type
            }
        } else if let emailUserId = UserDefaults.standard.string(forKey: "emailUserId") {
            self.userId = emailUserId
            self.isSignedIn = true
            self.fullName = UserDefaults.standard.string(forKey: "emailUserName")
            self.email = UserDefaults.standard.string(forKey: "emailUserEmail")
            self.profileImageData = UserDefaults.standard.data(forKey: "profileImageData")
            self.loginType = .email
        }
    }
    
    func signInWithEmail(email: String, password: String, name: String) {
        let userId = UUID().uuidString
        UserDefaults.standard.set(userId, forKey: "emailUserId")
        UserDefaults.standard.set(email, forKey: "emailUserEmail")
        UserDefaults.standard.set(name, forKey: "emailUserName")
        UserDefaults.standard.set(LoginType.email.rawValue, forKey: "loginType")
        
        self.userId = userId
        self.email = email
        self.fullName = name
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
            UserDefaults.standard.set(imageData, forKey: "profileImageData")
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

struct LoginView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var showLogin: Bool
    @State private var showEmailLogin = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Custom logo
                LHLogo(size: 96, showText: true, animated: true)
                    .padding(.bottom, 8)

                Text("Track your path to tax qualification")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.bottom, 8)

                Spacer()

                // Sign in buttons
                VStack(spacing: 14) {
                    if #available(iOS 16.0, *) {
                        AppleSignInButton {
                            viewModel.signIn()
                            showLogin = false
                        }
                    } else {
                        Button(action: {
                            viewModel.signIn()
                            showLogin = false
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18))
                                Text("Sign in with Apple")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button {
                        showEmailLogin = true
                    } label: {
                        HStack(spacing: 10) {
                            LHIconView(icon: .envelope, size: 18, color: .white)
                            Text("Sign up with Email")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [AppColors.primary.opacity(0.9), AppColors.primary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: AppColors.primary.opacity(0.3), radius: 8, y: 3)
                    }
                }
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                Text("Sign in to sync your data across devices")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Spacer()
                    .frame(height: 60)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background)
            .navigationDestination(isPresented: $showEmailLogin) {
                EmailSignUpView(showLogin: $showLogin)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    appeared = true
                }
            }
        }
    }
}

struct EmailSignUpView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var showLogin: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                LHCompactLogo(size: 48)
                    .padding(.top, 8)

                Text("Create Account")
                    .font(.system(size: 26, weight: .bold))

                // Form fields
                VStack(spacing: 16) {
                    formField(label: "Name", placeholder: "Your name", text: $name, contentType: .name)
                    formField(label: "Email", placeholder: "your@email.com", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
                    secureFormField(label: "Password", placeholder: "Password", text: $password)
                    secureFormField(label: "Confirm Password", placeholder: "Confirm password", text: $confirmPassword)
                }

                if !errorMessage.isEmpty {
                    HStack(spacing: 6) {
                        LHIconView(icon: .info, size: 14, color: AppColors.error)
                        Text(errorMessage)
                            .font(.system(size: 13))
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

                    AppleSignInManager.shared.signInWithEmail(email: email, password: password, name: name)
                    viewModel.signIn()
                    showLogin = false
                } label: {
                    Text("Create Account")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [AppColors.primary.opacity(0.9), AppColors.primary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: AppColors.primary.opacity(0.3), radius: 8, y: 3)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formField(label: String, placeholder: String, text: Binding<String>, contentType: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .emailAddress ? .none : .words)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func secureFormField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .textContentType(.newPassword)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
