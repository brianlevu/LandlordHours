import XCTest
@testable import LandlordHours

/// Field accuracy per tier over Tests/Fixtures/note-eval.json, and the hard rules on every
/// tier's answers. Prints "NOTE-EVAL" lines; writes JSON to $NOTE_EVAL_OUT when set
/// (TEST_RUNNER_NOTE_EVAL_OUT=<dir>).
final class NoteReaderEvalTests: XCTestCase {
    /// "note-eval" (66, dev set) and "note-eval-holdout" (45, written blind to the rules).
    static let sets = ["note-eval", "note-eval-holdout"]

    private func loadSet(_ name: String = "note-eval") throws -> NoteEvalSet {
        let bundle = Bundle(for: NoteReaderEvalTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "\(name).json missing from the test bundle")
        return try NoteEvalSet(data: Data(contentsOf: url))
    }

    func testFixtureHasAtLeastSixtyRealisticNotes() throws {
        let set = try loadSet()
        XCTAssertGreaterThanOrEqual(set.fixture.cases.count, 60)
        XCTAssertGreaterThanOrEqual(set.fixture.cases.filter(\.nonCountable).count, 6, "non-countable notes")
        XCTAssertGreaterThanOrEqual(set.fixture.cases.filter(\.spouseTracking).count, 4, "spouse notes")
        XCTAssertGreaterThanOrEqual(set.fixture.cases.filter { $0.hours == nil }.count, 15, "notes without hours")
        XCTAssertEqual(Set(set.fixture.cases.map(\.id)).count, set.fixture.cases.count)
    }

    /// Rules: always available, must never break a hard rule.
    func testRulesTierAccuracyAndHardRules() throws {
        for name in Self.sets {
            var set = try loadSet(name)
            var report = NoteEvalSet.TierReport(name: "rules@\(name)")
            for c in set.fixture.cases {
                set.record(&report, c, NoteRules.read(set.request(c)))
            }
            print(report.line)
            print("NOTE-EVAL rules@\(name) misses: \(report.misses.joined(separator: " "))")
            XCTAssertEqual(report.violations, [], "rules broke a hard rule on \(name)")
            write(report)
        }
    }

    /// The 1.x keyword parser the sheet used before, for comparison (not a gate).
    func testLegacyParserBaseline() async throws {
        for name in Self.sets {
            var set = try loadSet(name)
            var report = NoteEvalSet.TierReport(name: "legacy-1x@\(name)")
            for c in set.fixture.cases {
                let parsed = await AITimeEntryService.shared.parseTimeEntry(from: c.note, properties: set.properties)
                set.record(&report, c, NoteEvalSet.legacyReading(parsed))
            }
            print(report.line)
            print("NOTE-EVAL legacy-1x@\(name) hard-rule violations: \(report.violations.joined(separator: "; "))")
            write(report)
        }
    }

    /// PCC through a fake that injects an error into every third answer: the merge and the
    /// guards must catch every one.
    func testPCCFakeThroughTheGuards() throws {
        for name in Self.sets {
            var set = try loadSet(name)
            var report = NoteEvalSet.TierReport(name: "pcc-fake@\(name)")
            for (index, c) in set.fixture.cases.enumerated() {
                let request = set.request(c)
                let prompt = NoteModelPrompt(request)
                let draft = set.pccFakeDraft(c, index: index, prompt: prompt)
                let reading = NoteReadMerge.merge(rules: NoteRules.read(request), draft: draft, prompt: prompt, tier: .pcc)
                set.record(&report, c, reading, offeredDescription: draft.description != nil)
            }
            print(report.line)
            XCTAssertEqual(report.violations, [], "a guard let an injected error through on \(name)")
            write(report)
        }
    }

    /// Apple's on-device model, when this simulator can reach it (it uses the host Mac's model).
    func testOnDeviceModelTier() async throws {
        let backend = NoteModelBackends.onDevice()
        guard backend.availability.isAvailable else {
            let report = NoteEvalSet.TierReport(name: "on-device", unavailable: "\(backend.availability)")
            print(report.line)
            write(report)
            throw XCTSkip("On-device model unavailable here: \(backend.availability)")
        }
        for name in Self.sets {
            var set = try loadSet(name)
            try await runModel(backend, name: "on-device@\(name)", set: &set)
        }
    }

