# Implementation Plan: issue/35

**Branch:** `issue/35` (base `main`)
**Issue:** #35 — SDK-CLIENTS-JAVA-GO: Java + Go clients & verifiers (D-1 language
dirs)

## Classification

New implementations (two languages). Scope **Complex / Critical surface**.

## Approach

Independent (Strategy A) re-implementations in `java/` and `go/`, byte-exact on
the shared fixtures, protocol-only (no `rigorix-engine`). Each has a verifier and
a catalog client. The shared `schemas/**` corpus is consumed — never forked by
hand.

## Corpus strategy (no committed duplicate)

- **Go**: modules are fetched from VCS and cannot dereference a symlink or reach
  outside the module, so `internal/corpus/corpus_gen.go` is **generated** from
  the repo-root `schemas/` (`go generate ./...`) and committed. A
  `TestEmbeddedCorpusMatchesDisk` sync test + a CI `go generate` + `git diff
  --exit-code` gate fail on drift.
- **Java**: Maven copies `${project.basedir}/../schemas` into the jar under
  `rigorix/schemas/**` at build time. Nothing is committed; the published jar is
  self-contained.

## Deliverables

**Go** (`go/`, module `github.com/arman-jalili/rigorix-sdk/go`)
- `canonical.go` — field order from `envelope.json`, skip-none/empty, sorted
  maps, `json.Number` lexemes; `CanonicalBytes`, `EnvelopeHash`.
- `envelope.go` — `VerifySignature` (HMAC, GAP-M-12), `ValidateSchema` /
  `ValidateEnvelope` (draft 2020-12).
- `chain.go`, `anchor.go` — ADR-016 chains + Ed25519 artifacts.
- `client/` — JSON-RPC 2.0 (`Call`/`Notify`/`Batch`), transport seam
  (`HTTPTransport`/`MockTransport`), the full 23-method catalog binding table +
  drift test + no-raw-step-execution guard.

**Java** (`java/`, Maven `dev.rigorix:rigorix-verifier:0.2.0`, Java 17)
- `Canonical`, `Envelope`, `Chain`, `Anchor`, `Corpus`, `VerifyException`.
- `client/` — `Catalog` (23 methods), `Client` (JSON-RPC over `Transport`),
  `HttpTransport`/`MockTransport`, `RpcException`.

**CI** — `🐹 rigorix (go)` (drift check + vet + test) and
`☕ rigorix-verifier (java)` (`mvn verify`).

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Java + Go verifiers byte-exact on the fixtures (HMAC + chain + Ed25519) | ✅ Go 19 / Java 16 tests |
| 2 | Client binds every frozen catalog method (drift test) | ✅ both languages |
| 3 | Protocol-only; register-able artifacts (`go.mod`, `pom.xml`) | ✅ |
| 4 | Per-language CI green | ✅ |

## Status

- [x] Implemented
- [x] Local checks green (`go vet`/`go test`, `mvn verify`)
- [ ] MR pushed / merged
