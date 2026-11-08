# Issue #65 — Python in-process gate (SDL-3)

**Branch:** `issue/65`
**Component:** `python/rigorix_verifier/binding/`
**Priority:** high
**Status:** ready — WASI-1 resolved 2026-11-08

## Blocker resolution (checked, not assumed)

`rigorix-oss` builds the artifact from `wasi/ci/build.sh`; `node
wasi/ci/run-conformance.mjs` reports:

```
module imports 6 item(s)
contract 1.14.2 · engine 1.14.2 · gate true
✓ seeded-0001 (diverges, as recorded)
✓ vec-0001  ✓ vec-0002  ✓ vec-0003  ✓ vec-fixture-0001
✓ 5 of 5 vectors reproduced through node:wasi
```

- sha256 `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`
- 1,896,910 bytes; ABI `rigx_alloc(len) -> ptr`, `rigx_call(ptr, len) -> ptr`,
  `rigx_free(ptr, len)`; response `[len: u32 LE][payload]`.
- **Six imports, not zero** (`wasi/ci/imports.txt`): `random_get`,
  `environ_get`, `environ_sizes_get`, `clock_time_get`, `fd_write`,
  `proc_exit`. The embedder answers each with a constant, counts
  `clock_time_get`/`random_get`/`fd_write`, and refuses any other import at
  load (`wasi/ci/embedder-contract.json`). The issue's "imports nothing" is the
  stale claim; the checkable claim is "no decision reads them".

## API

```python
from rigorix_verifier.binding import Gate

gate = Gate.open(scenario=sc, fixtures=fx, clock=clk, seed=seed)
out = gate.attempt({"name": "payment_execute", "params": {"amount": "184.20"}})
out["steps"][0]["kind"]                              # "capacity_exceeded"
out["steps"][0]["detail"]["overage"]                 # 7420
sealed = gate.export_artifact_set()
gate.contract_version()                              # {contract, engine, ...}
gate.counters                                        # all zero
```

## Changes

- `python/rigorix_verifier/binding/__init__.py` — `Gate`, errors, `Counters`.
- `binding/loader.py` — resolve `_wasm/rigorix_gate_wasi.wasm` via
  `importlib.resources`; validate the module's import section is **exactly** the
  six and its exports are `memory`, `rigx_alloc`, `rigx_call`, `rigx_free`;
  refuse anything else with `NotWASIArtifact` naming the import.
- `binding/gate.py` — wasmtime-py `Engine`/`Module`/`Store`/`Linker`; six host
  functions answered with constants; counters; the three-export ABI with the
  host-side bounds rule; `Gate.open`/`attempt`/`export_artifact_set`/
  `contract_version`/`close`; `GateClosed` after sealing; a trap maps to a
  typed `GateTrap`, never a process exit.
- `python/rigorix_verifier/_wasm/rigorix_gate_wasi.wasm` + `PROVENANCE.md`.
- `python/tests/binding_test.py` + `tests/binding/vectors/` (five vectors).
- `python/pyproject.toml` — add `wasmtime` and `rigorix_verifier.binding`;
  package data `_wasm/*`.
- `python/MANIFEST.in` — include `_wasm`.
- `python/scripts/pack_smoke.py` — assert the wheel/sdist carries the artifact.
- `python/README.md` — binding section.

## Acceptance

| Criterion | Test |
|---|---|
| decides | `pytest -q tests/binding_test.py` |
| goldens | five vectors: four reproduce, `seeded-0001` diverges (the OSS harness rule) |
| operands | vec-0002 `capacity_exceeded`, `overage 7420`, `claimed 1427420`; vec-0003 `duplicate_effect`, `QR-2041` |
| no IO at decision time | patch `open`/`socket`/`subprocess` after open; `attempt` still decides |
| wheel carries it | `unzip -l dist/*.whl \| grep rigorix_gate_wasi.wasm` |
| digest recorded | sha256 of `_wasm` equals `PROVENANCE.md` |
| truncated request | `request_invalid` typed error; the instance still answers |
| sealed session | `attempt` after `export_artifact_set` → `GateClosed` |
| not the WASI artifact | synthetic `__wbindgen_placeholder__` import → `NotWASIArtifact` |
| no policy in Python | scan `binding/*.py` for business terms |

## Validators

```
pytest -q
python -m build; install wheel; python scripts/pack_smoke.py
validate-ci/tests/security/architecture/integration
```
