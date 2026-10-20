import SwiftUI
import AuthenticationServices
import Combine
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "Auth")

/// Sign in with Apple's result, applied to the device's sign-in keys. Shared by Welcome's small
/// "Sign in with Apple" button.
enum AppleSignInFlow {
    enum Outcome: Equatable {
        /// Signed in. `isNewUser`: this Apple ID never finished setup on this device.
        case signedIn(isNewUser: Bool)
        case cancelled
        case failed
    }

    static let failureMessage = "Sign in with Apple isn't available right now. You can start without an account, or check that you're signed in to your Apple Account in Settings."

    static func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    static func complete(_ result: Result<ASAuthorization, Error>) -> Outcome {
        switch result {
        case .success(let authorization):
            guard let appleIdCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return .failed }
            let userId = appleIdCredential.user
            // "New" means this Apple ID has never finished setup on this device — not merely
            // "not the currently stored ID" (a returning user who switched profiles must not be
            // sent through onboarding again).
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
            return .signedIn(isNewUser: isNewUser)
        case .failure(let error):
            logger.error("Apple Sign-In failed: \(error.localizedDescription)")
            // Code 1001 = user cancelled — don't show an error.
            return (error as NSError).code == 1001 ? .cancelled : .failed
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
