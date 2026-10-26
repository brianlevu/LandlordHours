import SwiftUI

// MARK: - Welcome's footer (P1 / P3 / P2), hosted by B's Welcome under the primary button
//
// `.footnote`, `textSecondary` on the dusk/night page (B's visual contract). While the device set
// is empty and iCloud is on it says it is checking (≤ 8 s, with a small spinner), then what it
// found ("They're already here." and the button reads Continue), else P1.

struct WelcomeRecordsFooter: View {
    let state: WelcomeRecordsState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        // A spinner has no text baseline, so it is centred on the line; when the line wraps
        // (XXL and up) it sits above the text, centred, instead of beside the first line (gate B5).
        let stacked = state == .checking && typeSize >= .xxLarge
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .center, spacing: 6))
                             : AnyLayout(HStackLayout(alignment: state == .checking ? .center : .firstTextBaseline, spacing: 8))
        layout {
            switch state {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .tint(colors.textSecondary)
                    .accessibilityHidden(true)
                Text(IdentityCopy.welcomeChecking)
            case .found(let hours):
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityHidden(true)
                Text(IdentityCopy.welcomeFound(hours))
            case .standard:
                Text(IdentityCopy.welcomeFooter)
            }
        }
        .font(.footnote)
        .foregroundStyle(colors.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .animation(reduceMotion ? nil : AppAnimation.quick, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var identifier: String {
        switch state {
        case .standard: return "welcome.records.p1"
        case .checking: return "welcome.records.checking"
        case .found: return "welcome.records.found"
        }
    }
}
