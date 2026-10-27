import SwiftUI

#if DEBUG
// MARK: - Log time v2: PROPOSED standard components (amendments, see docs/design/log-time-v2-plan.md)
//
// Built only from existing tokens (AdaptiveColors, LHMetrics, AppAnimation) and existing components
// (LHButton, LHChip, LHTag, LHStepper, LHSegmented, LHRowGroup, LHDivider, LHChevron). Each struct
// here is written to be lifted into Views/Components unchanged if Brian approves a direction:
//
//   LHCaptureField  §1.7a  LHField's multi-line form + a mic slot + a listening state
//   LHReadBack      §1.5a  the review card: LHRowGroup of LHReadRow, one open answer at a time
//   LHReadRow       §1.5a  LHRow.Value with the value in primary ink and a provenance line
//   LHAnswerChips   §1.16a LHChip used as answers inside a card (wraps; not a strip)
//   LHLevelMeter    §1.7a  five capsules bound to the microphone level
//   LHTimerFace     §1.28  the running timer: hero numeral + what + since when

// MARK: LHRowGroup inside a sheet

/// §1.5 says rows inside sheets sit on an inner surface (radius 12, `backgroundTertiary`): an
/// LHRowGroup (backgroundSecondary) on the opaque sheet (also backgroundSecondary) disappears.
/// Proposed as `LHRowGroup(inSheet: true)`.
struct LHSheetRowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(AdaptiveColors(colorScheme: colorScheme).backgroundTertiary,
                        in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
    }
}

// MARK: Flow layout for answer chips

struct LHFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(s.width, bounds.width), height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: LHLevelMeter

/// Five capsules, heights from the live microphone level. Bound to `level` (a state change), so it
/// stops the moment the level does; under Reduce Motion it is a static glyph.
struct LHLevelMeter: View {
    var level: Double
    var tint: Color
    private let weights: [Double] = [0.45, 0.8, 1.0, 0.7, 0.5]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: reduceMotion ? height * weights[i] * 0.6
                                                          : max(4, height * weights[i] * (0.25 + 0.75 * level)))
            }
        }
        .frame(height: height)
        .animation(AppAnimation.feedback, value: level)
        .accessibilityHidden(true)
    }
}

// MARK: LHCaptureField

/// The "What did you do?" input. LHField's multi-line metrics (inner surface radius 12, padding
/// 16/14, placeholder `textTertiary`, focus 1.5pt `action`) at `.title3`, min 104 (§1.7's Log time
/// note); compact (min 56, mic beside the words) once the card shows, and a mic slot: `.icon` at rest, `action` fill with a stop
/// square while listening. While listening the live words fill the field and a meter + "Listening"
/// line sits at its foot.
struct LHCaptureField: View {
    let placeholder: String
    @Binding var text: String
    var isListening = false
    var level: Double = 0
    var minHeight: CGFloat = 104
    /// Once a card shows under it, the field hugs its text and the mic sits beside the words
    /// (no empty band; D4).
    var compact = false
    /// r2: on the tinted page the field is a white surface (`backgroundSecondary`), like 2.2's rows.
    var onPage = false
    /// r2: the mic is a filled action button (44pt) at rest, as today's sheet has it.
    var prominentMic = false
    var focus: FocusState<Bool>.Binding
    var onMic: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// The filled mic grows with the text so the glyph stays inside its circle at AX sizes.
    @ScaledMetric(relativeTo: .body) private var micSide: CGFloat = 44
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        if compact && !isListening { compactBody } else { fullBody }
    }

    private var compactBody: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(text: $text, prompt: Text(placeholder).foregroundStyle(colors.textTertiary), axis: .vertical) {
                Text("What did you do?")
            }
                .font(.title3)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .focused(focus)
                .lineLimit(1...6)
                .accessibilityIdentifier("logv2.note")
            micButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                .strokeBorder(focus.wrappedValue ? colors.action : (onPage && colorScheme == .dark ? colors.border : .clear),
                              lineWidth: focus.wrappedValue ? 1.5 : LHMetrics.hairline)
        )
    }

    private var fill: Color { onPage ? colors.backgroundSecondary : colors.backgroundTertiary }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(text: $text, prompt: Text(placeholder).foregroundStyle(colors.textTertiary), axis: .vertical) {
                Text("What did you do?")
            }
            .font(.title3)
            .foregroundStyle(colors.textPrimary)
            .tint(colors.action)
            .focused(focus)
            .lineLimit(2...6)
            .accessibilityIdentifier("logv2.note")
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 10) {
                if isListening {
                    LHLevelMeter(level: level, tint: colors.action)
                    Text("Listening")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .accessibilityIdentifier("logv2.listening")
                }
                Spacer(minLength: 0)
                micButton
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                .strokeBorder(focus.wrappedValue || isListening ? colors.action : (onPage && colorScheme == .dark ? colors.border : .clear),
                              lineWidth: focus.wrappedValue || isListening ? 1.5 : LHMetrics.hairline)
        )
        .animation(AppAnimation.quick, value: isListening)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }

    @ViewBuilder private var micButton: some View {
        if isListening {
            Button(action: onMic) {
                Image(systemName: "stop.fill")
                    .font(.body)
                    .foregroundStyle(colors.onAction)
                    .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                    .background(colors.action, in: Circle())
            }
            .buttonStyle(LHButton.press)
            .accessibilityLabel("Stop listening")
            .accessibilityIdentifier("logv2.mic")
        } else if prominentMic {
            Button(action: onMic) {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.onAction)
                    .frame(width: max(LHMetrics.minTap, micSide), height: max(LHMetrics.minTap, micSide))
                    .background(colors.action, in: Circle())
            }
            .buttonStyle(LHButton.press)
            .accessibilityLabel("Say it instead")
            .accessibilityIdentifier("logv2.mic")
        } else {
            Button(action: onMic) { Image(systemName: "mic.fill") }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel("Say it instead")
                .accessibilityIdentifier("logv2.mic")
        }
    }
}

