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
  frozen `rigorix.*` catalog method (drift-tested against `catalog.json`) with
  typed wrappers for the 18 methods the TS client exposes.

## Install

Requires **Go 1.26+** (the floor exists so a patched `golang.org/x/text` is
reachable; `govulncheck` scans the stdlib of the toolchain that builds).

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

## Protocol client (`go/client`)

`client.New` takes a `Transport`; `client.NewHTTPTransport` is the `net/http`
implementation. The 18 typed methods mirror
`typescript-client/src/client.ts` over the frozen catalog; `Version` refuses an
`api_version` major other than 1, and `CallRaw` rejects a response whose `id`
is not the request's.

```go
import (
    "context"

    "github.com/arman-jalili/rigorix-sdk/go/client"
)

c := client.New(client.NewHTTPTransport("http://127.0.0.1:3001/rpc", nil))
plan, err := c.Plan(context.Background(), client.PlanParams{TemplateName: "attendance"})
version, err := c.Version(context.Background()) // *VersionMismatchError for a major != 1
```

`catalog_drift_test.go` pins the binding table to `schemas/api/catalog.json`
(24 methods, none invented); `AssertNoRawStepExecution` keeps the governed-flow
invariant. `TestLiveVersion` runs when `RIGORIX_SERVER_URL` is set.

## In-process gate (`go/gate`)

`gate.Open` embeds the vendored `rigorix_gate_wasi.wasm` and loads it with
wazero (pure Go; `CGO_ENABLED=0`). **It verifies the artifact's sha256 and size
at load** (`7414f8df…`, 1,896,910 bytes) and refuses a mismatch with
`*gate.ArtifactDigestError`, which names both digests; `gate.OpenUnverified` is
the opt-out for caller-supplied bytes and says so in its name. The six WASI
prologue imports are answered with constants; the clock must stay zero (#1477),
while randomness/stdout are counted. Any other import is refused at load, by
name.

The engine is **wazero v1.12.0**, pinned exactly in `go.mod` — no range, so the
version in a report is a fact. `scripts/check-pins.py` fails on a range, and
`.github/workflows/audit.yml` runs `govulncheck ./...` on every pull request and
weekly; `SECURITY.md` says who answers an advisory and how fast.

```go
g, err := gate.Open(ctx, gate.World{
    Scenario: sc, Fixtures: fx, Clock: clk, Seed: seed,
})
out, err := g.Attempt(ctx, gate.Action{
    Name: "payment_execute", Params: map[string]any{"amount": "184.20"},
})
// out["steps"].([]any)[0].(map[string]any)["detail"].(map[string]any)["overage"] == float64(7420)
sealed, err := g.ExportArtifactSet(ctx)
_ = sealed
```

`testdata/PROVENANCE.md` records the source commit, sha256, size and the five
vectors. The digest is enforced twice: at load (above) and by
`scripts/check-vendored-artifact.sh`, which fails if this copy, the Python copy,
either provenance file or either source constant disagrees.

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
