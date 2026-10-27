import SwiftUI

#if DEBUG
// MARK: - Log time v2 design sandbox: the model (DESIGN ONLY, compiled out of Release)
//
//   -LHLogV2 A|B  [-LHLogV2State <state>] [-LHColorScheme light|dark] [-LHTypeSize xxl|ax3]
//                 [-LHLogV2Play type|voice|timer] [-LHLogV2Free]
//
// Hard-coded sample rentals, no production wiring: nothing here reads or writes AppViewModel,
// the store or the timer. The ONLY production code it calls is the parser's rules tier
// (`NoteRules.read`), so the review card shows exactly the fields the shipping parser fills
// today. Provenance ("from your note" / assumed / needs an answer) is derived here from what
// the reading left nil; the plan (docs/design/log-time-v2-plan.md) moves it into the parser.

enum LogV2Direction: String { case a = "A", b = "B" }

enum LogV2Stage: String, CaseIterable {
    /// A: the one calm screen. B: the three doors.
    case entry
    /// B only: the Type door, field focused.
    case typing
    case listening
    case reading
    case review
    case timerRunning
    case timerNote
    case manual
    /// The sheet is dismissing after Log; the toast shows once it is gone (r2 glitch fix).
    case closing
    case logged
}

/// Where a value on the review card came from.
enum LogV2Source: Equatable {
    /// The note said it.
    case note
    /// A default the app chose; the string says which ("Your only rental", "Today", "Last used").
    case assumed(String)
    /// The note didn't say and there is no safe default: ask, inline.
    case needed
    /// The user changed it on the card.
    case edited
}

enum LogV2Field: String, CaseIterable, Identifiable {
    case rental, hours, work, who, day
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rental: return "Rental"
        case .hours: return "Time"
        case .work: return "Work"
        case .who: return "Who"
        case .day: return "Day"
        }
    }

    var question: String {
        switch self {
        case .rental: return "Which rental?"
        case .hours: return "How long did it take?"
        case .work: return "What kind of work?"
        case .who: return "Who did it?"
        case .day: return "Which day?"
        }
    }
}

struct LogV2Sample {
    static let pine = RentalProperty(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                                     name: "Pine Cabin", address: "18 Pine Ridge Rd, Big Bear, CA", propertyType: .str)
    static let oak = RentalProperty(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                                    name: "Oak Street Duplex", address: "412 Oak St, Pasadena, CA", propertyType: .ltr)
    static let elm = RentalProperty(id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                                    name: "Elm Cottage", address: "9 Elm Ct, Altadena, CA", propertyType: .ltr)

    /// A fixed "now" so every capture says the same day: Tue Oct 27 2026, 9:41.
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 27; c.hour = 9; c.minute = 41
        return Calendar.current.date(from: c) ?? Date()
    }()

    struct Recent: Identifiable {
        let id = UUID()
        let note: String
        let title: String
        let hours: Double
    }

    static let recents: [Recent] = [
        Recent(note: "turnover cleaning at Pine Cabin, 2 hours", title: "Turnover at Pine Cabin", hours: 2),
        Recent(note: "showing at Oak Street Duplex, 1 hour", title: "Showing at Oak Street Duplex", hours: 1),
        Recent(note: "paid bills and did the books, 30 min", title: "Books and bills", hours: 0.5),
    ]

    /// The scripted sentences for captures and videos.
    static let typedNote = "fixed the sink at Pine Cabin, 1 hour"
    static let spokenNote = "Met the plumber at Oak Street Duplex yesterday, about an hour and a half"
    static let unsureNote = "replaced the smoke detector batteries, 45 min"
    static let freeNote = "tenant called about the lease renewal"
    static let timerNote = "Turnover after the weekend guests"
}

/// The sandbox's one source of truth. Interactive (taps work on the simulator) and scriptable
/// (`-LHLogV2State`, `-LHLogV2Play`).
@MainActor
final class LogV2Model: ObservableObject {
    let direction: LogV2Direction
    let isFree: Bool
    let spouseTracking: Bool
    var properties: [RentalProperty]

    @Published var stage: LogV2Stage = .entry
    @Published var note = ""
    @Published var transcript = ""
    @Published var level: Double = 0
    @Published var expanded: LogV2Field?

