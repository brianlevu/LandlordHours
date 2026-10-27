import SwiftUI

// MARK: - The note: the field, the mic, and the line that says where values came from

/// The note field and the rental-name field. Built to the `LHField` spec (§1.7): an inner surface
/// of radius 12 on `backgroundTertiary`, padding 16 / 14, `.body`, the placeholder in `textTertiary`,
/// a 1.5pt `action` stroke on focus (`fieldFocus`). It exists beside `LHField` only because the
/// sheet owns the focus: the note takes it on open and again after Undo, and "Done" gives it up.
/// (Blocker note for package A: `LHField` needs an optional external `FocusState` binding; then this
/// type is deleted.)
struct LogTextField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false
    /// A note that is done (the rows have unfolded and the keyboard is down) shrinks to its text,
    /// so the rows get the room; empty or focused it is the spec's 104.
    var compact = false
    var focus: FocusState<Bool>.Binding
    var label: String
    var identifier: String
    var submitLabel: SubmitLabel = .return
    var onSubmit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    /// At AX sizes the system prompt truncates with an ellipsis whatever the line limit (owner
    /// ruling 2026-10-27: text never truncates at AX), so the placeholder is drawn as wrapping text.
    private var wrapsPlaceholder: Bool { multiline && typeSize.isAccessibilitySize }

    private var textField: some View {
        SwiftUI.TextField(text: $text,
                          prompt: wrapsPlaceholder ? Text("") : Text(placeholder).foregroundStyle(colors.textTertiary),
                          axis: multiline ? .vertical : .horizontal) {
            Text(label)
        }
        .font(.body)
        .foregroundStyle(colors.textPrimary)
        .tint(colors.action)
        .lineLimit(multiline ? (compact ? 1...8 : 3...8) : 1...1)
        .focused(focus)
        .submitLabel(submitLabel)
        .onSubmit { onSubmit?() }
        .accessibilityLabel(label)
        .accessibilityHint(placeholder)
        .accessibilityIdentifier(identifier)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if wrapsPlaceholder && text.isEmpty {
                // Sizes the ZStack, so the field grows to hold the whole placeholder.
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(colors.textTertiary)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            textField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: multiline && !compact ? LHField.multilineMinHeight : LHField.height,
               alignment: multiline ? .topLeading : .leading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                .strokeBorder(focus.wrappedValue ? colors.action : Color.clear, lineWidth: 1.5)
        )
        .animation(AppAnimation.quick, value: focus.wrappedValue)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}

extension LogTimeSheet {
    var notePlaceholder: String {
        if isReviewing { return lt("What did you work on?") }
        if isFirstRun { return lt("What did you do? Try \u{201C}fixed the sink, 1 hour\u{201D}") }
        return manual
            ? lt("What did you do? (optional)")
            : lt("What did you do? Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}")
    }

    var noteField: some View {
        LogTextField(placeholder: notePlaceholder, text: $form.note, multiline: true,
                     compact: unfolded && !noteFocused && !form.note.isEmpty, focus: $noteFocused,
                     label: lt("Note"), identifier: "log.note")
    }

    /// The caption on the left (listening, reading, where the fill came from), Done and the mic on
    /// the right. At AX sizes the buttons take their own line under the caption.
    var toolsRow: some View {
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            captionBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if noteFocused && !isListening { doneButton }
                micButton
            }
        }
    }

    var doneButton: some View {
        Button(lt("Done")) { noteFocused = false }
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("log.done")
    }

    var micButton: some View {
        let denied = voice.permissionDenied
        return Group {
            if denied {
                // Disabled = no opacity dim (§1.13): `textTertiary` ink on the icon circle. The button
                // stays tappable so the tap can drop the keyboard over the "Open Settings" line.
                Button(action: micTapped) { LogDeniedMicLabel() }
                    .buttonStyle(.plain)
            } else {
                Button(action: micTapped) {
                    ZStack {
                        if isListening {
                            LogMicLevelRing(level: voice.inputLevel)
                        }
                        Image(systemName: isListening ? "stop.fill" : "mic")
                    }
                }
                .buttonStyle(LHButton.icon)
            }
        }
        .accessibilityLabel(isListening ? lt("Stop listening") : lt("Talk instead of type"))
        .accessibilityHint(denied ? lt("Microphone is off in Settings") : "")
        .accessibilityIdentifier("log.mic")
    }

    // MARK: Caption

    /// What the sheet is doing or did with the note, in one line: listening, the timer's run time,
    /// reading, "Matched from your words" / "Filled from your note" with Undo, or why nothing matched.
    @ViewBuilder var captionBlock: some View {
        if isListening {
            captionLine(text: lt("Listening\u{2026} tap to stop"), identifier: "log.listening")
        } else if let ran = reviewCaption {
            captionLine(text: ran, identifier: "log.timer.ran")
        } else if isReading {
            captionLine(text: form.fillSource != nil && !noteDirty
                            ? lt("Matched from your words. Reading your note.")
                            : lt("Reading your note"),
                        reading: true, identifier: "log.reading")
        } else if noneFound {
            captionLine(text: lt("Couldn\u{2019}t tell which rental. Pick it below."), caution: true,
                        undo: form.canUndoFill, identifier: "log.noneFound")
        } else if let source = form.fillSource, form.canUndoFill, !noteDirty {
            captionLine(text: source.caption(tier: form.fillTier), sparkle: true, undo: true, identifier: "log.fill.caption")
        } else {
            Color.clear.frame(height: LHMetrics.minTap)
        }
    }

    func captionLine(text: String, reading: Bool = false, sparkle: Bool = false, caution: Bool = false,
                     undo: Bool = false, identifier: String) -> some View {
        let stack = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return stack {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if reading || sparkle { LogSparkle(reading: reading) }
                // A new line fades in; the old one is gone at once, so two captions never overlap.
                Text(text)
                    .id(text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(caution ? colors.cautionText : colors.textSecondary)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
            if undo {
                Button(lt("Undo"), action: undoFill)
                    .buttonStyle(LHButton.tertiary)
                    .accessibilityLabel(lt("Undo the fill"))
                    .accessibilityIdentifier("log.fill.undo")
            }
        }
        .frame(minHeight: LHMetrics.minTap, alignment: .leading)
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.reveal, value: text)
    }

    // MARK: Voice intro and denied

    var voiceIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lt("Talk like you\u{2019}d tell a friend. We\u{2019}ll fill the rest."))
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
            Button(lt("Start talking")) {
                LogVoiceIntro.markSeen()
                withMotion { showVoiceIntro = false }
                startListening()
            }
            .buttonStyle(LHButton.secondary)
            .accessibilityIdentifier("log.voice.start")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.voice.intro")
    }

    var deniedLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lt("Turn on the microphone in Settings to talk instead of type."))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            Button(lt("Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("log.voice.openSettings")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.voice.denied")
    }
}

/// The mic circle when the microphone is off in Settings: the `.icon` button's geometry with the
/// disabled ink (`textTertiary` on `backgroundTertiary`, no opacity).
private struct LogDeniedMicLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = LHButton.Metrics.controlHeight
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Image(systemName: "mic")
            .font(.body.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(colors.textTertiary)
            .frame(width: max(iconSide, LHButton.Metrics.controlHeight), height: max(iconSide, LHButton.Metrics.controlHeight))
            .background(colors.backgroundTertiary, in: Circle())
            .contentShape(Circle())
    }
}
