import Foundation
// Host-Mac classifier eval: rules vs Apple's on-device model vs the chain on
// Tests/Fixtures/calibration.json. Uses the app's own classifier sources (same prompt, schema
// and merge). Usage: run.sh [split ...]   (default: holdout all)

struct Fixture: Decodable {
    struct Property: Decodable { let key, name, address: String; var type: String?; var ownerOccupied: Bool?; var aliases: [String]? }
    struct Item: Decodable { let title: String; let landlord: Bool; let category: String?; let property: String?; let split: String; var kind: String?; var location: String? }
    let properties: [Property]; let items: [Item]
}

let categoryMap: [String: ActivityCategory] = [
    "repairs": .repairs, "management": .management, "leasing": .leasing, "bookkeeping": .bookkeeping,
    "legal": .legal, "insurance": .insurance, "travel": .travel, "renovations": .renovations,
    "investing": .investing, "financing": .financing, "contractNegotiation": .contractNegotiation,
]

struct Score {
    var n = 0, tp = 0, fp = 0, fn = 0, tn = 0, landlord = 0, visible = 0, cat = 0, prop = 0
    var precision: Double { Double(tp) / Double(max(tp + fp, 1)) }
    var recall: Double { Double(tp) / Double(max(landlord, 1)) }
    var f1: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }
    var acc: Double { Double(tp + tn) / Double(max(n, 1)) }
    func line(_ name: String) -> String {
        String(format: "%-34@ n=%3d acc=%.3f P=%.3f R=%.3f F1=%.3f visible=%.3f category=%.3f (%d/%d) property=%.3f",
               name as NSString, n, acc, precision, recall, f1, Double(visible) / Double(max(landlord, 1)),
               Double(cat) / Double(max(landlord, 1)), cat, landlord, Double(prop) / Double(max(landlord, 1)))
    }
}

@main struct Main {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()
        let fixturePath = ProcessInfo.processInfo.environment["FIXTURE"] ?? "Tests/Fixtures/calibration.json"
        let splits = args.isEmpty ? ["holdout", "all"] : Array(args)
        let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        let byKey = Dictionary(uniqueKeysWithValues: fx.properties.map {
            ($0.key, RentalProperty(name: $0.name, address: $0.address, propertyType: $0.type == "str" ? .str : .ltr,
                                    aliases: $0.aliases ?? [], isOwnerOccupied: $0.ownerOccupied ?? false))
        })
        let props = fx.properties.compactMap { byKey[$0.key] }
        let onDevice = OnDeviceClassifier.makeDefault()
        print("model availability: \(onDevice.availability)")
        let chain = ClassifierChain(onDevice: onDevice)
        let rules = RulesClassifier()
        let likely = ClassifierThresholds.likely

        func cand(_ item: Fixture.Item, _ kind: Suggestion.Kind) -> CaptureCandidate {
            let start = Date(timeIntervalSince1970: 1_790_000_000)
            return CaptureCandidate(sourceKey: "k:\(item.title)", kind: kind, start: start, end: start.addingTimeInterval(3600),
                                    title: item.title, location: item.location, detectedAt: start)
        }
        func add(_ s: inout Score, _ item: Fixture.Item, yes: Bool, visible: Bool, category: ActivityCategory?, property: UUID?) {
            s.n += 1
            if yes && item.landlord { s.tp += 1 } else if yes { s.fp += 1 } else if item.landlord { s.fn += 1 } else { s.tn += 1 }
            guard item.landlord else { return }
            s.landlord += 1
            if visible { s.visible += 1 }
            if category == categoryMap[item.category ?? ""] { s.cat += 1 }
            if property == item.property.flatMap({ byKey[$0]?.id }) { s.prop += 1 }
        }

        // One model call per item (4 in flight), cached by prompt+instructions so reruns are cheap.
        let cacheURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CACHE"] ?? "\(NSTemporaryDirectory())clf-eval-cache.json")
        var cache = (try? JSONDecoder().decode([String: CachedAnswer].self, from: Data(contentsOf: cacheURL))) ?? [:]
        var modelRows = [(Fixture.Item, OnDeviceClassifier.OnDeviceResult?)](repeating: (fx.items[0], nil), count: fx.items.count)
        var failed = 0
        let backend = onDevice.backend
        let keyed: [(String, OnDeviceRequest)] = fx.items.map { item in
            let kind: Suggestion.Kind = item.kind == "email" ? .gmail : .calendar
            let req = OnDeviceClassifier.request(for: cand(item, kind), properties: props)
            return (OnDeviceClassifier.instructions + "\n#\n" + OnDeviceClassifier.prompt(for: req), req)
        }
        try await withThrowingTaskGroup(of: (Int, String, OnDeviceAnswer?).self) { group in
            var next = 0
            func addNext() {
                while next < fx.items.count {
                    let i = next; next += 1
                    let (k, req) = keyed[i]
                    if let hit = cache[k] { modelRows[i] = (fx.items[i], hit.answer.map { OnDeviceClassifier.map($0, request: req, properties: props) }); continue }
                    group.addTask { (i, k, try? await backend.answer(req)) }
                    return
                }
            }
            for _ in 0..<4 { addNext() }
            while let (i, k, ans) = try await group.next() {
                cache[k] = CachedAnswer(answer: ans)
                let req = keyed[i].1
                modelRows[i] = (fx.items[i], ans.map { OnDeviceClassifier.map($0, request: req, properties: props) })
                addNext()
            }
        }
        try? JSONEncoder().encode(cache).write(to: cacheURL)
        failed = modelRows.filter { $0.1 == nil }.count
        print("model calls failed: \(failed)/\(fx.items.count)")
        let verbose = ProcessInfo.processInfo.environment["VERBOSE"] != nil

