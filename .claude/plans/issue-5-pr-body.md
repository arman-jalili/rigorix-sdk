## Summary

Reconciles the SDK contract surface with **rigorix-oss ADR-015 / issue #884**
(operator-controlled step requirements, R9). Grounded in the engine code
(code is truth), not the issue prose:

- `engine/src/sequence_policy/domain/requirement.rs` — `RequirementAction`,
  `StepRequirement`, `RequirementFinding`
- `engine/src/sequence_policy/domain/config.rs` — `SequencePolicyConfig.requirements`
  + R9 `SafetyCaps`
- `engine/src/audit/domain/envelope.rs` — `AuditEnvelope.requirement_findings`,
  `RequirementFindingRef`

Closes #5.

## Changes

**`schemas/policy.json`**
- `$defs.requirementAction` — lowercase `deny` | `promote`, default `deny`.
- `$defs.stepRequirement` — required `id` / `name` / `match`; optional
  `description` (default `""`), `require_identity` (default `false`),
  `require_params` (JSON-pointer array, default `[]`, items `^/`), `action`
  (default `deny`). Root gains the additive `requirements` array (serde field
  on `SequencePolicyConfig`, defaulted empty).
- `$defs.safetyCaps` — adds `max_requirements_per_file` (100) and
  `max_required_params_per_requirement` (16).

**`schemas/envelope.json`**
- Additive `requirement_findings[]` (serde-defaulted,
  `skip_serializing_if = Vec::is_empty`, declared struct position between
  `sequence_policy_findings` and `decision_context_ref`) +
  `$defs.requirementFindingRef` (`requirement_id` / `step` / `action` / `unmet`
  / `summary`). Pointer **names** may be recorded; parameter **values** never
  are (SpanPrivacy).

**Docs** — `schemas/README.md` rows + ADR-015 delta note in
`docs/contract-sync-2026-09-06.md`.

**`rust/rigorix-verifier`** — generalized `validate_schema_file` helper + two
focused conformance tests (policy step-requirement round-trip, envelope
`requirement_findings`). No frozen-struct change: no committed fixture carries
`requirement_findings` yet.

## Drift found and fixed (code is truth)

The issue draft listed `stepRequirement.name` as optional and `action` as
required. The engine struct has `name: String` with **no serde default**
(required) and `#[serde(default)] action: RequirementAction` (optional, default
`deny`). The schema follows the code.

## Validation

```
cd rust
cargo build
cargo test --workspace        # 14 passed (was 12)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo audit                   # 0 advisories
```

## Notes / follow-up

- ADR-015 is still **proposed** in rigorix-oss; #884 is in the engine working
  tree. Contract change is additive + serde-defaulted, so existing
  envelopes/rules validate unchanged (`requirements: []` = status quo).
- The next envelope fixture that carries `requirement_findings` must extend the
  frozen `AuditEnvelope` copy in `rigorix-verifier` (canonicalization parity).
- rigorix-oss conformance against the updated schemas is the cross-repo half of
  the DoD and runs in the engine repo.
