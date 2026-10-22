import SwiftUI
import UIKit
import LucideIcons

#if DEBUG
// MARK: - Root (reached from LandlordHoursAppEntry with -LHLogTimeProto 1)

struct LogTimeProtoRoot: View {
    @StateObject private var model: ProtoModel
    @Environment(\.colorScheme) private var scheme

    init() {
        let hold = LogTimeProtoLaunch.value("-LHProtoState") != nil
        let m = ProtoModel(hasModel: LogTimeProtoLaunch.value("-LHProtoModel") != "off", hold: hold)
        if let s = LogTimeProtoLaunch.value("-LHProtoScenario").flatMap(ProtoScenario.init(rawValue:))
            ?? LogTimeProtoLaunch.value("-LHProtoScript").flatMap(ProtoScenario.init(rawValue:)) { m.scenario = s }
        _model = StateObject(wrappedValue: m)
    }

    var body: some View {
        LogTimeProtoSheet(model: model)
            .preferredColorScheme(AppearanceManager.forcedColorSchemeFromLaunchArguments ?? .dark)
            .onAppear {
                // -LHProtoSlow 0.15: run every animation at 15% speed so a screen recording can be read frame by frame.
                if let s = LogTimeProtoLaunch.value("-LHProtoSlow").flatMap(Float.init) {
                    DispatchQueue.main.async {
                        for scene in UIApplication.shared.connectedScenes { (scene as? UIWindowScene)?.windows.forEach { $0.layer.speed = s } }
                    }
                }
                if let state = LogTimeProtoLaunch.value("-LHProtoState") { model.preset(state) }
                if LogTimeProtoLaunch.value("-LHProtoScript") != nil { model.runScript() }
                if LogTimeProtoLaunch.value("-LHProtoFocus") == "1" { model.wantsFocus = true }
            }
    }
}

// MARK: - Prototype-only tokens

extension AdaptiveColors {
    /// Dark cards lifted off the canvas (was 1.25:1): #1A2350 plus a 1px white 8% stroke. Light cards keep the brand white.
    var sheetCard: Color { colorScheme == .dark ? Color(hex: "283360") : backgroundSecondary }
    var sheetStroke: Color { colorScheme == .dark ? Color.white.opacity(0.10) : border }
}

/// Blur + fade in place; the outgoing view leaves at once so two lines never overlap.
private struct BlurFade: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View { content.blur(radius: on ? 4 : 0).opacity(on ? 0 : 1) }
}

// MARK: - The docked sheet

