# rigorix-verifier (Python)

Strategy A parity for the Rigorix signed audit trail: an **independent,
protocol-only** verifier so a Python consumer can check envelopes without
shelling out to Rust. No engine dependency.

- **HMAC-SHA256** over the canonical form (`signature` nulled) — byte-exact
  with the rigorix-oss engine and the Rust verifier.
- **JSON Schema** conformance (draft 2020-12, `jsonschema`).
- **ADR-016 chains**: per-producer sequence + `prev_hash` continuity, gaps
  accepted only when covered by a valid signed compaction checkpoint.
- **Ed25519 anchor artifacts** (`cryptography`): ledger receipt, history slice,
  compaction checkpoint.

## Install

```bash
pip install rigorix-verifier==0.9.0   # published artifact (embedded corpus)
pip install .                          # or: pip install -e ".[test]" (from source)
```

## Usage

```python
import json
from rigorix_verifier import (
    verify_signature, validate_envelope, verify_chain,
    verify_chain_with_checkpoints, verify_history_slice,
)

envelope = json.load(open("envelope.json"))
verify_signature(envelope, "fixture-hmac-key-2026")   # byte-exact HMAC
validate_envelope(envelope)                            # schema conformance

chain = json.load(open("chain.json"))
verify_chain(chain)                                    # ADR-016 local chain
```

## Protocol client

`rigorix_verifier.client` speaks JSON-RPC 2.0 over the frozen catalog with
`urllib.request` (no new dependency). It exposes the same 18 typed methods as
the TypeScript client; `version()` refuses an `api_version` major other than 1,
and a transport timeout is a `TransportError`, not an `RpcError`.

```python
from rigorix_verifier.client import Client, HTTPTransport

client = Client(HTTPTransport("http://127.0.0.1:3001/rpc"))
plan = client.plan({"template_name": "attendance"})
version = client.version()
```

## In-process gate (WASI)

`rigorix_verifier.binding.Gate` loads the vendored
`rigorix_gate_wasi.wasm` through `wasmtime`; the decision is made inside the
module. **`Gate.open` verifies the artifact's sha256 and size at load**
(`ab77bb82…`, 1,899,431 bytes) and raises `ArtifactDigestMismatch`, naming both
digests, when the installed package is not the artifact that was built;
`Gate.open_unverified(artifact=...)` is the opt-out for caller-supplied bytes
and says so in its name. The six WASI prologue imports are answered with
constants and counted, and any other import is a load-time refusal.

The engine is **`wasmtime==50.0.1`**, an exact pin guarded by
`scripts/check-pins.py`. `binding.runtime_version()` reports the installed
engine, so a support case quotes the artifact digest, the artifact's `contract`
version and the engine version together. `.github/workflows/audit.yml` runs
`pip-audit --strict` on every pull request and weekly.

```python
from rigorix_verifier.binding import Gate

gate = Gate.open(scenario=sc, fixtures=fx, clock=clk, seed=seed)
out = gate.attempt({"name": "payment_execute", "params": {"amount": "184.20"}})
out["steps"][0]["detail"]["overage"]          # 7420
sealed = gate.export_artifact_set()
```

## Canonical form

The HMAC is over `serde_json::to_string(envelope with signature=None)` as the
engine emits it: **struct field order**, `skip_serializing_if` fields omitted
when `None`/empty, non-skipped `Option` fields as `null`, `scoring_results` and
its `dimensions` maps sorted, and `serde_json::Value` payloads with sorted
keys. The field order is read from `schemas/envelope.json`. The committed
engine fixtures prove byte-exact parity (`tests/test_envelope.py`).

## Contract corpus

Resolution (mirrors the Rust verifier):

1. `RIGORIX_SDK_SCHEMAS` — an explicit external corpus (CI/local override).
2. The bundled `rigorix_verifier/_schemas` directory.

The bundled copy is **generated** from the repo-root `schemas/` (the single
source of truth) by [`scripts/bundle_schemas.py`](scripts/bundle_schemas.py):
the setuptools `build_py`/`sdist` hooks run it before packing, and
[`conftest.py`](conftest.py) runs it before tests. It is a real directory
(setuptools will **not** dereference a symlink into a wheel/sdist), never a
committed duplicate; `tests/test_corpus_sync.py` fails if it drifts from the
canonical corpus. The pack gate (`python -m build` → install wheel/sdist →
verify with `RIGORIX_SDK_SCHEMAS` unset) runs in CI. Run
`python scripts/bundle_schemas.py` manually if you need the copy outside a build.

## Test

```bash
pytest -q
```
