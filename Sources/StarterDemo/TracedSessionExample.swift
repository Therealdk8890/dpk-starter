// The real-app version of step 1: instead of hand-recording events, let the
// Foundation Models adapter capture the session for you. Compiles everywhere;
// runs on OS 26+ with Apple Intelligence hardware.
//
// The one rule: capture only happens inside an ambient run. Every FM capture
// path is a silent no-op outside `FMTrace.run { }` — the adapter will not
// invent a run for you.
#if canImport(FoundationModels)
import FoundationModels
import DProvenanceKit
import DProvenanceFoundationModels

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum TracedSessionExample {
    /// Greenfield: one line makes the session traced — every prompt, response,
    /// and tool call lands in the ambient run as fm_* events.
    static func summarize(
        _ ticket: String,
        store: InMemoryTraceStore<FoundationModelTraceEvent>
    ) async throws -> String {
        try await FMTrace.run(contextID: "ticket-summary", store: store) {
            let session = LanguageModelSession.traced(
                instructions: "Summarize support tickets in two sentences."
            )
            let response = try await session.respond(to: ticket)
            return response.content
        }
    }

    /// Zero-refactor: keep your existing session untouched and ingest its
    /// transcript after the fact — again, from inside `FMTrace.run { }`.
    static func recordExisting(
        _ session: LanguageModelSession,
        store: InMemoryTraceStore<FoundationModelTraceEvent>
    ) async throws {
        _ = try await FMTrace.run(contextID: "ticket-summary", store: store) {
            session.recordProvenance()
        }
    }
}
#endif
