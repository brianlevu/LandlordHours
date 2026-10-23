import SwiftUI
import UIKit
import LucideIcons

// MARK: - Log time: shared look (tokens, chips, small pieces)
//
// The note-first sheet (approved prototype r5, proto/logtime-note-first 6a281db): bare note on the
// canvas, one quiet details line, rows that unfold out of it, one filled Log button that names what
// it will do. Cards are lifted off the canvas in dark mode.

extension AdaptiveColors {
    /// Cards on the Log sheet. Dark: lifted off the canvas (the brand card was 1.25:1 against it).
    var sheetCard: Color { colorScheme == .dark ? Color(hex: "283360") : backgroundSecondary }
    /// Hairline around those cards.
    var sheetStroke: Color { colorScheme == .dark ? Color.white.opacity(0.10) : border }
    /// "This came from your note": the timber accent (ink on light, timber on dark).
    var noteMark: Color { colorScheme == .dark ? timber : timberInk }
}

/// Wrapping row of chips (the Log sheet's inline editors and recents).
struct LogChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 10_000, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in layout.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: ProposedViewSize(width: layout.sizes[index].width, height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint], sizes: [CGSize]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxWidth: CGFloat = 0
        var points: [CGPoint] = [], sizes: [CGSize] = []
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); sizes.append(size)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height); maxWidth = max(maxWidth, min(width, x - spacing))
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), points, sizes)
    }
}

/// A pill the user taps to pick a value (rental, kind of work, hours, day).
struct LogChip: View {
    let title: String
    var selected = false
    var identifier: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: scheme)
        let button = Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(selected ? colors.actionText : colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? colors.actionSurface : colors.background))
                .overlay(Capsule().strokeBorder(selected ? colors.action : colors.sheetStroke, lineWidth: selected ? 1.5 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if let identifier { button.accessibilityIdentifier(identifier) } else { button }
    }
}

/// The timber sparkle: "your note said this".
struct LogSparkle: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 14

    var body: some View {
        LucideIcon(image: Lucide.sparkles, size: size)
            .foregroundStyle(AdaptiveColors(colorScheme: scheme).noteMark)
            .accessibilityHidden(true)
    }
}

/// "A 1.5pt line being drawn": the reading caption's loader. Static under Reduce Motion.
struct LogReadingLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drawn = false

    var body: some View {
        Capsule()
            .fill(AdaptiveColors(colorScheme: scheme).draftingInk)
            .frame(width: 26, height: 1.5)
            .scaleEffect(x: reduceMotion || drawn ? 1 : 0.1, anchor: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) { drawn = true }
            }
            .accessibilityHidden(true)
    }
}
