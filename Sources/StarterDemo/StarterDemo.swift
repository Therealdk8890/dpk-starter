import CryptoKit
import DProvenanceKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DProvenanceKit starter: the whole loop in one `swift run`.
//
// The story: a support-ticket summarizer. Yesterday it worked — the model
// generated the summary. Today, after an OS update, the model declines and the
// app silently falls back to a template. The user-facing output still looks
// fine, every output check passes — but the reasoning path changed, and that is
// exactly what DProvenanceKit records, diffs, gates, and signs.
// ─────────────────────────────────────────────────────────────────────────────

/// Step 0 — your reasoning vocabulary. `typeIdentifier` is the stable key that
/// diffing and querying are defined over; payloads can evolve, identifiers cannot.
enum SummarizerEvent: TraceableEvent {
    case inputReceived(chars: Int)
    case aiSummaryGenerated(model: String)
    case templateFallbackUsed(reason: String)
    case summaryReturned(chars: Int)
    /// Binds an output artifact's SHA-256 into the signed trace (step 4).
    case artifactBound(role: String, sha256: String)

    var typeIdentifier: String {
        switch self {
        case .inputReceived: return "inputReceived"
        case .aiSummaryGenerated: return "aiSummaryGenerated"
        case .templateFallbackUsed: return "templateFallbackUsed"
        case .summaryReturned: return "summaryReturned"
        case .artifactBound: return "artifactBound"
        }
    }

    var priority: TracePriority {
        switch self {
        case .aiSummaryGenerated, .templateFallbackUsed, .artifactBound: return .critical
        case .inputReceived, .summaryReturned: return .structural
        }
    }
}

@main
struct StarterDemo {
    static func main() async throws {
        try await demo()
    }

    nonisolated static func demo() async throws {
        let ticket = "My export has been spinning for an hour and support chat is a robot loop."
        let summary = "Customer's export is stuck; escalate past the chat bot to a human."
        let summaryHash = sha256Hex(summary)

        // A durable, app-owned store — a plain SQLite file you can inspect and archive.
        // (Fresh per demo run so re-running prints the same story; a real app keeps it.)
        let storeURL = URL(fileURLWithPath: "starter-traces.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
        let store = try SQLiteTraceStore<SummarizerEvent>(fileURL: storeURL)

        print("DProvenanceKit starter")
        print("======================\n")

        // ── 1. Record what the feature actually did ─────────────────────────
        // Yesterday: the model was available and generated the summary.
        let (_, runBefore) = await DProvenanceKit<SummarizerEvent>.runReturningID(
            contextID: "ticket-4821", store: store
        ) { _ in
            DProvenanceKit<SummarizerEvent>.record(.inputReceived(chars: ticket.count))
            DProvenanceKit<SummarizerEvent>.record(.aiSummaryGenerated(model: "on-device"))
            DProvenanceKit<SummarizerEvent>.record(.summaryReturned(chars: summary.count))
        }

        // Today, after the OS update: the model declines, the app silently falls
        // back to a template — and the output still looks fine.
        let (_, runAfter) = await DProvenanceKit<SummarizerEvent>.runReturningID(
            contextID: "ticket-4821", store: store
        ) { _ in
            DProvenanceKit<SummarizerEvent>.record(.inputReceived(chars: ticket.count))
            DProvenanceKit<SummarizerEvent>.record(.templateFallbackUsed(reason: "model_unavailable"))
            DProvenanceKit<SummarizerEvent>.record(.summaryReturned(chars: summary.count))
            // The output artifact's hash goes INTO the trace before signing —
            // that's what lets a proof pack bind bytes to this exact run.
            DProvenanceKit<SummarizerEvent>.record(
                .artifactBound(role: "ticket-summary", sha256: summaryHash)
            )
        }
        try await store.flush()

        guard let before = try await store.getRun(id: runBefore),
              let after = try await store.getRun(id: runAfter)
        else { fatalError("recorded runs should be fetchable by id") }

        print("Before: \(before.events.map(\.payload.typeIdentifier).joined(separator: " → "))")
        print("After:  \(after.events.map(\.payload.typeIdentifier).joined(separator: " → "))\n")

        // ── 2. Diff the two reasoning paths ─────────────────────────────────
        let diff = TraceDiffEngine<SummarizerEvent>().diff(
            base: before, comparison: after, minimumPriority: .structural
        )
        print("Structural diff (before → after):")
        for change in diff.changes {
            print("  \(change.kind): \(change.typeIdentifier)")
        }
        print("")

        // ── 3. Gate it — the same rule works in CI ──────────────────────────
        let detector = AnomalyDetector(store: store)
        let rule = MissingSupportRule<SummarizerEvent>(
            name: "SilentFallback",
            whenPresent: "summaryReturned",
            isMissing: "aiSummaryGenerated"
        )
        let anomalies = try await detector.detectAnomalies(rules: [rule])
        print("Anomalies (\(rule.name)):")
        for anomaly in anomalies {
            print("  🚨 \(anomaly.description)")
        }
        print("")

        // ── 4. Sign it and bind the output bytes: a proof pack ──────────────
        let key = SoftwareTraceAttestationKey()
        let attestation = try TraceAttestationDocument.signed(run: after, using: key)
        let pack = ProofPackDocument(
            attestation: attestation,
            artifacts: [
                ProofPackArtifact(
                    role: "ticket-summary",
                    mediaType: "text/plain",
                    encoding: .utf8,
                    content: summary,
                    sha256: summaryHash
                )
            ]
        )
        let packURL = URL(fileURLWithPath: "proof-pack.json")
        try pack.jsonData().write(to: packURL)

        // ── 5. Verify — offline, fail-closed, signer pinned ─────────────────
        let keyID = attestation.attestation.keyID
        let verification = pack.verify(trustedKeyIDs: [keyID])
        print("Proof pack: \(verification.isValid ? "✅ VALID" : "❌ INVALID")")
        for binding in verification.bindings {
            print(
                "  artifact[\(binding.artifactIndex)] '\(binding.role)' bound by "
                    + "event[\(binding.eventIndex)] \(binding.eventTypeIdentifier)"
            )
        }
        if let failure = verification.failure {
            print("  failure: \(failure)")
        }

        print(
            """

            Written: \(packURL.path) — verify it anywhere, from a DProvenanceKit checkout:
              swift run dpk verify --in=proof-pack.json --proof-pack --trusted-key=\(keyID)
            Traces persisted in: \(storeURL.path)
            """
        )

        // The demo gates itself — in CI, a wrong diff, a silent anomaly, or a
        // failed verification is a red check, not a green lie.
        guard diff.changes.count == 3, anomalies.count == 1, verification.isValid else {
            print("\n❌ self-check failed: this output does not match the documented story")
            exit(1)
        }
    }

    nonisolated static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
