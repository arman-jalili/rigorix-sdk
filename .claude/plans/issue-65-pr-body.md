## Summary

Implements SDL-3: the gate as an in-process WASI artifact loaded by
`wasmtime`, with the artifact shipped inside the wheel and sdist.

## Blocker check (verified before coding)

`rigorix-oss` at `a314672c` builds the artifact with `wasi/ci/build.sh`:

- sha256 `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`
- 1,896,910 bytes; contract/engine `1.14.2`; `gate_evaluation: true`
- `node wasi/ci/run-conformance.mjs` → **5/5** (four recorded + `seeded-0001`
  diverging as recorded); `--truncate-request` → `request_invalid`

**Contract correction:** the artifact imports **six** WASI prologue functions
(`random_get`, `environ_get`, `environ_sizes_get`, `clock_time_get`, `fd_write`,
`proc_exit`), not zero. The binding answers each with a constant, refuses any
other import at load, and counts clock/random/fd_write. The zero-floor
invariant is the **clock** (#1477); `random_get` is legitimately called once
during sealing, so it is observed rather than required zero.

## What changed

- `binding/loader.py` — resolve `_wasm/rigorix_gate_wasi.wasm`; validate the
  import section is exactly the six and the exports are `memory`,
  `rigx_alloc`, `rigx_call`, `rigx_free`; name a bad import/export.
- `binding/gate.py` — `wasmtime` Engine/Module/Store/Linker; six constant host
  functions; the three-export ABI with the host-side `[len][payload]` bounds
  rule; `Gate.open`/`attempt`/`export_artifact_set`/`contract_version`/`close`;
  `GateClosed` after sealing; traps map to `GateTrap`.
- `binding/errors.py`, `binding/__init__.py`.
- `_wasm/rigorix_gate_wasi.wasm` + `PROVENANCE.md` (source commit, sha256,
  imports, vectors, conformance command).
- `tests/binding_test.py` + `tests/binding/vectors/` (five vectors).
- `pyproject.toml` — `wasmtime`, the `binding` package, `_wasm/*` package data.
- `MANIFEST.in`, `scripts/pack_smoke.py`, `README.md`.

`export_artifact_set` requires an attempt (the artifact answers `seal_failed`
otherwise); the wrapper now tests the real protocol.

## Evidence

```
Linux (python:3.12-slim, matches CI):
  pytest -q tests/binding_test.py     12 passed
  pytest -q                           47 passed, 1 skipped (live)
  wheel + sdist                       binding/ and _wasm/ present
  packed-wheel pack_smoke             verifier + client + gate artifact OK
validate-ci/tests/security/operations/canonical/architecture/integration  PASS
cargo build/test/clippy/fmt                                           green
```

Local note: this macOS host SIGKILLs wasmtime's JIT even for a trivial
`i32.const` module, so `tests/binding_test.py` skips on Darwin unless
`RIGORIX_WASMTIME_JIT=1`; the Linux CI runs them unconditionally.

Refs #65 — close after merge.
