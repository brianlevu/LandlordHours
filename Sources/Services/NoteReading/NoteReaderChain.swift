import Foundation
import os.log
#if canImport(FoundationModels)
import FoundationModels
#endif

private let noteLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "NoteReader")

// MARK: - Tier order for the Log time note
//
//   rules (instant, always) → on-device model (≤ 8 s) → PCC (≤ 10 s), PCC only when:
//     - the on-device model is unavailable, failed or timed out, OR
//     - its answer is incomplete: no category, no usable description, or no property while the
//       user has more than one (PCC is the stronger model for exactly these notes), AND
//     - PCCGate is open: the user's PCC setting (default on), the remote flag (default OFF),
//       the PCC entitlement in this build (PCCEntitlement; without it FoundationModels traps),
//       iOS 27, eligibility, readiness and quota. A quota hit mid-call closes PCC for that note.
//   Real-device latency (BLV-Phone, iOS 27, 111 calls): median 5.9 s, hence the 8 s budget.
//   Rate limits put the tier in a cool-down (15 s, doubling to 5 min). A refusal ("may contain
//   sensitive content") makes that note rules-only: no retry, no PCC. The same note is never
//   sent twice (NoteReadCache). All of it is quiet: the rules result stays in the form.
//
// Why on-device first: it answers in about a second, costs nothing, has no quota and the note
// never leaves the phone. PCC is a fallback, so most notes stay on the phone and the PCC quota
// is kept for the notes that need it. The rules result fills the form first, so the sheet
// never waits on a model; each later tier only refines fields the user hasn't touched.

struct NoteReaderChain {
    enum Attempt: Error, Equatable {
        case notNeeded
        case unavailable(ModelUnavailableReason)
        case timedOut
        case failed
        case answered
        /// "Request has been rate limited": the tier cools down.
        case rateLimited
        /// The model declined the note (guardrail/refusal): rules only for this note.
        case refused
        /// Same note as before: the earlier answer, no new model call.
        case cached
    }

    struct Outcome: Equatable {
        var reading: NoteReading
        var onDevice: Attempt
        var pcc: Attempt
    }

    static let defaultOnDeviceTimeout: TimeInterval = 8
    static let defaultPCCTimeout: TimeInterval = 10

    let onDevice: NoteModelBackend
    let pcc: NoteModelBackend
    let pccGate: PCCGate
    var onDeviceTimeout: TimeInterval
    var pccTimeout: TimeInterval
    let cooldown: NoteModelCooldown
    let cache: NoteReadCache

    init(onDevice: NoteModelBackend, pcc: NoteModelBackend, pccGate: PCCGate = PCCGate(),
         onDeviceTimeout: TimeInterval = NoteReaderChain.defaultOnDeviceTimeout,
         pccTimeout: TimeInterval = NoteReaderChain.defaultPCCTimeout,
         cooldown: NoteModelCooldown = NoteModelCooldown(), cache: NoteReadCache = NoteReadCache()) {
        self.onDevice = onDevice
        self.pcc = pcc
        self.pccGate = pccGate
        self.onDeviceTimeout = onDeviceTimeout
        self.pccTimeout = pccTimeout
        self.cooldown = cooldown
        self.cache = cache
    }

    /// Apple's models on this device, behind the user's PCC setting and the remote flag.
    static func live() -> NoteReaderChain {
        #if DEBUG
        if let debug = NoteReaderDebug.chain() { return debug }
        #endif
        let onDevice = CaptureFlags().isEnabled(.noteModel)
            ? NoteModelBackends.onDevice()
            : UnavailableNoteBackend(tier: .onDevice, reason: .disabledByFlag)
        return NoteReaderChain(onDevice: onDevice, pcc: NoteModelBackends.privateCloudCompute(),
                               cooldown: .shared, cache: .shared)
    }

    func rules(_ request: NoteReadRequest) -> NoteReading { NoteRules.read(request) }

    /// Whether any model tier could run now (the sheet shows the drafting line only then).
    var hasModel: Bool { onDeviceAvailability().isAvailable || pccAvailability().isAvailable }

