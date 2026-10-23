import SwiftUI
import LucideIcons

// MARK: - The note: bare text on the sheet, the mic, and the line that says where values came from

extension LogTimeSheet {
    var notePlaceholder: String {
        if isReviewing { return String(localized: "What did you work on?") }
        if isFirstRun { return String(localized: "What did you do? Try \u{201C}fixed the sink, 1 hour\u{201D}") }
        return manual
            ? String(localized: "What did you do? (optional)")
            : String(localized: "What did you do? Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}")
    }

    var noteField: some View {
        ZStack(alignment: .topLeading) {
            if form.note.isEmpty {
                Text(verbatim: notePlaceholder)
                    .font(.title3)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextField("", text: $form.note, axis: .vertical)
                .font(.title3)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .lineLimit(2...6)
                .focused($noteFocused)
                .accessibilityLabel("Note")
                .accessibilityHint(notePlaceholder)
                .accessibilityIdentifier("log.note")
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { noteFocused = true }
    }

    /// Recents or the caption on the left, the mic on the right (the mic moves to the header at AX sizes).
    var toolsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if unfolded || isListening {
                    captionBlock.opacity(exiting ? 0 : 1).transition(arrive)
                } else if !showVoiceIntro && !recents.isEmpty && !isFirstRun {
                    recentsView.opacity(exiting ? 0 : 1).transition(.identity)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if noteFocused && !isListening { doneButton }
            if !isAX { micButton }
        }
    }

    var doneButton: some View {
        Button("Done") { noteFocused = false }
            .font(.body.weight(.semibold))
            .foregroundStyle(colors.actionText)
            .frame(minWidth: 44, minHeight: 44)
            .fixedSize()
            .accessibilityIdentifier("log.done")
    }

    var micButton: some View {
        let denied = voice.permissionDenied
        return Button(action: micTapped) {
            ZStack {
                if isListening {
                    LogMicLevelRing(level: voice.inputLevel).frame(width: 52, height: 52)
                }
                LucideIcon(image: isListening ? Lucide.square : Lucide.mic, size: 20)
                    .foregroundStyle(isListening ? colors.onAction : colors.actionText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isListening ? colors.action : colors.actionSurface))
            }
            .frame(width: 52, height: 52)
            .opacity(denied ? 0.4 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(isListening ? "Stop listening" : "Talk instead of type")
        .accessibilityHint(denied ? "Microphone is off in Settings" : "")
        .accessibilityIdentifier("log.mic")
    }

    // MARK: Caption

    /// What the sheet is doing or did with the note, in one line: listening, the timer's run time,
    /// reading, "Matched from your words" / "Filled from your note" with Undo, or why nothing matched.
    @ViewBuilder var captionBlock: some View {
        if isListening {
            captionLine(text: String(localized: "Listening\u{2026} tap to stop"), identifier: "log.listening")
        } else if let ran = reviewCaption {
            captionLine(text: ran, identifier: "log.timer.ran")
        } else if isReading {
            captionLine(text: form.fillSource != nil && !noteDirty
                            ? String(localized: "Matched from your words. Reading your note.")
                            : String(localized: "Reading your note"),
                        reading: true, identifier: "log.reading")
        } else if noneFound {
            captionLine(text: String(localized: "Couldn\u{2019}t tell which rental. Pick it below."), caution: true,
                        undo: form.canUndoFill, identifier: "log.noneFound")
        } else if let source = form.fillSource, form.canUndoFill, !noteDirty {
            captionLine(text: source.caption(tier: form.fillTier), sparkle: true, undo: true, identifier: "log.fill.caption")
        } else {
            Color.clear.frame(height: 44)
        }
    }

    func captionLine(text: String, reading: Bool = false, sparkle: Bool = false, caution: Bool = false,
                     undo: Bool = false, identifier: String) -> some View {
        let stack = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return stack {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if reading { LogReadingLine().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 } }
                else if sparkle { LogSparkle() }
                Text(verbatim: text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(caution ? colors.cautionText : colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
            if undo {
                Button(action: undoFill) {
                    Text("Undo")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.actionText)
                        .padding(.horizontal, isAX ? 0 : 8)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.lhPressable)
                .accessibilityLabel("Undo the fill")
                .accessibilityIdentifier("log.fill.undo")
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: text)
    }

    // MARK: Voice intro and denied

    var voiceIntro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Talk like you\u{2019}d tell a friend. We\u{2019}ll fill the rest.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                LogVoiceIntro.markSeen()
                withMotion { showVoiceIntro = false }
                startListening()
            } label: {
                Text("Start talking")
                    .font(.headline)
                    .foregroundStyle(colors.onAction)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(colors.action))
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("log.voice.start")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.sheetCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.sheetStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.voice.intro")
    }

    var deniedLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Turn on the microphone in Settings to talk instead of type.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .frame(minHeight: 44)
            .accessibilityIdentifier("log.voice.openSettings")
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.voice.denied")
    }
}
