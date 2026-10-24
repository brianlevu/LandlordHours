import XCTest
import SwiftUI
import UIKit
@testable import LandlordHours

/// WP-H: motion plans (Reduce Motion paths and timing caps), asset resolution against the art
/// manifest, and a snapshot-style check that each stage renders the right imageset.
final class HouseMotionTests: XCTestCase {

    func testReduceMotionNeverAnimates() {
        XCTAssertEqual(HouseMotion.keyframeTransition(from: .k04_frame030, to: .k05_frame040, reduceMotion: true), .instant)
        for (old, new) in [(680.0, 682.0), (50, 120), (499, 501), (699, 701)] {
            let plan = HouseMotion.confirmPlan(oldHours: old, newHours: new, reduceMotion: true)
            XCTAssertFalse(plan.beam)
            XCTAssertNil(plan.boardOffset)
            XCTAssertFalse(plan.glow)
            XCTAssertFalse(plan.countUp)
            XCTAssertEqual(plan.keyframe, .instant)
            XCTAssertEqual(plan.target, HouseProgress.keyframe(for: new))
        }
        for c in [HouseCelebration.stage(.foundation100), .stage(.roof500), .stage(.keys750), .goalMet(.mp500)] {
            XCTAssertEqual(HouseMotion.celebrationSettleDuration(c, reduceMotion: true), 0.2, accuracy: 0.0001)
        }
    }

    func testConfirmIsRewardingAndTheHouseOnlyGrows() {
        // Same keyframe: beam, glow and count-up, but NO board (a board that then vanished
        // would take a course away, which the r1 gate measured as siding falling 4.2%).
        let same = HouseMotion.confirmPlan(oldHours: 600, newHours: 602, reduceMotion: false)
        XCTAssertTrue(same.beam && same.glow && same.countUp)
        XCTAssertNil(same.boardOffset)
        XCTAssertEqual(same.keyframe, .instant)
        XCTAssertEqual(same.target, .k14_siding040)
        // Crossing into a siding keyframe: board onto the new course, then crossfade to it.
        let siding = HouseMotion.confirmPlan(oldHours: 649, newHours: 651, reduceMotion: false)
        XCTAssertEqual(siding.target, .k15_siding060)
        XCTAssertEqual(siding.boardOffset ?? 99, HouseKeyframe.k15_siding060.courseAnchor.y - 0.577, accuracy: 0.0001)
        XCTAssertEqual(siding.keyframe, .crossfade(duration: HouseMotion.keyframeCrossfade))
        // Crossing a framing keyframe: no siding board, but the house crossfades and grows.
        let frame = HouseMotion.confirmPlan(oldHours: 139, newHours: 141, reduceMotion: false)
        XCTAssertNil(frame.boardOffset)
        XCTAssertEqual(frame.keyframe, .crossfade(duration: HouseMotion.keyframeCrossfade))
        XCTAssertEqual(frame.anchor, HouseKeyframe.k02_frame010.courseAnchor)
        // Nothing added, or hours removed: nothing plays.
        XCTAssertTrue(HouseMotion.confirmPlan(oldHours: 200, newHours: 200, reduceMotion: false).isEmpty)
        XCTAssertTrue(HouseMotion.confirmPlan(oldHours: 200, newHours: 150, reduceMotion: false).isEmpty)
    }

    func testSidingRunsForward() {
        // 600h and 602h are the same course (k14, siding 40%); more hours never pick an earlier one.
        XCTAssertEqual(HouseProgress.keyframe(for: 600), .k14_siding040)
        XCTAssertEqual(HouseProgress.keyframe(for: 602), .k14_siding040)
        XCTAssertEqual(HouseProgress.keyframe(for: 650), .k15_siding060)
        // Each siding keyframe's new course sits higher than the last (smaller y) until 80%.
        let ys = [HouseKeyframe.k13_siding020, .k14_siding040, .k15_siding060, .k16_siding080].map(\.courseAnchor.y)
        XCTAssertEqual(ys, ys.sorted(by: >))
    }