// MARK: LHReadRow

/// One line of the review card. LHRow.Value's grid (min 56, padding 16/10, `.body`) with two
/// changes: the VALUE is the content (primary ink) and the label is the quiet column; and a
/// provenance line under the value when the app assumed it ("Your only rental", "Last used"). A
/// field the note didn't give and that has no safe default shows its question and a "Needs you"
/// tag instead of a value. Tap opens the answer under the row.
struct LHReadRow: View {
    let label: String
    let value: String?
    let source: LogV2Source
    var question: String
    var isOpen: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelColumn: CGFloat = 64
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var needed: Bool { source == .needed && value == nil || source == .needed }

    var body: some View {
        Button(action: action) {
            let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            HStack(alignment: .center, spacing: 8) {
                layout {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .frame(width: ax ? nil : labelColumn, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if needed {
                            HStack(spacing: 8) {
                                Text(question)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(colors.textPrimary)
                                LHTag("Needs you", tone: .caution)
                            }
                        } else {
                            Text(value ?? LHFormat.unknown)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(colors.textPrimary)
                                .contentTransition(.numericText())
                            if case .assumed(let why) = source, !why.isEmpty {
                                Text(why)
                                    .font(.footnote)
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LHChevron(systemName: isOpen ? "chevron.up" : "chevron.down")
            }
            .padding(LHRow.insets)
            .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LHButton.press)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isOpen ? "Closes the choices" : "Shows the choices")
    }
}

// MARK: LHReadBack

/// The review card. One inner surface (§1.5: radius 12, `backgroundTertiary`, as value rows sit in sheets); rows are
/// LHReadRow with LHDivider(leadingInset: 16); at most ONE row is open, and an open question is
/// opened for the user. Motion: rows arrive with `sheetUnfold` (flow + reveal, 30 ms stagger);
/// a changed value rolls with `countChange`.
struct LHReadBack<Answer: View>: View {
    @ObservedObject var model: LogV2Model
    @ViewBuilder var answer: (LogV2Field) -> Answer

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
        VStack(spacing: 0) {
            ForEach(Array(model.fieldsShown.enumerated()), id: \.element) { index, field in
                if index > 0 { LHDivider(leadingInset: 16) }
                LHReadRow(label: field.label, value: model.value(field), source: model.sources[field] ?? .needed,
                          question: field.question, isOpen: model.expanded == field) {
                    model.toggle(field)
                }
                .accessibilityIdentifier("logv2.row.\(field.rawValue)")
                if model.expanded == field {
                    answer(field)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(AdaptiveColors(colorScheme: colorScheme).backgroundTertiary, in: shape)
        .animation(AppAnimation.flow, value: model.expanded)
    }
}

// MARK: LHAnswerChips

/// LHChip as answers inside a card: wraps (never scrolls), 8 gaps, the current answer selected.
struct LHAnswerChips<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var systemImage: ((Item) -> String?)? = nil
    let isSelected: (Item) -> Bool
    let pick: (Item) -> Void

    var body: some View {
        LHFlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                LHChip(title(item), systemImage: systemImage?(item), isSelected: isSelected(item)) { pick(item) }
            }
        }
    }
}

// MARK: LHTimerFace

/// The running timer, shaped like its Live Activity: what and where on top, the hero numeral
/// (SF Rounded tabular via `lhHeroNumberFont()`, the one sanctioned big number style), and the
/// start time under it. A positive dot says "running" without motion.
struct LHTimerFace: View {
    let rental: String
    let work: String
    let start: Date
    var frozenAt: Date? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(colors.positive).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("\(work) at \(rental)")
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Group {
                if let frozenAt {
                    Text(LogV2Format.clock(frozenAt.timeIntervalSince(start)))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(LogV2Format.clock(ctx.date.timeIntervalSince(start)))
                    }
                }
            }
            .lhHeroNumberFont()
            .foregroundStyle(colors.textPrimary)
            .contentTransition(.numericText())
            .accessibilityIdentifier("logv2.timer.clock")
            Text("Started \(start.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Shared answers (both directions use the same card)

struct LogV2Answer: View {
    @ObservedObject var model: LogV2Model
    let field: LogV2Field
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        switch field {
        case .rental:
            VStack(alignment: .leading, spacing: 8) {
                if model.noteNamesTwoRentals {
                    Text("Your note names 2 rentals. Log each one on its own.")
                        .font(.footnote).foregroundStyle(colors.textSecondary)
                }
                LHFlowLayout(spacing: 8) {
                    ForEach(model.properties, id: \.id) { p in
                        LHChip(p.name, isSelected: model.rentalId == p.id && model.sources[.rental] != .needed) {
                            model.setRental(p.id)
                        }
                    }
                    if model.isFree {
                        LHChip("Add a rental", systemImage: "lock.fill", isSelected: false) {}
                            .accessibilityHint("Opens Pro")
                            .accessibilityIdentifier("logv2.addRental.locked")
                    }
                }
                if model.isFree {
                    Text("Free covers one rental. Your hours here stay free.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("logv2.freeLine")
                }
            }
        case .hours:
            VStack(alignment: .leading, spacing: 12) {
                LHAnswerChips(items: [0.5, 1, 1.5, 2, 3], title: { LHFormat.hours($0) },
                              isSelected: { model.hours == $0 && model.sources[.hours] != .needed },
                              pick: { model.setHours($0) })
                if model.sources[.hours] != .needed {
                    LHStepper(hours: Binding(get: { model.hours ?? 1 }, set: { model.setHours($0) }), label: "Time")
                }
            }
        case .work:
            LHAnswerChips(items: ActivityCategory.allCases.filter(\.countsForREPS) + [.investing],
                          title: { $0.inboxLabel },
                          isSelected: { model.work == $0 }, pick: { model.setWork($0) })
        case .who:
            LHSegmented([.init(.selfParticipant, "You"), .init(.spouse, "Your spouse")],
                        selection: Binding(get: { model.who }, set: { model.setWho($0) }), accessibilityLabel: "Who")
        case .day:
            LHAnswerChips(items: [0, -1, -2], title: { off in
                off == 0 ? "Today" : off == -1 ? "Yesterday" :
                    LogV2Format.day(Calendar.current.date(byAdding: .day, value: off, to: LogV2Sample.now)!)
            }, isSelected: { off in
                Calendar.current.isDate(model.day, inSameDayAs: Calendar.current.date(byAdding: .day, value: off, to: LogV2Sample.now)!)
            }, pick: { off in
                model.setDay(Calendar.current.date(byAdding: .day, value: off, to: LogV2Sample.now)!)
            })
        }
    }
}

// MARK: The "logged" state: the sheet is gone, the toast says it (§1.19, canonical success line)

struct LogV2LoggedToast: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHToast(spec: LHToastSpec(kind: .success, message: text, actionTitle: "Undo"), onAction: {},
                identifier: "logv2.toast", actionIdentifier: nil, placement: .bottom)
    }
}
#endif
