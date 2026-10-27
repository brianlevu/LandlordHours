import SwiftUI

// MARK: - LHField (standard §1.7)
//
// Single line: inner surface radius 12, height 52, padding 16 / 14, `.body`. Placeholder in
// `textTertiary` (5.5:1), never the system placeholder grey. Focus: 1.5pt `action` stroke
// (motion `fieldFocus`, 0.15). Error: `destructive` stroke + `errorShake` + one `.footnote` line under
// the field saying what to do. Clear button: 20pt glyph in a 44 frame. Multi-line (the Log time
// note): min 104, same radius.

struct LHField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false
    /// One line saying what to do; non-nil shows the error state.
    var error: String? = nil
    var accessibilityLabel: String? = nil
    var identifier: String? = nil

    @FocusState private var focused: Bool
    @State private var shakeTrigger = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static let height: CGFloat = 52
    static let multilineMinHeight: CGFloat = 104

    init(_ placeholder: String, text: Binding<String>, multiline: Bool = false, error: String? = nil,
         accessibilityLabel: String? = nil, identifier: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.multiline = multiline
        self.error = error
        self.accessibilityLabel = accessibilityLabel
        self.identifier = identifier
    }

    private var strokeColor: Color {
        if error != nil { return colors.destructive }
        return focused ? colors.action : Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: multiline ? .top : .center, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    // A vertical-axis field draws its prompt on one line and cuts it with an ellipsis, so a
                    // multiline field draws its own placeholder, wrapping at every text size.
                    if multiline && text.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(nil)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    SwiftUI.TextField(text: $text,
                                      prompt: multiline ? Text(verbatim: "") : Text(placeholder).foregroundStyle(colors.textTertiary),
                                      axis: multiline ? .vertical : .horizontal) {
                        Text(accessibilityLabel ?? placeholder)
                    }
                    .lineLimit(multiline ? 3 : 1, reservesSpace: multiline)
                    .modifier(OptionalIdentifier(identifier: identifier))
                }
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .focused($focused)
                if !text.isEmpty && !multiline {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(colors.textTertiary)
                            .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, -12)
                    .accessibilityLabel(String(localized: "field.clear", defaultValue: "Clear text", table: "Foundations"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: multiline ? Self.multilineMinHeight : Self.height, alignment: multiline ? .topLeading : .leading)
            .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1.5)
            )
            .animation(AppAnimation.quick, value: focused)
            .animation(AppAnimation.quick, value: error)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shakeTrigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                // errorShake: x 0 → 8 → −6 → 4 → 0 over 0.28 s (colour only under Reduce Motion).
                KeyframeTrack {
                    LinearKeyframe(reduceMotion ? 0 : 8, duration: 0.07)
                    LinearKeyframe(reduceMotion ? 0 : -6, duration: 0.07)
                    LinearKeyframe(reduceMotion ? 0 : 4, duration: 0.07)
                    LinearKeyframe(0, duration: 0.07)
                }
            }
            .sensoryFeedback(.error, trigger: shakeTrigger)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(colors.destructive)
                    .transition(.opacity)
            }
        }
        .onChange(of: error) { old, new in
            if new != nil, new != old { shakeTrigger += 1 }
        }
    }

}
