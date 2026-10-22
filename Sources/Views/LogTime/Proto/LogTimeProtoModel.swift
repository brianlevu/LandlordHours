import SwiftUI
import UIKit

#if DEBUG
// MARK: - Log time, note-first prototype (DEBUG only, throwaway)
//
// Reachable with `-LHLogTimeProto 1`. Uses the real rules parser (NoteRules) and tokens; the model
// pass is scripted. The production Log time view is untouched.
//
//   -LHLogTimeProto 1
//   -LHProtoScript full|partial|two|swap   types the note, fills, unfolds, then taps Log (video)
//   -LHProtoState initial|typing|rules|model|partial|two|swap|edit|undone|manual|zero|zeroNamed|toast
//   -LHProtoFocus 1                        focus the note on launch (keyboard up)
//   -LHProtoModel off                      rules-only phone
//   -LHColorScheme dark|light              (existing flag)

enum LogTimeProtoLaunch {
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    static var isOn: Bool { value("-LHLogTimeProto") != nil }
}

/// Copy goes through the String Catalog (table LogTimeProto).
func pl(_ key: String.LocalizationValue) -> String { String(localized: key, table: "LogTimeProto") }
func PT(_ key: LocalizedStringKey) -> Text { Text(key, tableName: "LogTimeProto") }

enum ProtoScenario: String {
    case full, partial, two, swap, noKind
    var note: String {
        switch self {
        case .full: return "fixed the sink at Pine Cabin, about 2 hours yesterday"
        case .partial: return "met the plumber at Oak Street"
        case .two: return "turnover clean at Pine Cabin and Oak Street"
        case .swap: return "replaced the water heater at Oak Street, 3 hours"
        case .noKind: return "walked Oak Street with Mike"
        }
    }
}

enum ProtoData {
    static let pine = RentalProperty(name: "Pine Cabin", address: "88 Ridge Rd, Big Bear", propertyType: .str, aliases: ["Cabin", "Big Bear"])
    static let oak = RentalProperty(name: "Oak Street", address: "214 Oak St, Pasadena", propertyType: .ltr, aliases: ["Oak St", "The duplex"])
    static let maple = RentalProperty(name: "Maple Court", address: "12 Maple Ct, Glendale", propertyType: .ltr)
    static let all = [pine, oak, maple]
    static let hoursSoFar = 212.0
    static let goal = 500

    static func short(_ c: ActivityCategory) -> String {
        switch c {
        case .repairs: return pl("Repairs")
        case .management: return pl("Management")
        case .leasing: return pl("Showing")
        case .bookkeeping: return pl("Bookkeeping")
        case .legal: return pl("Legal")
        case .insurance: return pl("Insurance")
        case .travel: return pl("Travel")
        case .renovations: return pl("Renovations")
        default: return c.rawValue
        }
    }
    static let counted: [ActivityCategory] = [.repairs, .management, .leasing, .bookkeeping, .legal, .insurance, .travel, .renovations]
}

enum PField: Hashable { case property, category, hours, date, record }
enum PSource { case rules, model }

struct ProtoForm {
    var note = ""
    var propertyId: UUID?
    var category: ActivityCategory? = .repairs
    var categoryRemembered = true
    var hours: Double = 1
    var hoursIsDefault = true
    var date = Calendar.current.startOfDay(for: Date())
    var record: String?
    var marks: [PField: PSource] = [:]
    var touched: Set<PField> = []
    var unfolded = false
    var manual = false
}

func hoursText(_ h: Double) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.hour, .minute]
    f.unitsStyle = .abbreviated
    f.zeroFormattingBehavior = .dropAll
    return f.string(from: h * 3600) ?? "\(h)h"
}

@MainActor
final class ProtoModel: ObservableObject {
    let hasModel: Bool
    /// Capture mode: nothing times out, nothing flashes, so a frame is a state.
    let hold: Bool
    var scenario: ProtoScenario = .full
    var modelDelay: TimeInterval = 2.4

    @Published var f = ProtoForm()
    @Published var zeroMode = false
    @Published var rentalName = ""
    @Published var expanded: PField?
    @Published var flash: Set<PField> = []
    @Published var readingModel = false
    @Published var fillSource: PSource?
    @Published var noneFound = false
    @Published var mentioned: [RentalProperty] = []
    /// Rows the model changed after the user had seen them: field → value before.
    @Published var updated: [PField: ProtoForm] = [:]
    @Published var toast: (text: String, id: Int)?
    @Published var wantsFocus = false
    @Published var pendingTotal = ProtoData.hoursSoFar
    @Published var listening = false
    @Published var micIntro = false
    /// Timer review: the run that filled the hours.
    @Published var timerRan: String?
    static let transcript = "Fixed the sink at Pine Cabin, took about an hour"