    // The draft the card shows.
    @Published var rentalId: UUID?
    @Published var hours: Double?
    @Published var work: ActivityCategory?
    @Published var who: Participant = .selfParticipant
    @Published var day: Date = LogV2Sample.now
    @Published var sources: [LogV2Field: LogV2Source] = [:]
    @Published var noteNamesTwoRentals = false

    // Timer.
    @Published var timerStart: Date = LogV2Sample.now.addingTimeInterval(-(1 * 3600 + 12 * 60 + 8))
    @Published var timerStopped: Date?
    @Published var timerFrozen = false

    @Published var toast: String?
    @Published var usedVoice = false
    /// r2: which way the next step change pushes (A only).
    @Published var forward = true
    /// r2: the review came from a stopped timer.
    @Published var fromTimer = false
    private var pendingToast: String?
    /// Captures and the type video show the system keyboard.
    @Published var wantsKeyboard = false

    init(direction: LogV2Direction, isFree: Bool) {
        self.direction = direction
        self.isFree = isFree
        self.spouseTracking = !isFree
        self.properties = isFree ? [LogV2Sample.pine] : [LogV2Sample.pine, LogV2Sample.oak, LogV2Sample.elm]
    }

    // MARK: Reading

    /// The shipping rules tier, then provenance by field.
    func read(_ text: String) {
        let request = NoteReadRequest(text: text, properties: properties, spouseTracking: spouseTracking,
                                      now: LogV2Sample.now, calendar: .current)
        let r = NoteRules.read(request)
        var s: [LogV2Field: LogV2Source] = [:]
        noteNamesTwoRentals = r.mentionedPropertyCount >= 2

        if let id = r.propertyId {
            rentalId = id; s[.rental] = .note
        } else if properties.count == 1 {
            rentalId = properties[0].id; s[.rental] = .assumed("Your only rental")
        } else {
            rentalId = nil; s[.rental] = .needed
        }

        if let h = r.hours { hours = h; s[.hours] = .note } else { hours = nil; s[.hours] = .needed }

        if let c = r.category { work = c; s[.work] = .note } else { work = .repairs; s[.work] = .assumed("Last used") }

        if r.participant == .spouse { who = .spouse; s[.who] = .note } else { who = .selfParticipant; s[.who] = .assumed("") }

        if let d = r.date {
            day = d; s[.day] = Calendar.current.isDate(d, inSameDayAs: LogV2Sample.now) ? .note : .note
        } else { day = LogV2Sample.now; s[.day] = .assumed("") }

        sources = s
        expanded = firstNeeded
    }

    var firstNeeded: LogV2Field? {
        fieldsShown.first { sources[$0] == .needed }
    }

    var fieldsShown: [LogV2Field] {
        spouseTracking ? [.rental, .hours, .work, .who, .day] : [.rental, .hours, .work, .day]
    }

    var canLog: Bool { firstNeeded == nil && rentalId != nil && (hours ?? 0) > 0 }

    var rentalName: String? { properties.first { $0.id == rentalId }?.name }

    func value(_ field: LogV2Field) -> String? {
        switch field {
        case .rental: return rentalName
        case .hours: return hours.map { LHFormat.hours($0) }
        case .work: return work?.inboxLabel
        case .who: return who == .spouse ? "Your spouse" : "You"
        case .day: return LogV2Format.day(day)
        }
    }

    // MARK: Edits (the card's inline answers)

    func setRental(_ id: UUID) { rentalId = id; sources[.rental] = .edited; advance() }
    func setHours(_ h: Double) { hours = h; sources[.hours] = .edited; advance() }
    func setWork(_ c: ActivityCategory) { work = c; sources[.work] = .edited; advance() }
    func setWho(_ p: Participant) { who = p; sources[.who] = .edited }
    func setDay(_ d: Date) { day = d; sources[.day] = .edited }

    /// After an answer, the next open question opens; otherwise the card closes up.
    private func advance() {
        withAnimation(AppAnimation.flow) { expanded = firstNeeded }
    }

