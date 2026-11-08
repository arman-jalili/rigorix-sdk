# Issue #66 — Go in-process gate (SDL-4)

**Branch:** `issue/66`
**Component:** `go/gate/`
**Priority:** medium
**Status:** ready — WASI-1 resolved 2026-11-08; SDL-1 merged (`e11ef99`)

## Blocker resolution (checked, not assumed)

Same artifact as #65: `rigorix_gate_wasi.wasm`, sha256
`7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`,
1,896,910 bytes. `node wasi/ci/run-conformance.mjs` reproduces four vectors and
the recorded divergence; `--truncate-request` returns `request_invalid`.

- **Six imports, not zero.** wazero configures a host module with the six
  `wasi_snapshot_preview1` functions answered by constants and counters; it
  refuses any other import at load. The issue's "no host functions" acceptance
  is the stale claim; the checkable claim is "no decision reads them", proven by
  zero counters across the vectors.
- ABI: `rigx_alloc(len) -> ptr`, `rigx_call(ptr, len) -> ptr`,
  `rigx_free(ptr, len)`; response `[len: u32 LE][payload]`; host-side bounds
  checked before reading.

## API

```go
g, err := gate.Open(ctx, gate.World{Scenario: sc, Fixtures: fx, Clock: clk, Seed: seed})
out, err := g.Attempt(ctx, gate.Action{
    Name: "payment_execute", Params: map[string]any{"amount": "184.20"},
})
// out["steps"].([]any)[0].(map[string]any)["detail"].(map[string]any)["overage"] == float64(7420)
sealed, err := g.ExportArtifactSet(ctx)
_ = sealed
counters := g.Counters() // clock must stay zero; random/fd_write are observed
```

## Changes

- `go/gate/gate.go` — `//go:embed testdata/rigorix_gate_wasi.wasm`; `World`,
  `Action`, `Gate`, `Open`/`Attempt`/`ExportArtifactSet`/`ContractVersion`/
  `Counters`/`Close`; typed `GateError`, `GateTrap`, `ErrNotWASIArtifact`,
  `ErrGateClosed`.
- `go/gate/wasi.go` — the six constant host functions and counters.
- `go/gate/memory.go` — alloc/call/free; `[len][payload]` with host-side bounds
  checks; UTF-8 decoding.
- `go/gate/testdata/rigorix_gate_wasi.wasm` + `PROVENANCE.md`.
- `go/gate/testdata/vectors/` — the five vectors.
- `go/gate/{gate,conformance,memory}_test.go` — vectors, capacity/duplicate
  operands, digest, six-import contract, seventh-import refusal, truncated
  request, unknown op, no policy in Go, live counters.
- `go/go.mod` — one dependency: `github.com/tetratelabs/wazero`.
- `go/README.md` — gate section.

## Acceptance

| Criterion | Test |
|---|---|
| pure Go | `CGO_ENABLED=0 go test ./gate/...` |
| goldens | five vectors: four reproduce, `seeded-0001` diverges |
| artifact identity | sha256 equals `PROVENANCE.md` |
| six imports | exactly the six recorded; a seventh refused by name |
| counters | `clock_time_get_calls` zero (the #1477 invariant); `random_get_calls`/`fd_write_bytes` observed |
| no engine logic | scan `gate/*.go` for business terms; no rule evaluation |
| operands | vec-0002 `overage 7420`, `claimed 1427420`; vec-0003 `QR-2041` |
| truncated request | typed `request_invalid`; instance still answers |
| unknown op | typed `request_invalid`, no panic |
| sealed session | `Attempt` after `ExportArtifactSet` → `ErrGateClosed` |

## Validators

```
CGO_ENABLED=0 go test ./gate/... -cover
go vet ./...; gofmt -l go/gate
validate-ci/tests/security/architecture/integration
```
