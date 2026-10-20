import XCTest
import SwiftUI
@testable import LandlordHours

// MARK: - Rating prompt guards

final class RatingPromptPolicyTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(
        daysSinceInstall: Double? = 8,
        entries: Int = 10,
        paywall: Bool = false,
        error: Bool = false,
        lastVersion: String? = nil,
        sharedBefore: Bool = false
    ) -> RatingPromptPolicy.State {
        RatingPromptPolicy.State(
            now: now,
            installDate: daysSinceInstall.map { now.addingTimeInterval(-$0 * day) },
            entryCount: entries,
            sessionShowedPaywall: paywall,
            sessionHadError: error,
            lastRequestedVersion: lastVersion,
            currentVersion: "1.1",
            hasSharedExportBefore: sharedBefore
        )
    }

    func testAllGuardsMetAllowsBothTriggers() {
        XCTAssertTrue(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state()))
        XCTAssertTrue(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state()))
    }

    func testNeedsSevenDaysSinceInstall() {
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state(daysSinceInstall: 6.9)))
        XCTAssertTrue(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state(daysSinceInstall: 7)))
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state(daysSinceInstall: nil)),
                       "No recorded install date fails closed")
    }

    func testNeedsTenEntries() {
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(entries: 9)))
        XCTAssertTrue(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(entries: 10)))
    }

    func testNeverInSameSessionAsPaywallOrError() {
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state(paywall: true)))
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state(error: true)))
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(paywall: true)))
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(error: true)))
    }

    func testAtMostOncePerAppVersion() {
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(lastVersion: "1.1")))
        XCTAssertTrue(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(lastVersion: "1.0.6")))
    }

    func testOnlyTheFirstSharedExportTriggers() {
        XCTAssertFalse(RatingPromptPolicy.shouldRequest(trigger: .exportShared, state: state(sharedBefore: true)))
        XCTAssertTrue(RatingPromptPolicy.shouldRequest(trigger: .entriesMilestone, state: state(sharedBefore: true)),
                      "A past export doesn't block the entries milestone")
    }
}

final class RatingPromptCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var events: [(String, [String: Any])] = []

    override func setUp() {
        super.setUp()
        suiteName = "RatingPromptCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        events = []
        Analytics.testSpy = { [weak self] name, props in self?.events.append((name, props)) }
    }

    override func tearDown() {
        Analytics.testSpy = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeCoordinator(version: String = "1.1", enabled: Bool = true) -> RatingPromptCoordinator {
        RatingPromptCoordinator(defaults: defaults, now: { [unowned self] in self.clock },
                                currentVersion: version, isEnabled: enabled)
    }

    func testFirstLaunchRecordsInstallDateOnce() {
        let coordinator = makeCoordinator()
        coordinator.recordLaunch()
        let first = defaults.object(forKey: RatingPromptCoordinator.installDateKey) as? Date
        clock = clock.addingTimeInterval(3_600)
        coordinator.recordLaunch()
        XCTAssertEqual(defaults.object(forKey: RatingPromptCoordinator.installDateKey) as? Date, first)
    }

    func testFreshInstallDoesNotAsk() {
        let coordinator = makeCoordinator()
        coordinator.recordLaunch()
        XCTAssertFalse(coordinator.consider(.entriesMilestone, entryCount: 20))
        XCTAssertNil(coordinator.pendingRequest)
    }

    func testAsksOncePerVersionAndRecordsAnalytics() {
        let coordinator = makeCoordinator()
        coordinator.recordLaunch()
        clock = clock.addingTimeInterval(8 * 86_400)

        XCTAssertTrue(coordinator.consider(.entriesMilestone, entryCount: 10))
        XCTAssertEqual(coordinator.pendingRequest, .entriesMilestone)
        XCTAssertEqual(events.last?.0, "rating_prompt_requested")
        XCTAssertEqual(events.last?.1["trigger"] as? String, "entries_milestone")

        coordinator.pendingRequest = nil
        XCTAssertFalse(coordinator.consider(.entriesMilestone, entryCount: 11), "Once per version")

        let nextVersion = makeCoordinator(version: "1.2")
        XCTAssertTrue(nextVersion.consider(.entriesMilestone, entryCount: 12), "A new version may ask again")
    }

    func testPaywallOrErrorInSessionBlocks() {
        let coordinator = makeCoordinator()
        coordinator.recordLaunch()
        clock = clock.addingTimeInterval(8 * 86_400)
        coordinator.notePaywallShown()
        XCTAssertFalse(coordinator.consider(.entriesMilestone, entryCount: 30))

        coordinator.resetSession()
        coordinator.noteError()
        XCTAssertFalse(coordinator.consider(.entriesMilestone, entryCount: 30))

        coordinator.resetSession()
        XCTAssertTrue(coordinator.consider(.entriesMilestone, entryCount: 30))
    }

    func testFirstSharedExportIsTheOnlyExportTrigger() {
        let coordinator = makeCoordinator()
        coordinator.recordLaunch()
        // First export shared too early: it is used up even though the guards said no.
        XCTAssertFalse(coordinator.consider(.exportShared, entryCount: 30))
        clock = clock.addingTimeInterval(8 * 86_400)
        XCTAssertFalse(coordinator.consider(.exportShared, entryCount: 30), "Only the first shared export counts")
    }

    func testDisabledCoordinatorNeverAsks() {
        let coordinator = makeCoordinator(enabled: false)
        coordinator.recordLaunch()
        clock = clock.addingTimeInterval(30 * 86_400)
        XCTAssertFalse(coordinator.consider(.entriesMilestone, entryCount: 30))
        XCTAssertTrue(events.isEmpty)
    }

    func testDefaultCoordinatorIsOffUnderXCTest() {
        XCTAssertFalse(RatingPromptCoordinator.defaultEnabled)
    }
}