    func onDeviceAvailability() -> ModelAvailability {
        if cooldown.isCoolingDown(.onDevice) { return .unavailable(.coolingDown) }
        return onDevice.availability
    }

    func pccAvailability() -> ModelAvailability {
        let gate = pccGate.availability()
        guard gate.isAvailable else { return gate }
        if cooldown.isCoolingDown(.pcc) { return .unavailable(.coolingDown) }
        return pcc.availability
    }

    /// The model tiers over the rules result. `onRefine` gets the on-device reading when PCC is
    /// about to be asked too, so the sheet fills fields as they come.
    func read(_ request: NoteReadRequest, rules base: NoteReading? = nil,
              onRefine: @escaping @MainActor (NoteReading) -> Void = { _ in }) async -> Outcome {
        let rules = base ?? self.rules(request)
        let prompt = NoteModelPrompt(request)
        var result = Outcome(reading: rules, onDevice: .notNeeded, pcc: .notNeeded)
        let key = NoteReadCache.key(request)
        if let cached = cache.reading(for: key) {
            result.reading = cached
            result.onDevice = .cached
            return result
        }
        if cache.isRulesOnly(key) {
            result.onDevice = .refused
            return result
        }

        var onDeviceReading: NoteReading?
        let onDeviceState = onDeviceAvailability()
        if onDeviceState.isAvailable {
            switch await ask(onDevice, prompt: prompt, timeout: onDeviceTimeout) {
            case .success(let draft):
                result.onDevice = .answered
                cooldown.succeeded(.onDevice)
                onDeviceReading = NoteReadMerge.merge(rules: rules, draft: draft, prompt: prompt, tier: .onDevice)
            case .failure(let attempt):
                result.onDevice = attempt
                if attempt == .rateLimited { cooldown.rateLimited(.onDevice) }
                if attempt == .refused {
                    // The model won't read this note: rules only, and never sent elsewhere.
                    cache.markRulesOnly(key)
                    return result
                }
            }
        } else if case .unavailable(let reason) = onDeviceState {
            result.onDevice = .unavailable(reason)
        }
        if Task.isCancelled { return result }

        if let onDeviceReading {
            result.reading = onDeviceReading
            guard Self.needsEscalation(onDeviceReading, request: request) else {
                cache.store(onDeviceReading, for: key)
                return result
            }
        }

        let gate = pccAvailability()
        guard gate.isAvailable else {
            if case .unavailable(let reason) = gate { result.pcc = .unavailable(reason) }
            if let onDeviceReading { cache.store(onDeviceReading, for: key) }
            return result
        }
        if let onDeviceReading { await onRefine(onDeviceReading) }
        switch await ask(pcc, prompt: prompt, timeout: pccTimeout) {
        case .success(let draft):
            result.pcc = .answered
            cooldown.succeeded(.pcc)
            let pccReading = NoteReadMerge.merge(rules: rules, draft: draft, prompt: prompt, tier: .pcc)
            result.reading = NoteReadMerge.combine(primary: pccReading, secondary: onDeviceReading)
            cache.store(result.reading, for: key)
        case .failure(let attempt):
            result.pcc = attempt
            if attempt == .rateLimited { cooldown.rateLimited(.pcc) }
            if attempt == .refused { cache.markRulesOnly(key) }
            if let onDeviceReading, attempt != .timedOut { cache.store(onDeviceReading, for: key) }
        }
        return result
    }

    /// The on-device answer is good enough to stop: a category, a description that passed the
    /// fact guard, and a property whenever there is a choice to make.
    static func needsEscalation(_ reading: NoteReading, request: NoteReadRequest) -> Bool {
        if reading.category == nil || reading.description == nil { return true }
        if reading.propertyId == nil && request.properties.count > 1 { return true }
        return false
    }

    private enum Race {
        case answered(Swift.Result<NoteModelDraft, Error>)
        case timedOut
    }

