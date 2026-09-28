# rigorix-verifier (Go)

Strategy A parity for the Rigorix signed audit trail: an **independent,
protocol-only** Go verifier + client. No `rigorix-engine` dependency; the
canonical `schemas/**` corpus is embedded at build time (generated).

- **HMAC-SHA256** over the canonical form (`signature` nulled) — byte-exact with
  the rigorix-oss engine and the other verifiers.
- **JSON Schema** conformance (draft 2020-12, `santhosh-tekuri/jsonschema/v6`).
- **ADR-016 chains**: per-producer sequence + `prev_hash` continuity, gaps
  accepted only when covered by a valid signed compaction checkpoint.
- **Ed25519 anchor artifacts** (`crypto/ed25519`): ledger receipt, history slice,
  compaction checkpoint.
- **Client** (`.../go/client`): JSON-RPC 2.0 over a transport seam, binding every
  frozen `rigorix.*` catalog method (drift-tested against `catalog.json`).

## Install

```bash
go get github.com/arman-jalili/rigorix-sdk/go
```

## Usage

```go
import rigorix "github.com/arman-jalili/rigorix-sdk/go"

anchored, _ := rigorix.Fixture("envelope/envelope-anchored-signed.json")
_ = rigorix.VerifySignature(anchored, "fixture-hmac-key-2026") // byte-exact HMAC
_ = rigorix.ValidateEnvelope(anchored)                        // schema conformance
```

## Regenerating the embedded corpus

`internal/corpus/corpus_gen.go` is generated from the repo-root `schemas/` (the
single source of truth) because Go modules are fetched from VCS — they cannot
dereference a symlink or reach outside the module:

```bash
cd go && go generate ./...     # after any schemas/ change
```

`TestEmbeddedCorpusMatchesDisk` fails if it drifts.

## Test

```bash
cd go && go vet ./... && go test ./...
```
