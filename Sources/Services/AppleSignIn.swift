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

    static let failureMessage = "Sign in with Apple isn’t available right now. You can start without an account, or check that you’re signed in to your Apple Account in Settings."

    static func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    /// Applies one Apple authorization. Apple sends the name and email only the first time, so a
    /// later sign-in arrives with nil for both: that must never erase what is stored. A value the
    /// user edited in Profile is never replaced by Apple's; otherwise Apple's fills it in.
    static func record(userId: String, givenName: String?, familyName: String?, email: String?,
                       defaults: UserDefaults = .standard) -> Outcome {
        // "New" means this Apple ID has never finished setup on this device — not merely
        // "not the currently stored ID" (a returning user who switched profiles must not be
        // sent through onboarding again).
        let isNewUser = !defaults.bool(forKey: UserScope.key("hasCompletedOnboarding", userId: userId))
        let liveId = defaults.string(forKey: ProfileKeys.appleUserId)
        defaults.set(userId, forKey: ProfileKeys.appleUserId)

        var stored = ProfileIdentity.saved(userId: userId, defaults: defaults)
        // Live keys of this same Apple ID (signed in before this build stashed a copy).
        if liveId == userId {
            stored.name = stored.name ?? ProfileIdentity.clean(defaults.string(forKey: ProfileKeys.appleUserName))
            stored.email = stored.email ?? ProfileIdentity.clean(defaults.string(forKey: ProfileKeys.appleUserEmail))
        }
        let appleName = ProfileIdentity.clean([givenName, familyName].compactMap { $0 }.joined(separator: " "))
        let appleEmail = ProfileIdentity.clean(email)
        let name = stored.edited ? (stored.name ?? appleName) : (appleName ?? stored.name)
        let mail = stored.edited ? (stored.email ?? appleEmail) : (appleEmail ?? stored.email)
        if let name { defaults.set(name, forKey: ProfileKeys.appleUserName) }
        if let mail { defaults.set(mail, forKey: ProfileKeys.appleUserEmail) }
        ProfileIdentity.remember(userId: userId, name: name, email: mail, edited: false, defaults: defaults)

        let manager = AppleSignInManager.shared
        manager.userId = userId
        manager.isSignedIn = true
        manager.loginType = .apple
        manager.fullName = name
        manager.email = mail
        return .signedIn(isNewUser: isNewUser)
    }

    static func complete(_ result: Result<ASAuthorization, Error>) -> Outcome {
        switch result {
        case .success(let authorization):
            guard let appleIdCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return .failed }
            let name = appleIdCredential.fullName.map { [$0.givenName, $0.familyName].compactMap { $0 }.joined(separator: " ") }
            return record(userId: appleIdCredential.user, givenName: name, familyName: nil, email: appleIdCredential.email)
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
        ProfileIdentity.hydrateActive(defaults)
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

        var edited = false
        if let name = ProfileIdentity.clean(name) {
            edited = edited || name != ProfileIdentity.clean(fullName)
            fullName = name
            defaults.set(name, forKey: nameKey)
        }

        if let email = ProfileIdentity.clean(email) {
            edited = edited || email != ProfileIdentity.clean(self.email)
            self.email = email
            defaults.set(email, forKey: emailKey)
        }
        if let id = userId {
            ProfileIdentity.remember(userId: id, name: fullName, email: self.email, edited: edited, defaults: defaults)
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
