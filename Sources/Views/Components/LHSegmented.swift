import SwiftUI

// MARK: - LHSegmented (standard §1.8) and LHStepper (§1.9)
//
// Segmented: one struct replaces BPSegmentedPicker, LogWhoPicker and the confirm sheet's picker.
// Capsule track `backgroundTertiary`, height 36, 2–3 segments (more → `LHRow.Value`), labels
// `.subheadline.semibold`; the selected thumb is `backgroundSecondary` with a hairline and
// `textPrimary` ink; motion `segmentSlide` (0.25 spring, labels crossfade 0.15; crossfade only under
// Reduce Motion); `.selection` haptic; min segment width 64.
//
// Stepper: one struct replaces LogHoursStepper and the confirm sheet's stepper. Two `LHButton.icon`
// (`minus`, `plus`) flank the value in `.title2.rounded.semibold` tabular, value column 100pt (fits
// "12h 30m" ≈ 94). Step 15m; long-press repeats every 0.12 s after 0.4 s; `.selection` per step;
// min 0, max 24h.

struct LHSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
        init(_ value: Value, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    let options: [Option]
    @Binding var selection: Value
    var accessibilityLabel: String? = nil

    @Namespace private var thumb
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static var height: CGFloat { 36 }
    static var minSegmentWidth: CGFloat { 64 }

    init(_ options: [Option], selection: Binding<Value>, accessibilityLabel: String? = nil) {
        precondition((2...3).contains(options.count), "LHSegmented takes 2–3 segments; use LHRow.Value for more")
        self.options = options
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    withAnimation(reduceMotion ? AppAnimation.quick : AppAnimation.segmentSlide) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? colors.textPrimary : colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: Self.height - 4)
                        .frame(minWidth: Self.minSegmentWidth)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(colors.backgroundSecondary)
                                    .overlay(Capsule().strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                        .animation(AppAnimation.quick, value: selected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(minHeight: Self.height)
        .background(colors.backgroundTertiary, in: Capsule())
        .frame(minHeight: LHMetrics.minTap)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

// MARK: - LHStepper

struct LHStepper: View {
    @Binding var hours: Double
    var step: Double = 0.25
    var range: ClosedRange<Double> = 0...24
    var label: String

    @State private var repeatTask: Task<Void, Never>?
    @State private var repeated = false
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .title2) private var valueColumn: CGFloat = 100
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static let repeatDelay: Double = 0.4
    static let repeatInterval: Double = 0.12

    init(hours: Binding<Double>, step: Double = 0.25, range: ClosedRange<Double> = 0...24, label: String) {
        self._hours = hours
        self.step = step
        self.range = range
        self.label = label
    }

    /// The next value one step up or down, snapped to the step and clamped to the range.
    static func stepped(_ value: Double, by delta: Double, step: Double, range: ClosedRange<Double>) -> Double {
        guard step > 0 else { return min(max(value, range.lowerBound), range.upperBound) }
        let snapped = ((value + delta) / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    private func apply(_ direction: Double) {
        hours = Self.stepped(hours, by: direction * step, step: step, range: range)
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At AX sizes the scaled value column and the two 44+ buttons no longer fit one row of a
        // phone: the value goes above the buttons.
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                valueText
                HStack(spacing: 24) { lessButton; moreButton }
            }
            .modifier(StepperAccessibility(stepper: self))
        } else {
            HStack(spacing: 12) { lessButton; valueText.frame(width: valueColumn); moreButton }
                .modifier(StepperAccessibility(stepper: self))
        }
    }

    private var lessButton: some View {
        stepButton("minus", direction: -1, enabled: hours > range.lowerBound,
                   label: String(localized: "stepper.less", defaultValue: "Less", table: "Foundations"))
    }

    private var moreButton: some View {
        stepButton("plus", direction: 1, enabled: hours < range.upperBound,
                   label: String(localized: "stepper.more", defaultValue: "More", table: "Foundations"))
    }

    private var valueText: some View {
            Text(LHFormat.hours(hours))
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
                .contentTransition(.numericText(value: hours))
                .animation(AppAnimation.standard, value: hours)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
    }

    fileprivate func applyStep(_ direction: Double) { apply(direction) }

    private func stepButton(_ symbol: String, direction: Double, enabled: Bool, label: String) -> some View {
        Button {
            // A long press that already repeated does not add one more step on release.
            if repeated { repeated = false } else { apply(direction) }
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(LHButton.icon)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .onLongPressGesture(minimumDuration: Self.repeatDelay, maximumDistance: 20, perform: {}) { pressing in
            repeatTask?.cancel()
            guard pressing else { return }
            repeatTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.repeatDelay))
                while !Task.isCancelled {
                    repeated = true
                    apply(direction)
                    try? await Task.sleep(for: .seconds(Self.repeatInterval))
                }
            }
        }
    }
}

private struct StepperAccessibility: ViewModifier {
    let stepper: LHStepper
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.selection, trigger: stepper.hours)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stepper.label)
            .accessibilityValue(LHFormat.spokenHours(stepper.hours))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: stepper.applyStep(1)
                case .decrement: stepper.applyStep(-1)
                @unknown default: break
                }
            }
    }
}
