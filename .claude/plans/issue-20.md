# Implementation Plan: issue/20

**Branch:** `issue/20` (stacked on `issue/19`)
**Base:** `issue/19` → `main` after the publishing stack merges
**Issue:** #20 — SDK-CATALOG-AUDIT: declare `rigorix.audit.head` / `.history` /
`.overdue` (ADR-016 Phase B surface)

## Classification

Contract change (additive catalog methods). Scope: **Complex**.

## Code truth (grounded)

`rigorix-enterprise` PR #210 (merged):
- `core/src/execution_api/application/catalog.rs` — the three `MethodSpec`s
  (query / `AuthLevel::Session` / `mcp_tool: None`) and dispatch arms.
- `core/src/execution_api/application/dto.rs` — `LedgerHeadParams`,
  `LedgerHistoryParams`, `OverdueParams`.
- `core/src/execution_api/application/services.rs` — `overdue` result
  `{ threshold_secs, count, runs[{ execution_id, status, registered_at }] }`,
  `DEFAULT_OVERDUE_SECS = 3600`; history defaults `since` to the epoch.
- `core/src/execution_api/infrastructure/adapters.rs` — `head` result
  `{ producer_id, sequence|null, envelope_hash|null, anchor_public_key }`;
  `history_slice` serializes `HistorySlice`.
- `core/src/execution_api/domain/value.rs` — `RunStatus` snake_case set.

## Drift vs the issue draft (fix from code)

- The issue's head result was `{ producer_id, sequence, envelope_hash }`; the
  adapter also emits **`anchor_public_key`** and makes the head fields null
  (not the object) when there is no chain. Schema mirrors the code.
- `threshold_secs` is echoed unclamped (could be negative), so it is a plain
  integer, not `minimum: 0`.
- `status` is the four-value `RunStatus` serde set, not a free string.

## Deliverables

1. `schemas/api/catalog.json` — 3 methods + `$defs` (`auditHeadParams/Result`,
   `auditHistoryParams/Result`, `auditOverdueParams/Result`);
   `auditHistoryResult` `$ref`s `api/history-slice-v1.json` (reuse).
2. `rust/rigorix-verifier` — register `api/history-slice.json` as a cross-file
   resource in `build_validator`; `catalog_integrity` asserts the three methods'
   shape + the history reuse; the closed-namespace subset test uses the
   enterprise 13-method set.
3. `schemas/api/method-catalog.md` — list the three methods.
4. `docs/contract-sync-2026-09-06.md` — delta note.

## Validation

- [x] `cargo test --workspace` — rig. schemas 2 + verifier 25 (+1 ignored)
- [x] `cargo clippy --all-targets -- -D warnings`; `cargo fmt --check`
- [x] `cargo package -p rigorix-schemas` — verify build OK
- [x] catalog.json parses + validates against catalog.schema.json (catalog_integrity)
- [x] `verify_catalog_subset` passes the enterprise 13-method set

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