// MARK: - Analytics events

final class FunnelAnalyticsTests: XCTestCase {
    private var events: [(name: String, props: [String: Any])] = []

    override func setUp() {
        super.setUp()
        events = []
        Analytics.testSpy = { [weak self] name, props in self?.events.append((name, props)) }
    }

    override func tearDown() {
        Analytics.testSpy = nil
        super.tearDown()
    }

    private func only(_ name: String) -> [String: Any]? {
        let matches = events.filter { $0.name == name }
        XCTAssertEqual(matches.count, 1, "\(name) should fire exactly once, got \(events.map(\.name))")
        return matches.first?.props
    }

    func testEntryLoggedCarriesSourceForEverySource() {
        for source in EntrySource.allCases {
            events = []
            Analytics.entryLogged(source: source)
            XCTAssertEqual(only("entry_logged")?["source"] as? String, source.rawValue)
        }
        XCTAssertEqual(EntrySource.allCases.map(\.rawValue).sorted(),
                       ["calendar", "gmail", "location", "manual", "other", "receipt", "shortcut", "timer", "voice"])
    }

    func testExportSharedCarriesFormat() {
        Analytics.exportShared(format: .pdf)
        XCTAssertEqual(only("export_shared")?["format"] as? String, "pdf")
        events = []
        Analytics.exportShared(format: .csv)
        XCTAssertEqual(only("export_shared")?["format"] as? String, "csv")
    }

    func testPaywallAndPurchaseEventsCarryContext() {
        for context in PaywallContext.allCases {
            events = []
            Analytics.paywallViewed(context: context)
            Analytics.purchaseCompleted(context: context)
            XCTAssertEqual(only("paywall_viewed")?["context"] as? String, context.rawValue)
            XCTAssertEqual(only("purchase_completed")?["context"] as? String, context.rawValue)
        }
    }

    func testPropertyFreeEvents() {
        Analytics.purchaseRestored()
        Analytics.onboardingCompleted()
        XCTAssertEqual(only("purchase_restored")?.isEmpty, true)
        XCTAssertEqual(only("onboarding_completed")?.isEmpty, true)
    }

    func testProfileCreatedKind() {
        Analytics.profileCreated(kind: .apple)
        XCTAssertEqual(only("profile_created")?["kind"] as? String, "apple")
        events = []
        Analytics.profileCreated(kind: .local)
        XCTAssertEqual(only("profile_created")?["kind"] as? String, "local")
    }

    func testRatingPromptRequestedTrigger() {
        Analytics.ratingPromptRequested(trigger: .exportShared)
        XCTAssertEqual(only("rating_prompt_requested")?["trigger"] as? String, "export_shared")
    }