    private var before: ProtoForm?
    private var readTask: Task<Void, Never>?
    private var modelTask: Task<Void, Never>?
    private var rulesAt = Date()
    private var suppress = false
    private var toastCounter = 0
    private var lastLogged: ProtoForm?
    var properties: [RentalProperty] { ProtoData.all }

    init(hasModel: Bool, hold: Bool) { self.hasModel = hasModel; self.hold = hold }

    // MARK: derived

    func property(_ id: UUID?) -> RentalProperty? { properties.first { $0.id == id } }
    var propertyName: String? {
        zeroMode ? (rentalName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : rentalName.trimmingCharacters(in: .whitespaces)) : property(f.propertyId)?.name
    }
    enum Gap { case name, rental, kind }
    var gap: Gap? {
        if zeroMode { return propertyName == nil ? .name : (f.category == nil ? .kind : nil) }
        if f.propertyId == nil { return .rental }
        if f.category == nil { return .kind }
        return nil
    }
    var hoursLabel: String { hoursText(f.hours) }
    /// A note was read and it never said how long: the 1h is a default, not a fact.
    var hoursQuestionable: Bool { f.hoursIsDefault && !f.note.isEmpty && !f.manual }
    var isToday: Bool { Calendar.current.isDateInToday(f.date) }
    var dateWord: String {
        if Calendar.current.isDateInToday(f.date) { return pl("Today") }
        if Calendar.current.isDateInYesterday(f.date) { return pl("Yesterday") }
        return f.date.formatted(.dateTime.weekday(.abbreviated))
    }
    var dateValue: String {
        let md = f.date.formatted(.dateTime.month(.abbreviated).day())
        return pl("\(dateWord), \(md)")
    }
    /// What the button says it will do: hours and rental, plus the day when it isn't today.
    var barText: String {
        switch gap {
        case .name?: return pl("Name your rental")
        case .rental?: return pl("Pick a rental")
        case .kind?: return pl("Pick the kind of work")
        case nil:
            let name = propertyName ?? ""
            var t = zeroMode ? pl("Add \(name) and log \(hoursLabel)") : pl("Log \(hoursLabel) at \(name)")
            if !isToday { t += "\u{00A0}· " + dateWord }
            return t
        }
    }
    var eyebrow: String {
        let d = f.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        return isToday ? pl("TODAY · \(d)") : pl("\(dateWord.uppercased()) · \(d)")
    }
    var caption: String? {
        if listening { return pl("Listening… tap to stop") }
        if let ran = timerRan { return pl("Timer ran \(ran)") }
        if readingModel { return fillSource == .rules ? pl("Matched from your words. Reading your note.") : pl("Reading your note") }
        if noneFound { return pl("Couldn't tell which rental. Pick it below.") }
        switch fillSource {
        case .rules?: return pl("Matched from your words")
        case .model?: return pl("Filled from your note")
        case nil: return nil
        }
    }

    // MARK: animation helper

    func anim(_ body: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled { withAnimation(.easeOut(duration: 0.2), body) }
        else { withAnimation(.spring(response: 0.3, dampingFraction: 1.0), body) }
    }

    // MARK: note + rules

