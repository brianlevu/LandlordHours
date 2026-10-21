import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Model tiers for the Log time note reader
//
// One backend type per Apple model, behind `NoteModelBackend` so tests inject every
// availability state, failure and answer (including adversarial ones) without Apple
// Intelligence. Both real backends use the same prompt and the same guided-generation schema:
// a @Generable struct (`NoteFillDraft`) whose property and category fields are constrained at
// run time to the user's own property names and the 11 categories (DynamicGenerationSchema
// anyOf), so the model cannot produce a property that isn't on the user's list.

protocol NoteModelBackend {
    var tier: Suggestion.Tier { get }
    var availability: ModelAvailability { get }
    func draft(_ prompt: NoteModelPrompt) async throws -> NoteModelDraft
}

enum NoteModelError: Error, Equatable {
    case unavailable(ModelUnavailableReason)
}

/// Below iOS 26/27, or wherever a model can't run.
struct UnavailableNoteBackend: NoteModelBackend {
    var tier: Suggestion.Tier
    var reason: ModelUnavailableReason
    var availability: ModelAvailability { .unavailable(reason) }
    func draft(_ prompt: NoteModelPrompt) async throws -> NoteModelDraft { throw NoteModelError.unavailable(reason) }
}

enum NoteModelBackends {
    /// Apple's on-device model on iOS 26+.
    static func onDevice() -> NoteModelBackend {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemNoteBackend() }
        #endif
        return UnavailableNoteBackend(tier: .onDevice, reason: .osTooOld)
    }

    /// Private Cloud Compute on iOS 27+. Availability here is the system's only; the user
    /// setting and the remote flag are checked by `PCCGate` in the chain.
    static func privateCloudCompute() -> NoteModelBackend {
        // Without the entitlement a PCC call traps the app: never build the real backend.
        guard PCCEntitlement.isConfigured else { return UnavailableNoteBackend(tier: .pcc, reason: .notEntitled) }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) { return PCCNoteBackend() }
        #endif
        return UnavailableNoteBackend(tier: .pcc, reason: .osTooOld)
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@Generable(description: "Fields for one time-log entry, read from a landlord's note")
struct NoteFillDraft {
    @Guide(description: "One of the user's property names from the list, or none")
    var property: String
    @Guide(description: "The kind of work, or unclear")
    var category: String
    @Guide(description: "True only when the note says how long the work took")
    var hoursStated: Bool
    @Guide(description: "How long, in hours, only when stated; otherwise 0", .range(0.0...24.0))
    var hours: Double
    @Guide(description: "The exact words from the note that say which day, or empty")
    var datePhrase: String
    @Guide(description: "self, spouse or unclear")
    var doneBy: String
    @Guide(description: "One short past-tense sentence for a tax record using only facts in the note")
    var recordDescription: String
}

@available(iOS 26.0, *)
enum NoteFillSchema {
    /// The @Generable shape with the property and category constrained to this user's options.
    static func make(for prompt: NoteModelPrompt) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(
            name: "NoteFillDraft",
            description: "Fields for one time-log entry, read from a landlord's note",
            properties: [
                .init(name: "property", description: "One of the user's property names from the list, or none",
                      schema: DynamicGenerationSchema(name: "PropertyChoice", anyOf: prompt.propertyOptions + [NoteModelPrompt.noProperty])),
                .init(name: "category", description: "The kind of work, or unclear",
                      schema: DynamicGenerationSchema(name: "CategoryChoice", anyOf: NoteModelPrompt.categoryKeys.map(\.0) + [NoteModelPrompt.unclearCategory])),
                .init(name: "hoursStated", description: "True only when the note says how long the work took",
                      schema: DynamicGenerationSchema(type: Bool.self)),
                .init(name: "hours", description: "How long, in hours, only when stated; otherwise 0",
                      schema: DynamicGenerationSchema(type: Double.self, guides: [.range(0.0...24.0)])),
                .init(name: "datePhrase", description: "The exact words from the note that say which day, or empty",
                      schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "doneBy", description: "Who did the work",
                      schema: DynamicGenerationSchema(name: "DoneByChoice", anyOf: ["self", "spouse", "unclear"])),
                .init(name: "recordDescription", description: "One short past-tense sentence for a tax record using only facts in the note",
                      schema: DynamicGenerationSchema(type: String.self)),
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    static func map(_ content: GeneratedContent) throws -> NoteModelDraft {
        let fill = try NoteFillDraft(content)
        return map(fill)
    }

    static func map(_ fill: NoteFillDraft) -> NoteModelDraft {
        let property = fill.property.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = fill.datePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = fill.recordDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteModelDraft(
            propertyOption: property.isEmpty || property.lowercased() == NoteModelPrompt.noProperty ? nil : property,
            category: NoteModelPrompt.category(forKey: fill.category),
            hours: fill.hoursStated && fill.hours > 0 ? fill.hours : nil,
            datePhrase: date.isEmpty ? nil : date,
            doneBySpouse: fill.doneBy.lowercased() == "spouse",
            description: description.isEmpty ? nil : description
        )
    }

    static let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 220)
}

@available(iOS 26.0, *)
struct SystemNoteBackend: NoteModelBackend {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) { self.model = model }

    var tier: Suggestion.Tier { .onDevice }
    var availability: ModelAvailability { SystemModelBackend.map(model.availability) }

    func draft(_ prompt: NoteModelPrompt) async throws -> NoteModelDraft {
        // A fresh session per note: nothing from one note carries into the next.
        let session = LanguageModelSession(model: model, instructions: NoteModelPrompt.instructions)
        let response = try await session.respond(to: prompt.prompt, schema: try NoteFillSchema.make(for: prompt),
                                                  options: NoteFillSchema.options)
        return try NoteFillSchema.map(response.content)
    }
}

@available(iOS 27.0, *)
struct PCCNoteBackend: NoteModelBackend {
    var tier: Suggestion.Tier { .pcc }
    var availability: ModelAvailability { SystemPCCStatus().status() }

    func draft(_ prompt: NoteModelPrompt) async throws -> NoteModelDraft {
        guard PCCEntitlement.isConfigured else { throw NoteModelError.unavailable(.notEntitled) }
        let model = PrivateCloudComputeLanguageModel()
        let session = LanguageModelSession(model: model, dynamicInstructions: Instructions(NoteModelPrompt.instructions))
        let response = try await session.respond(to: prompt.prompt, schema: try NoteFillSchema.make(for: prompt),
                                                  options: NoteFillSchema.options)
        return try NoteFillSchema.map(response.content)
    }
}
#endif
