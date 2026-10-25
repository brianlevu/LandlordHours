import XCTest
import SwiftUI
import UIKit
@testable import LandlordHours

/// Plan package B (the conversion path): launch → hand-off → Welcome → steps → paywall, v2.
final class ConversionPathTests: XCTestCase {

    // MARK: Launch and hand-off (standard §H.5)

    private func rgbHex(_ color: UIColor, dark: Bool) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func testLaunchColourIsPageTopInBothAppearances() throws {
        let launch = try XCTUnwrap(UIColor(named: "LaunchBackground"), "the launch colour set ships")
        XCTAssertEqual(rgbHex(launch, dark: false), BrandHex.duskTop.uppercased(), "light launch = pageTop (dusk)")
        XCTAssertEqual(rgbHex(launch, dark: true), BrandHex.darkNightTop.uppercased(), "dark launch = pageTop (night)")
        // The hand-off draws the same colour from the token.
        XCTAssertEqual(rgbHex(UIColor(AdaptiveColors(colorScheme: .light).pageTop), dark: false), BrandHex.duskTop.uppercased())
        XCTAssertEqual(rgbHex(UIColor(AdaptiveColors(colorScheme: .dark).pageTop), dark: true), BrandHex.darkNightTop.uppercased())
    }

    func testTheBlueprintLaunchColourIsRetired() {
        XCTAssertNil(UIColor(named: "LaunchBlueprint"), "no blueprint flash before a dusk Welcome")
    }

    func testLaunchMarkHasAnyAndDarkInks() throws {
        let mark = try XCTUnwrap(UIImage(named: "LaunchMark"))
        let light = mark.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = mark.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotNil(light)
        XCTAssertNotNil(dark)
        XCTAssertNotEqual(light?.pngData(), dark?.pngData(), "the mark is textPrimary per appearance")
    }

    func testHandOffFadesOutMonotonicallyForBothDestinations() {
        for destination in [LaunchHandoffOverlay.Destination.today, .welcome] {
            XCTAssertEqual(LaunchHandoffOverlay.overlayOpacity(destination, 0), 1, "the first frame is the storyboard frame")
            XCTAssertEqual(LaunchHandoffOverlay.overlayOpacity(destination, 1), 0)
            var last = 1.0
            for i in 0...100 {
                let o = LaunchHandoffOverlay.overlayOpacity(destination, CGFloat(i) / 100)
                XCTAssertLessThanOrEqual(o, last)
                last = o
            }
        }
    }

    // MARK: Welcome (standard §1.24, §H.1)

    func testWelcomeHeroUsesTheTodayHeroSizes() {
        XCTAssertEqual(OnbWelcomeView.heroSide(windowWidth: 402, windowHeight: 874, accessibility: false), 390)
        XCTAssertEqual(OnbWelcomeView.heroSide(windowWidth: 402, windowHeight: 874, accessibility: true), 295, "H3 at AX: held, never hidden")
        XCTAssertEqual(OnbWelcomeView.heroSide(windowWidth: 375, windowHeight: 667, accessibility: false), 297)
        XCTAssertEqual(OnbWelcomeView.heroSide(windowWidth: 820, windowHeight: 1180, accessibility: false), 390, "band B: a fixed 390 frame")
    }

    private func sentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".?!".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func testWelcomeCopyIsShortPlainAndClaimFree() {
        let all = [OnbWelcomeView.headline, OnbWelcomeView.line]
        let words = all.flatMap(sentences).map { $0.split(separator: " ").count }
        XCTAssertLessThanOrEqual(Double(words.reduce(0, +)) / Double(words.count), 14, "C.1: average ≤ 14 words")
        XCTAssertLessThanOrEqual(words.max() ?? 0, 22, "C.1: hard max 22")
        for line in all {
            let l = line.lowercased()
            for banned in ["qualif", "audit-ready", "evidence", "proof", "compliance", "material participation", "reps"] {
                XCTAssertFalse(l.contains(banned), "\(banned) in \(line)")
            }
        }
    }

    // MARK: Steps (option rows stay one line at XXL)

    func testGoalRowWordsFitOneLine() {
        for goal in OnbGoal.allCases {
            XCTAssertLessThanOrEqual(OnbGoalCopy.rowTitle(goal).count, 20, goal.rawValue)
            for pro in [RealEstatePro.me, .spouse, .nobody, nil] {
                XCTAssertLessThanOrEqual(OnbGoalCopy.rowMeta(goal, pro: pro).count, 22, "\(goal) \(String(describing: pro))")
            }
        }
    }

