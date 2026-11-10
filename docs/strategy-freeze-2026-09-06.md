# Rigorix SDK + Server Mode — Strategy Freeze (2026-09-06)

**Status:** Frozen — session decisions from the SDK/server brainstorm. No code implied by
this doc alone; it records *why* and *in what order*.

## Context

- rigorix-oss is at 1.4.0 (published: engine/mcp/cli/actions), demos (migration-demo,
  conference-demo) validated end-to-end with Claude Code/Codex over **stdio MCP only**.
- The MCP surface is the only cross-runtime boundary today (17 tools). rigorix-mcp has
  **no network transport** — SSE was removed (GAP-A-10); `--sse` warns and runs stdio.
- The enterprise product is a **control plane** (policy bundle export, audit ingestion with
  HMAC verify, teams/RBAC, dashboards, REST axum + Postgres) — and is **far behind OSS**:
  identity attestation, approval binding, sequence policy (R7) and runtime wiring all
  landed OSS-side recently; enterprise has none of it. Enterprise `findings/log.md`
  still marks OSS-side findings F-20260904-05/06/07 as **Open** even though OSS fixed
  them — the log is stale (drift proof).

## Decisions

### D-1 — SDK shape: standalone `rigorix-sdk` repo, contract-first
A cargo crate cannot hold publishable python/ts/java packages. Subfolder idea is right;
the container is a repo: `/rust /python /typescript /java /go` + **`schemas/`**
(canonical contracts, single source of truth) + `docs/`. Rust client is protocol-only —
no `rigorix-engine` dependency. Versioning: release train, not single-version fiction.
All SDK-ish crates.io names verified AVAILABLE (`rigorix-sdk`, `rigorix-mcp-client`,
`rigorix-schemas`, `rigorix-verify`).

### D-2 — Strategy A first: trust multiplier (cheap, now)
Schemas + per-language **envelope verifiers** (Rust/Python/TS) so the HMAC-signed trail
is independently checkable in any CI / by any downstream consumer. Not redundant with
`rigorix-action` (which is GitHub-only workflow governance). Enterprise `audit_ingestion`
already runs this exact HMAC check — the verifier makes the same proof portable.

### D-3 — Strategy B next: server mode, one native catalog
Two distinct "servers" exist conceptually; both speak **one** `rigorix.*` JSON-RPC
catalog frozen in `schemas/`:
1. **OSS `rigorix-server`** (rigorix-oss workspace crate) — single-tenant reference
   execution server: engine orchestrator + event bus + approvals + identity + audit
   store behind the catalog over HTTP JSON-RPC + SSE push. stdio MCP unchanged.
2. **Enterprise execution-API module** (enterprise `core`, **module-in-core**
   recommended over a separate service: policy_engine/auth/audit_ingestion/Postgres all
   already live there; a sidecar quadruples the sync surface and doubles drift).
Why OSS first: without a reference server, OSS users never get the any-stack unlock and
the OSS→enterprise funnel dies; the existing `enterprise_proxy` seam
(`rigorix_enterprise_*`, JSON-RPC client) currently has **no live server** — enterprise
speaks REST, not JSON-RPC (contract mismatch to close).

### D-4 — SSE verdict
Legacy MCP SSE (ADR-004, removed via GAP-A-10 as advertised-but-unimplemented) is **not
resurrected**: it's 1:1 per process and superseded by MCP Streamable HTTP. What matters
for server mode is HTTP: rigorix-native JSON-RPC endpoints + an SSE **push channel on
the native contract** (approval requests, run progress, policy-change notifications —
the engine event bus already supplies the events). MCP Streamable HTTP endpoint is
optional later, gated on GUI-agent adoption.

### D-5 — Sequencing
1. **Contract sync** (envelope v2, policy/config model, identity/claim format +
   conformance tests + enterprise trust gate F-20260904-01 + log reconciliation) —
   doubles as Strategy A's substrate. **Sync-by-doing as milestone 1 of the server plan,
   not an open-ended catch-up phase.**
2. Server catalog design (`rigorix.*` method catalog) over the synced contracts.
3. Implement both servers in parallel (same fixtures in both CIs).
4. SDK clients per language (now trivial against a frozen, conformance-tested catalog).

### D-6 — Governance invariant
SDK surfaces expose **governed flows only** (plan → enforce → approve → run → audit);
no direct-execute escape hatch (mirrors the demo hook philosophy). Embedded engine use
stays Rust-only via `rigorix-engine`.

## Artifacts
- This freeze: rigorix-sdk `docs/strategy-freeze-2026-09-06.md`
- Sync design: rigorix-sdk `docs/contract-sync-2026-09-06.md`
- Enterprise-side situation + path: `findings/contract-sync-server-plan-2026-09-06.md` in the enterprise repository
- OSS-side pointer: rigorix-oss `docs/sdk-server-strategy-freeze-2026-09-06.md`
