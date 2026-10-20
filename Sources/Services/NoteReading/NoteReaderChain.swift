import Foundation
import os.log
#if canImport(FoundationModels)
import FoundationModels
#endif

private let noteLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "NoteReader")

// MARK: - Tier order for the Log time note
//
//   rules (instant, always) → on-device model (≤ 3.5 s) → PCC (≤ 6 s), PCC only when:
//     - the on-device model is unavailable, failed or timed out, OR
//     - its answer is incomplete: no category, no usable description, or no property while the
//       user has more than one (PCC is the stronger model for exactly these notes), AND
//     - PCCGate is open: the user's PCC setting (default on), the remote flag, iOS 27,
//       eligibility, readiness and quota. A quota hit mid-call closes PCC for that note.
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
    }

    struct Outcome: Equatable {
        var reading: NoteReading
        var onDevice: Attempt
        var pcc: Attempt
    }

    let onDevice: NoteModelBackend
    let pcc: NoteModelBackend
    let pccGate: PCCGate
    var onDeviceTimeout: TimeInterval = 3.5
    var pccTimeout: TimeInterval = 6

    init(onDevice: NoteModelBackend, pcc: NoteModelBackend, pccGate: PCCGate = PCCGate(),
         onDeviceTimeout: TimeInterval = 3.5, pccTimeout: TimeInterval = 6) {
        self.onDevice = onDevice
        self.pcc = pcc
        self.pccGate = pccGate
        self.onDeviceTimeout = onDeviceTimeout
        self.pccTimeout = pccTimeout
    }

    /// Apple's models on this device, behind the user's PCC setting and the remote flag.
    static func live() -> NoteReaderChain {
        #if DEBUG
        if let debug = NoteReaderDebug.chain() { return debug }
        #endif
        return NoteReaderChain(onDevice: NoteModelBackends.onDevice(), pcc: NoteModelBackends.privateCloudCompute())
    }

    func rules(_ request: NoteReadRequest) -> NoteReading { NoteRules.read(request) }

    /// Whether any model tier could run now (the sheet shows the drafting line only then).
    var hasModel: Bool { onDevice.availability.isAvailable || pccAvailability().isAvailable }

    func pccAvailability() -> ModelAvailability {
        let gate = pccGate.availability()
        guard gate.isAvailable else { return gate }
        return pcc.availability
    }

    /// The model tiers over the rules result. `onRefine` gets the on-device reading when PCC is
    /// about to be asked too, so the sheet fills fields as they come.
    func read(_ request: NoteReadRequest, rules base: NoteReading? = nil,
              onRefine: @escaping @MainActor (NoteReading) -> Void = { _ in }) async -> Outcome {
        let rules = base ?? self.rules(request)
        let prompt = NoteModelPrompt(request)
        var result = Outcome(reading: rules, onDevice: .notNeeded, pcc: .notNeeded)

        var onDeviceReading: NoteReading?
        if onDevice.availability.isAvailable {
            switch await ask(onDevice, prompt: prompt, timeout: onDeviceTimeout) {
            case .success(let draft):
                result.onDevice = .answered
                onDeviceReading = NoteReadMerge.merge(rules: rules, draft: draft, prompt: prompt, tier: .onDevice)
            case .failure(let attempt):
                result.onDevice = attempt
            }
        } else if case .unavailable(let reason) = onDevice.availability {
            result.onDevice = .unavailable(reason)
        }
        if Task.isCancelled { return result }

        if let onDeviceReading {
            result.reading = onDeviceReading
            guard Self.needsEscalation(onDeviceReading, request: request) else { return result }
        }

        let gate = pccAvailability()
        guard gate.isAvailable else {
            if case .unavailable(let reason) = gate { result.pcc = .unavailable(reason) }
            return result
        }
        if let onDeviceReading { await onRefine(onDeviceReading) }
        switch await ask(pcc, prompt: prompt, timeout: pccTimeout) {
        case .success(let draft):
            result.pcc = .answered
            let pccReading = NoteReadMerge.merge(rules: rules, draft: draft, prompt: prompt, tier: .pcc)
            result.reading = NoteReadMerge.combine(primary: pccReading, secondary: onDeviceReading)
        case .failure(let attempt):
            result.pcc = attempt
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
            noteLogger.error("Note reader \(backend.tier.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if let reason = Self.unavailableReason(for: error) { return .failure(.unavailable(reason)) }
            return .failure(.failed)
        }
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