struct LogTimeProtoSheet: View {
    @ObservedObject var model: ProtoModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var noteFocused: Bool
    @FocusState private var nameFocused: Bool
    @ScaledMetric(relativeTo: .body) private var chevronSize: CGFloat = 16
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    private var isLarge: Bool { model.f.unfolded || model.zeroMode || model.listening || model.micIntro || model.toast != nil || type.isAccessibilitySize }
    /// New content slides in out of the line above it; old content leaves at once, so two layouts never overlap.
    private var enter: AnyTransition { .asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -14)), removal: .identity) }
    private var unfoldTransition: AnyTransition { enter }
    /// Changed text: the new words blur in, the old words leave at once, so two strings are never on screen together.
    private var textSwap: AnyTransition { reduceMotion ? .asymmetric(insertion: .opacity, removal: .identity) : .asymmetric(insertion: .modifier(active: BlurFade(on: true), identity: BlurFade(on: false)), removal: .identity) }
    private var sheetAnim: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                colors.background.ignoresSafeArea()
                Color.black.opacity(scheme == .dark ? 0.5 : 0.28).ignoresSafeArea()
                panel
                    .frame(height: isLarge ? geo.size.height - 6 : min(geo.size.height, UIScreen.main.bounds.height * 0.56))
            }
        }
        .onChange(of: model.wantsFocus) { _, want in if model.zeroMode && want { nameFocused = true } else { noteFocused = want } }
        .onChange(of: model.zeroMode) { _, z in if z && !model.hold { nameFocused = true } }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Capsule().fill(colors.textTertiary.opacity(0.6)).frame(width: 36, height: 5).padding(.top, 8).padding(.bottom, 6)
                .accessibilityHidden(true)
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    }
                }
                .onAppear {
                    if LogTimeProtoLaunch.value("-LHProtoScroll") == "1" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("rows", anchor: .top) }
                    }
                }
            }
            if let toast = model.toast { toastView(type.isAccessibilitySize ? toast.short : toast.text).transition(.asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)), removal: .opacity)) }
            logBar
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(colors.background)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous).strokeBorder(colors.sheetStroke, lineWidth: 1))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.zeroMode { rentalNameField }
            noteField
            toolsRow
            if model.micIntro { micIntroCard.transition(enter) }
            if model.f.unfolded {
                rows.id("rows").transition(enter)
                if model.hoursQuestionable { hoursFootnote.transition(enter) }
                if model.f.manual { autoFillOff.transition(enter) }
            } else if !model.micIntro {
                detailsLine.transition(.identity)
                enterDetails.transition(.identity)
            }
        }
    }

    // MARK: header

    private var title: String { model.zeroMode ? pl("Log your first hour") : (model.timerRan != nil ? pl("Log the timer") : pl("Log time")) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.eyebrow)
                .font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.3)
                .foregroundStyle(colors.draftingInk)
                .id(model.eyebrow)
                .transition(textSwap)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.eyebrow)
            HStack(alignment: .center) {
                Text(title).font(.system(.title).weight(.bold)).foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !model.f.unfolded && !model.zeroMode { timerPill.transition(.asymmetric(insertion: .opacity, removal: .identity)) }
                closeButton
            }
        }
    }

    private var timerPill: some View {
        Button {} label: {
            HStack(spacing: 6) {
                LucideIcon(image: Lucide.timer, size: 16)
                if !type.isAccessibilitySize { PT("Timer").font(.system(.subheadline).weight(.semibold)) }
            }
            .foregroundStyle(colors.textPrimary).padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(colors.sheetCard)).overlay(Capsule().strokeBorder(colors.sheetStroke, lineWidth: 1))
        }
        .buttonStyle(.lhPressable).accessibilityLabel(pl("Timer"))
    }

    private var closeButton: some View {
        Button {} label: {
            LucideIcon(image: Lucide.x, size: 18).foregroundStyle(colors.textPrimary).frame(width: 44, height: 44)
                .background(Circle().fill(colors.sheetCard)).overlay(Circle().strokeBorder(colors.sheetStroke, lineWidth: 1))
        }
        .buttonStyle(.lhPressable).accessibilityLabel(pl("Close"))
    }

    // MARK: first-run rental field

    private var rentalNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            PT("Which rental is this for?").font(.system(.headline)).foregroundStyle(colors.textPrimary)
            ZStack(alignment: .leading) {
                if model.rentalName.isEmpty {
                    PT("Name or address, like “Pine Cabin”").font(.system(.body)).foregroundStyle(colors.textSecondary).allowsHitTesting(false)
                }
                TextField("", text: $model.rentalName).font(.system(.body)).foregroundStyle(colors.textPrimary)
                    .focused($nameFocused).accessibilityLabel(pl("Rental name"))
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.sheetCard))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(nameFocused ? colors.action : colors.sheetStroke, lineWidth: nameFocused ? 1.5 : 1))
            PT("You can add the address and type later.").font(.system(.footnote)).foregroundStyle(colors.textSecondary)
        }
    }

    // MARK: note (bare text on the sheet, Todoist Quick Add style)

    private var notePlaceholder: String {
        if model.timerRan != nil { return pl("What did you work on?") }
        if model.zeroMode { return pl("What did you do? Try “fixed the sink, 1 hour”") }
        return model.f.manual ? pl("What did you do? (optional)") : pl("What did you do? Try “fixed the sink at Pine Cabin, 1 hour”")
    }

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if model.f.note.isEmpty {
                Text(notePlaceholder).font(.system(.title3)).foregroundStyle(colors.textSecondary).allowsHitTesting(false).accessibilityHidden(true)
            }
            TextField("", text: Binding(get: { model.f.note }, set: { model.setNote($0) }), axis: .vertical)
                .font(.system(.title3)).foregroundStyle(colors.textPrimary).tint(colors.action)
                .lineLimit(2...6).focused($noteFocused).submitLabel(.done)
                .accessibilityLabel(pl("What did you do?"))
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
    }

    // MARK: tools row: recents or caption on the left, mic on the right

    private var toolsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if model.f.unfolded || model.listening { captionBlock.transition(enter) } else { recents.transition(.identity) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            micButton
        }
    }

    private var micButton: some View {
        Button { model.micTapped() } label: {
            ZStack {
                if model.listening { Circle().strokeBorder(colors.action.opacity(0.5), lineWidth: 3).frame(width: 52, height: 52) }
                LucideIcon(image: model.listening ? Lucide.square : Lucide.mic, size: 20)
                    .foregroundStyle(model.listening ? colors.onAction : colors.actionText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(model.listening ? colors.action : colors.actionSurface))
            }.frame(width: 52, height: 52)
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(model.listening ? pl("Stop listening") : pl("Talk instead of type"))
    }

    @ViewBuilder private var captionBlock: some View {
        if let text = model.caption {
            let ax = type.isAccessibilitySize
            let stack = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            stack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if model.readingModel { ReadingLine().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 } }
                    else if model.fillSource != nil && !model.noneFound && !model.listening { Sparkle() }
                    Text(text)
                        .font(.system(.footnote).weight(.medium))
                        .foregroundStyle(model.noneFound ? colors.cautionText : colors.textSecondary)
                        .id(text)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .modifier(active: BlurFade(on: true), identity: BlurFade(on: false)), removal: .identity))
                }
                if model.fillSource != nil && !model.readingModel && !model.listening {
                    Button { model.undoFill() } label: {
                        PT("Undo").font(.system(.footnote).weight(.semibold)).foregroundStyle(colors.actionText)
                            .padding(.horizontal, ax ? 0 : 8).frame(minHeight: 44)
                    }
                    .buttonStyle(.lhPressable).accessibilityLabel(pl("Undo the fill"))
                }
            }
            .frame(minHeight: 44, alignment: .leading)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: text)
        } else { Color.clear.frame(height: 44) }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            PT("RECENT").font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.3).foregroundStyle(colors.draftingInk)
            FlowLayout(spacing: 8) {
                recentChip(.repairs, ProtoData.pine, 1)
                recentChip(.leasing, ProtoData.oak, 0.5)
            }
        }
    }

    private func recentChip(_ c: ActivityCategory, _ p: RentalProperty, _ h: Double) -> some View {
        let text = type.isAccessibilitySize ? "\(ProtoData.short(c)) · \(p.name)" : "\(ProtoData.short(c)) · \(p.name) · \(hoursText(h))"
        return Button { model.applyRecent(c, p, h) } label: {
            Text(verbatim: text).font(.system(.subheadline).weight(.medium)).foregroundStyle(colors.textPrimary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(colors.sheetCard)).overlay(Capsule().strokeBorder(colors.sheetStroke, lineWidth: 1))
        }
        .buttonStyle(.lhPressable)
    }

    private var micIntroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PT("Talk like you'd tell a friend. We'll fill the rest.").font(.system(.title3).weight(.semibold)).foregroundStyle(colors.textPrimary)
            Button { model.startTalking() } label: {
                PT("Start talking").font(.system(.headline)).foregroundStyle(colors.onAction).frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(colors.action))
            }.buttonStyle(.lhPressable)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.sheetCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.sheetStroke, lineWidth: 1))
    }

    // MARK: initial: one quiet details line + a quiet text button

    /// The quiet details line; the rows slide out of it. (matchedGeometryEffect on the values was tried and dropped: it keeps both layouts on screen during the move.)
    private var detailsLine: some View {
        let pieces = model.initialPieces
        return FlowLayout(spacing: 4) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                HStack(spacing: 4) {
                    Text(piece.1).font(.system(.footnote)).foregroundStyle(colors.textSecondary)
                    if i < pieces.count - 1 { Text(verbatim: "·").font(.system(.footnote)).foregroundStyle(colors.textSecondary) }
                }
            }
        }
    }

    private var enterDetails: some View {
        Button { model.enterManual() } label: {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.slidersHorizontal, size: 16)
                PT("Enter details yourself").font(.system(.body).weight(.medium))
            }
            .foregroundStyle(colors.actionText).frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.lhPressable)
        .accessibilityHint(pl("Shows every field and turns off auto-fill for this entry."))
    }

    private var autoFillOff: some View {
        HStack {
            PT("Auto-fill is off for this entry.").font(.system(.footnote)).foregroundStyle(colors.textSecondary)
            Button { model.turnAutoFillOn() } label: {
                PT("Turn on").font(.system(.footnote).weight(.semibold)).foregroundStyle(colors.actionText).frame(minHeight: 44)
            }.buttonStyle(.lhPressable)
            Spacer()
        }
    }

    private var hoursFootnote: some View {
        HStack(spacing: 8) {
            Circle().fill(colors.cautionText).frame(width: 6, height: 6)
            PT("You didn't say how long").font(.system(.footnote).weight(.medium)).foregroundStyle(colors.cautionText)
        }.padding(.horizontal, 4)
    }

    // MARK: rows

    private var rows: some View {
        VStack(spacing: 0) {
            if !model.zeroMode { row(.property); divider }
            row(.category); divider
            row(.hours); divider
            row(.date)
            if model.f.record != nil { divider; recordRow.transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.12)), removal: .identity)) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.sheetCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.sheetStroke, lineWidth: 1))
    }

    private var divider: some View { Rectangle().fill(colors.sheetStroke).frame(height: 1).padding(.horizontal, 12) }

    private func label(_ f: PField) -> String {
        switch f { case .property: return pl("Rental"); case .category: return pl("Kind of work"); case .hours: return pl("How long")
        case .date: return pl("Date"); case .record: return pl("On the record") }
    }

    private enum Look { case filled(Bool), empty, caution, updated }

    private func look(_ f: PField) -> Look {
        if model.updated[f] != nil { return .updated }
        switch f {
        case .property: return model.f.propertyId == nil ? .empty : .filled(model.f.marks[.property] != nil)
        case .category: return model.f.category == nil ? .empty : .filled(model.f.marks[.category] != nil)
        case .hours: return model.hoursQuestionable ? .caution : .filled(model.f.marks[.hours] != nil)
        case .date: return .filled(model.f.marks[.date] != nil)
        case .record: return .filled(model.f.marks[.record] != nil)
        }
    }

    private func valueText(_ f: PField) -> String {
        switch f {
        case .property: return model.propertyName ?? ""
        case .category: return model.f.category.map(ProtoData.short) ?? ""
        case .hours: return hoursText(model.f.hours)
        case .date: return model.dateValue
        case .record: return model.f.record ?? ""
        }
    }

    private func row(_ f: PField) -> some View {
        let l = look(f)
        let open = model.expanded == f
        return VStack(spacing: 0) {
            Button { model.toggle(f) } label: { rowLabel(f, l, open: open) }
                .buttonStyle(.lhPressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowA11y(f, l))
                .accessibilityHint(pl("Double-tap to change."))
            if f == .property, model.f.propertyId == nil, model.mentioned.count >= 2 { twoRentalHint }
            if case .updated = l { updatedLine(f) }
            if open { editor(f).transition(.opacity) }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.timber.opacity(model.flash.contains(f) ? 0.16 : 0)))
    }

    private func rowLabel(_ f: PField, _ l: Look, open: Bool) -> some View {
        let stacked = type.isAccessibilitySize
        return HStack(alignment: .center, spacing: 10) {
            accentBar(l)
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(f)).font(.system(.subheadline)).foregroundStyle(colors.textSecondary)
                    valueView(f, l, trailing: false).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(label(f)).font(.system(.subheadline)).foregroundStyle(colors.textSecondary).frame(minWidth: 96, alignment: .leading)
                Spacer(minLength: 4)
                valueView(f, l, trailing: true)
            }
            LucideIcon(image: Lucide.chevronRight, size: chevronSize).foregroundStyle(colors.textSecondary).rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The one timber accent: a 3pt bar on rows whose value came from the note.
    @ViewBuilder private func accentBar(_ l: Look) -> some View {
        if case .filled(true) = l { Capsule().fill(scheme == .dark ? colors.timber : colors.timberInk).frame(width: 3, height: 26).accessibilityHidden(true) }
        else { Color.clear.frame(width: 3, height: 26) }
    }

    @ViewBuilder private func valueView(_ f: PField, _ l: Look, trailing: Bool) -> some View {
        let align: TextAlignment = trailing ? .trailing : .leading
        switch l {
        case .empty:
            PT("Choose").font(.system(.body).weight(.semibold)).foregroundStyle(colors.actionText)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .overlay(Capsule().strokeBorder(colors.action, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        case .caution, .updated:
            HStack(spacing: 8) {
                Circle().fill(colors.cautionText).frame(width: 6, height: 6)
                Text(valueText(f)).font(.system(.body).weight(.semibold)).foregroundStyle(colors.cautionText).multilineTextAlignment(align)
            }
        case .filled:
            Text(valueText(f)).font(.system(.body).weight(.semibold)).foregroundStyle(colors.textPrimary).multilineTextAlignment(align)
        }
    }

    private func rowA11y(_ f: PField, _ l: Look) -> String {
        switch l {
        case .empty: return pl("\(label(f)), not chosen. Button.")
        case .caution: return pl("\(label(f)), \(valueText(f)), you didn't say how long. Button.")
        case .updated: return pl("\(label(f)), \(valueText(f)), updated from your note. Button.")
        case .filled(let note): return note ? pl("\(label(f)), \(valueText(f)), filled from your note. Button.") : pl("\(label(f)), \(valueText(f)). Button.")
        }
    }

    private var recordRow: some View {
        HStack(alignment: .top, spacing: 10) {
            accentBar(.filled(true)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(label(.record)).font(.system(.subheadline)).foregroundStyle(colors.textSecondary)
                Text(model.f.record ?? "").font(.system(.body)).foregroundStyle(colors.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.timber.opacity(model.flash.contains(.record) ? 0.16 : 0)))
        .accessibilityElement(children: .combine)
    }

    private var twoRentalHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            PT("Your note mentions 2 rentals. Log each one on its own.").font(.system(.footnote)).foregroundStyle(colors.textSecondary)
            FlowLayout(spacing: 8) { ForEach(model.mentioned) { p in chip(p.name, selected: false) { model.pick(property: p.id) } } }
        }
        .padding(.horizontal, 16).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updatedLine(_ f: PField) -> some View {
        HStack(spacing: 4) {
            PT("Updated from your note.").font(.system(.footnote).weight(.medium)).foregroundStyle(colors.cautionText)
            Button { model.undoUpdate(f) } label: {
                PT("Undo").font(.system(.footnote).weight(.semibold)).foregroundStyle(colors.cautionText).underline().frame(minHeight: 44).padding(.horizontal, 6)
            }.buttonStyle(.lhPressable)
            Spacer()
        }
        .padding(.horizontal, 25).padding(.bottom, 2)
    }

    // MARK: inline editors

    @ViewBuilder private func editor(_ f: PField) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch f {
            case .property:
                FlowLayout(spacing: 8) { ForEach(model.properties) { p in chip(p.name, selected: model.f.propertyId == p.id) { model.pick(property: p.id) } } }
            case .category:
                FlowLayout(spacing: 8) { ForEach(ProtoData.counted, id: \.self) { c in chip(ProtoData.short(c), selected: model.f.category == c) { model.pick(category: c) } } }
            case .hours:
                FlowLayout(spacing: 8) {
                    ForEach([0.5, 1, 1.5, 2, 4], id: \.self) { h in chip(hoursText(h), selected: !model.f.hoursIsDefault && model.f.hours == h) { model.set(hours: h, collapse: true) } }
                }
                stepper
            case .date:
                FlowLayout(spacing: 8) {
                    chip(pl("Today"), selected: model.isToday) { model.set(date: Date()) }
                    chip(pl("Yesterday"), selected: Calendar.current.isDateInYesterday(model.f.date)) {
                        model.set(date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) }
                }
                DatePicker(pl("Date"), selection: Binding(get: { model.f.date }, set: { model.set(date: $0) }), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().tint(colors.action)
            case .record: EmptyView()
            }
            if f == .category, let c = model.f.category, !c.countsForREPS {
                PT("This kind of work doesn't count toward your hours.").font(.system(.footnote)).foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepper: some View {
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            stepButton(Lucide.minus, label: pl("Less")) { model.set(hours: model.f.hours - 0.25, collapse: false) }
            Text(hoursText(model.f.hours)).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(colors.textPrimary).contentTransition(.numericText()).frame(minWidth: 110)
            stepButton(Lucide.plus, label: pl("More")) { model.set(hours: model.f.hours + 0.25, collapse: false) }
        }.frame(maxWidth: .infinity)
    }

    private func stepButton(_ image: UIImage, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(image: image, size: 20).foregroundStyle(colors.textPrimary).frame(width: 48, height: 48)
                .background(Circle().fill(colors.sheetCard)).overlay(Circle().strokeBorder(colors.sheetStroke, lineWidth: 1))
        }.buttonStyle(.lhPressable).accessibilityLabel(label)
    }

    private func chip(_ text: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: text).font(.system(.subheadline).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(selected ? colors.actionText : colors.textPrimary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(selected ? colors.actionSurface : colors.background))
                .overlay(Capsule().strokeBorder(selected ? colors.action : colors.sheetStroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.lhPressable).accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: the Log bar: one filled button that names what it will do

    private var logBar: some View {
        Button { model.primary() } label: {
            Text(verbatim: model.barText)
                .font(.system(.headline)).foregroundStyle(colors.onAction)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(colors.action))
                .contentShape(Capsule())
                .id(model.barText)
                .transition(textSwap)
        }
        .buttonStyle(.lhPressable)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18), value: model.barText)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
        .background(colors.background.overlay(alignment: .top) { Rectangle().fill(colors.sheetStroke).frame(height: 1) })
    }

    // MARK: toast

    /// Sits in the panel, above the Log bar: content makes room for it and is never covered.
    private func toastView(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: text).font(.system(.subheadline).weight(.medium)).foregroundStyle(colors.background)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.undoLog() } label: {
                PT("Undo").font(.system(.subheadline).weight(.semibold)).foregroundStyle(colors.background).underline().frame(minHeight: 44)
            }.buttonStyle(.lhPressable)
        }
        .padding(.horizontal, 20).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: type.isAccessibilitySize ? 24 : 28, style: .continuous).fill(colors.textPrimary))
        .padding(.horizontal, 20).padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - small pieces

