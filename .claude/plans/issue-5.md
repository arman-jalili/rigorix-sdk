# Implementation Plan: issue/5

**Branch:** `issue/5`
**Base:** `main` (6cf715e)
**Issue:** #5 — schemas: operator step-requirements in policy.json + envelope.json (ADR-015)

## Code truth (rigorix-oss working tree, ADR-015 / issue #884)

Grounded in:
- `engine/src/sequence_policy/domain/requirement.rs` — `RequirementAction`, `StepRequirement`, `RequirementFinding`
- `engine/src/sequence_policy/domain/config.rs` — `SequencePolicyConfig.requirements`, new `SafetyCaps` fields
- `engine/src/audit/domain/envelope.rs` — `AuditEnvelope.requirement_findings`, `RequirementFindingRef`
- `.pi/architecture/decisions/ADR-015-operator-step-requirements.md`

### Drift vs the issue draft (fix draft from code — never invent)

| Item | Issue draft | Code truth |
|---|---|---|
| `stepRequirement.name` | optional | **required** (`String`, no serde default) |
| `stepRequirement.description` | optional | optional, serde default `""` |
| `stepRequirement.action` | required | optional, serde default `deny` |
| `safetyCaps` | not mentioned | gains `max_requirements_per_file` (100) + `max_required_params_per_requirement` (16) |

Confirmed matches: `requirementAction` = lowercase `deny`/`promote`; `require_identity` bool default false;
`require_params` pointer array default `[]`; envelope `requirement_findings[]` serde-defaulted/skip-when-empty;
`RequirementFindingRef` = `requirement_id`, `step`, `action`, `unmet`, `summary`.

## Steps

1. `schemas/policy.json`
   - add `$defs.requirementAction` (enum deny|promote, default deny)
   - add `$defs.stepRequirement` (required id/name/match; optional description/require_identity/require_params/action)
   - add root `requirements` array property (serde field on `SequencePolicyConfig`)
   - extend `$defs.safetyCaps` with the two R9 caps
2. `schemas/envelope.json`
   - add root `requirement_findings` array (after `sequence_policy_findings`, struct order)
   - add `$defs.requirementFindingRef`
3. `schemas/README.md` — row updates for policy.json + envelope.json
4. `docs/contract-sync-2026-09-06.md` — ADR-015 delta note
5. `rust/rigorix-verifier` — schema-conformance tests for both new shapes (no frozen-struct change: no fixture carries `requirement_findings`)

## Validation

- [x] `cargo build` (rust/)
- [x] `cargo test --workspace` green (14 passed, was 12)
- [x] `cargo clippy --all-targets -- -D warnings`
- [x] `cargo fmt --check`
- [x] schema JSON parses + compiles (all_schemas_compile)
- [x] `cargo audit` (0 advisories)

## Status

- [x] Implemented + committed (`1abc4cb`)
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