        for split in splits {
            var sRulesCal = Score(), sRulesMail = Score(), sModel = Score(), sChainCal = Score(), sChainLoc = Score(), sForced = Score()
            for (item, m) in modelRows where split == "all" || item.split == split {
                let kind: Suggestion.Kind = item.kind == "email" ? .gmail : .calendar
                let rc = rules.classifySync(cand(item, kind), properties: props)
                add(&sRulesCal, item, yes: rc.confidence >= likely, visible: rc.band != .unlikely, category: rc.category, property: rc.propertyId)
                // Rules with the rich table category (what the test calls "rules": kind .gmail).
                let rm = rules.classifySync(cand(item, .gmail), properties: props)
                add(&sRulesMail, item, yes: rm.confidence >= likely, visible: rm.band != .unlikely, category: rm.category, property: rm.propertyId)
                if let m {
                    add(&sModel, item, yes: m.isRentalWork && m.confidence >= likely, visible: m.isRentalWork, category: m.category, property: m.propertyId)
                } else { add(&sModel, item, yes: false, visible: false, category: nil, property: nil) }
                // Production chain for this item's kind (gmail = rules only; calendar = model votes, 1.x category).
                var cc = rc
                if let m, chain.shouldAskModel(cand(item, kind), rulesResult: rc) { cc = chain.merge(rules: rc, model: m, candidate: cand(item, kind), properties: props) }
                add(&sChainCal, item, yes: cc.confidence >= likely, visible: cc.band != .unlikely, category: cc.category, property: cc.propertyId)
                // Chain where the model's category is used (non-calendar source the model sees: .location).
                let rl = rules.classifySync(cand(item, .location), properties: props)
                var cl = rl
                if let m, chain.shouldAskModel(cand(item, .location), rulesResult: rl) { cl = chain.merge(rules: rl, model: m, candidate: cand(item, .location), properties: props) }
                add(&sChainLoc, item, yes: cl.confidence >= likely, visible: cl.band != .unlikely, category: cl.category, property: cl.propertyId)
                // Model forced on every item (no skip thresholds), merged with rich rules category: upper bound of "trust FM category".
                if let m {
                    let f = chain.merge(rules: rm, model: m, candidate: cand(item, .location), properties: props)
                    add(&sForced, item, yes: f.confidence >= likely, visible: f.band != .unlikely, category: f.category, property: f.propertyId)
                } else { add(&sForced, item, yes: rm.confidence >= likely, visible: rm.band != .unlikely, category: rm.category, property: rm.propertyId) }
                if verbose && item.landlord && cc.propertyId != rc.propertyId {
                    let name: (UUID?) -> String = { id in props.first { $0.id == id }?.name ?? "none" }
                    print("  [\(item.split)] PROP want=\(item.property ?? "none") rules=\(name(rc.propertyId)) chain=\(name(cc.propertyId)) ev=\(rc.evidence.filter { $0.hasPrefix("prop") }) | \(item.title)")
                }
                if verbose && item.landlord {
                    print("  [\(item.split)] want=\(item.category ?? "-") rules=\(rm.category.map { "\($0)" } ?? "-") model=\(m?.category.map { "\($0)" } ?? "-") yes=\(m?.isRentalWork ?? false) c=\(String(format: "%.2f", m?.confidence ?? -1)) | \(item.title)")
                }
                if verbose && !item.landlord, let m, m.isRentalWork {
                    print("  [\(item.split)] FP model c=\(String(format: "%.2f", m.confidence)) | \(item.title)")
                }
            }
            print("== split=\(split)")
            print(sRulesCal.line("rules (production kind)"))
            print(sRulesMail.line("rules (table category)"))
            print(sModel.line("model alone"))
            print(sChainCal.line("chain (production kind)"))
            print(sChainLoc.line("chain as .location (model cat)"))
            print(sForced.line("chain forced, model cat wins"))
        }
    }
}

struct CachedAnswer: Codable { var answer: OnDeviceAnswer? }
extension OnDeviceAnswer: Codable {
    enum K: String, CodingKey { case isRentalWork, category, propertyRef, confidence, reason }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        self.init(isRentalWork: try c.decode(Bool.self, forKey: .isRentalWork),
                  category: try c.decodeIfPresent(String.self, forKey: .category).flatMap { ActivityCategory(rawValue: $0) },
                  propertyRef: try c.decodeIfPresent(String.self, forKey: .propertyRef),
                  confidence: try c.decode(Double.self, forKey: .confidence), reason: try c.decode(String.self, forKey: .reason))
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(isRentalWork, forKey: .isRentalWork); try c.encodeIfPresent(category?.rawValue, forKey: .category)
        try c.encodeIfPresent(propertyRef, forKey: .propertyRef); try c.encode(confidence, forKey: .confidence); try c.encode(reason, forKey: .reason)
    }
}
