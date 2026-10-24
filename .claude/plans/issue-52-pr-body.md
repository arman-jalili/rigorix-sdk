## Summary

Closes #52. OSS 1.11.0 ships the effect-commitment bounded context, but the SDK
at 0.6.0 knew nothing about it — a deployment could produce commitment evidence
that no third party could check without our code. This freezes the artifact
contract and makes the newest evidence type independently verifiable.

## Decisions (review-confirmed)

1. **Wire record + sibling settlement.** `record` mirrors the frozen enterprise
   `EffectRecordResponse` exactly (what an operator exports). `settlement`
   mirrors the OSS `ObservedOutcome` (`receipt_id`, `readback_digest`,
   `observed_at`, `source`, `verdict`) plus the exact provider read-back bytes
   and an optional resolver.
2. **`levels` = deployment claim on two axes.** `durability: l1|l2`,
   `settlement: none|l3`, orthogonal — `l1` + `l3` is legal. A dispatched record
   from an L3-capable deployment may say `l3` while carrying no settlement
   object. No single scalar (the #1182 defect).

## What changed

| File | Change |
|---|---|
| `schemas/api/effect-record.json` | **new** frozen v1 schema; ceiling stated in its own text |
| `schemas/fixtures/effect/` | **new** 5 accepted + 7 rejected fixtures (README included) |
| `rust/rigorix-verifier/src/lib.rs` | typed mirror, 3 error variants, `verify_effect_record` (structural), `verify_settlement_evidence` (readback), 9 tests |
| `go/internal/corpus/corpus_gen.go` | regenerated (48 files) |
| `schemas/README.md`, `schemas/api/README.md` | catalog rows |
| `docs/contract-sync-2026-10-24-effect-record.md` | delta note + grounding + release gate |

### Verification levels

- **Structural:** terminal ⇒ evidence; non-terminal ⇒ no outcome/resolver;
  `dispatched` ⇒ deadline; verdict ⇒ terminal state; evidence ⇒
  `levels.settlement = l3`.
- **Readback:** `hex(SHA-256(readback bytes)) == readback_digest`. Missing bytes
  are refused (`ReadbackMissing`), not silently downgraded.
- **Ceiling:** **no envelope binding.** The record carries no signature and its
  intent is not derivable from the audit envelope; authenticity rests on the
  signed envelope chain and the provider receipt. This is stated in the schema.

### Rejected fixtures (one per invariant, plus the readback layer)

- terminal record with no evidence
- dispatched record carrying an outcome/resolver
- dispatched record with no deadline
- verdict that does not authorise the terminal state
- receipt digest that does not match the carried bytes
- terminal record with no readback bytes (readback claim refused)
- evidence present while `levels.settlement = none`

## Verification

```
rust: build, test --all (38 verifier), clippy -D warnings, fmt --check   ✅
python: pytest (19)                                                      ✅
typescript: verifier (19) + client (10)                                  ✅
go: go test ./...                                                        ✅
java: mvn -B -q verify                                                   ✅
validators: ci/tests/security/operations/canonical/architecture/integration ✅
corpora regenerated: go 48, python 48, typescript 48                     ✅
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Schema + fixture, embedded with an id; invariants as schema + verifier checks | ✅ |
| 2 | Typed mirror + both verifiers, existing `VerifyError` vocabulary | ✅ |
| 3 | Rejected case per invariant (terminal w/o evidence, dispatched w/ outcome, digest mismatch) | ✅ (+4) |
| 4 | Schema text states the ceiling: no envelope binding | ✅ |
| 5 | `0.7.0` released once OSS 1.11.0 is tagged | ⏳ contract frozen; release gated |

## Release gate

OSS `Cargo.toml` is at `1.11.0`, but the latest tag is `v1.9.5`. This PR does not
bump or publish 0.7.0; it freezes what 0.7.0 will ship. Once OSS 1.11.0 is
tagged, the release can proceed.