private struct Sparkle: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 14
    var body: some View {
        LucideIcon(image: Lucide.sparkles, size: size).foregroundStyle(AdaptiveColors(colorScheme: scheme).timberInk).accessibilityHidden(true)
    }
}

/// "A 1.5pt line being drawn": the reading caption's loader. Static under reduced motion.
private struct ReadingLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drawn = false
    var body: some View {
        let c = AdaptiveColors(colorScheme: scheme)
        Capsule().fill(c.draftingInk).frame(width: 26, height: 1.5)
            .scaleEffect(x: reduceMotion || drawn ? 1 : 0.1, anchor: .leading)
            .onAppear { guard !reduceMotion else { return }; withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) { drawn = true } }
            .accessibilityHidden(true)
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 10_000, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let a = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in a.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: ProposedViewSize(width: a.sizes[i].width, height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint], sizes: [CGSize]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var pts: [CGPoint] = [], sizes: [CGSize] = []
        for s in subviews {
            var sz = s.sizeThatFits(.unspecified)
            if sz.width > width { sz = s.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y)); sizes.append(sz)
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, min(width, x - spacing))
        }
        return (CGSize(width: maxW, height: y + rowH), pts, sizes)
    }
}

extension ProtoModel {
    /// The details line as separate values, one per row.
    var initialPieces: [(PField, String)] {
        let kind = f.category.map { ProtoData.short($0) + (f.categoryRemembered ? " " + pl("(last used)") : "") } ?? pl("Choose kind of work")
        return [(.property, propertyName ?? (zeroMode ? pl("Name your rental") : pl("Choose rental"))), (.category, kind), (.hours, hoursLabel), (.date, dateWord)]
    }

    /// The initial summary of what Log would record: defaults in words, one quiet line.
    var initialLine: String {
        let kind = f.category.map { ProtoData.short($0) + (f.categoryRemembered ? " " + pl("(last used)") : "") } ?? pl("Choose kind of work")
        let who = propertyName ?? (zeroMode ? pl("Name your rental") : pl("Choose rental"))
        return [who, kind, hoursLabel, dateWord].joined(separator: "\u{00A0}· ")
    }
}
#endif
