import Foundation

// Host-Mac note-reader eval: runs the app's NoteReading code against Apple's on-device model
// and (with --pcc) Private Cloud Compute on this Mac (macOS 27, Apple Intelligence on).
// Build + run: scripts/note-eval-host/run.sh [--pcc]

@main
struct NoteEvalHost {
    static func main() async throws {
        let args = CommandLine.arguments
        let fixture = URL(fileURLWithPath: args.first(where: { $0.hasSuffix(".json") }) ?? "Tests/Fixtures/note-eval.json")
        var set = try NoteEvalSet(data: Data(contentsOf: fixture))
        var tiers: [(String, NoteModelBackend)] = [("on-device", NoteModelBackends.onDevice())]
        if args.contains("--pcc") { tiers.append(("pcc", NoteModelBackends.privateCloudCompute())) }

        var rules = NoteEvalSet.TierReport(name: "rules")
        for c in set.fixture.cases { set.record(&rules, c, NoteRules.read(set.request(c))) }
        print(rules.line)
        print("NOTE-EVAL rules misses: \(rules.misses.joined(separator: " "))")
        if args.contains("--rules-only") { return }

        var chainReport = NoteEvalSet.TierReport(name: "chain")
        for (name, backend) in tiers {
            guard backend.availability.isAvailable else { print("NOTE-EVAL \(name): unavailable \(backend.availability)"); continue }
            var report = NoteEvalSet.TierReport(name: name)
            var latencies: [Double] = []
            for c in set.fixture.cases {
                let request = set.request(c)
                let prompt = NoteModelPrompt(request)
                let base = NoteRules.read(request)
                let t0 = Date()
                do {
                    let draft = try await backend.draft(prompt)
                    latencies.append(Date().timeIntervalSince(t0))
                    let reading = NoteReadMerge.merge(rules: base, draft: draft, prompt: prompt, tier: backend.tier)
                    if let d = draft.description, reading.description == nil {
                        print("NOTE-EVAL \(name) rejected \(c.id): \(d) [\(NoteFactGuard.untraceable(d, request: request, propertyId: reading.propertyId, category: reading.category).joined(separator: ","))]")
                    }
                    if draft.hours != nil, c.hours == nil { print("NOTE-EVAL \(name) raw-hours \(c.id): \(draft.hours!)") }
                    set.record(&report, c, reading, offeredDescription: draft.description != nil)
                } catch {
                    print("NOTE-EVAL \(name) failed \(c.id): \(error)")
                    set.record(&report, c, base)
                }
            }
            latencies.sort()
            print(report.line)
            print(String(format: "NOTE-EVAL %@ median %.2fs p90 %.2fs", name, latencies.isEmpty ? 0 : latencies[latencies.count / 2], latencies.isEmpty ? 0 : latencies[Int(Double(latencies.count) * 0.9)]))
            print("NOTE-EVAL \(name) misses: \(report.misses.joined(separator: " "))")
            for v in report.violations { print("NOTE-EVAL \(name) VIOLATION \(v)") }
            for s in report.samples { print("NOTE-EVAL \(name) desc \(s)") }
        }

        if args.contains("--chain") {
            let chain = NoteReaderChain(onDevice: NoteModelBackends.onDevice(), pcc: NoteModelBackends.privateCloudCompute(),
                                        pccGate: PCCGate(settings: PCCSettings(defaults: UserDefaults(suiteName: "note-eval-host")!), isFlagEnabled: { args.contains("--pcc") }),
                                        onDeviceTimeout: 3.5, pccTimeout: 6)
            var escalated = 0
            for c in set.fixture.cases {
                let outcome = await chain.read(set.request(c))
                if outcome.pcc == .answered { escalated += 1 }
                set.record(&chainReport, c, outcome.reading, offeredDescription: true)
            }
            print(chainReport.line)
            print("NOTE-EVAL chain escalated to PCC: \(escalated)/\(set.fixture.cases.count)")
            for v in chainReport.violations { print("NOTE-EVAL chain VIOLATION \(v)") }
        }
    }
}
