import SwiftUI

// MARK: - Category tool tile (shared, plan package 0)
//
// Moved out of `Inbox/InboxComponents.swift` (v2 revamp plan, package 0a) so Records, Inbox, Log
// time, Reports and the confirm sheet consume one component that no screen lane owns. The
// category's art name and wash (`blueprintToolName`, `inboxWash`) stay on the `ActivityCategory`
// extension in the Inbox file. Sizes per the design standard: 36 in browse rows and picker lists,
// 56 in picker grids and sheet headers, never under 32, never in decision rows.

/// The category's tool on a soft material tile. Falls back to a dashed drafting square, never a
/// flat symbol mixed into the 3D set.
struct CategoryToolTile: View {
    let category: ActivityCategory?
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(category.map { $0.inboxWash(colors) } ?? colors.backgroundTertiary)
            .frame(width: size, height: size)
            .overlay {
                if let category {
                    Image("bp_tool_\(category.blueprintToolName)_\(size > 40 ? 56 : 36)")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.08)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(colors.drafting, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .padding(size * 0.22)
                }
            }
            .accessibilityHidden(true)
    }
}
