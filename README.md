# rigorix-sdk

Contract-first SDK + integration surface for Rigorix. **Not a crate inside rigorix-oss** —
a standalone repo whose job is to make the Rigorix boundary speakable from any stack.

## What lives here

| Path | Purpose |
|------|---------|
| `schemas/` | **Single source of truth** for Rigorix contracts: envelope v2, policy/config model, identity claim format, native `rigorix.*` API method catalog. Drift-tested against rigorix-oss (CI). |
| `rust/` | `rigorix-sdk` crate — typed MCP/JSON-RPC client + envelope verifier (planned; protocol-only, **no** `rigorix-engine` dependency) |
| `python/` · `typescript/` · `java/` · `go/` | Same thin client + verifier story per language (sequenced on demand) |
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
- [ ] Envelope v2 schema completed via delta mapping
- [ ] Policy/config model schema (rigorix.toml + sequence-policy semantics)
- [ ] Identity/claim schema (ADR-012)
- [ ] Drift CI in rigorix-oss
- [ ] rust/ v0: model + client + verifier + live-server tests
