import SwiftUI

// MARK: - LayoutMode: compact, two-pane or stacked (standard §1.27; plan package J)
//
// The one place the layout mode is computed [grep]. Inputs are the scene's size W × H (from
// `onGeometryChange` on the root, never the screen, the idiom, a device name or the orientation),
// the active `.division` region if there is one (the Duo's fold, iOS 27.1 `reservedRegions`), and
// whether a resize is live.
//
//   · a vertical division (the Duo held open) → two-pane split at the division, if each pane ≥ 380;
//   · a horizontal division (the Duo propped) → stacked split at the division, if each half ≥ 380;
//   · no division → two-pane iff W ≥ 800 and H ≥ 645, else compact.
//
// Hysteresis only while a resize is live, and only above the threshold: two-pane turns on at
// 808 / 653 and off below 800 / 645. When the size has been still for 0.3 s, and at every scene
// connect and launch, the mode is re-resolved with no history (`previous: nil`), so a window
// settled at a given size always gets the same mode. Inside compact the A/B split (600) is
// `LayoutBand`'s (A2), kept as it was.

enum LayoutMode: Equatable, Sendable {
    /// One column: the locked phone Today (bands A/B inside it).
    case compact
    /// The house on the left, the workstation on the right.
    case twoPane
    /// Two-pane turned on its side: house above, workstation below (the Duo propped).
    case stacked

    var isSplit: Bool { self != .compact }
}

/// The fold or gap between the panes.
struct PaneDivision: Equatable, Sendable {
    /// The division's rect in the root's space, margins included.
    let rect: CGRect

    /// A tall, thin division runs top to bottom: the panes sit side by side.
    var isVertical: Bool { rect.height >= rect.width }
}

/// The mode plus the geometry of the panes.
struct LayoutSplit: Equatable, Sendable {
    let mode: LayoutMode
    /// The window size the split was resolved for.
    let size: CGSize
    /// The gap (iPad: `LayoutMode.paneGap`) or the fold band (the Duo: the division rect).
    let gap: CGRect
    /// True when the gap is a physical division (the Duo), not the iPad's page gap.
    let isDivision: Bool

    /// Leading (two-pane) or top (stacked) pane rect.
    var first: CGRect {
        switch mode {
        case .compact: return CGRect(origin: .zero, size: size)
        case .twoPane: return CGRect(x: 0, y: 0, width: gap.minX, height: size.height)
        case .stacked: return CGRect(x: 0, y: 0, width: size.width, height: gap.minY)
        }
    }

    /// Trailing (two-pane) or bottom (stacked) pane rect.
    var second: CGRect {
        switch mode {
        case .compact: return .zero
        case .twoPane: return CGRect(x: gap.maxX, y: 0, width: max(0, size.width - gap.maxX), height: size.height)
        case .stacked: return CGRect(x: 0, y: gap.maxY, width: size.width, height: max(0, size.height - gap.maxY))
        }
    }

    static func compact(_ size: CGSize) -> LayoutSplit {
        LayoutSplit(mode: .compact, size: size, gap: .zero, isDivision: false)
    }
}

extension LayoutMode {
    /// The iPad gap between the panes (the Duo's assumed fold band). The one allowed hard-coded 24
    /// in shipping layout code (§1.27 [grep]); the Duo reads its band from the division.
    static let paneGap: CGFloat = 24
    /// The narrowest pane: the 290 hero with 16 gutters and a phone-width list.
    static let minPane: CGFloat = 380
    /// Two-pane from 800 × 645 (panes of 388; above the 11" 2/3 tile; 290 / 0.45 = 645).
    static let minWidth: CGFloat = 800
    static let minHeight: CGFloat = 645
    /// Live-resize hysteresis above the threshold.
    static let hysteresis: CGFloat = 8
    /// The quiet time after which a live resize counts as settled and the mode is re-resolved
    /// with no history.
    static let settleDelay: Double = 0.3

    /// The one mode function.
    /// - Parameters:
    ///   - previous: the mode before this change, used only while `live` (nil = no history).
    ///   - size: the scene's size.
    ///   - division: the active `.division` region (the Duo's fold), if any.
    ///   - live: a resize is in progress (sizes changing within `settleDelay`).
    static func resolve(previous: LayoutMode?, size: CGSize, division: PaneDivision?, live: Bool) -> LayoutSplit {
        let w = size.width, h = size.height
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return .compact(size) }