    func toggle(_ field: LogV2Field) {
        withAnimation(AppAnimation.flow) { expanded = expanded == field ? nil : field }
    }

    // MARK: Flow

    func submitNote() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        withAnimation(AppAnimation.reveal) { stage = .reading }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            read(text)
            withAnimation(AppAnimation.flow) { stage = .review }
        }
    }

    /// A: the card builds while you type (600 ms after the last key, like today's sheet).
    private var liveTask: Task<Void, Never>?
    func noteChangedLive() {
        guard direction == .a, stage == .entry || stage == .review else { return }
        liveTask?.cancel()
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count < 6 {
            withAnimation(AppAnimation.flow) { stage = .entry }
            return
        }
        liveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            read(text)
            withAnimation(AppAnimation.flow) { stage = .review }
        }
    }

    func startListening() {
        transcript = ""
        forward = true
        withAnimation(AppAnimation.reveal) { stage = .listening }
    }

    func stopListening() {
        forward = false
        usedVoice = true
        note = transcript
        submitNote()
    }

    func startTimer() {
        forward = true
        timerStart = Date()
        timerFrozen = false
        withAnimation(AppAnimation.flow) { stage = .timerRunning }
    }

    /// "1h 12m at Pine Cabin" for the note step.
    var timerSummary: String {
        let end = timerStopped ?? Date()
        return "\(LHFormat.hours((end.timeIntervalSince(timerStart) / 60).rounded(.down) / 60)) at Pine Cabin"
    }

    func stopTimer() {
        timerStopped = Date()
        withAnimation(AppAnimation.flow) { stage = .timerNote }
    }

    /// Stopped timer + optional note → the same review card. The timer knows the rental, the
    /// time and the day; the note only adds the work and the words.
    func finishTimer() {
        let elapsed = (timerStopped ?? Date()).timeIntervalSince(timerStart)
        forward = true
        fromTimer = true
        read(note.isEmpty ? "turnover" : note)
        rentalId = LogV2Sample.pine.id
        // r2 (A): the minutes the timer ran, never rounded, so the note step and the card agree.
        // B keeps r1's quarter-hour rounding for comparison.
        hours = direction == .a ? max(1, (elapsed / 60).rounded(.down)) / 60
                                : max(0.25, (elapsed / 3600 / 0.25).rounded() * 0.25)
        day = LogV2Sample.now
        sources[.rental] = .assumed("From the timer")
        sources[.hours] = .assumed("From the timer")
        sources[.day] = .assumed("")
        if note.isEmpty { sources[.work] = .assumed("Last used") }
        expanded = firstNeeded
        withAnimation(AppAnimation.flow) { stage = .review }
    }

    func log() {
        guard canLog else { return }
        // r2: the sheet dismisses first; the toast appears after it is gone (no sheet behind it).
        pendingToast = "Logged \(LHFormat.hours(hours)) at \(rentalName ?? "")"
        stage = .closing
    }

    /// Called by the root's `onDismiss`.
    func sheetDismissed() {
        guard stage == .closing else { return }
        withAnimation(AppAnimation.reveal) {
            toast = pendingToast
            stage = .logged
        }
    }

    /// r2: "Answer 1 question" on the disabled Log button.
    var openQuestions: Int { fieldsShown.filter { sources[$0] == .needed }.count }

    func reset() {
        note = ""; transcript = ""; sources = [:]; expanded = nil; hours = nil; rentalId = nil; toast = nil
        withAnimation(AppAnimation.flow) { stage = .entry }
    }

    // MARK: Scripted states (captures)

    func apply(state: String) {
        switch state {
        case "entry": stage = .entry
        case "typing":
            note = "fixed the sink at Pi"
            wantsKeyboard = true
            stage = direction == .b ? .typing : .entry
        case "listening":
            stage = .listening; transcript = "Met the plumber at Oak Street Duplex yesterday, about"; level = 0.62
        case "reading":
            note = LogV2Sample.spokenNote; stage = .reading
        case "review":
            note = LogV2Sample.typedNote; read(note); stage = .review
        case "reviewVoice":
            note = LogV2Sample.spokenNote; usedVoice = true; read(note); stage = .review
        case "question":
            note = LogV2Sample.unsureNote; read(note); stage = .review
        case "free":
            note = LogV2Sample.freeNote; read(note); stage = .review
            if direction == .b { expanded = .rental }
        case "freeRental":
            note = LogV2Sample.freeNote; read(note); stage = .review
            expanded = .rental
        case "freeHours":
            note = LogV2Sample.freeNote; read(note); stage = .review
        case "timerRunning":
            timerStart = LogV2Sample.now.addingTimeInterval(-(1 * 3600 + 12 * 60 + 8))
            timerFrozen = true; stage = .timerRunning
        case "timerNote":
            timerStart = LogV2Sample.now.addingTimeInterval(-(1 * 3600 + 12 * 60 + 8))
            timerStopped = LogV2Sample.now; timerFrozen = true
            note = LogV2Sample.timerNote; stage = .timerNote
        case "timerReview":
            timerStart = LogV2Sample.now.addingTimeInterval(-(1 * 3600 + 12 * 60 + 8))
            timerStopped = LogV2Sample.now; timerFrozen = true
            note = LogV2Sample.timerNote; finishTimer(); stage = .review
        case "manual":
            if direction == .a {
                // r2: no time is ever assumed, not even here.
                rentalId = LogV2Sample.pine.id; hours = nil; work = .repairs; stage = .manual
                sources = [.rental: .assumed("Last used"), .hours: .needed, .work: .assumed("Last used"),
                           .who: .assumed(""), .day: .assumed("")]
                expanded = .hours
            } else {
                rentalId = LogV2Sample.pine.id; hours = 1; work = .repairs; stage = .manual
                sources = [.rental: .edited, .hours: .edited, .work: .edited, .who: .edited, .day: .edited]
            }
        case "edit":
            note = LogV2Sample.typedNote; read(note); stage = .review; expanded = .hours
        case "logged":
            note = LogV2Sample.typedNote; read(note); stage = .logged; toast = "Logged 1h at Pine Cabin"
        default: break
        }
    }

    // MARK: Autoplay (videos)

    func play(_ script: String) async {
        func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
        await pause(1500)
        switch script {
        case "type":
            wantsKeyboard = true
            if direction == .b {
                withAnimation(AppAnimation.flow) { stage = .typing }
                await pause(700)
            }
            for ch in LogV2Sample.typedNote {
                note.append(ch)
                if direction == .a { noteChangedLive() }
                await pause(ch == " " ? 120 : 70)
            }
            await pause(900)
            wantsKeyboard = false
            if direction == .b { submitNote(); await pause(900) }
            await pause(1600)
            log()
            await pause(2500)
        case "voice":
            if direction == .a { await pause(300) }
            startListening()
            let words = LogV2Sample.spokenNote.split(separator: " ")
            for (i, w) in words.enumerated() {
                transcript += (i == 0 ? "" : " ") + w
                withAnimation(AppAnimation.feedback) { level = Double.random(in: 0.35...0.9) }
                await pause(260)
            }
            withAnimation(AppAnimation.feedback) { level = 0 }
            await pause(700)
            stopListening()
            await pause(2600)
            log()
            await pause(2500)
        case "question":
            note = ""
            for ch in LogV2Sample.unsureNote {
                note.append(ch)
                if direction == .a { noteChangedLive() }
                await pause(60)
            }
            await pause(800)
            if direction == .b { submitNote(); await pause(900) }
            await pause(1500)
            setRental(LogV2Sample.elm.id)
            await pause(1500)
            log()
            await pause(2500)
        case "timer":
            startTimer()
            timerStart = Date().addingTimeInterval(-(72 * 60 + 5))
            await pause(3500)
            stopTimer()
            await pause(700)
            for ch in LogV2Sample.timerNote { note.append(ch); await pause(55) }
            await pause(700)
            finishTimer()
            await pause(2200)
            log()
            await pause(2500)
        default: break
        }
    }
}

enum LogV2Format {
    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: LogV2Sample.now) { return "Today" }
        if let y = cal.date(byAdding: .day, value: -1, to: LogV2Sample.now), cal.isDate(date, inSameDayAs: y) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static let subtitle = "Today, Tue Oct 27"

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
#endif
