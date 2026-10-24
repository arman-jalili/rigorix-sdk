# rigorix-sdk schemas — single source of truth

Contract-first schemas for Rigorix audit, identity, and policy surfaces.
Grounded in rigorix-oss Rust types (code is truth) and reconciled with
rigorix-enterprise consumers via contract-sync milestone 1 (delta maps).
Contract changes are DECISIONS (see AGENTS.md + docs/strategy-freeze).

## Catalog

| Schema | Status | Grounds (code is truth) | Notes |
|---|---|---|---|
| `envelope.json` | **format v2 / schema rev 1** (2026-09-07, freeze 2026-09-19) | rigorix-oss `engine/src/audit/domain/envelope.rs`, `identity/domain/claim.rs` | Envelope **format v2** (`$id` `envelope-v2.json`) — carries the additive approval/identity/sequence-policy blocks. Full reconciliation vs v0 draft: EventStatus serde-exact values (Success/Failure/Skipped/Cancelled — no rename_all), `decision_context_ref` corrected (string ref, not object), all `$defs` completed. Canonicalization contract for HMAC documented in the schema description. Consumers key on `$id`. ADR-014: additive `effect_key` (string, omitted when absent) — one-way keyed hash, never raw params. ADR-015: additive `requirement_findings[]` (R9 operator step-requirement evidence — `requirement_id`/`step`/`action`/`unmet`/`summary`; pointer names only, values never recorded; serde-defaulted, omitted when empty). ADR-016 (Phase A): additive chain fields `producer_id`/`sequence`/`prev_hash`/`history_integrity`/`history_policy` (serde-defaulted, omitted when absent) mirroring the engine struct field order (`history_integrity` ∈ `local_unanchored`/`anchored`/`anchored_pending`; only `anchored` asserts a verified head); `prev_hash`/`envelope_hash` use the SAME canonical bytes as the HMAC (`signature` nulled). Fixtures: `fixtures/integrity/chain.json` (engine-signed). |
| `claims.json` | **v1** (2026-09-07) | rigorix-oss `engine/src/identity/domain/claim.rs` | IdentityClaim (full, root) + IdentityRef (redacted, `$defs`) — serde-stable, Options always serialized as null (no skips on IdentityClaim). Raw JWT claim sets are an extension slot (enterprise delta map). |
| `policy.json` | **v1** (2026-09-07) | rigorix-oss `engine/src/sequence_policy/domain/rule.rs` + `config.rs`, `configuration/domain/config.rs` | SequenceRule/StepPredicate/ParamPredicate/HistoryPredicate/RuleAction semantics; SafetyCaps + root-config surface for cross-tool alignment. Enterprise policy-bundle exports must emit rule semantics in this shape. ADR-014: `paramPredicate.kind` += `equals_step` (+ optional `step` index, value optional); `historyPredicate.effect_key` (bool, default false). ADR-015: root `requirements[]` (`StepRequirement`: required `id`/`name`/`match` — `name` has no serde default; optional `description`/`require_identity`/`require_params`/`action`; `requirementAction` = `deny`|`promote`, default `deny`); `SafetyCaps` += `max_requirements_per_file` / `max_required_params_per_requirement`. |
| `api/catalog.json` | **v1** (2026-09-19, FROZEN) | rigorix-sdk `docs/adr/ADR-0001-native-api-catalog.md`; rigorix-oss MCP tool descriptors + `*/application/dto` | Frozen `rigorix.*` JSON-RPC catalog: 24 methods (name/kind/auth/params+result refs, MCP adapter mapping). Additive-only within `apiVersion` major. `transport.push` carries `schema: "api/events.json"` (ADR-0002). |
| `api/catalog.schema.json` | **v1** (2026-09-19, FROZEN) | ADR-0001 | JSON Schema describing the `catalog.json` data document (including the `transport.push` schema ref). |
| `api/errors.json` | **v1** (2026-09-19, FROZEN) | ADR-0001 D6; rigorix-oss `EngineFacadeError`/`ProxyError` categories | JSON-RPC error model. Stable machine id in `data.type`; `denied_by_sequence` carries `rule_id` + `step`. |
| `api/events.json` | **v1** (2026-09-24, FROZEN) | ADR-0002 / SDK-C1; rigorix-oss `server/src/events.rs` (`ServerEvent`) + `engine/.../event.rs` (`event_type_name()`) | SSE push channel: the three ADR-0001 D8 payloads as a `oneOf` discriminated union on the `event:` name; `data` `$ref`s `envelope.json#/$defs/executionEventRef` (no second dialect); `x-engine-event-mapping` maps all 24 engine `ExecutionEvent` variants (5 host-telemetry ones not pushed). Fixtures in `fixtures/events/`. |
| `api/ledger-receipt.json` | **v1** (2026-09-24, FROZEN) | ADR-016 (Contract) | Anchor-signed ledger receipt `{ ledger_id, envelope_hash, sequence, recorded_at, sig }` — Ed25519 over the canonical bytes (`sig` nulled). Fixture in `fixtures/integrity/`. |
| `api/history-slice.json` | **v1** (2026-09-24, FROZEN) | ADR-016 (Contract); engine `HistoryAction` | Anchor-signed history projection `{ scope, since, actions[], head_hash, sig }` the guard consumes in `anchored` mode; actions mirror `HistoryAction` (no parameter values). Fixture in `fixtures/integrity/`. |
| `api/compaction-checkpoint.json` | **v1** (2026-09-24, FROZEN) | ADR-016 (Contract, GDPR/compaction) | Anchor-signed compaction proof `{ sequence_from, sequence_to, reason, prior_head, new_head, sig }`; a verifier accepts a chain gap iff covered by a valid checkpoint. Fixture in `fixtures/integrity/`. |
| `api/authority-fact-bundle.json` | **v1** (2026-10-13, FROZEN) | rigorix-oss `engine/src/audit/domain/authority_fact.rs` (`AuthorityFactBundle`/`AuthorityFactProjection`/`AuthorityFact`) + `docs/spec/consequence-gating-v1.md` §4.3 | The authority-fact projection bundle: projection + the signed history it was derived from + `subjects_without_record`. `envelopes[]` `$ref`s `envelope.json` by `$id` (no second dialect). Verified by re-derivation, not signature (§4.3.1). `generated_at` is not compared. |
| `api/effect-record.json` | **v1** (2026-10-24, FROZEN) | rigorix-oss `effect_commitment/domain/{state,outcome}.rs` + `infrastructure/provider_receipt.rs`; rigorix-enterprise `effect_commitment/interfaces/http/dto.rs` (`EffectRecordResponse`) | Effect-commitment artifact = the frozen wire record + the provider evidence that settled it (`ObservedOutcome` + the raw read-back bytes + optional resolver) + two independent deployment axes (`durability` l1/l2, `settlement` none/l3). Terminal ⇒ evidence, non-terminal ⇒ none, dispatched ⇒ deadline. Verified structurally and by re-deriving `readback_digest`; **no envelope binding**. Fixtures in `fixtures/effect/`. |
| `api/method-catalog.md` | sketch (2026-09-06, historical) | — | Pre-freeze sketch. **Superseded by `api/catalog.json` + ADR-0001**; kept as history. |

