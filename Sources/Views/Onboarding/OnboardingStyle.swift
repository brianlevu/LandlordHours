import SwiftUI

// MARK: - Onboarding on the standard components (standard §1.24; plan package B)
//
// v2: onboarding uses the app's own components and tokens. `OnbColor` and the `Onb*` button
// styles are deleted; buttons are `LHButton`, option rows are `LHRow.Browse` in one `LHRowGroup`,
// fields are `LHField`, the kind picker is `LHSegmented`. This file holds the three onboarding
// pieces that are not app components: the motion choices, the progress track and the option row
// (an `LHRow.Browse` with the trailing `checkmark` the standard specifies for selection).

/// The package's String Catalog (`Sources/Resources/Strings/ConversionPath.xcstrings`).
enum OnbStrings {
    static let table = "ConversionPath"
}

enum OnbMotion {
    /// Step to step: `flow` (0.30 spring, bounce 0). Reduce Motion: a `quick` crossfade.
    static func morph(_ reduce: Bool) -> Animation { reduce ? AppAnimation.quick : AppAnimation.flow }
    /// The progress fill: `smooth`. Reduce Motion: `quick`.
    static func progress(_ reduce: Bool) -> Animation { reduce ? AppAnimation.quick : AppAnimation.smooth }
    /// In-step reveals (a note, the address field): `flow`, or `quick` under Reduce Motion.
    static func flow(_ reduce: Bool) -> Animation { reduce ? AppAnimation.quick : AppAnimation.flow }
    /// The step content's transition: a short slide with opacity; opacity only under Reduce Motion.
    static func stepTransition(forward: Bool, reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .asymmetric(
            insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity),
            removal: .offset(x: forward ? -24 : 24).combined(with: .opacity))
    }
}

/// Progress (§1.24): a 3pt track in `border`, the fill in `action`.
struct OnbProgressTrack: View {
    var total: Int
    var value: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let fraction = CGFloat(value) / CGFloat(max(total, 1))
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.border)
                Capsule().fill(colors.action)
                    .frame(width: max(3, g.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
        .animation(OnbMotion.progress(reduce), value: value)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Step \(value) of \(total)", table: "ConversionPath"))
        .accessibilityIdentifier("onb-progress")
    }
}

/// One option in an onboarding question: an `LHRow.Browse` (the option's SF glyph in the leading
/// slot, title, one meta line) with a trailing `checkmark` in `action` (`.body.semibold`, 44 frame)
/// on the selected row. The whole row is the target. The 22pt leading circle is the confirm
/// control's (§1.3) and never appears here.
struct OnbOptionRow: View {
    var symbol: String
    var title: String
    var meta: String? = nil
    var selected: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Button(action: action) {
            HStack(spacing: 0) {
                LHRow.Browse(title: title, meta: meta, showsChevron: false) {
                    LHRowGlyph(systemImage: symbol, tint: selected ? .action : .neutral)
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .frame(width: 44, height: 44)
                    .opacity(selected ? 1 : 0)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LHButton.press)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The options of one question in one grouped container (§1.24): hairline dividers between rows,
/// and the container's edge turns `action` while a row in it is selected.
struct OnbOptionGroup<Content: View>: View {
    var hasSelection: Bool
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LHRowGroup { content }
            .overlay {
                if hasSelection {
                    RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                        .strokeBorder(colors.action, lineWidth: 1)
                }
            }
            .animation(AppAnimation.quick, value: hasSelection)
    }
}