    func setNote(_ text: String) {
        guard text != f.note else { return }
        f.note = text
        guard !suppress, !f.manual else { return }
        // Editing the note after a fill starts a new fill; the old caption goes away.
        readTask?.cancel()
        modelTask?.cancel()
        if fillSource != nil || readingModel { anim { fillSource = nil; readingModel = false; noneFound = false } }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 else { return }
        readTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.readRules()
        }
    }

    private func request() -> NoteReadRequest {
        NoteReadRequest(text: f.note, properties: zeroMode ? [] : properties, spouseTracking: false)
    }

    func readRules() {
        let r = NoteRules.read(request())
        if before == nil { before = f }
        var changed: Set<PField> = []
        anim {
            mentioned = r.mentionedPropertyCount >= 2 && !zeroMode
                ? NoteRules.mentionedProperties(normalized: RulesEngine.normalize(f.note), properties: properties) : []
            if !f.touched.contains(.property), let id = r.propertyId { f.propertyId = id; f.marks[.property] = .rules; changed.insert(.property) }
            if !f.touched.contains(.category) {
                if let c = r.category { f.category = c; f.categoryRemembered = false; f.marks[.category] = .rules; changed.insert(.category) }
                else if f.categoryRemembered { f.category = nil; f.categoryRemembered = false }
            }
            if !f.touched.contains(.hours), let h = r.hours { f.hours = h; f.hoursIsDefault = false; f.marks[.hours] = .rules; changed.insert(.hours) }
            if !f.touched.contains(.date), let d = r.date { f.date = d; f.marks[.date] = .rules; changed.insert(.date) }
            f.unfolded = true
            expanded = nil
            fillSource = changed.isEmpty ? nil : .rules
            noneFound = changed.isEmpty || (f.propertyId == nil && f.category == nil && mentioned.isEmpty)
            readingModel = hasModel
        }
        rulesAt = Date()
        pulse(changed)
        UIAccessibility.post(notification: .announcement, argument: pl("Filled from your words."))
        guard hasModel, !hold else { return }
        modelTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.modelDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.applyModel(late: Date().timeIntervalSince(self.rulesAt) > 1.5)
        }
    }

    /// The scripted model pass: confirms what the rules found, fills the kind of work from intent,
    /// adds the record sentence. It never invents hours and never picks between two rentals.
    func applyModel(late: Bool) {
        let r = NoteRules.read(request())
        var category = r.category
        if scenario == .swap { category = (r.category == .renovations) ? .repairs : .renovations }
        else if category == nil, f.note.lowercased().contains("plumber") { category = .repairs }
        let sentence = f.note.split(separator: ",").first.map { String($0) } ?? f.note
        let record = sentence.prefix(1).uppercased() + sentence.dropFirst()
        var changed: Set<PField> = []
        let seen = f
        anim {
            if !f.touched.contains(.category), let c = category, c != f.category {
                if f.category != nil, f.marks[.category] != nil, late {
                    updated[.category] = seen
                    scheduleUpdateExpiry(.category)
                }
                f.category = c; f.categoryRemembered = false; changed.insert(.category)
            }
            if f.category != nil, f.marks[.category] == nil || changed.contains(.category) { f.marks[.category] = .model }
            f.record = record
            f.marks[.record] = .model
            changed.insert(.record)
            readingModel = false
            fillSource = .model
            noneFound = false
        }
        pulse(changed)
        UIAccessibility.post(notification: .announcement, argument: pl("Filled from your note."))
    }

    private func scheduleUpdateExpiry(_ field: PField) {
        guard !hold else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self?.anim { _ = self?.updated.removeValue(forKey: field) }
        }
    }

    private func pulse(_ fields: Set<PField>) {
        guard !fields.isEmpty, !hold else { return }
        if !UIAccessibility.isReduceMotionEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(.easeOut(duration: 0.3)) { flash.formUnion(fields) }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeOut(duration: 0.3)) { self?.flash.subtract(fields) }
        }
    }

    // MARK: actions

    func undoFill() {
        guard let b = before else { return }
        readTask?.cancel(); modelTask?.cancel()
        let note = f.note
        anim {
            f = b
            f.note = note
            f.unfolded = true
            f.marks = [:]
            fillSource = nil; readingModel = false; noneFound = false; updated = [:]; mentioned = []
        }
        before = nil
    }

    func undoUpdate(_ field: PField) {
        guard let old = updated[field] else { return }
        anim {
            if field == .category { f.category = old.category; f.marks[.category] = .rules; f.touched.insert(.category) }
            updated.removeValue(forKey: field)
        }
    }

    func micTapped() {
        anim {
            if listening { listening = false }
            else if !micSeen { micIntro = true }
            else { listening = true }
        }
    }
    func startTalking() { anim { micSeen = true; micIntro = false; listening = true } }
    @Published var micSeen = false

    func enterManual() {
        readTask?.cancel(); modelTask?.cancel()
        anim { f.manual = true; f.unfolded = true; fillSource = nil; readingModel = false; noneFound = false }
    }

    func turnAutoFillOn() {
        anim { f.manual = false }
        if f.note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 { readRules() }
    }

    func toggle(_ field: PField) { anim { expanded = expanded == field ? nil : field } }

    func touch(_ field: PField) {
        f.touched.insert(field)
        f.marks[field] = nil
        updated.removeValue(forKey: field)
        if field == .hours { f.hoursIsDefault = false }
        if field == .category { f.categoryRemembered = false }
    }

    func pick(property id: UUID) { anim { f.propertyId = id; touch(.property); mentioned = []; noneFound = false; f.unfolded = true; expanded = nil } }
    func pick(category c: ActivityCategory) { anim { f.category = c; touch(.category); expanded = nil } }
    func set(hours h: Double, collapse: Bool) { anim { f.hours = max(0.25, min(24, h)); touch(.hours); if collapse { expanded = nil } } }
    func set(date d: Date) { anim { f.date = Calendar.current.startOfDay(for: d); touch(.date); expanded = nil } }

    func applyRecent(_ c: ActivityCategory, _ p: RentalProperty, _ h: Double) {
        anim {
            f.category = c; f.categoryRemembered = false; f.propertyId = p.id; f.hours = h; f.hoursIsDefault = false
            f.touched = [.property, .category, .hours]; f.marks = [:]; f.unfolded = true
        }
    }

    func primary() {
        if let gap {
            anim {
                f.unfolded = true
                switch gap { case .rental: expanded = .property; case .kind: expanded = .category; case .name: break }
            }
            return
        }
        log()
    }

    func log() {
        let text = pl("Logged \(hoursText(f.hours)) · \(Int(ProtoData.hoursSoFar + f.hours)) of \(ProtoData.goal) hours")
        lastLogged = f
        if !UIAccessibility.isReduceMotionEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        readTask?.cancel(); modelTask?.cancel()
        let keepZero = zeroMode
        anim {
            f = ProtoForm(); fillSource = nil; readingModel = false; noneFound = false; updated = [:]; mentioned = []; expanded = nil
            zeroMode = false
            _ = keepZero
        }
        before = nil
        showToast(text)
    }

    func showToast(_ text: String) {
        toastCounter += 1
        let id = toastCounter
        withAnimation(.easeOut(duration: 0.22)) { toast = (text, id) }
        guard !hold else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.toast?.id == id else { return }
            withAnimation(.easeIn(duration: 0.18)) { self.toast = nil }
        }
    }

    func undoLog() {
        withAnimation(.easeIn(duration: 0.18)) { toast = nil }
        if let l = lastLogged { anim { f = l } }
    }

    // MARK: presets (captures) and the script (video)

    func preset(_ name: String) {
        suppress = true
        defer { suppress = false }
        switch name {
        case "initial": break
        case "typing": f.note = scenario.note
        case "rules": f.note = scenario.note; readRules(); readingModel = hasModel
        case "model": f.note = scenario.note; readRules(); applyModel(late: false)
        case "partial": f.note = scenario.note; readRules(); if hasModel { applyModel(late: false) }
        case "two": f.note = scenario.note; readRules(); if hasModel { applyModel(late: false) }
        case "swap": f.note = scenario.note; readRules(); applyModel(late: true)
        case "edit": f.note = scenario.note; readRules(); applyModel(late: false); expanded = .hours
        case "undone": f.note = scenario.note; readRules(); applyModel(late: false); undoFill()
        case "manual": enterManual()
        case "listening":
            f.note = Self.transcript; readRules(); readingModel = false; listening = true
        case "micIntro": micIntro = true
        case "timerReview":
            f.propertyId = ProtoData.pine.id; f.category = .repairs; f.categoryRemembered = false
            f.hours = 4440.0 / 3600.0; f.hoursIsDefault = false; f.unfolded = true; timerRan = hoursText(4440.0 / 3600.0)
        case "zero": zeroMode = true; f.category = .repairs
        case "zeroNamed": zeroMode = true; rentalName = "Pine Cabin"; f.note = "fixed the sink, 1 hour"; readRules()
        case "toast": showToast(pl("Logged \(hoursText(2)) · \(Int(ProtoData.hoursSoFar + 2)) of \(ProtoData.goal) hours"))
        default: break
        }
    }

    func runScript() {
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.wantsFocus = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            for ch in self.scenario.note {
                self.setNote(self.f.note + String(ch))
                try? await Task.sleep(nanoseconds: 42_000_000)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)   // the pause: rules fill, rows unfold
            self.wantsFocus = false
            try? await Task.sleep(nanoseconds: 3_800_000_000) // model lands
            self.primary()
        }
    }
}
#endif
