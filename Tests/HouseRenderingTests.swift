import XCTest
import SwiftUI
import UIKit
@testable import LandlordHours

/// WP-H: motion plans (Reduce Motion paths and timing caps), asset resolution against the art
/// manifest, and a snapshot-style check that each stage renders the right imageset.
final class HouseMotionTests: XCTestCase {

    func testReduceMotionNeverAnimates() {
        XCTAssertEqual(HouseMotion.keyframeTransition(from: .k04_frame030, to: .k05_frame040, reduceMotion: true), .instant)
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 680, newHours: 682, reduceMotion: true), .instantSwap)
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 50, newHours: 120, reduceMotion: true), .instantSwap)
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 499, newHours: 501, reduceMotion: true), .instantSwap)
        for milestone in HouseMilestone.allCases {
            XCTAssertEqual(HouseMotion.milestoneSettleDuration(milestone, reduceMotion: true), 0.2, accuracy: 0.0001)
        }
    }

    func testConfirmPlansWithMotion() {
        // Same keyframe: board plays, no keyframe change after.
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 680, newHours: 682, reduceMotion: false),
                       .boardSequence(frames: 13, fps: 30, thenKeyframe: .instant))
        // Crosses a siding keyframe: board, then crossfade.
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 699, newHours: 701, reduceMotion: false),
                       .boardSequence(frames: 13, fps: 30, thenKeyframe: .crossfade(duration: HouseMotion.keyframeCrossfade)))
        // Lot: no course for the board, crossfade to the slab.
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 99, newHours: 101, reduceMotion: false),
                       .crossfadeOnly(.crossfade(duration: HouseMotion.keyframeCrossfade)))
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 10, newHours: 12, reduceMotion: false), .crossfadeOnly(.instant))
        // Finished house: no board.
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 800, newHours: 802, reduceMotion: false), .crossfadeOnly(.instant))
        // Nothing added, or hours removed: no plan.
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 200, newHours: 200, reduceMotion: false), .none)
        XCTAssertEqual(HouseMotion.confirmPlan(oldHours: 200, newHours: 150, reduceMotion: false), .none)
    }

    func testTimingCaps() {
        XCTAssertEqual(HouseMotion.confirmFrameCount, 13)
        XCTAssertEqual(HouseMotion.confirmSequenceDuration, 13.0 / 30.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(HouseMotion.backfillTotalDuration, 2.5, "backfill sketch-in must finish within 2.5 s")
        XCTAssertLessThanOrEqual(HouseMotion.backfillLeadIn + HouseMotion.backfillSketchDuration, HouseMotion.backfillTotalDuration)
        for milestone in HouseMilestone.allCases {
            XCTAssertLessThan(HouseMotion.milestoneSettleDuration(milestone, reduceMotion: false), 3, "\(milestone) celebration must run under 3 s")
        }
        XCTAssertEqual(HouseMotion.roofDropPoints, 12)
        XCTAssertEqual(HouseMotion.confirmFrameNames.first, "bp_confirm_row_00")
        XCTAssertEqual(HouseMotion.confirmFrameNames.last, "bp_confirm_row_12")
    }

    func testCelebrationCopyNeverOverclaims() {
        XCTAssertTrue(MilestoneCelebrationView.detail(for: .roof500, hours: 500).contains("needs more than 500"))
        XCTAssertTrue(MilestoneCelebrationView.detail(for: .roof500, hours: 502).contains("met, based on your records"))
        XCTAssertTrue(MilestoneCelebrationView.detail(for: .foundation100, hours: 100).contains("needs more than 100"))
        for milestone in HouseMilestone.allCases {
            for hours in [milestone.thresholdHours, milestone.thresholdHours + 1] {
                XCTAssertFalse(MilestoneCelebrationView.detail(for: milestone, hours: hours).lowercased().contains("qualif"))
            }
        }
    }

    func testLineworkTintPerCanvas() {
        XCTAssertEqual(HouseCanvas.blueprintHero.lineworkHex(for: .light), "8FD3FF")
        XCTAssertEqual(HouseCanvas.blueprintHero.lineworkHex(for: .dark), "8FD3FF")
        XCTAssertEqual(HouseCanvas.card.lineworkHex(for: .light), "2369B5")
        XCTAssertEqual(HouseCanvas.card.lineworkHex(for: .dark), "60A8E6")
    }

    #if DEBUG
    func testPreviewLaunchArgumentsParse() {
        let config = HousePreviewLaunch.parse(["app", "-LHHousePreview", "499.5", "mp500", "dark", "-LHHouseScene", "milestone", "-LHHouseSettled"])
        XCTAssertEqual(config?.hours, 499.5)
        XCTAssertEqual(config?.goal, .mp500)
        XCTAssertEqual(config?.scheme, .dark)
        XCTAssertEqual(config?.scene, .milestone)
        XCTAssertEqual(config?.settled, true)
        XCTAssertEqual(config?.resolvedMilestone, .foundation100)
        XCTAssertEqual(HousePreviewLaunch.parse(["app", "-LHHousePreview", "500", "reps", "light"])?.resolvedMilestone, .roof500)
        XCTAssertNil(HousePreviewLaunch.parse(["app", "-LHHousePreview", "abc", "reps", "light"]))
        XCTAssertNil(HousePreviewLaunch.parse(["app", "-LHHousePreview", "100"]))
        XCTAssertNil(HousePreviewLaunch.parse(["app"]))
    }
    #endif
}