    /// No event ever carries free text: every property value is one of a fixed set.
    func testEventPropertiesAreFixedEnumsOnly() {
        EntrySource.allCases.forEach { Analytics.entryLogged(source: $0) }
        Analytics.exportShared(format: .pdf)
        PaywallContext.allCases.forEach { Analytics.paywallViewed(context: $0) }
        Analytics.profileCreated(kind: .local)
        Analytics.ratingPromptRequested(trigger: .entriesMilestone)
        LockEntry.allCases.forEach { Analytics.lockPreviewShown(entry: $0) }
        PaywallContext.allCases.forEach {
            Analytics.paywallShown(context: $0, entry: .exportPage)
            Analytics.paywallCtaTapped(context: $0)
            Analytics.purchaseSucceeded(context: $0)
            Analytics.purchaseFailed(context: $0, outcome: "pending")
        }
        let allowedKeys: Set<String> = ["source", "format", "context", "kind", "trigger", "entry", "outcome"]
        let allowedValues: Set<String> = Set(EntrySource.allCases.map(\.rawValue))
            .union(["pdf", "csv", "apple", "local", "export_shared", "entries_milestone"])
            .union(PaywallContext.allCases.map(\.rawValue))
            .union(LockEntry.allCases.map(\.rawValue))
            .union(["failed", "pending", "cancelled"])
        for event in events {
            for (key, value) in event.props {
                XCTAssertTrue(allowedKeys.contains(key), "\(event.name) has unexpected key \(key)")
                XCTAssertTrue(allowedValues.contains(value as? String ?? "<non-string>"),
                              "\(event.name).\(key) has a free-form value")
            }
        }
    }
}

@MainActor
final class FunnelAnalyticsIntegrationTests: XCTestCase {
    private var events: [(name: String, props: [String: Any])] = []
    private let id = "local-funnel-analytics-tests"

    override func setUp() {
        super.setUp()
        events = []
        Analytics.testSpy = { [weak self] name, props in self?.events.append((name, props)) }
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
    }

    override func tearDown() {
        Analytics.testSpy = nil
        AppViewModel.clearScopedAccountData(for: id)
        UserDefaults.standard.removeObject(forKey: ProfileKeys.localProfileId)
        super.tearDown()
    }

    func testAddingAnEntryFiresEntryLoggedWithItsSource() {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        let property = try! XCTUnwrap(viewModel.properties.first)
        events = []
        viewModel.addTimeEntry(propertyId: property.id, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: Date(), notes: "Private note about tenant", source: .voice)
        let logged = events.filter { $0.name == "entry_logged" }
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.props["source"] as? String, "voice")
        let allValues = events.flatMap { $0.props.values.compactMap { $0 as? String } }
        XCTAssertFalse(allValues.contains { $0.contains("Private note") }, "Notes never reach analytics")
    }

    func testSharingAnExportFiresExportShared() {
        let viewModel = AppViewModel()
        viewModel.exportShared(format: .csv)
        let shared = events.filter { $0.name == "export_shared" }
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(shared.first?.props["format"] as? String, "csv")
    }
}

// MARK: - Paywall copy

final class PaywallContextTests: XCTestCase {
    func testHeadlineSpeaksToTheThingTapped() {
        XCTAssertEqual(PaywallCopy.make(.export, year: 2026).headline, "The record your accountant gets")
        XCTAssertTrue(PaywallCopy.make(.secondProperty, year: 2026).headline.contains("rental"))
        XCTAssertNotEqual(PaywallCopy.make(.todayUnlock, year: 2026).headline, PaywallCopy.make(.settings, year: 2026).headline,
                          "Today's record card gets its own headline")
    }

    func testCopyNeverOverclaimsTaxOutcomes() {
        let banned = ["audit-proof", "audit proof", "guarantee", "irs-approved", "irs approved", "qualify you", "ensures",
                      "qualified", "audit-ready", "evidence", "defensible", "tax-ready"]
        var copy: [String] = []
        for context in PaywallContext.allCases {
            let c = PaywallCopy.make(context, year: 2026, propertyName: "Oak", confirmedHours: 212)
            copy += [c.headline, c.planLine, c.nextStep]
        }
        copy += PaywallCopy.benefits.flatMap { [$0.title, $0.line] }
        for entry in LockEntry.allCases { copy += [ProGate.lockLine(entry), ProGate.keepsLine(entry)] }
        copy.append(NotTaxAdviceNote.text)
        for line in copy where line != NotTaxAdviceNote.text {
            for word in banned {
                XCTAssertFalse(line.lowercased().contains(word), "Overclaim '\(word)' in: \(line)")
            }
        }
    }

