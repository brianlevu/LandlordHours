import SwiftUI

// MARK: - Screen header for Records and Reports (standard §1.14)
//
// `LHScreenTitle` composed with the two controls the tests and VoiceOver need to find by name:
// a back icon ("Back to Today") and one trailing icon (Export). Same layout as `LHScreenTitle`'s
// own back and trailing slots: the trailing icon sits beside the title and moves above it at
// accessibility sizes so the title keeps the full width.

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var back: (label: String, identifier: String, action: () -> Void)? = nil
    var trailing: (symbol: String, label: String, identifier: String, action: () -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize
    private var ax: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if back != nil || (ax && trailing != nil) {
                HStack {
                    if let back {
                        Button(action: back.action) { Image(systemName: "chevron.backward") }
                            .buttonStyle(LHButton.icon)
                            .accessibilityLabel(back.label)
                            .accessibilityIdentifier(back.identifier)
                    }
                    Spacer(minLength: 0)
                    if ax { trailingButton }
                }
            }
            HStack(alignment: .center, spacing: 12) {
                LHScreenTitle(title, subtitle: subtitle)
                if !ax { trailingButton }
            }
        }
    }

    @ViewBuilder private var trailingButton: some View {
        if let trailing {
            Button(action: trailing.action) { Image(systemName: trailing.symbol) }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel(trailing.label)
                .accessibilityIdentifier(trailing.identifier)
        }
    }
}
