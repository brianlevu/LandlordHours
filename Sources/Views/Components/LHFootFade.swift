import SwiftUI

// MARK: - LHFootFade (standard §1.20, 2.3 amendment 7)
//
// The background of a pinned sheet foot (`safeAreaInset(edge: .bottom)` holding the `.primary`):
// opaque in the sheet's own surface colour, with a 16pt fade above it, so content scrolling under
// the button softens instead of being cut flat. Pass the sheet's surface: `background` for sheets of
// grouped cards (lessons, pick your free rental), `backgroundSecondary` for sheets of inner
// surfaces (day-12 reminder, Log time). Never hit-testable; runs into the bottom safe area.
// [grep] no hand-made `LinearGradient(… .opacity(0) …)` foot outside this file (lint `foot-fade`).

struct LHFootFade: View {
    static let fadeHeight: CGFloat = 16
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fadeHeight)
            color
        }
        .padding(.top, -Self.fadeHeight)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
