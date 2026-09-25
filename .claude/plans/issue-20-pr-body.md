## Summary

Declares the three ADR-016 Phase B ledger methods the enterprise Execution API
already registers — `rigorix.audit.head` / `.history` / `.overdue` — so the
**closed** `rigorix.*` namespace stays honest (ADR-0001 D3). Same drift class
SDK-C5 (#15) fixed for `rigorix.auth.verify`; now caught by
`verify_catalog_subset`.

Closes #20. **Stacked on #19** (base branch `issue/19`).

## Code truth (enterprise PR #210, merged)

- `catalog.rs` — three `MethodSpec`s: query / `session` / `mcp_tool: None`.
- `dto.rs` — `LedgerHeadParams { producer_id }`,
  `LedgerHistoryParams { producer_id, since? }`,
  `OverdueParams { threshold_secs? }`.
- `adapters.rs` — `head` → `{ producer_id, sequence|null, envelope_hash|null,
  anchor_public_key }`; `history_slice` → the signed `HistorySlice`.
- `services.rs` — `overdue` → `{ threshold_secs, count, runs[] }`
  (`DEFAULT_OVERDUE_SECS = 3600`); `status` is the `RunStatus` snake_case set.

## Changes

**`schemas/api/catalog.json`**
- `rigorix.audit.head` / `.history` / `.overdue` (query / session / no MCP tool,
  `since` 1.0.0) + `$defs` mirroring the enterprise DTOs/adapters.
- `auditHistoryResult` **reuses `api/history-slice.json` by `$id`** (no second
  dialect).

**`rust/rigorix-verifier`**
- `build_validator` registers `api/history-slice.json` as a cross-file resource.
- `catalog_integrity` asserts the three methods' shape + the history-slice reuse.
- The closed-namespace subset test now uses the enterprise **13-method** set.

**Docs** — `schemas/api/method-catalog.md` + contract-sync delta note.

## Drift fixed from code (issue draft)

- Head result also carries `anchor_public_key`, and the head fields are null
  (not the whole object) when a producer has no chain.
- `threshold_secs` is echoed unclamped → plain integer, not `minimum: 0`.
- `status` is the four-value `RunStatus` enum, not a free string.

## Verification

```
cd rust
cargo test --workspace                 # rigorix-schemas 2 + verifier 25 (+1 ignored)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo package -p rigorix-schemas       # verify build OK
```

`catalog_integrity` validates `catalog.json` against `catalog.schema.json`,
resolves every method's refs, and specifically checks the three new methods
(query/session/no-MCP-tool, resolvable refs) and the history-slice reuse. The
subset test proves the enterprise 13-method set passes the guard.

## Acceptance criteria

| # | Criterion | Where |
|---|-----------|-------|
| 1 | Three methods declared with `$defs` | `catalog_integrity` |
| 2 | `history` result reuses `history-slice` | `auditHistoryResult.$ref` assertion |
| 3 | Enterprise 13-method set passes `verify_catalog_subset` | `catalog_subset_guard_rejects_undeclared_method` |
| 4 | Docs + delta note | `method-catalog.md`, contract-sync |
| 5 | CI green | CI |

## Out of scope

- The enterprise implementation (merged) and wiring the guard into enterprise CI.
- Redefining `history-slice.json` (already frozen, reused).
