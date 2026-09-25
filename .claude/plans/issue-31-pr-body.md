## Summary

Closes the ADR-016 **Phase C** contract gap. rigorix-oss PR #908 (`issue/899`)
binds a new **signed** envelope field `anchor_head` — the verified anchor ledger
head a decision was decided against — but no companion contract change shipped.
The frozen `schemas/envelope.json` and all three verifiers didn't declare it, so
they **dropped it** when computing canonical bytes → an engine-signed **anchored**
envelope's HMAC never reproduced out-of-band. Anchored evidence (the strongest
mode) was not independently verifiable — the Strategy A guarantee ADR-016 exists
to provide. `envelope.json` has no `additionalProperties:false`, so schema
validation silently tolerated the gap; only HMAC verification caught it.

Closes #31.

## Regression (proved before the fix)

```
$ verify_signature(envelope-anchored-signed.json, "fixture-hmac-key-2026")
SignatureMismatch: expected a28fca21…4ba07d45, got c946f1d5…d9ed3f9
```

## Changes

**Schema**
- `schemas/envelope.json` — additive `anchor_head` (string|null, pattern
  `^[0-9a-f]{64}$`) at the engine's **exact** property position:
  `history_policy → anchor_head → approval_events`. Mirrors
  `engine/src/audit/domain/envelope.rs` (bound by
  `envelope_factory_impl.rs::with_anchor` → `runtime.head()`).
- `schemas/fixtures/envelope/envelope-anchored-signed.json` — **engine-produced**
  anchored envelope (`history_integrity=anchored`, non-null `anchor_head`,
  non-empty `approval_events` so the position relative to them is proved),
  generated through the REAL anchored factory on `issue/899` with the fixed key
  `fixture-hmac-key-2026`. The existing corpus was all `local_unanchored`/legacy,
  so the anchored path had no byte-exact coverage.
- `schemas/fixtures/envelope/README.md` + `docs/contract-sync-2026-09-06.md`.

**Verifiers (all three)**
- `rust/rigorix-verifier` — `AuditEnvelope.anchor_head: Option<String>` at the
  same struct position, same `#[serde(default, skip_serializing_if =
  "Option::is_none")]`.
- `python/rigorix_verifier/canonical.py` + `typescript/src/canonical.ts` —
  `anchor_head` added to the skip-if-none set (field order already derives from
  `envelope.json`).

**Tests (all three)**
- Anchored fixture verifies byte-exact; tampering the head is detected; the
  field is present in the signed bytes in the engine's position; legacy and
  `local_unanchored` fixtures still verify byte-exact (skip-if-none unchanged).

## Verification

```
# Rust
cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings
cargo test --workspace         # verifier 26 (+1 ignored); schemas sync holds (31 files)

# Python
cd python && pytest -q         # 18
python -m build                # wheel + sdist; installed wheel verifies the
                               # ANCHORED fixture with RIGORIX_SDK_SCHEMAS unset

# TypeScript
cd typescript && npm test      # 18
npm pack --dry-run | grep -c _schemas/   # 31
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `anchor_head` declared in `envelope.json`; schema-lint passes | ✅ |
| 2 | Rust/Python/TS place it after `history_policy`, before `approval_events` | ✅ |
| 3 | Engine-signed anchored fixture verifies byte-exact (all 3); local fixtures unchanged | ✅ |
| 4 | Regression test proves the drop is fixed | ✅ |
| 5 | CI green (Rust · pytest · node · pack gates) | ✅ |

## Notes

- **Cross-repo status:** the field's origin (rigorix-oss #908, `issue/899`) is
  still **open**. Per "code is truth", the contract follows that branch's code
  and the fixture was generated from it, so the SDK validates anchored evidence
  the moment #908 lands — no SDK change needed then.
- `anchor_head` mirrors `HistorySlice.head_hash` / `prev_hash` (SHA-256 hex), so
  the `^[0-9a-f]{64}$` pattern is the existing contract, not an invention.
- Additive and serde-defaulted: legacy and `local_unanchored` envelopes
  canonicalize unchanged.
