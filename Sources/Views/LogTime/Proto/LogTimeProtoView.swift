import SwiftUI
import UIKit
import LucideIcons

#if DEBUG
// MARK: - Root (reached from LandlordHoursAppEntry with -LHLogTimeProto 1)

struct LogTimeProtoRoot: View {
    @StateObject private var model: ProtoModel
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

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
            .background(colors.background.ignoresSafeArea())
            .onAppear {
                if let state = LogTimeProtoLaunch.value("-LHProtoState") { model.preset(state) }
                if LogTimeProtoLaunch.value("-LHProtoScript") != nil { model.runScript() }
                if LogTimeProtoLaunch.value("-LHProtoFocus") == "1" { model.wantsFocus = true }
            }
    }
}

// MARK: - The sheet

struct LogTimeProtoSheet: View {
    @ObservedObject var model: ProtoModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var noteFocused: Bool
    @ScaledMetric(relativeTo: .body) private var chevronSize: CGFloat = 16
    @FocusState private var nameFocused: Bool
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    private var unfoldTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            colors.background.ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if model.zeroMode { rentalNameField }
                    noteCard
                    if let caption = model.caption { captionLine(caption).transition(.opacity) }
                    if model.f.unfolded {
                        rows.id("rows").transition(unfoldTransition)
                        if model.f.manual { autoFillOff.transition(.opacity) }
                    } else {
                        recents.transition(.opacity)
                        detailsEntry.transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if LogTimeProtoLaunch.value("-LHProtoScroll") == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("rows", anchor: .top) }
                }
            }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { logBar }
            if let toast = model.toast { toastView(toast.text).padding(.bottom, 96).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .onChange(of: model.wantsFocus) { _, want in if model.zeroMode && want { nameFocused = true } else { noteFocused = want } }
        .onChange(of: model.zeroMode) { _, z in if z && !model.hold { nameFocused = true } }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.eyebrow)
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
            HStack(alignment: .center) {
                (model.zeroMode ? PT("Log your first hour") : PT("Log time"))
                    .font(.system(.title, design: .default).weight(.bold))
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !model.f.unfolded && !model.zeroMode { timerPill }
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
            .foregroundStyle(colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(colors.backgroundSecondary))
            .overlay(Capsule().strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(pl("Timer"))
    }

    private var closeButton: some View {
        Button {} label: {
            LucideIcon(image: Lucide.x, size: 18)
                .foregroundStyle(colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(colors.backgroundSecondary))
                .overlay(Circle().strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(pl("Close"))
    }

    // MARK: first-run rental field

    private var rentalNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            PT("Which rental is this for?")
                .font(.system(.headline))
                .foregroundStyle(colors.textPrimary)
            ZStack(alignment: .leading) {
                if model.rentalName.isEmpty {
                    PT("Name or address, like “Pine Cabin”")
                        .font(.system(.body)).foregroundStyle(colors.textSecondary).allowsHitTesting(false)
                }
                TextField("", text: $model.rentalName)
                    .font(.system(.body))
                    .foregroundStyle(colors.textPrimary)
                    .focused($nameFocused)
                    .accessibilityLabel(pl("Rental name"))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(nameFocused ? colors.action : colors.border, lineWidth: nameFocused ? 1.5 : 0.5))
            PT("You can add the address and type later.")
                .font(.system(.footnote)).foregroundStyle(colors.textSecondary)
        }
    }

    // MARK: note

    private var notePlaceholder: String { model.zeroMode ? pl("What did you do? Try “fixed the sink, 1 hour”") : (model.f.manual ? pl("What did you do? (optional)") : pl("What did you do? Try “fixed the sink at Pine Cabin, 1 hour”")) }

    private var noteCard: some View {
        // Double bezel: a card shell, a tertiary core, concentric radii.
        ZStack(alignment: .topLeading) {
            if model.f.note.isEmpty {
                Text(notePlaceholder)
                    .font(.system(.title3))
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextField("", text: Binding(get: { model.f.note }, set: { model.setNote($0) }), axis: .vertical)
                .font(.system(.title3))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(3...6)
                .focused($noteFocused)
                .submitLabel(.done)
                .accessibilityLabel(pl("What did you do?"))
                .padding(.bottom, 44)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(colors.backgroundTertiary))
        .overlay(alignment: .bottomTrailing) { micButton.padding(8) }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(noteFocused ? colors.action : colors.border, lineWidth: noteFocused ? 1.5 : 0.5))
    }

    private var micButton: some View {
        Button {} label: {
            LucideIcon(image: Lucide.mic, size: 20)
                .foregroundStyle(colors.actionText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(colors.actionSurface))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(pl("Talk instead of type"))
    }

    // MARK: caption

    private func captionLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if model.readingModel { ReadingLine().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 } }
            else if !model.noneFound { Sparkle() }
            Text(text)
                .font(.system(.footnote).weight(.medium))
                .foregroundStyle(model.noneFound ? colors.caution : colors.textSecondary)
                .id(text)
                .transition(.opacity)
            Spacer(minLength: 4)
            if model.fillSource != nil && !model.readingModel {
                Button { model.undoFill() } label: {
                    PT("Undo").font(.system(.footnote).weight(.semibold)).foregroundStyle(colors.actionText)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                }
                .buttonStyle(.lhPressable)
                .accessibilityLabel(pl("Undo the fill"))
            }
        }
        .padding(.horizontal, 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: text)
    }

    // MARK: initial: recents + the labelled manual door

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            PT("RECENT")
                .font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.3)
                .foregroundStyle(colors.draftingInk)
            FlowLayout(spacing: 8) {
                recentChip(.repairs, ProtoData.pine, 1)
                recentChip(.leasing, ProtoData.oak, 0.5)
            }
        }
        .padding(.horizontal, 4)
    }

    private func recentChip(_ c: ActivityCategory, _ p: RentalProperty, _ h: Double) -> some View {
        Button { model.applyRecent(c, p, h) } label: {
            Text(verbatim: "\(ProtoData.short(c)) · \(p.name) · \(hoursText(h))")
                .font(.system(.subheadline).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(colors.backgroundSecondary))
                .overlay(Capsule().strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
    }

    private var detailsEntry: some View {
        Button { model.enterManual() } label: {
            HStack(spacing: 12) {
                LucideIcon(image: Lucide.slidersHorizontal, size: 18).foregroundStyle(colors.actionText)
                VStack(alignment: .leading, spacing: 2) {
                    PT("Enter details yourself").font(.system(.body).weight(.semibold)).foregroundStyle(colors.textPrimary)
                    Text(model.initialLine).font(.system(.footnote)).fixedSize(horizontal: false, vertical: true).foregroundStyle(colors.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                LucideIcon(image: Lucide.chevronRight, size: 16).foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
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
        }.padding(.horizontal, 4)
    }

    // MARK: rows

    private var rows: some View {
        VStack(spacing: 0) {
            if !model.zeroMode { row(.property); divider }
            row(.category); divider
            row(.hours); divider
            row(.date)
            if model.f.record != nil { divider; recordRow }
        }
        .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(colors.backgroundTertiary))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
    }

    private var divider: some View { Rectangle().fill(colors.border.opacity(0.6)).frame(height: 0.5).padding(.leading, 16) }

    private func label(_ f: PField) -> String {
        switch f { case .property: return pl("Rental"); case .category: return pl("Kind of work"); case .hours: return pl("How long")
        case .date: return pl("Date"); case .record: return pl("On the record") }
    }

    private enum Look { case filled(PSource?), empty, loud(String), updated }

    private func look(_ f: PField) -> Look {
        if model.updated[f] != nil { return .updated }
        switch f {
        case .property: return model.f.propertyId == nil ? .empty : .filled(model.f.marks[.property])
        case .category: return model.f.category == nil ? .empty : .filled(model.f.marks[.category])
        case .hours: return model.f.hoursIsDefault ? .loud(pl("\(hoursText(model.f.hours))? You didn't say how long")) : .filled(model.f.marks[.hours])
        case .date: return .filled(model.f.marks[.date])
        case .record: return .filled(model.f.marks[.record])
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
            Button { model.toggle(f) } label: {
                rowLabel(f, l, open: open)
            }
            .buttonStyle(.lhPressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rowA11y(f, l))
            .accessibilityHint(pl("Double-tap to change."))
            if f == .property, model.f.propertyId == nil, model.mentioned.count >= 2 { twoRentalHint }
            if case .updated = l { updatedLine(f) }
            if open { editor(f).transition(.opacity) }
        }
        .background(rowWash(f, l))
    }

    @ViewBuilder private func rowWash(_ f: PField, _ l: Look) -> some View {
        switch l {
        case .loud, .updated: colors.cautionSurface
        default: colors.timber.opacity(model.flash.contains(f) ? 0.16 : 0)
        }
    }

    private func rowLabel(_ f: PField, _ l: Look, open: Bool) -> some View {
        let stacked = type.isAccessibilitySize
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(f)).font(.system(.subheadline)).foregroundStyle(colors.textSecondary)
                    HStack { valueView(f, l); Spacer(minLength: 4); chevron(open) }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text(label(f)).font(.system(.subheadline)).foregroundStyle(colors.textSecondary)
                        .frame(minWidth: 96, alignment: .leading)
                    Spacer(minLength: 4)
                    valueView(f, l)
                    chevron(open)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func chevron(_ open: Bool) -> some View {
        LucideIcon(image: Lucide.chevronRight, size: chevronSize).foregroundStyle(colors.textSecondary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }

    @ViewBuilder private func valueView(_ f: PField, _ l: Look) -> some View {
        switch l {
        case .empty:
            PT("Choose").font(.system(.body).weight(.semibold)).foregroundStyle(colors.actionText)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .overlay(Capsule().strokeBorder(colors.action, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        case .loud(let text):
            Text(text).font(.system(.body).weight(.semibold)).foregroundStyle(colors.cautionText).multilineTextAlignment(.trailing)
        case .updated:
            HStack(spacing: 6) { Text(valueText(f)).font(.system(.body).weight(.semibold)).foregroundStyle(colors.cautionText) }
        case .filled(let src):
            HStack(spacing: 6) {
                Text(valueText(f)).font(.system(.body).weight(.semibold)).foregroundStyle(colors.textPrimary).multilineTextAlignment(.trailing)
                if src != nil { Sparkle() }
            }
        }
    }

    private func rowA11y(_ f: PField, _ l: Look) -> String {
        switch l {
        case .empty: return pl("\(label(f)), not chosen. Button.")
        case .loud: return pl("\(label(f)), \(valueText(f)), you didn't say how long. Button.")
        case .updated: return pl("\(label(f)), \(valueText(f)), updated from your note. Button.")
        case .filled(let s): return s == nil ? pl("\(label(f)), \(valueText(f)). Button.") : pl("\(label(f)), \(valueText(f)), filled from your note. Button.")
        }
    }

    private var recordRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label(.record)).font(.system(.subheadline)).foregroundStyle(colors.textSecondary)
                Sparkle()
            }
            Text(model.f.record ?? "").font(.system(.body)).foregroundStyle(colors.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.timber.opacity(model.flash.contains(.record) ? 0.16 : 0))
        .accessibilityElement(children: .combine)
    }

    private var twoRentalHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            PT("Your note mentions 2 rentals. Log each one on its own.")
                .font(.system(.footnote)).foregroundStyle(colors.textSecondary)
            FlowLayout(spacing: 8) {
                ForEach(model.mentioned) { p in chip(p.name, selected: false) { model.pick(property: p.id) } }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updatedLine(_ f: PField) -> some View {
        HStack(spacing: 4) {
            PT("Updated from your note.").font(.system(.footnote).weight(.medium)).foregroundStyle(colors.cautionText)
            Button { model.undoUpdate(f) } label: {
                PT("Undo").font(.system(.footnote).weight(.semibold)).foregroundStyle(colors.cautionText).underline().frame(minHeight: 44).padding(.horizontal, 6)
            }.buttonStyle(.lhPressable)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 2)
    }

    // MARK: inline editors

    @ViewBuilder private func editor(_ f: PField) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch f {
            case .property:
                FlowLayout(spacing: 8) {
                    ForEach(model.properties) { p in chip(p.name, selected: model.f.propertyId == p.id) { model.pick(property: p.id) } }
                }
            case .category:
                FlowLayout(spacing: 8) {
                    ForEach(ProtoData.counted, id: \.self) { c in chip(ProtoData.short(c), selected: model.f.category == c) { model.pick(category: c) } }
                }
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
        .padding(.horizontal, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepper: some View {
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            stepButton(Lucide.minus, label: pl("Less")) { model.set(hours: model.f.hours - 0.25, collapse: false) }
            Text(hoursText(model.f.hours))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 110)
            stepButton(Lucide.plus, label: pl("More")) { model.set(hours: model.f.hours + 0.25, collapse: false) }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ image: UIImage, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(image: image, size: 20).foregroundStyle(colors.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(colors.backgroundSecondary))
                .overlay(Circle().strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(label)
    }

    private func chip(_ text: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: text).font(.system(.subheadline).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(selected ? colors.actionText : colors.textPrimary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Capsule().fill(selected ? colors.actionSurface : colors.backgroundSecondary))
                .overlay(Capsule().strokeBorder(selected ? colors.action : colors.border, lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.lhPressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: the Log bar

    private var logBar: some View {
        VStack(spacing: 8) {
            if let gap = model.gap {
                Button { model.primary() } label: {
                    barLabel(gapText(gap)).foregroundStyle(colors.actionText)
                        .background(Capsule().fill(colors.actionSurface))
                        .overlay(Capsule().strokeBorder(colors.action.opacity(0.6), lineWidth: 1))
                }.buttonStyle(.lhPressable)
            } else if let summary = model.summary {
                let short = pl("Log \(model.hoursLabel)")
                let full = model.zeroMode ? pl("Add \(model.propertyName ?? "") and log \(summary)") : pl("Log \(summary)")
                ViewThatFits(in: .horizontal) {
                    Button { model.primary() } label: { barLabel(full, oneLine: true).foregroundStyle(colors.onAction).background(Capsule().fill(colors.action)) }
                        .buttonStyle(.lhPressable)
                    VStack(spacing: 8) {
                        Text(summary).font(.system(.footnote)).lineLimit(3).foregroundStyle(colors.textPrimary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        Button { model.primary() } label: { barLabel(short).foregroundStyle(colors.onAction).background(Capsule().fill(colors.action)) }
                            .buttonStyle(.lhPressable)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.summary)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
        .background(colors.background.overlay(alignment: .top) { Rectangle().fill(colors.border.opacity(0.5)).frame(height: 0.5) })
    }

    private func gapText(_ g: ProtoModel.Gap) -> String {
        switch g { case .name: return pl("Name your rental"); case .rental: return pl("Pick a rental"); case .kind: return pl("Pick the kind of work") }
    }

    private func barLabel(_ text: String, oneLine: Bool = false) -> some View {
        Text(verbatim: text)
            .font(.system(.headline))
            .lineLimit(oneLine ? 1 : 3)
            .fixedSize(horizontal: oneLine, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Capsule())
    }

    // MARK: toast

    private func toastView(_ text: String) -> some View {
        HStack(spacing: 14) {
            Text(verbatim: text).font(.system(.subheadline).weight(.medium)).foregroundStyle(colors.background).fixedSize(horizontal: false, vertical: true)
            Button { model.undoLog() } label: {
                PT("Undo").font(.system(.subheadline).weight(.semibold)).foregroundStyle(colors.background).underline().frame(minHeight: 44)
            }.buttonStyle(.lhPressable)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
        .background(Capsule().fill(colors.textPrimary))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - small pieces

private struct Sparkle: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 14
    var body: some View {
        LucideIcon(image: Lucide.sparkles, size: size)
            .foregroundStyle(AdaptiveColors(colorScheme: scheme).timberInk)
            .accessibilityHidden(true)
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
    /// The initial summary of what Log would record: defaults in words.
    var initialLine: String {
        let kind = f.category.map { ProtoData.short($0) + (f.categoryRemembered ? " " + pl("(last used)") : "") } ?? pl("Choose kind of work")
        let who = propertyName ?? (zeroMode ? pl("Name your rental") : pl("Choose rental"))
        return [who, kind, hoursLabel, dateWord].joined(separator: "\u{00A0}· ")
    }
}
#endif
