import XCTest
@testable import LandlordHours

/// fix/2.0.1-signin: "I updated my profile, signed out and signed in again with Apple, and the
/// name and email were wiped." Apple sends name and email only on the first authorization, and
/// sign-out used to delete the only copy (global `appleUserName` / `appleUserEmail`).
@MainActor
final class ProfileIdentityTests: XCTestCase {
    private let appleId = "001234.profileidentity.test"
    private var snapshot = AuthStateSnapshot()

    override func setUp() {
        super.setUp()
        snapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        clearScoped()
    }

    override func tearDown() {
        clearScoped()
        snapshot.restore()
        AppleSignInManager.shared.checkExistingSignIn()
        super.tearDown()
    }

    private func clearScoped() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("u.\(appleId).") {
            defaults.removeObject(forKey: key)
        }
    }

    /// The first Apple authorization: Apple supplies the name and email.
    private func firstAppleSignIn() {
        _ = AppleSignInFlow.record(userId: appleId, givenName: "Apple", familyName: "Given", email: "relay@privaterelay.appleid.com")
        AppleSignInManager.shared.checkExistingSignIn()
    }

    /// A later authorization: Apple sends nothing.
    private func returningAppleSignIn() {
        _ = AppleSignInFlow.record(userId: appleId, givenName: nil, familyName: nil, email: nil)
        AppleSignInManager.shared.checkExistingSignIn()
    }

    private let photo = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])

    func testEditedProfileSurvivesSignOutAndReturningAppleSignIn() {
        let vm = AppViewModel()
        firstAppleSignIn()
        AppleSignInManager.shared.updateProfile(name: "Brian Le Vu", email: "brian@example.com", imageData: photo)

        vm.signOut()
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.appleUserName), "sign-out still clears the live keys")

        returningAppleSignIn()
        let manager = AppleSignInManager.shared
        XCTAssertEqual(manager.fullName, "Brian Le Vu")
        XCTAssertEqual(manager.email, "brian@example.com")
        XCTAssertEqual(manager.profileImageData, photo)
        XCTAssertEqual(UserDefaults.standard.string(forKey: ProfileKeys.appleUserName), "Brian Le Vu")
        XCTAssertEqual(AppViewModel.resolvedProfileName(), "Brian Le Vu", "never falls back to \"User\"")
    }

    func testAppleNameSurvivesSignOutWhenNeverEdited() {
        let vm = AppViewModel()
        firstAppleSignIn()
        vm.signOut()
        returningAppleSignIn()
        XCTAssertEqual(AppleSignInManager.shared.fullName, "Apple Given")
        XCTAssertEqual(AppleSignInManager.shared.email, "relay@privaterelay.appleid.com")
    }

    func testUserEditWinsOverALaterAppleValue() {
        firstAppleSignIn()
        AppleSignInManager.shared.updateProfile(name: "Brian Le Vu", email: "brian@example.com", imageData: nil)
        _ = AppleSignInFlow.record(userId: appleId, givenName: "Other", familyName: "Name", email: "other@example.com")
        AppleSignInManager.shared.checkExistingSignIn()
        XCTAssertEqual(AppleSignInManager.shared.fullName, "Brian Le Vu")
        XCTAssertEqual(AppleSignInManager.shared.email, "brian@example.com")
    }

    func testAppleValueFillsAnUneditedProfile() {
        firstAppleSignIn()
        _ = AppleSignInFlow.record(userId: appleId, givenName: "New", familyName: "Name", email: "new@example.com")
        AppleSignInManager.shared.checkExistingSignIn()
        XCTAssertEqual(AppleSignInManager.shared.fullName, "New Name")
        XCTAssertEqual(AppleSignInManager.shared.email, "new@example.com")
    }

    func testEmptyAndUserFallbackNeverOverwriteStoredValues() {
        let defaults = UserDefaults(suiteName: "ProfileIdentityTests.\(UUID().uuidString)")!
        ProfileIdentity.remember(userId: "x", name: "Real Name", email: "real@example.com", edited: true, defaults: defaults)
        ProfileIdentity.remember(userId: "x", name: "", email: "  ", edited: true, defaults: defaults)
        ProfileIdentity.remember(userId: "x", name: "User", email: nil, edited: true, defaults: defaults)
        XCTAssertEqual(ProfileIdentity.saved(userId: "x", defaults: defaults).name, "Real Name")
        XCTAssertEqual(ProfileIdentity.saved(userId: "x", defaults: defaults).email, "real@example.com")
    }

    func testProfilesDoNotShareIdentity() {
        let vm = AppViewModel()
        firstAppleSignIn()
        AppleSignInManager.shared.updateProfile(name: "Brian Le Vu", email: "brian@example.com", imageData: nil)
        vm.signOut()
        _ = AppleSignInFlow.record(userId: appleId + ".other", givenName: nil, familyName: nil, email: nil)
        AppleSignInManager.shared.checkExistingSignIn()
        XCTAssertNil(AppleSignInManager.shared.fullName, "a different Apple ID gets none of the first profile's name")
        XCTAssertNil(AppleSignInManager.shared.email)
        UserDefaults.standard.removeObject(forKey: ProfileKeys.appleUserId)
    }

    func testLocalProfileEditSurvivesSwitchAway() {
        let vm = AppViewModel()
        let defaults = UserDefaults.standard
        let id = ProfileKeys.newLocalProfileId()
        defaults.set(id, forKey: ProfileKeys.localProfileId)
        defaults.set(LoginType.local.rawValue, forKey: ProfileKeys.loginType)
        AppleSignInManager.shared.checkExistingSignIn()
        AppleSignInManager.shared.updateProfile(name: "Local Person", email: "local@example.com", imageData: nil)
        vm.signOut()
        ProfileRestore.activate(DiscoveredProfile(id: id, entryCount: 0, propertyCount: 0, lastEntryDate: nil, sources: [.device], name: nil), defaults: defaults)
        AppleSignInManager.shared.checkExistingSignIn()
        XCTAssertEqual(AppleSignInManager.shared.fullName, "Local Person")
        XCTAssertEqual(AppleSignInManager.shared.email, "local@example.com")
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("u.\(id).") { defaults.removeObject(forKey: key) }
    }
}
