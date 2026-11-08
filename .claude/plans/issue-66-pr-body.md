## Summary

Implements SDL-4: the gate as an in-process WASI artifact loaded by **wazero**,
pure Go, with no cgo. The artifact is embedded from
`go/gate/testdata/rigorix_gate_wasi.wasm`.

## Blocker check (verified before coding)

- `rigorix-oss` at `a314672c` builds the artifact with `wasi/ci/build.sh`
- sha256 `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`,
  1,896,910 bytes
- `node wasi/ci/run-conformance.mjs` → **5/5** (four recorded + `seeded-0001`
  diverging as recorded); `--truncate-request` → `request_invalid`
- #63's Go client landed in `e11ef99`, so SDL-1 is satisfied

**Contract correction:** the artifact imports **six** WASI prologue functions
(`environ_get`, `environ_sizes_get`, `clock_time_get`, `random_get`, `fd_write`,
`proc_exit`), not zero. wazero defines a host module with exactly those six,
answers them with constants, counts clock/random/stdout, and refuses any other
import at load by name. The clock counter is the zero-floor invariant (#1477);
randomness is an observed count (one inert read during sealing).

## What changed

- `go/gate/gate.go` — embed the artifact; `World`, `Action`, `Gate`;
  `Open`/`Attempt`/`ExportArtifactSet`/`ContractVersion`/`Counters`/`Close`;
  typed `GateError`, `GateTrap`, `ErrNotWASIArtifact`, `ErrGateClosed`.
- `go/gate/wasi.go` — import validation and the six constant host functions.
- `go/gate/memory.go` — alloc/write/call/read/free with the host-side
  `[len][payload]` bounds checks; the response is copied before freeing.
- `go/gate/testdata/rigorix_gate_wasi.wasm` + `PROVENANCE.md` + five vectors.
- `go/gate/gate_test.go` — five vectors, capacity/duplicate operands, digest,
  exactly-six import record, seventh-import refusal by name, truncated request,
  unknown op, sealed session, no policy in Go.
- `go/go.mod` / `go.sum` — `github.com/tetratelabs/wazero v1.7.3`.
- `go/README.md` — gate usage.

## Evidence

```
CGO_ENABLED=0 go test ./gate/... ./client/...    gate ok; client 87.6%
go test ./...                                    all packages ok
go vet ./...; gofmt -l go/gate                   clean
five vectors                                     four reproduce, seeded diverges
capacity operands                                overage 7420, claimed 1427420
seventh import                                   ErrNotWASIArtifact names it
validate-ci/tests/security/operations/canonical/architecture/integration  PASS
cargo build/test/clippy/fmt                      green
```

Gate coverage is 62.3 % (the error/cleanup paths are the remainder); #66 sets no
coverage threshold. Refs #66 — close after merge.