## Conformance fixtures (milestone 1)

`fixtures/` is the home for real run artifacts (signed envelopes produced by
real engine runs with fixed keys) — produced by the rigorix-oss conformance
session (F-20260907-01), verified against `envelope.json` and byte-exact
HMAC-verifiable by `rigorix-verifier` from any language.

`fixtures/integrity/` (ADR-016 / SDK-AUDIT-A) adds an engine-signed per-producer
`chain.json` (+ a `broken-chain.json`) and the three anchor-artifact contract
fixtures (ledger receipt / history slice / compaction checkpoint, Ed25519-signed
with a documented test-only key). `rigorix-verifier` verifies the chain, rejects
a broken one, and accepts a gap iff covered by a valid signed checkpoint.

`fixtures/effect/` (ADR-019 / SDK 0.7.0) holds the effect-commitment artifact
cases: five accepted (including `l1` durability + `l3` settlement) and one
rejected fixture per invariant, plus readback mismatches. Contract-first until
the engine exports the artifact.

## Verifier

`../rust/rigorix-verifier` — protocol-only Rust crate (no rigorix-engine dep):
HMAC-SHA256 integrity over the documented canonical form + JSON Schema
conformance. Frozen struct copies of the envelope contract.

## Validation

```bash
# schemas are valid JSON; verifier tests exercise schema + HMAC semantics
cd rust && cargo test
```
