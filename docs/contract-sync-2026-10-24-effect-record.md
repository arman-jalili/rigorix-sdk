# Contract sync — effect-record artifact (SDK 0.7.0)

**Date:** 2026-10-24
**Issue:** #52
**Status:** frozen (`schemas/api/effect-record.json`, `$id`
`https://rigorix.eu/schemas/api/effect-record-v1.json`)
**Upstream:** rigorix-oss 1.11.0 (engine + ADR-019), enterprise consumer
(`EffectRecordResponse`)

## Why

OSS 1.11.0 ships the effect-commitment bounded context: a write-ahead record with
a non-terminal `Ambiguous` state, a resolver authority, and an L2 wire contract.
At SDK 0.6.0 the SDK knew nothing about it, so a deployment could produce
commitment evidence that no third party could check without our code — the exact
claim the SDK exists to make true. The contract lands here first, before the
servers claim it.

## Decisions (review-confirmed, not implementer choices)

1. **Artifact shape = wire record + sibling settlement.** The `record` section
   mirrors the frozen enterprise `EffectRecordResponse` exactly (that is what an
   operator exports). The `settlement` section mirrors the OSS `ObservedOutcome`
   (`receipt_id`, `readback_digest`, `observed_at`, `source`, `verdict`) plus the
   raw provider read-back bytes and an optional resolver. The engine aggregate
   was not chosen: it is richer in one place and poorer in `attempt` / `deadline`
   / `dispatched_by`.
2. **`levels` describes the producing deployment, on two independent axes.**
   `durability: l1|l2` (in-process vs shared/durable) and
   `settlement: none|l3` (can the deployment prove settlement). They are
   orthogonal: `l1` + `l3` is legitimate. This deliberately avoids the #1182
   defect where one scalar `L3` implied durability. Because these are deployment
   claims, a `dispatched` record may say `settlement: l3` while carrying no
   settlement object.

## Grounding (code is truth)

| Artifact field | Source |
|---|---|
| `record.*` | enterprise `effect_commitment/interfaces/http/dto.rs` → `EffectRecordResponse`; `EffectRecordView` for `deadline` (set only while dispatched) |
| `record.intent_key` | enterprise `IntentKey` — 64 lowercase hex (`H(dag_id, node_id, intent_digest)`) |
| `record.state` | OSS `effect_commitment/domain/state.rs` → `EffectState` (four snake_case words) |
| `settlement.*` | OSS `effect_commitment/domain/outcome.rs` → `ObservedOutcome` + `OutcomeVerdict` |
| `settlement.readback_digest` | OSS `infrastructure/provider_receipt.rs:222` — `hex(Sha256::digest(body))` |
| `settlement.resolver.kind` | enterprise `domain/value.rs` → `ResolverKind` (`operator`/`reconciler`/`break_glass`) |
| `levels.*` | OSS runbook effect-commitment + issue #1182 (durability/settlement axes) |

## Verification

- **Structural** (`verify_effect_record`): terminal ⇒ settlement; non-terminal ⇒
  no settlement (outcome or resolver); `dispatched` ⇒ deadline; verdict ⇒
  terminal state; evidence ⇒ `levels.settlement = l3`.
- **Readback** (`verify_settlement_evidence`): `hex(SHA-256(readback bytes))`
  must equal `readback_digest`. Missing bytes are refused, not downgraded.

**Ceiling (stated in the schema):** no envelope binding. The record is unsigned
and its intent is not derivable from the audit envelope; authenticity rests on
the signed envelope chain and the provider receipt.

## Fixtures

`schemas/fixtures/effect/` — five accepted cases (including `l1` + `l3`) and
seven rejected cases, one per invariant plus three at the readback layer. See the
[fixture README](../../schemas/fixtures/effect/README.md). These are
contract-first: regenerate from the engine once it exports the artifact.

## Surface impact

- **Additive only.** New schema file; no catalog method, no changed method, no
  removed field. `catalog.json` remains 24 methods.
- Corpus regeneration is required for consumers that vendor `schemas/`
  (Go corpus, Python `_schemas`, TypeScript `_schemas`).
- No Python/TypeScript/Java/Go verifier code change: those verifiers iterate the
  envelope/anchor fixtures and validate through the corpus; the new schema is
  embedded by the existing bundle scripts. The typed mirror and verification
  functions are Rust (`rigorix-verifier`), as the issue requires.

## Release gate

`0.7.0` ships **after** OSS 1.11.0 is tagged, so "the newest evidence type is
independently verifiable" is true at the next OSS release. This PR freezes the
contract; it does not publish.
