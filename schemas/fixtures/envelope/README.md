# Envelope conformance fixtures (F-20260907-01)

Real signed audit envelopes produced by **actual rigorix-oss engine runs**
(the real `AuditEnvelopeFactoryImpl`, real drained event payloads — never
hand-rolled JSON), committed here as the conformance corpus.

## HMAC key

All signatures use the **test-only** key:

```
fixture-hmac-key-2026
```

This key exists ONLY so fixtures can be re-verified independently; it must
never be used for live envelopes. Live envelopes are signed with per-deployment
keys held in the engine configuration.

## Files

| File | Variant |
|------|---------|
| `envelope-minimal-signed.json` | Minimal signed envelope (single tool event) |
| `envelope-unsigned-degraded.json` | Unsigned run — `evidence_degraded=true` (GAP-M-12), no signature |
| `envelope-rich-signed.json` | Rich: identity + approval_events + scope_violations + sequence_policy_findings + scoring_results + decision_context_ref |
| `envelope-sequence-denied-signed.json` | Dispatch-boundary deny recorded (`sequence_policy_denied`) |
| `envelope-rich-pre-identity.json` | Rich additive blocks without the identity block (pre-identity shape) |
| `envelope-effect-key-signed.json` | ADR-014: run-level `effect_key` (one-way keyed hash) recorded — effect-keyed history input |
| `envelope-anchored-signed.json` | ADR-016 Phase C: anchored run — `history_integrity=anchored` + signed `anchor_head` (the verified ledger head), placed after `history_policy` / before `approval_events` |
| `envelope-precondition-signed.json` | ADR-017: dispatch-time `precondition_findings[]` (`passed` / `failed` / `error`; `exit_code` + `inputs_hash`; no parameter values) |

Each file validates against `schemas/envelope.json` (format v2) and its HMAC
verifies byte-exact with `rigorix-verifier::verify_signature` under the key
above — proving canonicalization parity between the engine and the independent
verifier (Strategy A: the HMAC trail is checkable anywhere).

## Regenerate

Fixtures are regenerated from rigorix-oss (fixed key, `RIGORIX_FIXTURE_OUT`):

```bash
RIGORIX_FIXTURE_OUT=<dir> cargo test -p rigorix-engine \
  --features conformance --test conformance write_real_signed_fixtures \
  -- --ignored
```

Then replace the JSON files here and re-run the verifier fixture test.

`envelope-precondition-signed.json` (ADR-017) is currently **contract-first**: the
engine does not implement ADR-017 yet, so it is signed by the reference verifier's
ignored `generate_precondition_fixture` test. Replace it from the engine once
ADR-017 Phase B lands.