    func testNotTaxAdviceWording() {
        XCTAssertEqual(NotTaxAdviceNote.text,
                       "LandlordHours keeps your records. It doesn't give tax advice. Check your qualification with a tax professional.")
    }

    func testOnboardingHasNoPaywallStep() {
        XCTAssertEqual(OnboardingStep.allCases, [.goalSelection, .addProperty, .notifications, .calendar])
        XCTAssertEqual(OnboardingStep.totalSegments, 4)
        XCTAssertNil(OnboardingStep.fromLaunchArgument("paywall"))
    }
}

// MARK: - Dashboard 50% rule

@MainActor
final class MoreThanHalfDisplayTests: XCTestCase {
    private func entries(_ hours: Double) -> [TimeEntry] {
        [TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs,
                   hours: hours, date: Date(), notes: "")]
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    func testZeroOtherWorkHoursIsNotEnteredNotMet() {
        let result = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                       year: year, nonRealEstateHours: 0)
        XCTAssertEqual(result.moreThanHalfStatus, .notEntered)
        XCTAssertTrue(result.meets750HourTest)
        XCTAssertFalse(result.isQualified, "An empty field must never read as qualified")
        XCTAssertEqual(TaxQualificationEngine.MoreThanHalfStatus.notEnteredPrompt,
                       "Add your other work hours to check this")
    }

    func testNegativeOtherWorkHoursIsNotEntered() {
        let result = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                       year: year, nonRealEstateHours: -5)
        XCTAssertEqual(result.moreThanHalfStatus, .notEntered)
    }

    func testEnteredHoursAreEvaluated() {
        let met = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                    year: year, nonRealEstateHours: 400)
        XCTAssertEqual(met.moreThanHalfStatus, .met)
        XCTAssertTrue(met.isQualified)

        let notMet = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                       year: year, nonRealEstateHours: 900)
        XCTAssertEqual(notMet.moreThanHalfStatus, .notMet)
        XCTAssertFalse(notMet.isQualified)
    }

    /// Dashboard and the audit export agree: 0 other work hours is "not entered".
    func testDashboardAgreesWithExport() {
        let input = AuditReportBuilder.inputFromTaxProfile(
            entries: entries(800), properties: [], taxYear: year, spouseTracking: false,
            nonREWorkHours: 0, groupingElection: false, noOneParticipatedMore: nil)
        let report = AuditReportBuilder.build(input)
        let exportSays = report.qualifications.first?.meetsMoreThanHalfTest
        let dashboard = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                          year: year, nonRealEstateHours: 0)
        XCTAssertNil(exportSays)
        XCTAssertEqual(dashboard.moreThanHalfStatus, .notEntered)
    }

    /// Home and Reports use the same words when 750 h are met but the 50% rule is open.
    func testHoursMetRuleOpenWordingIsShared() {
        let unset = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                      year: year, nonRealEstateHours: 0)
        XCTAssertTrue(unset.hoursMetButRuleOpen)
        XCTAssertFalse(unset.isQualified)
        let open = TaxQualificationEngine.hoursMetRuleOpenStatus(unset)
        XCTAssertEqual(open?.label, "Hours target met")
        XCTAssertEqual(open?.detail, "Add your other work hours to check the 50% rule")

        let failing = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                        year: year, nonRealEstateHours: 900)
        XCTAssertEqual(TaxQualificationEngine.hoursMetRuleOpenStatus(failing)?.detail, "50% rule not met yet")

        let met = TaxQualificationEngine.repsStatus(entries: entries(800), participant: .selfParticipant,
                                                    year: year, nonRealEstateHours: 400)
        XCTAssertNil(TaxQualificationEngine.hoursMetRuleOpenStatus(met))
        XCTAssertTrue(met.isQualified)

        let short = TaxQualificationEngine.repsStatus(entries: entries(300), participant: .selfParticipant,
                                                      year: year, nonRealEstateHours: 0)
        XCTAssertNil(TaxQualificationEngine.hoursMetRuleOpenStatus(short), "Below 750 h the pace text applies")
        XCTAssertEqual(TaxQualificationEngine.MoreThanHalfStatus.notEnteredValue, "Not checked")
    }

    func testViewModelMeets50PercentRuleIsFalseWhenNotEntered() {
        let manager = TaxProfileManager.shared
        let original = manager.nonREWorkHours
        defer { manager.nonREWorkHours = original }
        manager.nonREWorkHours = 0
        let viewModel = AppViewModel()
        XCTAssertFalse(viewModel.meets50PercentRule(year: year))
    }
}

