import SwiftUI

// MARK: - Properties (2.0) shared parts
//
// The rental's identity (seal), its own mini-house, and the `.row` size of the one locked
// preview. Spec: AgentScratch redesign-specs.md §0 + §4; sandbox S2Core.swift (approved r4).

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

/// The rental's own hours as a house stage (Today's mapping), on a small blueprint tile. The
/// plaster slab and timber frame read against blue; linework is left off at mini size so the
/// built stage is what reads. Always shown beside an hours label. Decorative.
struct PropertyHouseTile: View {
    let hours: Double
    var size: CGFloat = 48

    var body: some View {
        let keyframe = PropertyHouseStage.keyframe(for: hours)
        InboxBlueprintPaper(cornerRadius: size * 0.28)
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    Image(decorative: keyframe.builtImageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                    if size >= 80 {
                        HouseLineworkImage(name: keyframe.linesImageName)
                            .foregroundStyle(HouseTokens.drafting)
                            .opacity(0.8)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(1.18)
                .offset(y: -size * 0.02)
            }
            .overlay(alignment: .bottom) {
                // Below the slab the art can't move yet (0h and 27h are the same empty lot), so a
                // thin drafting line fills toward "Foundation at 100h".
                if hours < HouseStep.foundation.thresholdHours {
                    GroundworkProgressLine(fraction: max(0, hours) / HouseStep.foundation.thresholdHours)
                        .padding(.horizontal, size * 0.16)
                        .padding(.bottom, size * 0.1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Progress toward the slab, drawn on the blueprint tile: a 3pt drafting track with a cyan fill.
struct GroundworkProgressLine: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(HouseTokens.drafting.opacity(0.3))
                Capsule().fill(HouseTokens.drafting)
                    .frame(width: fraction > 0 ? max(3, g.size.width * min(1, fraction)) : 0)
            }
        }
        .frame(height: 3)
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

/// Scroll edge under the status bar: content fades into the canvas instead of meeting the clock.
struct PropertyTopEdgeFade: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let canvas = AdaptiveColors(colorScheme: colorScheme).background
        Color.clear.frame(maxWidth: .infinity).frame(height: 0)
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [.init(color: canvas, location: 0), .init(color: canvas, location: 0.78),
                                       .init(color: canvas.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
                    .offset(y: 18)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// "How do guests stay?": two capsules in one track.
struct PropertyStaySegment: View {
    @Binding var propertyType: PropertyType
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 2))
        // Stacked (AX sizes), the pills are rounded rectangles with an equal 4pt gap on every
        // side of the container, so the selected one is centred in its track.
        let radius: CGFloat = stacked ? 24 : 26
        layout {
            segment("Months or longer", type: .ltr, colors: colors)
            segment("A few nights at a time", type: .str, colors: colors)
        }
        .padding(stacked ? 4 : 3)
        .background(RoundedRectangle(cornerRadius: radius + 4, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: radius + 4, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
        .sensoryFeedback(.selection, trigger: propertyType)
    }

    private func segment(_ title: String, type: PropertyType, colors: AdaptiveColors) -> some View {
        let on = propertyType == type
        return Button {
            if reduceMotion { propertyType = type } else { withAnimation(AppAnimation.quick) { propertyType = type } }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(on ? colors.onAction : colors.textPrimary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 24 : 26, style: .continuous).fill(on ? colors.action : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(type == .ltr ? "property.stay.long" : "property.stay.short")
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

/// A future "PEOPLE" section on the property detail (smart layer: key contacts). Data-driven:
/// with no people it renders nothing and reserves no space. No feature is built yet.
struct PropertyPerson: Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    let visits: Int
}
