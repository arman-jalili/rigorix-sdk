# Issue #64 — Python protocol client (SDL-2)

**Branch:** `issue/64`
**Component:** `python/rigorix_verifier/client/` (second package in the same
distribution)
**Priority:** high
**Status:** ready (no external dependency)

## Current state — code is truth

`python/rigorix_verifier/` is verify-only: canonical, envelope, chain, anchor,
corpus, errors. There is **no client and no HTTP**. The package currently
depends on `jsonschema` and `cryptography` for the verifier; the issue's
"zero-dependency package / `Requires: empty`" premise is stale. The client must
add **no new dependency** (stdlib `urllib.request`, `json`, `socket` only) —
removing the verifier's two dependencies is out of scope and would break it.

## Surface — the TS client is the reference

Same 18 typed methods as #63. The issue's "eight" predates audit/template/auth;
`executeStep` is not in the frozen catalog and is forbidden by ADR-0001 D10.

```
plan, validatePlan, run, execute, approve, checkEnforcement,
audit.read, audit.list, audit.summary,
template.list, template.get, template.create, template.validate,
auth.login, auth.status, auth.logout,
usageGuide, version
```

The six `ServerOnly` catalog methods stay unbound, mirroring `go/client` and
`catalog.go` / `catalog.ts`:
audit.head, audit.history, audit.overdue, audit.authorityFacts, auth.verify,
policy.bundle.

## Files

- **`python/rigorix_verifier/client/__init__.py`** — exports `Client`,
  `HTTPTransport`, `Transport`, `BatchCall`, and the error taxonomy.
- **`python/rigorix_verifier/client/catalog.py`** — `CLIENT_API_MAJOR = 1`,
  `CLIENT_API_VERSION = "1.0.0"`, the 18 `TYPED_METHODS`, the 6
  `SERVER_ONLY_METHODS` with reasons, the full 24-method `METHODS` table, and
  `TypedDict` DTOs mirroring `schemas/api/catalog.json` `$defs` (TS
  `types.ts` is the reference).
- **`python/rigorix_verifier/client/jsonrpc.py`** — `call`, `notification`,
  `encode`, `decode`, `decode_batch`, request/response shapes.
- **`python/rigorix_verifier/client/error.py`** — `ClientError`,
  `TransportError`, `ProtocolError`, `RpcError(code, message, data)`,
  `IncompatibleVersion(server, client_major)`. `RpcError.code` survives
  (issue S1); `data.type`/`rule_id`/`step` remain accessible.
- **`python/rigorix_verifier/client/transport.py`** — `Transport` `Protocol`
  with `post(body: str) -> str`; `HTTPTransport` over `urllib.request` with an
  explicit timeout, JSON headers, `TransportError` on non-2xx/timeout/URLError.
- **`python/rigorix_verifier/client/client.py`** — `Client`: `call_raw`,
  `call`, `notify`, `batch_raw`, the 18 typed methods. `call_raw` rejects a
  mismatched response id with `ProtocolError`; a transport `socket.timeout` is
  wrapped as `TransportError`, never `RpcError`; `version()` rejects a major
  other than 1 with `IncompatibleVersion` naming the advertised major.
- **`python/rigorix_verifier/__init__.py`** — export the `client` **namespace**
  (`from . import client`, add `"client"` to `__all__`), not its names.
- **`python/pyproject.toml`** — add `"rigorix_verifier.client"` to
  `[tool.setuptools] packages`; no new dependencies.
- **`python/tests/client_test.py`** — fake transport; seeds S1–S4; table test
  for all 18 methods; catalog parity against the bundled
  `_schemas/api/catalog.json` (24/24, none invented); no-new-import check;
  live test gated on `RIGORIX_SERVER_URL`.
- **`python/README.md`** — a client section with the two-line example.

## Acceptance mapping

| Issue criterion | Test |
|---|---|
| tests | `pytest -q tests/client_test.py` |
| no new dependency | `pyproject.toml` dependencies unchanged; client imports stdlib only |
| verifier unchanged | existing `pytest -q tests/` green |
| live | `RIGORIX_SERVER_URL=... pytest -q -k live` |
| S1 code preserved | fake error `-32601` → `RpcError.code == -32601` |
| S2 id mismatch refused | response `id: 2` for request `1` → `ProtocolError` |
| S3 v2 refused | `IncompatibleVersion`, message names the advertised major |
| S4 timeout is transport | fake raises `socket.timeout` → `TransportError`, not `RpcError` |
| wheel carries the client | `python -m build` + `unzip -l dist/*.whl \| grep client/` |

## Validators

```
python -m pytest -q python/tests
python scripts/bundle_schemas.py
python -m build && unzip -l dist/*.whl
python scripts/pack_smoke.py
guardian validate ci/tests/security/architecture/integration
```

## Notes

- No schema change; `api/catalog.json` is already bundled into `_schemas` and
  used only by the parity test.
- The client returns plain `dict`s (the issue's end state uses dict access);
  `TypedDict` provides the static shape without a runtime dependency.
- The `from __future__ import annotations` style matches the verifier.
