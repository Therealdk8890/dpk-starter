# DProvenanceKit starter

Watch DProvenanceKit record, diff, gate, and sign an AI feature's reasoning — in five minutes.

```bash
git clone https://github.com/Therealdk8890/dpk-starter && cd dpk-starter && swift run
```

No API keys, no live model, no setup. Requires a Swift 6.2+ toolchain (Xcode 26+); the library itself deploys back to macOS 13 / iOS 16.

## What you just watched

The demo simulates a support-ticket summarizer with a failure mode output tests can't see: after an OS update the model declines, the app silently falls back to a template, and the user-facing output still looks fine. (Simulates: the two runs are scripted so the story replays identically on your machine — no model is invoked.)

1. **Record** — two runs land in `starter-traces.sqlite`, a durable store your app owns (the demo resets it each run so the story replays; a real app keeps it).
2. **Diff** — the structural diff flags exactly what changed: `aiSummaryGenerated` disappeared, `templateFallbackUsed` appeared (plus `artifactBound`, the hash-binding step from step 4).
3. **Gate** — one declarative rule (`summaryReturned` without `aiSummaryGenerated`) turns that into a CI-failable anomaly. This repo's own CI runs the demo and fails if the diff, the anomaly, or the verification ever stops matching this README.
4. **Sign** — the run is signed into a **proof pack** (`proof-pack.json`): the trace plus the output bytes it vouches for, bound by SHA-256.
5. **Verify** — fail-closed, offline, signer-pinned. Anyone can re-verify the pack with no network and no access to your store.

## Make it yours

**1. Name what your feature does.** Copy `SummarizerEvent` in [StarterDemo.swift](Sources/StarterDemo/StarterDemo.swift) and replace its cases with your feature's reasoning steps. Keep `typeIdentifier` stable forever; mark the steps whose disappearance should page you as `.critical`.

**2. Record real runs.** Wrap your feature's execution in `DProvenanceKit<YourEvent>.run(contextID:store:)` and `record(...)` each step — recording is non-blocking and async-safe. Recording outside a `run { }` scope is a silent no-op, by design.

**Using Apple Foundation Models?** Skip hand-recording: one line traces the whole session (see [TracedSessionExample.swift](Sources/StarterDemo/TracedSessionExample.swift), OS 26+):

```swift
try await FMTrace.run(contextID: "…", store: store) { _ in
    let session = LanguageModelSession.traced(instructions: "…")
    // every prompt, response, and tool call is now recorded
}
```

or keep your existing session untouched and call `session.recordProvenance()` after the fact — same rule, inside `FMTrace.run { }`.

**3. Gate your CI.** Run your rules against the store in a test, the way this demo's self-check does — a reasoning regression becomes a red PR, not a mystery in production. (The DPK CLI's `evaluate --gate` gates DPK's own diff-engine corpus, not your store.)

**4. Ship evidence, not logs.** Hash your output into the trace before signing (the `artifactBound` event in this demo), wrap it in a `ProofPackDocument`, and hand reviewers a single JSON file they can verify offline from any [DProvenanceKit](https://github.com/Therealdk8890/DProvenanceKit) checkout:

```bash
swift run dpk verify --in=proof-pack.json --proof-pack --trusted-key=<key-id>
```

One caveat before production: keep your signing key in the Keychain — the [attestation guide](https://github.com/Therealdk8890/DProvenanceKit/blob/main/docs/ATTESTATION.md) has a copy-paste recipe.

## Where this sits

| Tool | Its job |
|---|---|
| Apple's Evaluations framework | Pre-release datasets, scoring, regression tests |
| Xcode Instruments | Development-time tracing and performance |
| OpenTelemetry | Moving telemetry into existing backends |
| **DProvenanceKit** | Persistent, app-owned production provenance, structural comparison, signed offline evidence |

Full documentation, the query DSL, redaction, OTLP export, and the threat model live in the main repo: **[DProvenanceKit](https://github.com/Therealdk8890/DProvenanceKit)**.

Apache 2.0 — see [LICENSE](LICENSE).
