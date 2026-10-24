# Implementation Plan: issue/52

**Branch:** `issue/52`
**Base:** `main` (`9c14d15`, SDK 0.6.0)
**Issue:** #52 — effect-record schema, ambiguous artifact, commitment-evidence verifier
**Severity:** critical / release-trailing (blocks the OSS 1.11.0 trust claim)

## Status

- [x] Upstream contract derived from code (OSS engine + enterprise wire)
- [x] Decisions confirmed (artifact shape; level semantics)
- [x] `schemas/api/effect-record.json` frozen
- [x] 12 fixtures (5 accepted, 7 rejected)
- [x] Typed mirror + `verify_effect_record` + `verify_settlement_evidence`
- [x] Corpus regenerated (Go, Python, TypeScript)
- [x] Full deterministic gate green
- [ ] MR created
- [ ] Merged

## Decisions (review-confirmed)

1. **Artifact shape = wire record + sibling settlement.** `record` mirrors the
   frozen enterprise `EffectRecordResponse` exactly. `settlement` mirrors the OSS
   `ObservedOutcome` (`receipt_id`, `readback_digest`, `observed_at`, `source`,
   `verdict`) plus the raw provider read-back bytes and an optional resolver.
2. **`levels` = the producing deployment's claim, on two axes.** `durability`
   `l1|l2`, `settlement` `none|l3`; orthogonal (`l1` + `l3` is legal). A dispatched
   record from an L3 deployment may say `l3` while carrying no settlement object.
   This avoids the #1182 single-scalar defect.

## Grounding (code is truth)

| Field | Source |
|---|---|
| `record.*` | enterprise `interfaces/http/dto.rs` → `EffectRecordResponse`; `EffectRecordView` for `deadline` |
| `record.intent_key` | enterprise `IntentKey` — 64 lowercase hex |
| `record.state` | OSS `domain/state.rs` → `EffectState` |
| `settlement.*` | OSS `domain/outcome.rs` → `ObservedOutcome` + `OutcomeVerdict` |
| `readback_digest` | OSS `infrastructure/provider_receipt.rs:222` — `hex(Sha256::digest(body))` |
| `resolver.kind` | enterprise `domain/value.rs` → `ResolverKind` |
| `levels.*` | OSS runbook + #1182 (durability/settlement axes) |

## Deliverables

| File | Change |
|---|---|
| `schemas/api/effect-record.json` | **new** frozen v1 artifact schema; ceiling stated |
| `schemas/fixtures/effect/` | **new** 5 accepted + 7 rejected fixtures + README |
| `rust/rigorix-verifier/src/lib.rs` | typed mirror (`EffectState`, `OutcomeVerdict`, `ResolverKind`, `EffectRecord`, `SettlementEvidence`, `ClaimLevels`, `EffectRecordArtifact`), 3 error variants, 2 verifiers, 9 tests |
| `go/internal/corpus/corpus_gen.go` | regenerated (48 files) |
| `schemas/README.md`, `schemas/api/README.md` | catalog rows |
| `docs/contract-sync-2026-10-24-effect-record.md` | delta note + decision record |

## Verification model

- **Structural:** terminal ⇒ settlement; non-terminal ⇒ no settlement (outcome or
  resolver); `dispatched` ⇒ deadline; verdict ⇒ terminal state; evidence ⇒
  `levels.settlement = l3`.
- **Readback:** `hex(SHA-256(readback bytes)) == readback_digest`; missing bytes
  are refused (`ReadbackMissing`), never downgraded.
- **Ceiling:** no envelope binding. The record is unsigned and the intent is not
  derivable from the envelope; authenticity is the envelope chain + receipt.

## Commands run

```
rust: build, test --all (38 verifier), clippy -D warnings, fmt --check   ✅
python: pytest (19)                                                      ✅
typescript: verifier (19) + client (10)                                  ✅
go: go test ./...                                                        ✅
java: mvn -B -q verify                                                   ✅
validators: ci/tests/security/operations/canonical/architecture/integration ✅
corpora regenerated: go 48, python 48, typescript 48                     ✅
```

## Acceptance criteria (#52)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `rigorix-schemas`: effect-record schema + fixture, id, invariants as schema + verifier checks | ✅ |
| 2 | `rigorix-verifier`: typed mirror + `verify_effect_record` + `verify_settlement_evidence`, existing `VerifyError` | ✅ |
| 3 | Rejected fixture per invariant (terminal w/o evidence, dispatched w/ outcome, digest mismatch) | ✅ (+4 more) |
| 4 | Schema text states the ceiling: no envelope binding | ✅ |
| 5 | `0.7.0` released once OSS 1.11.0 is tagged | ⏳ contract frozen; release gated |

## Release gate

OSS 1.11.0 is at `1.11.0` in `Cargo.toml` but the latest tag is `v1.9.5`. This PR
freezes the contract; it does not bump or publish 0.7.0. Once OSS 1.11.0 is
tagged, the 0.7.0 release commit can ship with this schema + verifier.