    func testGoalNoteFollowsTheStandardRewrite() {
        XCTAssertEqual(OnbGoalCopy.detail(.reps750, pro: .me, isSuggested: true, rental: .longTerm),
                       "Counts the rental hours you log here. Other real-estate work isn’t tracked yet.")
        XCTAssertFalse(OnbGoalCopy.detail(.record, pro: nil, isSuggested: false, rental: nil).contains("entries"))
    }

    func testUpgraderHouseStageComesFromTheOneStageFunction() {
        XCTAssertEqual(OnbWhatsNewHouseStep.stage(hours: 0, goal: .reps750), CraftStage.stage(hours: 0, goal: 750))
        XCTAssertEqual(OnbWhatsNewHouseStep.stage(hours: 760, goal: .reps750), .complete)
        XCTAssertEqual(OnbWhatsNewHouseStep.stage(hours: -5, goal: .mp100), CraftStage.stage(hours: 0, goal: 100))
    }

    // MARK: Paywall (standard §1.23)

    func testRecordPreviewTitleIsThePDFTitle() {
        XCTAssertEqual(RecordPagePreview.title(year: 2026), "Rental hours record 2026")
    }

    func testPaywallPreviewStaysUnderTheCap() {
        XCTAssertLessThanOrEqual(PaywallView.previewShare, 0.40)
        XCTAssertLessThanOrEqual(PaywallView.previewShareAccessibility, 0.40)
    }

    func testBenefitRowsFitOneLine() {
        for row in PaywallView.benefitRows {
            XCTAssertLessThanOrEqual(row.title.count, 26, row.title)
            XCTAssertLessThanOrEqual(row.meta.count, 24, row.meta)
        }
        let words = PaywallView.benefitRows.flatMap { [$0.title, $0.meta] }.joined(separator: " ").lowercased()
        XCTAssertFalse(words.contains("accountant"), "C.4: your CPA")
    }

    // MARK: Fix round 2 (gate B 1.1)

    func testPaywallCopyIsLocalizedAndSaysCPA() {
        for context in PaywallContext.allCases {
            let c = PaywallCopy.localized(context, year: 2026, propertyName: "Pine Cabin", confirmedHours: 46.7)
            let words = [c.headline, c.planLine, c.nextStep].joined(separator: " ").lowercased()
            XCTAssertFalse(words.contains("accountant"), "C.4: your CPA (\(context))")
            XCTAssertFalse(words.contains("property"), "C.4: rental (\(context))")
        }
        XCTAssertEqual(PaywallCopy.localized(.export, year: 2026).headline, "The record your CPA gets")
        XCTAssertEqual(PaywallCopy.localized(.export, year: 2026).nextStep, "Export 2026")
        XCTAssertEqual(PaywallCopy.localized(.secondProperty, year: 2026, propertyName: " Pine Cabin ").nextStep, "Add Pine Cabin")
        XCTAssertEqual(PaywallCopy.localized(.secondProperty, year: 2026, propertyName: "  ").nextStep, "Add a rental")
        XCTAssertEqual(PaywallCopy.localized(.todayUnlock, year: 2026, confirmedHours: 46.7).planLine,
                       "Turn 46 confirmed hours into a clean record.")
        XCTAssertEqual(PaywallCopy.localized(.todayUnlock, year: 2026).planLine,
                       "Turn your confirmed hours into a clean record.")
    }

    func testBuyTitleUsesTheStorePriceAndDropsItAtLargeSizes() {
        XCTAssertEqual(PaywallCopy.buyTitle(billed: "$29.99", large: false), "Unlock for $29.99")
        XCTAssertEqual(PaywallCopy.buyTitle(billed: "$29.99", large: true), "Unlock Pro")
        XCTAssertEqual(PaywallCopy.buyTitle(billed: nil, large: false), "Unlock Pro")
    }

    func testOnboardingHouseFitsItsFrameAtEveryStage() {
        for stage in CraftStage.allCases {
            let box = OnbHouseThumb.contentBox(stage)
            let scale = OnbHouseThumb.scale(stage)
            XCTAssertLessThanOrEqual(box.width * scale, 0.96 + 1e-9, "\(stage) width")
            XCTAssertLessThanOrEqual(box.height * scale, 0.96 + 1e-9, "\(stage) height")
            XCTAssertGreaterThan(max(box.width, box.height) * scale, 0.95, "\(stage) fills the frame")
        }
    }

    func testAccountSheetFitsItsContent() {
        XCTAssertEqual(OnbAccountSheet.detents(contentHeight: 300), [.height(300 + OnbAccountSheet.chromeHeight), .large])
        XCTAssertEqual(OnbAccountSheet.detents(contentHeight: 0), [.medium, .large])
        XCTAssertEqual(OnbAccountSheet.detents(contentHeight: .infinity), [.medium, .large])
        XCTAssertEqual(OnbAccountSheet.detents(contentHeight: 300, accessibility: true), [.large])
    }
}
