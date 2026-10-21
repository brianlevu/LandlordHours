import XCTest
@testable import LandlordHours

/// fix/onb-start: ContentView shows onboarding while `!isSignedIn || showOnboarding`. Every new
/// profile made from Welcome must set showOnboarding BEFORE isSignedIn turns true, or the shell
/// mounts for a frame and onboarding restarts on Welcome (the first tap looks ignored).
@MainActor
final class OnboardingProfileHoldTests: XCTestCase {

    /// Mirrors ContentView's two flags and records every moment onboarding would unmount.
    private final class Shell {
        var isSignedIn = false
        var showOnboarding = false
        var unmounted = false
        var order: [String] = []
        func check() { if !(!isSignedIn || showOnboarding) { unmounted = true } }
    }

    private func services(_ shell: Shell, held: Bool) -> OnbServices {
        var s = OnbServices()
        s.ensureProfile = { shell.order.append("signedIn"); shell.isSignedIn = true; shell.check() }
        s.signUpWithApple = { shell.order.append("signedIn"); shell.isSignedIn = true; shell.check() }
        guard held else { return s }
        return s.holdingOnboarding { shell.order.append("shown"); shell.showOnboarding = true; shell.check() }
    }

    func testStartBuildingShowsOnboardingBeforeSigningIn() {
        let shell = Shell()
        let flow = OnbFlow(cohort: .new, services: services(shell, held: true))
        flow.start()
        XCTAssertEqual(shell.order, ["shown", "signedIn"])
        XCTAssertFalse(shell.unmounted, "Onboarding never unmounts mid-flow")
        XCTAssertEqual(flow.step, .goal)
    }

    func testNewAppleUserShowsOnboardingBeforeSigningIn() {
        let shell = Shell()
        let flow = OnbFlow(cohort: .new, services: services(shell, held: true))
        flow.signUpWithApple()
        XCTAssertEqual(shell.order, ["shown", "signedIn"])
        XCTAssertFalse(shell.unmounted, "Onboarding never unmounts mid-flow")
        XCTAssertEqual(flow.step, .goal)
    }

    /// The old wiring (no hold) is exactly the bug: both paths open the unmount window.
    func testWithoutTheHoldBothPathsOpenTheWindow() {
        for path in ["start", "apple"] {
            let shell = Shell()
            let flow = OnbFlow(cohort: .new, services: services(shell, held: false))
            if path == "start" { flow.start() } else { flow.signUpWithApple() }
            XCTAssertTrue(shell.unmounted, "\(path): signed in while showOnboarding was false")
        }
    }
}
