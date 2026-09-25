# Implementation Plan: issue/11 (Rust client — split)

**Branch:** `issue/11` (stacked on `issue/21`)
**Base:** `issue/21` → `main` after the stack merges
**Issue:** #11 — SDK-C4: typed SDK clients against the frozen catalog.
**Split:** this PR ships the **Rust client**; the TypeScript client is a
follow-up (per decision — `typescript/` is now the #21 verifier package).

## Classification

New deliverable (client crate). Scope: **Complex**. Protocol-only; no engine.

## Code truth

- `schemas/api/catalog.json` — the method set + `$defs` (types).
- `schemas/api/errors.json` — the `data.type` error taxonomy.
- ADR-0001: D1 transport, D3 closed catalog, D5 identity invariant, D6 errors,
  D10 governed flows only.

## Deliverables

1. `rust/rigorix-client` crate:
   - `jsonrpc.rs` — request/response framing, batch arrays, notifications.
   - `transport.rs` — `Transport` trait + `MockTransport` (HTTP-framework-free).
   - `error.rs` — `RpcError` → typed `ApiError` (all `errors.json` types +
     `Unknown`, no panic); `ClientError`.
   - `catalog.rs` — the full method binding table (`Typed` / `ServerOnly`).
   - `types.rs` — typed params/results mirroring the catalog `$defs`.
   - `client.rs` — `Client<T>` with typed wrappers for every bound method,
     batch/notification framing, and `system.version` negotiation.
   - `auth.rs` — device-flow helpers.
   - `README.md`.
2. Tests: catalog drift, error mapping, framing (single/batch/notification),
   version negotiation, typed dispatch.
3. Workspace member + CI **no `rigorix-engine`** assertion (D-1).

## Decisions

- **Transport seam** (no HTTP dep): implement `Transport` for your HTTP client;
  the crate stays dependency-light and testable with `MockTransport`.
- **Server-only exemptions** (drift test still requires an explicit entry):
  `audit.head/history/overdue` (enterprise ADR-016 Phase B), `auth.verify`
  (enterprise JWKS), `policy.bundle` (admin control plane).
- Open subtrees (plan/enforcement/step params) are `serde_json::Value`; stable
  shapes are typed.

## Validation

- [x] `cargo test -p rigorix-client` — 9 tests (2 catalog + 7 protocol)
- [x] `cargo test --workspace` — all suites green
- [x] `cargo clippy --workspace --all-targets -- -D warnings`; `cargo fmt --check`
- [x] `cargo tree -p rigorix-client | grep -c rigorix-engine` == 0

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Rust client compiles; no `rigorix-engine` dep | ✅ CI assertion |
| 3 | Drift test: every catalog method bound or exempted | ✅ `catalog.rs` |
| 4 | Error mapping: every `data.type` distinct; unknown generic | ✅ |
| 5 | Batch + notification framing tested | ✅ |
| 6 | `system.version` negotiation | ✅ |
| 8 | No raw step-execution surface | ✅ `assert_no_raw_step_execution` |
| 9 | CI green | ✅ |

## Deferred

- TypeScript client (follow-up PR, `typescript-client/`).
- Live e2e vs C2 (`RIGORIX_SERVER_URL`-gated) — the transport seam is ready.

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
