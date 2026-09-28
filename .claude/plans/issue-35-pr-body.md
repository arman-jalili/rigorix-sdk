## Summary

Adds the two missing D-1 language directories: **`go/`** and **`java/`**. Each is
an independent (Strategy A) **verifier + catalog client**, byte-exact on the
shared fixtures (`envelope/`, `integrity/`), protocol-only (no `rigorix-engine`).
Closes the gap so the two remaining enterprise-native stacks can consume the
frozen catalog and verify the signed trail.

Closes #35.

## What's implemented

**Go** — module `github.com/arman-jalili/rigorix-sdk/go`
- `CanonicalBytes` / `EnvelopeHash`: field order read from `envelope.json`,
  skip-if-none/empty, sorted map fields, `json.Number` lexemes preserved.
- `VerifySignature` (HMAC-SHA256, GAP-M-12), `ValidateSchema`/`ValidateEnvelope`
  (draft 2020-12 via `santhosh-tekuri/jsonschema/v6`).
- `VerifyChain` / `VerifyChainWithCheckpoints` (ADR-016) and Ed25519
  `VerifyLedgerReceipt`/`VerifyHistorySlice`/`VerifyCompactionCheckpoint`.
- `client/`: JSON-RPC 2.0 (`CallRaw`/`Notify`/`BatchRaw` + `CallTyped`), a
  `Transport` seam (`HTTPTransport`/`MockTransport`), the full **23-method**
  catalog binding table, a `catalog_drift` test, and a no-raw-step-execution
  guard (ADR-0001 D10).

**Java** — Maven `dev.rigorix:rigorix-verifier:0.2.0` (Java 17)
- `Canonical`, `Envelope`, `Chain`, `Anchor`, `Corpus`, `VerifyException`.
- `client/`: `Catalog` (23 methods + typed/server-only + no-raw-step guard),
  `Client` (JSON-RPC over a `Transport`), `HttpTransport`/`MockTransport`.
- Jackson (exact `BigDecimal` for `1.0`), networknt JSON Schema, BouncyCastle
  Ed25519.

**CI** — two jobs: `🐹 rigorix (go)` (`go generate` drift check + `go vet` +
`go test`) and `☕ rigorix-verifier (java)` (`mvn -B -q verify`).

## Corpus (no committed duplicate)

- **Go**: modules are fetched from VCS and cannot dereference a symlink or reach
  outside the module, so `internal/corpus/corpus_gen.go` is **generated** from
  the repo-root `schemas/` (`go generate ./...`) and committed. The
  `TestEmbeddedCorpusMatchesDisk` sync test + the CI `git diff --exit-code` gate
  fail on drift.
- **Java**: Maven copies the repo-root `schemas/` into the jar under
  `rigorix/schemas/**` at build time — the jar is self-contained and nothing is
  re-vendored.

## Verification

```
# Go
cd go && go vet ./...
go test ./...     # 19 tests: HMAC, tamper, GAP-M-12, anchored-anchor_head,
                  # chain (+gap/checkpoint/forgery), Ed25519 artifacts, corpus sync
cd client && ...  # 6 tests: catalog drift, framing, notify, RPC error, batch

# Java
cd java && mvn -B verify   # 16 tests (Verifier 4, ChainAnchor 8, Client 4)
unzip -l target/rigorix-verifier-0.2.0.jar | grep rigorix/schemas/envelope.json   # present
```

Both verifiers verify the engine fixtures **byte-exact**, including
`envelope-anchored-signed.json` (the ADR-016 Phase C `anchor_head` position test)
and the local `chain.json`/anchor artifacts.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Java + Go verifiers byte-exact on the fixtures (HMAC + chain + Ed25519) | ✅ |
| 2 | Client binds every frozen catalog method (drift test) | ✅ both |
| 3 | Protocol-only; register-able artifacts | ✅ |
| 4 | Per-language CI green | ✅ |

## Notes

- Canonical field order is **derived from `schemas/envelope.json`** in both
  languages (never from memory), preserving skip-when-absent semantics.
- No new contract changes: this PR only adds consumers of the frozen surface.
