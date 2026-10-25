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

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch state {
            case .checking:
                ProgressView()
                    .controlSize(.mini)
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
