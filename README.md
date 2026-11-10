# rigorix-sdk

Contract-first SDK + integration surface for Rigorix. **Not a crate inside rigorix-oss** —
a standalone repo whose job is to make the Rigorix boundary speakable from any stack.

## What lives here

| Path | Purpose |
|------|---------|
| `schemas/` | **Single source of truth** for Rigorix contracts: envelope v2, policy/config model, identity claim format, native `rigorix.*` API method catalog. Drift-tested against rigorix-oss (CI). |
| `rust/` | `rigorix-schemas` + `rigorix-verifier` (published **0.9.0**) + `rigorix-client` — typed JSON-RPC client + envelope/chain/anchor verifier (protocol-only, **no** `rigorix-engine` dependency) |
| `python/` · `typescript/` · `java/` · `go/` | The same verifier + catalog client, byte-exact on the shared fixtures (`rigorix-verifier` on PyPI/npm; Maven `eu.rigorix:rigorix-verifier`; Go module) |
| `docs/` | Strategy freezes + contract-sync design (this repo is also the planning home for server mode) |

## Strategy (frozen 2026-09-06 — see `docs/strategy-freeze-2026-09-06.md`)

- **A — Trust multiplier (now):** schemas + envelope verifiers so the HMAC-signed audit
  trail is independently checkable in any CI, any language. Rigorix's core claim is
  *trust-but-verify*; a signature only rigorix's own tools can check is self-referential.
- **B — Adoption unlock (next):** rigorix **server mode** — OSS `rigorix-server`
  (reference impl) + enterprise execution-API module — both speaking **one** native
  `rigorix.*` JSON-RPC catalog frozen here. SDK clients become thin typed wrappers.
- SSE verdict: legacy MCP SSE stays removed (GAP-A-10). What returns is HTTP JSON-RPC +
  an SSE push channel on the **native** contract (approvals, progress); MCP Streamable
  HTTP is optional later for GUI agents.
- Sequence: **contract sync → catalog design → server in both repos → SDK clients.**

## Governance invariant

Every SDK exposes **governed flows only** (plan → enforce → approve → run → audit) — no
direct-execute escape hatch. Embedded governance is Rust-only, via `rigorix-engine` on
crates.io, documented as a separate path. This repo is itself intended to be
rigorix-governed once v0 lands (dogfood demo #2).

## Status

- [x] Repo scaffold + strategy freeze (2026-09-06)
- [x] Contract-sync design doc (2026-09-06) — enterprise-side situation file created
- [x] Envelope v2 schema + signed fixtures (anchored / effect-key / sequence-denied / unsigned-degraded)
- [x] Policy/config model schema (`policy.json`) + identity/claim schema (`claims.json`)
- [x] Catalog freeze — ADR-0001, **24** `rigorix.*` methods (OSS server serves a 19-method subset) — drift CI in both OSS and enterprise
- [x] ADR-017 / consequence-gating §4.3 — `rigorix.audit.authorityFacts` + `api/authority-fact-bundle.json` (SDK #44)
- [x] SSE push channel — ADR-0002 + `events.json` + fixtures
- [x] ADR-016 integrity contract — `api/history-slice.json`, `api/ledger-receipt.json`, `api/compaction-checkpoint.json`
- [x] `rust/` **0.9.0** (`rigorix-schemas`, `rigorix-verifier`, `rigorix-client`) — published to crates.io, npm, PyPI and Maven Central (all four verifier channels at 0.9.0)
- [x] Python / TypeScript / Java / Go verifiers + catalog clients — fixtures green in each language

*Last verified: 2026-11-10 against `rigorix-oss` `v1.14.3` (the gate artifact the
vendored copies hash to).*

## Development

```bash
bash .ci/local-ci.sh     # every CI job plus the seven validators, no secret needed
```

The runner prints how many steps it executed and exits `1` on a failure, `3` when
a step was skipped for lack of a subject (the Python binding tests need Linux or
Docker: wasmtime's JIT is killed by the macOS sandbox).

- **Contributing:** [CONTRIBUTING.md](CONTRIBUTING.md) — DCO sign-off, the rules
  this repository holds itself to.
- **Publication readiness:** [docs/publication-readiness.md](docs/publication-readiness.md)
  — including the recorded decision to publish the history as it stands.
- **Security:** [SECURITY.md](SECURITY.md) — private reporting, and who answers a
  wasm-engine advisory.

## Licence

**Apache-2.0**, and only Apache-2.0. The full text is [LICENSE](LICENSE), the
attribution statement is [NOTICE](NOTICE), and every published artefact declares
the same in its manifest (`rust/Cargo.toml`, both `package.json` files,
`python/pyproject.toml`).

The Apache licence rather than MIT because it carries an express patent grant,
which matters for a verifier others embed. The schemas under `schemas/` are part of
this repository and covered by the same licence; they carry no per-file licence
field, deliberately — adding one would change the bytes of a frozen contract that
other repositories pin, so the terms are stated here and in
[schemas/README.md](schemas/README.md).
