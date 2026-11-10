# rigorix_gate_wasi.wasm

Vendored copy of the `rigorix-oss` WASI artifact (WASI-1; vendored).

- **source:** `arman-jalili/rigorix-oss`, tag `v1.14.3`, commit `c8d162e11a5b9c9c50c34d03211e33df33537d48`
- **crate:** `rigorix-gate-wasi` 1.14.3
- **build:** `bash wasi/ci/build.sh` from the repo root
  (`wasm32-wasip1`, `panic=abort`, debug `name` section stripped)
- **sha256:** `ab77bb821bcff564dd2302a43cf3a73930cfd5ec94925b78328770a8023b7928`
- **size:** 1,899,431 bytes

## Obtainability

**Released.** `rigorix-oss` `v1.14.3` publishes this artifact as the asset
`rigorix_gate_wasi.wasm` (1,899,431 bytes), built by `package-wasi` from
`c8d162e11a5b9c9c50c34d03211e33df33537d48` (the commit the tag peels to):

```bash
gh release download v1.14.3 --repo arman-jalili/rigorix-oss \
  --pattern 'rigorix_gate_wasi.wasm*'
shasum -a 256 -c rigorix_gate_wasi.wasm.sha256   # ab77bb82…
```

The digest above is the downloaded asset's, not a local build's: a macOS build of
the same commit hashes to `0cfacf43…`, so a locally produced artifact would pin a
digest no download reproduces. The page's number is the fact.

## One fact, two copies

`scripts/check-vendored-artifact.sh` fails if this file, the other language's
copy, either `PROVENANCE.md` or either source constant disagrees. The two copies
in this repository are not two artifacts.

## Runtime

The binding pins **`wasmtime==50.0.1`** (an exact pin, guarded by
`scripts/check-pins.py`) and `binding.runtime_version()` reports the installed
engine at run time. A support case therefore quotes three numbers that belong to
one decision: the artifact digest above, the artifact's `contract` version, and
the wasm engine that executed it. Advisories in either engine are scanned by
`.github/workflows/audit.yml`; `SECURITY.md` says who answers one and how fast.

## Imports (six, answered by constants)

`std` on `wasm32-wasip1` links six `wasi_snapshot_preview1` prologue functions;
no decision reads them. The binding answers each with a constant and counts the
three that could silently become real (clock, randomness, stdout):

| import | answer |
|---|---|
| `environ_get` | `0`, writes nothing |
| `environ_sizes_get` | writes `0,0` |
| `clock_time_get` | writes `0`, counts the call (must stay 0) |
| `random_get` | leaves the buffer zeroed, counts the call |
| `fd_write` | discards, counts bytes (must stay 0) |
| `proc_exit` | raises a typed `GateTrap` |

Any other import is a load-time `NotWASIArtifact` refusal.

## Exports

`memory`, `rigx_alloc`, `rigx_call`, `rigx_free`.

## Verification

```
node wasi/ci/run-conformance.mjs target/wasm32-wasip1/release/rigorix_gate_wasi.wasm
  module imports 6 item(s)
  contract 1.14.3 · engine 1.14.3 · gate true
  ✓ seeded-0001 (diverges, as recorded)
  ✓ vec-0001  ✓ vec-0002  ✓ vec-0003  ✓ vec-fixture-0001
  ✓ 5 of 5 vectors reproduced through node:wasi

node ... --truncate-request
  ✓ a truncated request is request_invalid, and the instance still answers
```

Vectors copied from `wasm/tests/conformance/vectors` (five files; the
`seeded-0001` vector must **not** reproduce its recorded digest).
