## Summary

Adds `rigorix_verifier.client` — a stdlib-only JSON-RPC client over the frozen
`rigorix.*` catalog. It exposes the same **18** typed methods as the TypeScript
client, with DTO shapes mirrored from `schemas/api/catalog.json` `$defs`.

## What changed

- **`client/catalog.py`** — the frozen binding table (18 typed + 6 server-only
  with reasons; 24 total), `CLIENT_API_MAJOR`/`CLIENT_API_VERSION`, and
  `TypedDict` DTOs for every method.
- **`client/jsonrpc.py`** — request/notification/batch framing.
- **`client/error.py`** — `ClientError`, `TransportError`, `ProtocolError`,
  `RpcError(code, message, data)` (code and `data.rule_id`/`data.step` survive),
  `IncompatibleVersion`.
- **`client/transport.py`** — `Transport` `Protocol`; `HTTPTransport` over
  `urllib.request` with an explicit timeout; `MockTransport` for tests.
- **`client/client.py`** — 18 typed methods; `call_raw` rejects a mismatched
  response id (`ProtocolError`); a transport `socket.timeout` becomes
  `TransportError`, never `RpcError`; `version()` refuses a major other than 1.
- **`python/rigorix_verifier/__init__.py`** — exports the `client` namespace,
  not its names.
- **`python/pyproject.toml`** — adds `rigorix_verifier.client` to `packages`;
  no new dependency.
- **`python/scripts/pack_smoke.py`** — imports the client from the installed
  wheel/sdist, so the pack gate proves the subpackage is carried.
- **`python/tests/client_test.py`** — 15 tests: all 18 wire names, seeds S1–S4,
  catalog parity (24/24), no-new-dependency, HTTP 200/500, live gated.

## Surface note (code is truth)

The issue says "eight methods" and lists `executeStep`. The current TS client
exposes **18** typed methods; `executeStep` is not in the frozen catalog and
ADR-0001 D10 forbids it — it is not bound. The six server-only methods are
recorded with reasons and the parity test proves none is omitted.

## Dependency note

The issue's "zero-dependency package / `Requires: empty`" premise is stale: the
verifier already requires `jsonschema` and `cryptography`. The **client** adds
no dependency (`urllib.request`, `json`, `socket`, `typing` only); removing the
verifier's dependencies would break it and is out of scope. The test pins the
existing dependency line unchanged.

## Evidence

```
pytest -q                         35 passed, 1 skipped (live)
pytest -q tests/client_test.py    15 passed, 1 skipped (live)
wheel                             rigorix_verifier/client/*.py + _schemas/api/catalog.json
wheel venv pack_smoke             verifier + client import OK
sdist                             client/*.py present
validate-ci/tests/security/operations/canonical/architecture/integration  PASS
cargo build/test/clippy/fmt       green
```

Refs #64 — close after merge.