final class HouseAssetTests: XCTestCase {

    private func image(_ name: String, dark: Bool = false) -> UIImage? {
        UIImage(named: name, in: Bundle.main, compatibleWith: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }

    /// The manifest the art lane exported (design/blueprint-house/exports/manifest.json).
    private func loadManifest() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design/blueprint-house/exports/manifest.json")
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("Manifest not readable from this test host (device run); the Swift-side names are still checked.")
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEveryManifestAssetResolves() throws {
        let manifest = try loadManifest()
        var names: [String] = []
        for entry in manifest["house"] as? [[String: Any]] ?? [] {
            names += [entry["built"] as? String, entry["lines"] as? String].compactMap { $0 }
        }
        names += (manifest["confirm_row"] as? [String: Any])?["frames"] as? [String] ?? []
        if let base = (manifest["confirm_row"] as? [String: Any])?["base"] as? String { names.append(base) }
        for tool in manifest["tools"] as? [[String: Any]] ?? [] {
            names += tool["images"] as? [String] ?? []
        }
        XCTAssertGreaterThanOrEqual(names.count, 38 + 13 + 22, "manifest looked empty")
        for name in names {
            XCTAssertNotNil(image(name), "\(name) does not resolve in the app bundle")
        }
    }

    func testSwiftKeyframesMatchManifestOrder() throws {
        let manifest = try loadManifest()
        let keys = (manifest["house"] as? [[String: Any]] ?? []).compactMap { $0["key"] as? String }
        XCTAssertEqual(keys, HouseKeyframe.allCases.map(\.rawValue))
        let frames = (manifest["confirm_row"] as? [String: Any])?["frames"] as? [String]
        XCTAssertEqual(frames, HouseMotion.confirmFrameNames)
        XCTAssertEqual((manifest["confirm_row"] as? [String: Any])?["base"] as? String, HouseKeyframe.confirmSequenceBase.builtImageName)
        XCTAssertEqual((manifest["confirm_row"] as? [String: Any])?["fps"] as? Double, HouseMotion.confirmFPS)
    }

    func testEverySwiftAssetNameResolvesLightAndDark() {
        for keyframe in HouseKeyframe.allCases {
            XCTAssertNotNil(image(keyframe.builtImageName), keyframe.builtImageName)
            XCTAssertNotNil(image(keyframe.builtImageName, dark: true), keyframe.builtImageName)
            XCTAssertNotNil(image(keyframe.linesImageName), keyframe.linesImageName)
        }
        for name in HouseMotion.confirmFrameNames {
            XCTAssertNotNil(image(name), name)
        }
        XCTAssertNotNil(UIColor(named: "bp_drafting", in: Bundle.main, compatibleWith: nil))
    }

    func testBuiltPassHasDistinctDarkLighting() throws {
        let light = try XCTUnwrap(image(HouseKeyframe.k14_siding040.builtImageName)?.pngData())
        let dark = try XCTUnwrap(image(HouseKeyframe.k14_siding040.builtImageName, dark: true)?.pngData())
        XCTAssertNotEqual(light, dark, "the dark built pass should resolve its own lighting")
    }

    // MARK: Snapshot-style: the right imageset per stage

    @MainActor
    private func render<V: View>(_ view: V, scheme: ColorScheme = .light) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: 160, height: 160).environment(\.colorScheme, scheme))
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    @MainActor
    func testHeroRendersTheExpectedKeyframePerStage() throws {
        let samples: [(Double, HouseKeyframe)] = [
            (0, .k00_lot), (120, .k01_slab), (212, .k03_frame020), (499, .k10_frame090),
            (500, .k12_roof), (680, .k15_siding060), (750, .k17_siding100), (751, .k18_finished),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (hours, keyframe) in samples {
                let hero = try XCTUnwrap(render(HouseHeroView(progress: HouseProgress(hours: hours, goal: .reps750), animatesConfirms: false), scheme: scheme))
                let expected = try XCTUnwrap(render(HouseArtView(keyframe: keyframe), scheme: scheme))
                XCTAssertEqual(hero, expected, "\(hours)h \(scheme) should draw \(keyframe.rawValue)")
                let neighbor = HouseKeyframe.allCases[keyframe.index == 0 ? 1 : keyframe.index - 1]
                let other = try XCTUnwrap(render(HouseArtView(keyframe: neighbor), scheme: scheme))
                XCTAssertNotEqual(hero, other, "\(hours)h must not look like \(neighbor.rawValue)")
            }
        }
    }

    @MainActor
    func testLineworkTintChangesTheRender() throws {
        let hero = try XCTUnwrap(render(HouseArtView(keyframe: .k04_frame030, canvas: .blueprintHero)))
        let card = try XCTUnwrap(render(HouseArtView(keyframe: .k04_frame030, canvas: .card)))
        XCTAssertNotEqual(hero, card)
    }
}