    func testTimingCaps() {
        XCTAssertEqual(HouseMotion.confirmFrameCount, 13)
        XCTAssertEqual(HouseMotion.confirmSequenceDuration, 13.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(HouseMotion.beamSpringResponse, 0.32)
        XCTAssertEqual(HouseMotion.beamSpringDamping, 0.86)
        XCTAssertLessThanOrEqual(HouseMotion.beamFlight, 0.2)
        XCTAssertLessThanOrEqual(HouseMotion.backfillTotalDuration, 2.5, "backfill sketch-in must finish within 2.5 s")
        XCTAssertLessThanOrEqual(HouseMotion.backfillLeadIn + HouseMotion.backfillSketchDuration, HouseMotion.backfillTotalDuration)
        for c in [HouseCelebration.stage(.foundation100), .stage(.roof500), .stage(.keys750), .goalMet(.reps750), .goalMet(.mp500), .goalMet(.mp100)] {
            XCTAssertLessThan(HouseMotion.celebrationSettleDuration(c, reduceMotion: false), 3, "\(c) must run under 3 s")
        }
        XCTAssertEqual(HouseMotion.roofDropPoints, 12)
        XCTAssertEqual(HouseMotion.confirmFrameNames.first, "bp_confirm_row_00")
        XCTAssertEqual(HouseMotion.confirmFrameNames.last, "bp_confirm_row_12")
    }

    func testCelebrationCopyNeverOverclaims() {
        XCTAssertTrue(MilestoneCelebrationView.detail(for: .stage(.roof500), hours: 500).contains("needs more than 500"))
        XCTAssertTrue(MilestoneCelebrationView.detail(for: .stage(.roof500), hours: 502).contains("Past the 500-hour line"))
        XCTAssertTrue(MilestoneCelebrationView.detail(for: .stage(.foundation100), hours: 100).contains("needs more than 100"))
        XCTAssertEqual(MilestoneCelebrationView.title(for: .goalMet(.mp100)), "100 hours.")
        XCTAssertEqual(MilestoneCelebrationView.title(for: .stage(.roof500)), "500 hours.")
        XCTAssertEqual(MilestoneCelebrationView.hoursLine(for: .goalMet(.reps750), hours: 751.4, year: 2026), "751 confirmed hours in 2026")
        let all: [HouseCelebration] = [.stage(.foundation100), .stage(.roof500), .stage(.keys750), .goalMet(.reps750), .goalMet(.mp500), .goalMet(.mp100)]
        for c in all {
            for hours in [c.thresholdHours, c.thresholdHours + 1] {
                XCTAssertFalse(MilestoneCelebrationView.detail(for: c, hours: hours).lowercased().contains("qualif"))
            }
        }
    }

    func testLineworkAlphaIsLiftedToTokenContrast() throws {
        // The exported strokes peak at alpha 92/255 (0.36); lifted they must reach >= 0.8 so
        // #8FD3FF on #1E3FA6 clears 4:1 (non-text floor 3:1; concept ~4.3:1).
        let boosted = try XCTUnwrap(HouseLineworkStore.image(named: HouseKeyframe.k04_frame030.linesImageName)?.cgImage)
        let raw = try XCTUnwrap(UIImage(named: HouseKeyframe.k04_frame030.linesImageName)?.cgImage)
        XCTAssertGreaterThanOrEqual(Self.maxAlpha(boosted), 204)
        XCTAssertLessThanOrEqual(Self.maxAlpha(raw), 100)
    }

    static func maxAlpha(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var best: UInt8 = 0
        var i = 3
        while i < data.count { best = max(best, data[i]); i += 4 }
        return Int(best)
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
        XCTAssertEqual(config?.resolvedCelebration, .stage(.foundation100))
        XCTAssertEqual(HousePreviewLaunch.parse(["app", "-LHHousePreview", "500", "reps", "light"])?.resolvedCelebration, .stage(.roof500))
        XCTAssertEqual(HousePreviewLaunch.parse(["app", "-LHHousePreview", "501", "mp500", "light"])?.resolvedCelebration, .goalMet(.mp500))
        XCTAssertEqual(HousePreviewLaunch.parse(["app", "-LHHousePreview", "300", "mp100", "light", "-LHHouseStartDelay", "2"])?.startDelay, 2)
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

    /// v2: the Today hero is `CraftHouseView`; every stage draws its own still (lit and unlit).
    @MainActor
    func testCraftHeroRendersADistinctStillPerStage() throws {
        for scheme in [ColorScheme.light, .dark] {
            var seen: [Data] = []
            for stage in CraftStage.allCases {
                let lit = try XCTUnwrap(render(CraftHouseView(stage: stage, windowsLit: true, side: 160), scheme: scheme))
                XCTAssertFalse(seen.contains(lit), "\(stage) \(scheme) must not look like an earlier stage")
                seen.append(lit)
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
