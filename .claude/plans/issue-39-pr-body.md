## Summary

Freezes the cross-repo **ADR-017 (consequence gating)** contract **before** the
engine implements it: operator precondition config, the additive envelope
evidence, and the denial taxonomy. Contract-first per D-011/D-012.

Closes #39.

## Changes

**`schemas/policy.json`**
- New root `preconditions[]` → `$defs.precondition`: `id`, `match` (reuses the
  frozen `stepPredicate`), `require_params[]` (ADR-015 presence-only),
  `command[]` (argv, no shell), `timeout_ms` (default 5000), `failure`
  (`deny`, the v1-only value), `capture_output` (default false).
- New `$defs.gating`: `release_dependents_on_failure` (default **true** =
  today's behavior; `false` stops a failed step's dependents — R2).
- `$defs.stepRequirement` gains **`require_companion_step = { match }`** (R3,
  closes the ADR-015 companion-step non-goal); description updated.

**`schemas/envelope.json`**
- Additive `precondition_findings[]` → `$defs.preconditionFindingRef`:
  `precondition_id`, `step`, `outcome` (`passed|failed|error|unarmed`),
  `exit_code`, `inputs_hash`, `checked_at`, `summary`.
- **Frozen position**: after `requirement_findings`, before
  `decision_context_ref`. `skip_serializing_if = Vec::is_empty` — an absent list
  leaves legacy chain/HMAC bytes unchanged. Only an `inputs_hash` is recorded
  (never parameter values or stdout).

**`schemas/api/errors.json`**
- `data.precondition_id` + `data.outcome`; `x-precondition-denial` documents a
  precondition refusal as `policy_violation` with **`retryable: false`** (no new
  error type).

**`schemas/fixtures/envelope/envelope-precondition-signed.json`**
- Contract-first signed fixture: three findings covering `failed` (exit 3),
  `passed` (exit 0), and `error` (**`exit_code: null`** — exercises the nullable
  path). Signed with `fixture-hmac-key-2026` by the reference verifier (the
  engine has no ADR-017 code yet); README documents regeneration once Phase B
  lands.

**Verifiers (all five)**
- Rust: `AuditEnvelope.precondition_findings` + `PreconditionFindingRef` at the
  frozen position; `exit_code` always serialized.
- Python / TypeScript / Java / Go: `precondition_findings` added to the
  skip-empty set and nested-`$defs` mapping (field order derives from the
  schema).
- Focused ADR-017 regression test in each: outcome ordering, `exit_code`
  `3/0/null`, byte-exact verify, `inputs_hash` tamper detection, legacy fixture
  unchanged.

`docs/contract-sync-2026-09-06.md` carries the delta note.

## Frozen design choices (engine must follow)

- `precondition_findings[]` **after `requirement_findings`** / **before
  `decision_context_ref`**.
- The finding is **fixed-shape**: `exit_code` is `integer|null` and is always
  serialized (`null` for `error`/`unarmed`).
- `catalog.json` **unchanged (23 methods)** — config + evidence only; no new
  `rigorix.*` method (ADR-0001 D3).

## Verification

```
Rust  cargo test --workspace                 # 27 (+2 ignored)
Py    pytest -q                              # 19
TS    npm test                               # 19
Java  mvn -B verify                          # 17
Go    go vet ./... && go test ./...          # 20
```

All five independently verify `envelope-precondition-signed.json` **byte-exact**
(cross-language parity), including the `exit_code: null` finding.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `policy.json` preconditions + gating (serde-exact) | ✅ |
| 2 | `envelope.json` additive `precondition_findings[]`; absent ⇒ bytes unchanged | ✅ |
| 3 | `errors.json` denial taxonomy (`retryable: false`) | ✅ |
| 4 | Signed fixture verifies byte-exact in Rust/Python/TS/Java/Go | ✅ |
| 5 | Drift CI / `verify_catalog_subset` unaffected | ✅ |
| 6 | `catalog.json` method count unchanged (23) | ✅ |

## Notes

- The fixture is **contract-first**; regenerate from the engine when ADR-017
  Phase B lands (ignored `generate_precondition_fixture` in the Rust verifier).
- No parameter values or stdout enter evidence — only `inputs_hash`.
