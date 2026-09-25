## Summary

Ships the **Rust** half of SDK-C4: a protocol-only typed client for the frozen
`rigorix.*` JSON-RPC catalog. It mirrors the catalog `$defs`, speaks JSON-RPC
2.0 over `POST /rpc` (single/batch/notification), maps the `errors.json`
taxonomy, and enforces the two invariants that matter: **governed flows only**
(no raw step execution) and **no `rigorix-engine` dependency**.

Part of #11 (does **not** close it — the TypeScript client is the follow-up).
**Stacked on #21** (base branch `issue/21`). The TS client will live in
`typescript-client/` because `typescript/` is now the #21 verifier package.

## Changes

**`rust/rigorix-client/`** (new workspace member)
- `jsonrpc.rs` — request/response framing, batch arrays, notifications.
- `transport.rs` — `Transport` trait + `MockTransport`; the crate depends on no
  HTTP framework (implement `Transport` for reqwest/ureq).
- `error.rs` — `RpcError` → typed `ApiError`: every `errors.json` `data.type`
  maps to a distinct variant; unknown → `ApiError::Unknown` (never panics).
- `catalog.rs` — the full method binding table (`Typed` / `ServerOnly`).
- `types.rs` — typed params/results mirroring the catalog `$defs`.
- `client.rs` — `Client<T>` with typed wrappers, batch/notification framing, and
  `system.version` negotiation (API-major constraint).
- `auth.rs` — device-flow helpers; `README.md`.

**CI** — `rigorix-client` has no `rigorix-engine` dependency (ADR-0001 D-1);
the workspace test job already runs the client suite.

## Catalog drift

`catalog_drift` reads `schemas/api/catalog.json` (embedded via `rigorix-schemas`,
a dev-dependency) and asserts the client binding table mirrors it exactly —
every method is either typed or explicitly server-only. Server-only exemptions:
`audit.head`/`.history`/`.overdue` (enterprise Phase B), `auth.verify`
(enterprise JWKS), `policy.bundle` (admin control plane). A raw
step-execution method is impossible by construction and asserted against.

## Verification

```
cd rust
cargo test -p rigorix-client            # 9 tests (2 catalog + 7 protocol)
cargo test --workspace                  # all suites green
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --check
cargo tree -p rigorix-client | grep -c rigorix-engine   # 0
```

Covered by tests: single-call framing + typed result, notification has no `id`,
batch is one JSON array, RPC error → typed `denied_by_sequence`, version
matching/mismatch, protocol error, catalog drift, and full error-taxonomy
mapping.

## Acceptance criteria (Rust half)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | No `rigorix-engine` dep (CI assertion) | ✅ |
| 3 | Drift test: every method bound or exempted | ✅ |
| 4 | Error taxonomy maps every type; unknown generic | ✅ |
| 5 | Batch + notification framing tested | ✅ |
| 6 | `system.version` negotiation | ✅ |
| 8 | No raw step-execution surface | ✅ |
| 9 | CI green | ✅ |

## Deferred (follow-up)

- **TypeScript client** at `typescript-client/` (types/transport/error/drift).
- Live e2e against C2 `rigorix-server` (env-gated); the transport seam is ready.
- `cargo package` for the client follows the same prerequisite as #19
  (`rigorix-schemas` on crates.io, because the drift test needs it as a dev-dep).

## Out of scope

- The verifier crate (#18/#19) and the multi-language verifiers (#21).
- Publishing client packages.
