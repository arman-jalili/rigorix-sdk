# rigorix_gate_wasi.wasm

Vendored copy of the `rigorix-oss` WASI artifact (SDL-3 / WASI-1).

- **source:** `arman-jalili/rigorix-oss`, commit `a314672c89ca49e550a636b3fd6a2ee468038d17`
- **crate:** `rigorix-gate-wasi` 1.14.2
- **build:** `bash wasi/ci/build.sh` from the repo root
  (`wasm32-wasip1`, `panic=abort`, debug `name` section stripped)
- **sha256:** `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`
- **size:** 1,896,910 bytes

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
  contract 1.14.2 · engine 1.14.2 · gate true
  ✓ seeded-0001 (diverges, as recorded)
  ✓ vec-0001  ✓ vec-0002  ✓ vec-0003  ✓ vec-fixture-0001
  ✓ 5 of 5 vectors reproduced through node:wasi

node ... --truncate-request
  ✓ a truncated request is request_invalid, and the instance still answers
```

Vectors copied from `wasm/tests/conformance/vectors` (five files; the
`seeded-0001` vector must **not** reproduce its recorded digest).
