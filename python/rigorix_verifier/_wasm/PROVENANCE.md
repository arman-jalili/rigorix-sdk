# rigorix_gate_wasi.wasm

Vendored copy of the `rigorix-oss` WASI artifact (WASI-1; vendored).

- **source:** `arman-jalili/rigorix-oss`, commit `a314672c89ca49e550a636b3fd6a2ee468038d17`
- **crate:** `rigorix-gate-wasi` 1.14.2
- **build:** `bash wasi/ci/build.sh` from the repo root
  (`wasm32-wasip1`, `panic=abort`, debug `name` section stripped)
- **sha256:** `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`
- **size:** 1,896,910 bytes

## Obtainability

**No published release asset today.** The source commit above is `rigorix-oss`
`main`, not a tagged release, and `v1.14.2` carries no assets (`package-wasi` has
never executed). Obtain the artifact by building it from that commit:

```bash
git clone https://github.com/arman-jalili/rigorix-oss
cd rigorix-oss && git checkout a314672c89ca49e550a636b3fd6a2ee468038d17
bash wasi/ci/build.sh   # writes target/wasm32-wasip1/release/rigorix_gate_wasi.wasm
```

A rebuild is byte-identical (`7414f8df…`, 1,896,910 bytes), so the digest above
is a function of the commit. When `rigorix-oss` publishes `v1.14.3` with a
`rigorix_gate_wasi.wasm` asset, this section becomes that URL and the digest does
not change.

## One fact, two copies

`scripts/check-vendored-artifact.sh` fails if this file, the other language's
copy, either `PROVENANCE.md` or either source constant disagrees. The two copies
in this repository are not two artifacts.

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