    private func ask(_ backend: NoteModelBackend, prompt: NoteModelPrompt, timeout: TimeInterval) async -> Swift.Result<NoteModelDraft, Attempt> {
        let outcome: Race = await withTaskGroup(of: Race.self) { group in
            group.addTask {
                do { return .answered(.success(try await backend.draft(prompt))) } catch { return .answered(.failure(error)) }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
        switch outcome {
        case .timedOut:
            noteLogger.info("Note reader \(backend.tier.rawValue, privacy: .public) timed out")
            return .failure(.timedOut)
        case .answered(.success(let draft)):
            return .success(draft)
        case .answered(.failure(let error)):
            if let kind = Self.generationFailure(error) {
                noteLogger.info("Note reader \(backend.tier.rawValue, privacy: .public): \(String(describing: kind), privacy: .public)")
                return .failure(kind)
            }
            noteLogger.error("Note reader \(backend.tier.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if let reason = Self.unavailableReason(for: error) { return .failure(.unavailable(reason)) }
            return .failure(.failed)
        }
    }

    /// Rate limits and refusals from FoundationModels (both models share these errors).
    static func generationFailure(_ error: Error) -> Attempt? {
        if let scripted = error as? NoteModelScriptedError {
            return scripted == .rateLimited ? .rateLimited : .refused
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .rateLimited, .concurrentRequests: return .rateLimited
            case .guardrailViolation, .refusal: return .refused
            default: return nil
            }
        }
        #endif
        return nil
    }

    /// A PCC quota or service error, or an availability error from a backend.
    static func unavailableReason(for error: Error) -> ModelUnavailableReason? {
        if case NoteModelError.unavailable(let reason) = error { return reason }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *), let reason = SystemPCCStatus.reason(for: error) { return reason }
        #endif
        return nil
    }
}

// MARK: - Cool-down and cache (never hammer the model)

/// Test stand-ins for FoundationModels' rate-limit and refusal errors (which tests can't build).
enum NoteModelScriptedError: Error, Equatable {
    case rateLimited
    case refused
}

/// Per-tier back-off after "Request has been rate limited": 15 s, doubling to 5 min; a success
/// resets it. Shared by every Log sheet in the app (`shared`).
final class NoteModelCooldown: @unchecked Sendable {
    static let shared = NoteModelCooldown()
    static let base: TimeInterval = 15
    static let cap: TimeInterval = 300

    private let lock = NSLock()
    private var until: [Suggestion.Tier: Date] = [:]
    private var strikes: [Suggestion.Tier: Int] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    func isCoolingDown(_ tier: Suggestion.Tier) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let end = until[tier] else { return false }
        return now() < end
    }

    func rateLimited(_ tier: Suggestion.Tier) {
        lock.lock(); defer { lock.unlock() }
        let count = (strikes[tier] ?? 0) + 1
        strikes[tier] = count
        let wait = min(Self.base * pow(2, Double(count - 1)), Self.cap)
        until[tier] = now().addingTimeInterval(wait)
    }

    func succeeded(_ tier: Suggestion.Tier) {
        lock.lock(); defer { lock.unlock() }
        strikes[tier] = 0
        until[tier] = nil
    }

    func remaining(_ tier: Suggestion.Tier) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return max(0, (until[tier] ?? now()).timeIntervalSince(now()))
    }
}

/// The last model readings by note (text + the user's properties + spouse tracking), so pausing
/// on the same words, reopening the sheet or Undo-and-retype never calls the model again; and
/// the notes a model refused, which stay rules-only. In memory only, never saved.
final class NoteReadCache: @unchecked Sendable {
    static let shared = NoteReadCache()
    static let capacity = 32

    private let lock = NSLock()
    private var readings: [String: NoteReading] = [:]
    private var order: [String] = []
    private var rulesOnly: Set<String> = []

    static func key(_ request: NoteReadRequest) -> String {
        let props = request.properties.map { "\($0.id.uuidString):\($0.name):\($0.aliases.joined(separator: ","))" }.joined(separator: "|")
        let day = Int(request.calendar.startOfDay(for: request.now).timeIntervalSince1970)
        return "\(request.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())#\(props)#\(request.spouseTracking)#\(day)"
    }

