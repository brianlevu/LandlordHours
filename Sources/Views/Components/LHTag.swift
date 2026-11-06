import SwiftUI

// MARK: - LHTag and LHChip (standard §1.16)
//
//            LHTag                         LHChip
// Height     20                            34 (44 tap frame)
// Type       .caption2.medium              .subheadline.medium
// Padding    6 / 2                         12 / 0
// Shape      radius 6                      capsule
// Colour     intent ink on a 12% wash      selected action / onAction; idle backgroundTertiary / textPrimary
//            (category wash for categories)
// Limit      2 per row ("+1" overflow)     one strip per screen, 8 gaps
//
// A tag is read-only metadata on a row, never a button. A chip filters or prefills; it is never the
// primary action.

struct LHTag: View {
    enum Tone: Equatable {
        case neutral
        case positive
        case caution
        case destructive
        case informational
        case action
        /// A category's own ink and wash (from `ActivityCategory`'s colour tokens).
        case custom(ink: Color, wash: Color)

        /// The tone every category tag uses (Inbox and Today rows): the tag ink on its own 12% wash, so
        /// every pair is >= 4.5:1 (`categoryTagInkHex`). The 14% tile ink (`categoryInk`) is for bars and labels.
        static func category(_ category: ActivityCategory, colors: AdaptiveColors) -> Tone {
            .custom(ink: colors.categoryTagInk(category), wash: colors.categoryTagWash(category))
        }
    }

    let text: String
    var tone: Tone = .neutral

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    static let height: CGFloat = 20
    static let radius: CGFloat = 6
    static let maxPerRow = 2

    private var ink: Color {
        switch tone {
        case .neutral: return colors.textSecondary
        case .positive: return colors.positive
        case .caution: return colors.caution
        case .destructive: return colors.destructive
        case .informational: return colors.informational
        case .action: return colors.action
        case .custom(let ink, _): return ink
        }
    }

    private var wash: Color {
        switch tone {
        case .neutral: return colors.textSecondary.opacity(AppColors.tagWashOpacity)
        case .positive: return colors.positiveSurface
        case .caution: return colors.cautionSurface
        case .destructive: return colors.destructiveSurface
        case .informational: return colors.informationalSurface
        case .action: return colors.actionSurface
        case .custom(_, let wash): return wash
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(ink)
            // One line at default; at AX sizes a tag wraps rather than truncating ("Rep…").
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minHeight: Self.height)
            .background(wash, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .layoutPriority(1)
    }

    /// Up to two tags, then "+N" (§1.3 meta line).
    static func capped(_ tags: [LHTag]) -> (shown: [LHTag], overflow: Int) {
        (Array(tags.prefix(maxPerRow)), max(0, tags.count - maxPerRow))
    }
}

// MARK: - LHChip

struct LHChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static let height: CGFloat = 34

    init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? colors.onAction : colors.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: Self.height)
            .background(isSelected ? colors.action : colors.backgroundTertiary, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : colors.border, lineWidth: 0.5))
            .animation(AppAnimation.quick, value: isSelected)
            .frame(minHeight: 44)
        }
        .buttonStyle(LHButton.press)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One horizontal chip strip per screen, 8pt gaps, page gutter 20.
struct LHChipStrip<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, LHMetrics.gutter)
        }
        .scrollIndicators(.hidden)
    }
}
