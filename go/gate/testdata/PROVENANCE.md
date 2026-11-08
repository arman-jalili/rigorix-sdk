# rigorix_gate_wasi.wasm

Vendored copy of the `rigorix-oss` WASI artifact (SDL-4 / WASI-1).

- **source:** `arman-jalili/rigorix-oss`, commit `a314672c89ca49e550a636b3fd6a2ee468038d17`
- **crate:** `rigorix-gate-wasi` 1.14.2
- **build:** `bash wasi/ci/build.sh` from the repo root
  (`wasm32-wasip1`, `panic=abort`, debug `name` section stripped)
- **sha256:** `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`
- **size:** 1,896,910 bytes

## Imports (six, answered by constants)

| import | answer |
|---|---|
| `environ_get` | `0`, writes nothing |
| `environ_sizes_get` | writes `0,0` |
| `clock_time_get` | writes `0`, counts the call (the zero-floor invariant, #1477) |
| `random_get` | leaves the buffer zeroed, counts the call |
| `fd_write` | discards, counts bytes |
| `proc_exit` | maps to a typed `GateTrap` |

Any other import is a load-time `ErrNotWASIArtifact` refusal naming it.

## Exports

`memory`, `rigx_alloc`, `rigx_call`, `rigx_free`; response is
`[len: u32 LE][payload]`.

## Verification

```
node wasi/ci/run-conformance.mjs target/wasm32-wasip1/release/rigorix_gate_wasi.wasm
  module imports 6 item(s)
  contract 1.14.2 · engine 1.14.2 · gate true
  ✓ seeded-0001 (diverges, as recorded)
  ✓ vec-0001  ✓ vec-0002  ✓ vec-0003  ✓ vec-fixture-0001
  ✓ 5 of 5 vectors reproduced through node:wasi
```

Vectors copied from `wasm/tests/conformance/vectors`.