    func reading(for key: String) -> NoteReading? {
        lock.lock(); defer { lock.unlock() }
        return readings[key]
    }

    func store(_ reading: NoteReading, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if readings[key] == nil { order.append(key) }
        readings[key] = reading
        while order.count > Self.capacity { readings[order.removeFirst()] = nil }
    }

    func markRulesOnly(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        rulesOnly.insert(key)
    }

    func isRulesOnly(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return rulesOnly.contains(key)
    }
}

// MARK: - DEBUG: deterministic model tiers for UI tests and captures (compiled out of Release)
//
//   -LHNoteModel fake         a scripted on-device answer after 0.8 s (PCC off)
//   -LHNoteModel thinking     the on-device model never answers (the drafting line stays)
//   -LHNoteModel partial      on-device answers category and description only
//   -LHNoteModel unavailable  no model: rules only (the default under -LHMockScenario)
#if DEBUG
enum NoteReaderDebug {
    /// UI tests and captures (every one launches with -LHMockScenario) are deterministic: no
    /// live model unless they script one.
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHNoteModel"), args.indices.contains(i + 1) { return args[i + 1] }
        return args.contains("-LHMockScenario") ? "unavailable" : nil
    }

    static func chain() -> NoteReaderChain? {
        guard let mode else { return nil }
        let closedPCC = PCCGate(settings: PCCSettings(), isFlagEnabled: { false }, system: ScriptedPCCStatus())
        let off = UnavailableNoteBackend(tier: .pcc, reason: .disabledByFlag)
        switch mode {
        case "unavailable":
            return NoteReaderChain(onDevice: UnavailableNoteBackend(tier: .onDevice, reason: .appleIntelligenceNotEnabled), pcc: off, pccGate: closedPCC)
        case "thinking":
            return NoteReaderChain(onDevice: ScriptedNoteBackend(delay: 3600, partial: false), pcc: off, pccGate: closedPCC, onDeviceTimeout: 3600)
        case "partial":
            return NoteReaderChain(onDevice: ScriptedNoteBackend(delay: 0.8, partial: true), pcc: off, pccGate: closedPCC)
        default:
            return NoteReaderChain(onDevice: ScriptedNoteBackend(delay: 0.8, partial: false), pcc: off, pccGate: closedPCC)
        }
    }

    struct ScriptedPCCStatus: PCCSystemStatusProviding {
        func status() -> ModelAvailability { .unavailable(.disabledByFlag) }
    }

    /// Answers like the on-device model would for the capture notes.
    struct ScriptedNoteBackend: NoteModelBackend {
        var delay: TimeInterval
        var partial: Bool
        var tier: Suggestion.Tier { .onDevice }
        var availability: ModelAvailability { .available }

        func draft(_ prompt: NoteModelPrompt) async throws -> NoteModelDraft {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let rules = NoteRules.read(prompt.request)
            let property = prompt.request.properties.first { $0.id == rules.propertyId }
            let option = property.flatMap { p in prompt.request.properties.firstIndex(of: p).map { prompt.propertyOptions[$0] } }
            let lower = prompt.request.text.lowercased()
            var description: String?
            if lower.contains("sink") {
                description = "Fixed the sink at \(property?.name ?? "the rental") with Mike"
            } else if lower.contains("lender") {
                description = "Met the lender about refinancing"
            } else if let property {
                description = "Worked at \(property.name)"
            }
            if partial {
                return NoteModelDraft(propertyOption: nil, category: rules.category ?? .repairs, hours: nil, datePhrase: nil,
                                      doneBySpouse: false, description: description)
            }
            return NoteModelDraft(propertyOption: option, category: rules.category, hours: rules.hours,
                                  datePhrase: lower.contains("yesterday") ? "yesterday" : nil,
                                  doneBySpouse: false, description: description)
        }
    }
}
#endif
