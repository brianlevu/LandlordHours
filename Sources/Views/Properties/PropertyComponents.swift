import SwiftUI

// MARK: - Properties: parts other packages still call (v2, plan package F)
//
// The v2 Rentals screens use the `LH*` components and the house-only thumbnail (`LHThumb`); none
// of the types below appears on them. They stay only because other packages' 1.x screens still
// call them (`PropertySeal`: Log time pickers, profile sheets; `propertyCard`/`PropertyInsetDivider`:
// Learn, Delete all data, profile sheets; `PropertySectionHeader`: Log time pickers;
// `PropertyTintedButtonStyle`: Log time, the timer, Delete all data). Each lane removes its own
// uses; the cleanup pass (plan §3 step 7) deletes this file's legacy types when no caller remains.
// `PropertyChipFlow` is the edit sheet's wrapping layout for other names.

/// The rental's identity: a circle in its colour at a 14% wash, a 1pt ring at 40%, an inner
/// hairline inset 3pt, and a two-letter monogram. Colour by creation order (PropertySealStyle).
struct PropertySeal: View {
    var monogram: String
    var palette: SealPalette = .blueprint
    var size: CGFloat = 40
    /// The ghost seal of "Your next rental" on the locked row.
    var dashed = false
    @Environment(\.colorScheme) private var colorScheme

    init(_ property: RentalProperty, in properties: [RentalProperty], size: CGFloat = 40) {
        monogram = PropertySealStyle.monogram(property.name)
        palette = PropertySealStyle.palette(for: property, in: properties)
        self.size = size
    }

    init(monogram: String, palette: SealPalette = .blueprint, size: CGFloat = 40, dashed: Bool = false) {
        self.monogram = monogram
        self.palette = palette
        self.size = size
        self.dashed = dashed
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let ink = dashed ? colors.textTertiary : colors.sealInk(palette)
        ZStack {
            Circle().fill(ink.opacity(dashed ? 0.06 : 0.14))
            if dashed {
                Circle().strokeBorder(ink.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                Circle().strokeBorder(ink.opacity(0.4), lineWidth: 1)
                Circle().strokeBorder(ink.opacity(0.22), lineWidth: 0.5).padding(3)
            }
            Text(monogram)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Tinted button (44pt, action on actionSurface, 15 semibold).
struct PropertyTintedButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().fill(colors.actionSurface))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// The one card surface: radius 20, a 4% shadow in light only.
struct PropertyCardModifier: ViewModifier {
    var radius: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        content
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 6, x: 0, y: 2)
    }
}

extension View {
    func propertyCard(_ radius: CGFloat = 20) -> some View { modifier(PropertyCardModifier(radius: radius)) }
}

/// Hairline inset to the text column.
struct PropertyInsetDivider: View {
    var leading: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Rectangle()
            .fill(AdaptiveColors(colorScheme: colorScheme).border)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

/// Section header with an optional trailing link ("See all in Records").
struct PropertySectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension PropertySectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Wraps chips onto as many rows as they need (other names).
struct PropertyChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
