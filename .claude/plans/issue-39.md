# Implementation Plan: issue/39

**Branch:** `issue/39`
**Base:** `main`
**Issue:** #39 — freeze precondition config + envelope `precondition_findings`
(ADR-017)

## Classification

Contract change (additive, contract-first). Scope **Complex**; touches schema +
all five verifiers + fixture + docs. No engine implementation.

## Source of truth

`rigorix-oss` ADR-017 (`engine/.pi/architecture/decisions/ADR-017-consequence-gating.md`)
+ module `consequence-gating.md` (present locally, not yet on `origin/main`; the
engine has **no** precondition code — this is the deliberate contract-first
freeze per D-011/D-012).

## Frozen decisions (contract-first — the engine must follow)

- **Field position**: envelope `precondition_findings[]` sits **after
  `requirement_findings`, before `decision_context_ref`** (last additive finding
  list, before the trailing decision ref). Declared in `envelope.json`
  properties order; the Rust frozen struct mirrors it.
- **Fixed-shape finding**: `precondition_id`, `step`, `outcome`, `exit_code`,
  `inputs_hash`, `checked_at`, `summary` — all present. `exit_code` is
  `integer|null` and is **always serialized** (no `skip_serializing_if`) so the
  JSON is `null` for `error`/`unarmed`; `skip-if-empty` applies to the list.
- **Outcome** = `passed | failed | error | unarmed` (serde snake_case).
- **Error taxonomy**: a precondition refusal is `policy_violation` with
  `data.precondition_id`/`data.step`/`data.outcome`, `retryable: false` — no new
  error type, no new catalog method.

## Changes

- `schemas/policy.json` — `preconditions[]` + `$defs.precondition`,
  `$defs.gating`, `require_companion_step` on `$defs.stepRequirement`; top
  description.
- `schemas/envelope.json` — `precondition_findings` property +
  `$defs.preconditionFindingRef`; top description.
- `schemas/api/errors.json` — `data.precondition_id`/`outcome` +
  `x-precondition-denial` (`retryable:false`).
- `schemas/fixtures/envelope/envelope-precondition-signed.json` +
  README row/note.
- Rust: `AuditEnvelope.precondition_findings` + `PreconditionFindingRef` +
  ignored generator + focused test.
- Python/TS/Java/Go: skip-empty set + nested def mapping + focused test.
- `docs/contract-sync-2026-09-06.md` delta note.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `policy.json` preconditions + gating + companion-step (serde-exact) | ✅ |
| 2 | `envelope.json` additive `precondition_findings[]`; absent ⇒ bytes unchanged | ✅ |
| 3 | `errors.json` denial taxonomy (`retryable:false`) | ✅ |
| 4 | Signed fixture verifies byte-exact in Rust/Python/TS/Java/Go | ✅ 27/19/19/17/20 |
| 5 | OSS+enterprise drift CI unaffected; `verify_catalog_subset` unaffected | ✅ catalog 23 unchanged |
| 6 | `catalog.json` method count unchanged (23) | ✅ |

## Status

- [x] Implemented
- [x] Local checks green (5 languages)
- [ ] MR pushed / merged