        if let division {
            let r = division.rect
            if division.isVertical {
                // The Duo held open: two panes split at the fold, each at least 380 wide.
                guard r.minX >= minPane, w - r.maxX >= minPane else { return .compact(size) }
                return LayoutSplit(mode: .twoPane, size: size, gap: r, isDivision: true)
            } else {
                // The Duo propped up: stacked at the fold, each half at least 380 tall.
                guard r.minY >= minPane, h - r.maxY >= minPane else { return .compact(size) }
                return LayoutSplit(mode: .stacked, size: size, gap: r, isDivision: true)
            }
        }

        // No division: the width and height floors, with hysteresis only while a live resize
        // continues a two-pane window (on at 808/653 from compact, off below 800/645).
        let wasSplit = live && previous == .twoPane
        let onW = wasSplit ? minWidth : minWidth + (live ? hysteresis : 0)
        let onH = wasSplit ? minHeight : minHeight + (live ? hysteresis : 0)
        guard w >= onW, h >= onH else { return .compact(size) }
        let pane = (w - paneGap) / 2
        guard pane >= minPane else { return .compact(size) }
        let gap = CGRect(x: pane, y: 0, width: paneGap, height: h)
        return LayoutSplit(mode: .twoPane, size: size, gap: gap, isDivision: false)
    }
}

// MARK: - Sizes inside a pane (§1.27 "Sizes by mode")

enum PaneMetrics {
    /// Content inside a pane is capped at 600 and centred (13" landscape: panes 676, content 600).
    static let contentCap: CGFloat = 600
    /// Room the floating tab bar takes at the foot of the right pane (bar ~62 + its float + air):
    /// the last row clears the bar glass at rest (DU4, v7 `barClearance`).
    static let barClearance: CGFloat = 84

    /// The gutter inside a pane: 16 on the Duo and in iPad panes under 440, else 24 (§1.27 density).
    static func gutter(paneWidth: CGFloat, onDuo: Bool = false) -> CGFloat { (onDuo || paneWidth < 440) ? 16 : 24 }

    /// The content width of a pane: the pane, capped at 600.
    static func contentWidth(paneWidth: CGFloat) -> CGFloat { min(paneWidth, contentCap) }

    /// The two-pane hero: `clamp(round(0.626 × pane), 290, 390)`, never above 0.45 × H; × 0.75 at AX.
    ///
    /// iPad sizing (plan J, Brian 2026-10-25): a tall pane may grow the hero to the pane's content
    /// width less its gutters and 0.45 × H, so the house fills the wall instead of leaving a phone-
    /// sized house on a tall iPad pane (DU4's 20% empty wall applies to both panes). The cap stays
    /// 390 on the Duo and in every pane whose height is under 900.
    static func heroSide(paneWidth: CGFloat, paneHeight: CGFloat, accessibility: Bool) -> CGFloat {
        let content = contentWidth(paneWidth: paneWidth)
        var side = min(max((0.626 * content).rounded(), 290), 390)
        if paneHeight >= 900 {
            // Tall iPad panes (portrait): fill toward the content width, never past 0.45 × H.
            side = max(side, min(content - 2 * gutter(paneWidth: paneWidth), 0.45 * paneHeight, 480))
        }
        side = min(side, 0.45 * paneHeight)
        // At AX the hero is × 0.75, never under the 220 diorama floor (§H.5).
        if accessibility { side = max(CraftHeroSize.minimumDioramaSide, side * 0.75) }
        return side.rounded()
    }

    /// The stacked hero sits beside the number block at 220; the diorama floor keeps it 220 at AX.
    static func stackedHeroSide(accessibility: Bool) -> CGFloat { CraftHeroSize.minimumDioramaSide }

    /// The numeral: 76 in a pane (84 in a pane of 500 or more on a tall window), 60 stacked, 54 at AX.
    static func numeral(mode: LayoutMode, paneWidth: CGFloat, paneHeight: CGFloat, accessibility: Bool) -> CGFloat {
        if accessibility { return 54 }
        switch mode {
        case .stacked: return 60
        case .twoPane: return (paneWidth >= 500 && paneHeight >= 900) ? 84 : 76
        case .compact: return 84
        }
    }

    /// The shelf's house model: 104 on the Duo and narrow panes (in 108 slots), growing with the
    /// pane so a wide iPad shelf is not a strip of tiny houses (max 140).
    static func shelfModel(paneWidth: CGFloat) -> CGFloat {
        let content = contentWidth(paneWidth: paneWidth)
        return min(max((content * 0.225).rounded(), 104), 140)
    }
}

// MARK: - Environment

private struct LayoutModeKey: EnvironmentKey {
    static let defaultValue: LayoutMode = .compact
}

extension EnvironmentValues {
    /// The window's layout mode, set once by `TwoPaneLayout`.
    var layoutMode: LayoutMode {
        get { self[LayoutModeKey.self] }
        set { self[LayoutModeKey.self] = newValue }
    }
}