    /// Real PCC when available here (rare in the simulator); the host-Mac harness covers it.
    func testPrivateCloudComputeTierWhenAvailable() async throws {
        var set = try loadSet()
        let backend = NoteModelBackends.privateCloudCompute()
        guard backend.availability.isAvailable, ProcessInfo.processInfo.environment["NOTE_EVAL_PCC"] == "1" else {
            throw XCTSkip("PCC not used in this run (\(backend.availability)); set NOTE_EVAL_PCC=1 to spend quota on it")
        }
        try await runModel(backend, name: "pcc", set: &set)
    }

    private func runModel(_ backend: NoteModelBackend, name: String, set: inout NoteEvalSet) async throws {
        var report = NoteEvalSet.TierReport(name: name)
        var rawViolations: [String] = []
        var failures = 0
        var latencies: [Double] = []
        // NOTE_EVAL_LIMIT=<n> runs the first n notes (short real-device runs); calls are paced
        // and a rate limit backs off (15 s, doubling) instead of hammering the model.
        let limit = Int(ProcessInfo.processInfo.environment["NOTE_EVAL_LIMIT"] ?? "") ?? Int.max
        var backoff: UInt64 = 15
        for c in set.fixture.cases.prefix(limit) {
            let request = set.request(c)
            let prompt = NoteModelPrompt(request)
            let rules = NoteRules.read(request)
            var started = Date()
            do {
                var draft: NoteModelDraft?
                for attempt in 0..<3 {
                    do {
                        started = Date()
                        draft = try await backend.draft(prompt)
                        backoff = 15
                        break
                    } catch where NoteReaderChain.generationFailure(error) == .rateLimited && attempt < 2 {
                        rawViolations.append("\(c.id): rate limited, waiting \(backoff)s")
                        try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                        backoff = min(backoff * 2, 120)
                    }
                }
                guard let draft else { throw NoteModelScriptedError.rateLimited }
                latencies.append(Date().timeIntervalSince(started))
                // What the model said before the guards (for the report).
                if draft.hours != nil && c.hours == nil { rawViolations.append("\(c.id): model hours \(draft.hours!)") }
                if let option = draft.propertyOption, prompt.property(for: option) == nil { rawViolations.append("\(c.id): model property \(option)") }
                let reading = NoteReadMerge.merge(rules: rules, draft: draft, prompt: prompt, tier: backend.tier)
                if draft.description != nil, reading.description == nil {
                    rawViolations.append("\(c.id): description rejected: \(draft.description!) [\(NoteFactGuard.untraceable(draft.description!, request: request, propertyId: reading.propertyId, category: reading.category).joined(separator: ","))]")
                }
                set.record(&report, c, reading, offeredDescription: draft.description != nil)
            } catch {
                failures += 1
                set.record(&report, c, rules)
                rawViolations.append("\(c.id): call failed \(error)")
            }
        }
        if failures == min(limit, set.fixture.cases.count) {
            // The model says it's available but every call failed (a slimmed simulator answers
            // ModelManagerError 1008): that's "unavailable here", not a score.
            print("NOTE-EVAL \(name): every call failed (\(rawViolations.first ?? "")); the chain fell back to rules on each")
            throw XCTSkip("\(name): the model failed on every call here")
        }
        latencies.sort()
        let median = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
        let p90 = latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.9))]
        print(report.line)
        print(String(format: "NOTE-EVAL %@ latency n=%d median %.2fs p90 %.2fs max %.2fs · failures %d", name, latencies.count, median, p90, latencies.last ?? 0, failures))
        print("NOTE-EVAL \(name) misses: \(report.misses.joined(separator: " "))")
        for line in rawViolations { print("NOTE-EVAL \(name) raw: \(line)") }
        for line in report.samples { print("NOTE-EVAL \(name) description: \(line)") }
        XCTAssertEqual(report.violations, [], "\(name) broke a hard rule after the guards")
        write(report, extra: ["medianLatency": median, "failures": failures, "raw": rawViolations])
    }

    private func write(_ report: NoteEvalSet.TierReport, extra: [String: Any] = [:]) {
        guard let dir = ProcessInfo.processInfo.environment["NOTE_EVAL_OUT"], !dir.isEmpty else { return }
        var json: [String: Any] = ["tier": report.name, "n": report.total, "violations": report.violations,
                                   "descriptionsOffered": report.descriptionsOffered, "descriptionsKept": report.descriptionsKept,
                                   "misses": report.misses, "descriptions": report.samples]
        if let unavailable = report.unavailable { json["unavailable"] = unavailable }
        for field in NoteEvalSet.fields { json["accuracy.\(field)"] = report.percent(field) }
        for (k, v) in extra { json[k] = v }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("note-eval-\(report.name).json"))
        }
    }
}
