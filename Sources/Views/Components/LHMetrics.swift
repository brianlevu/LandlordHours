import SwiftUI

// MARK: - LHMetrics (standard §1.2) and LayoutBand (§1.27)
//
// The spacing and radius tokens every LH* component uses. Page gutter 20 (24 in bands B and C),
// section gap 24, header → content 8, card padding 16, card radius 20 (continuous), inner surface
// 12, stat tile 16, tag 6, hairline 0.5.

enum LHMetrics {
    static let gutter: CGFloat = 20
    static let wideGutter: CGFloat = 24
    static let sectionGap: CGFloat = 24
    static let headerToContent: CGFloat = 8
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 12
    static let tileRadius: CGFloat = 16
    static let tagRadius: CGFloat = 6
    static let hairline: CGFloat = 0.5
    /// Minimum tap target for every control (§1.17).
    static let minTap: CGFloat = 44
    /// Row heights (D1): 56–88 at default, target 64.
    static let rowMinHeight: CGFloat = 56
    static let rowTargetHeight: CGFloat = 64
    static let rowMaxHeight: CGFloat = 88
    /// Reading column cap (§1.27).
    static let readingColumn: CGFloat = 600

    /// The page gutter for a band.
    static func gutter(for band: LayoutBand) -> CGFloat { band == .a ? gutter : wideGutter }
}

// MARK: - Layout band

/// Window-width band (§1.27): A < 600 (the phone layout), B 600–899 (one column ≤ 600), C ≥ 900.
/// Bands carry 8pt hysteresis (A↔B at 592/608, B↔C at 892/908). This is the only place a band is
/// computed; the root reads the scene width with `onGeometryChange` and passes the band down.
enum LayoutBand: String, Equatable, Sendable, CaseIterable {
    case a, b, c

    static let hysteresis: CGFloat = 8

    /// The band for `width`, keeping `previous` while the width sits inside its 8pt hysteresis.
    static func resolve(previous: LayoutBand?, width: CGFloat) -> LayoutBand {
        guard width.isFinite, width > 0 else { return previous ?? .a }
        let raw: LayoutBand = width < 600 ? .a : (width < 900 ? .b : .c)
        guard let previous, previous != raw else { return raw }
        // Stay in the previous band until the width clears the boundary by the hysteresis.
        switch (previous, raw) {
        case (.a, .b): return width >= 600 + hysteresis ? .b : .a
        case (.b, .a): return width < 600 - hysteresis ? .a : .b
        case (.b, .c): return width >= 900 + hysteresis ? .c : .b
        case (.c, .b): return width < 900 - hysteresis ? .b : .c
        default: return raw   // a jump over a whole band (a ↔ c) is never held
        }
    }
}

private struct LayoutBandKey: EnvironmentKey {
    static let defaultValue: LayoutBand = .a
}

extension EnvironmentValues {
    /// The window's layout band, set once at the root (`ContentView`).
    var layoutBand: LayoutBand {
        get { self[LayoutBandKey.self] }
        set { self[LayoutBandKey.self] = newValue }
    }
}

// MARK: - Hairline

/// The 0.5pt `border` divider used between rows, with the row grid's leading inset.
struct LHDivider: View {
    var leadingInset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AdaptiveColors(colorScheme: colorScheme).border)
            .frame(height: LHMetrics.hairline)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}