// MARK: - Timer draft card

final class TimerDraftReviewTests: XCTestCase {
    private func draft(_ hours: Double, reason: StaleTimerRecovery.Reason = .forgotten) -> StaleTimerRecovery {
        StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs, elapsedHours: hours, reason: reason)
    }

    /// One line carries both facts so the run time and the cap don't contradict each other.
    func testCappedHeadlineSaysRunTimeAndCapInOneLine() {
        XCTAssertEqual(draft(30).cardHeadline, "Ran 30.0h. We stopped counting at 24h \u{2014} check it before saving.")
        XCTAssertTrue(draft(26, reason: .pausedAtSwitch).cardHeadline.hasPrefix("Ran 26.0h. We stopped counting at 24h"))
        XCTAssertEqual(draft(0.75).cardHeadline, "Ran 45 min", "Uncapped drafts still show the real run time")
    }

    func testCappedMessageDoesNotRepeatTheCap() {
        let message = draft(30).cardMessage(propertyName: "Oak", hasAnyProperty: true)
        XCTAssertFalse(message.contains("24h"), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("24 hours"), message)
        XCTAssertFalse(message.contains("30.0h"), message)
    }

    func testReviewSaveNeedsAChangeOrAConfirmation() {
        let capped = draft(30)
        XCTAssertFalse(capped.canSaveReview(hours: 24, confirmed: false), "One tap can't commit 24h")
        XCTAssertTrue(capped.canSaveReview(hours: 24, confirmed: true))
        XCTAssertTrue(capped.canSaveReview(hours: 6, confirmed: false))
        XCTAssertTrue(capped.canSaveReview(hours: 23.75, confirmed: false))
        XCTAssertFalse(capped.canSaveReview(hours: 0, confirmed: true), "Zero hours never saves")
    }
}

// MARK: - Contrast follow-ups

final class LaneCContrastTests: XCTestCase {
    private func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let la = luminance(a, style), lb = luminance(b, style)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Token pairs used by onboarding, the Home goal card and the guided-setup coach mark.
    func testOnboardingDashboardAndCoachTokenPairsPassAA() {
        let light = AdaptiveColors(colorScheme: .light)
        let dark = AdaptiveColors(colorScheme: .dark)
        let cream = AppColors.background   // onboarding page background (#FAF7F2)
        var pairs: [(String, Color, Color, UIUserInterfaceStyle)] = [
            ("skip/secondary on cream", light.textSecondary, cream, .light),
            ("secondary on light page", light.textSecondary, light.background, .light),
            ("secondary on dark page", dark.textSecondary, dark.background, .dark),
            ("coach CTA light", light.onAction, light.action, .light),
            ("coach CTA dark", dark.onAction, dark.action, .dark),
            ("coach skip light", light.actionText, light.actionSurface, .light),
            ("coach skip dark", dark.actionText, dark.actionSurface, .dark),
            ("tab inactive light", light.textSecondary, light.background, .light),
            ("tab active light", light.actionText, light.actionSurface, .light),
            ("tab active dark", dark.actionText, dark.actionSurface, .dark),
        ]
        for (scheme, colors, style) in [(ColorScheme.light, light, UIUserInterfaceStyle.light), (.dark, dark, .dark)] {
            // Today's metric tiles under the house hero (50% rule, pace) sit on the card fill.
            pairs.append(("today metric text \(scheme)", colors.textPrimary, colors.backgroundSecondary, style))
            pairs.append(("today metric secondary \(scheme)", colors.textSecondary, colors.backgroundSecondary, style))
        }
        for (name, fg, bg, style) in pairs {
            let ratio = contrast(fg, bg, style)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) = \(ratio)")
        }
    }

    func testLightDiscardOnSnowPillPassesAA() {
        let light = AdaptiveColors(colorScheme: .light)
        let ratio = contrast(light.destructive, AppColors.snow, .light)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Discard on #F0EFF4 = \(ratio)")
    }

    /// #444444 stands in for the brightest measured point of the dark ambient wash
    /// (where #A8A8BC measured 4.18:1).
    func testDarkCanvasSubtitlesPassAAOnTheAmbientWash() {
        let dark = AdaptiveColors(colorScheme: .dark)
        let washPeak = Color(hex: "444444")
        let ratio = contrast(dark.textSecondaryOnCanvas, washPeak, .dark)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Settings subtitle on wash = \(ratio)")
    }
}
