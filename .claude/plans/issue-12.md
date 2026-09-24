# Implementation Plan: issue/12

**Branch:** `issue/12`
**Base:** `main`
**Issue:** #12 — SDK-AUDIT-A: Envelope integrity contract (envelope chain fields +
receipt / history-slice / compaction schemas + verifier chain support)

## Classification

Contract slice. Scope: **Critical** (audit-integrity is an enforcement property;
new signing primitive). No server/runtime code — schemas + protocol-only verifier.

## Code truth (grounded)

| Source | What |
|---|---|
| `rigorix-oss/engine/src/audit/domain/envelope.rs` | `HistoryIntegrity` (`local_unanchored`\|`anchored`), `HistoryPolicy` (`allow_unanchored`), and the chain fields `producer_id`/`sequence`/`prev_hash`/`history_integrity`/`history_policy` in exact struct order |
| `rigorix-oss/engine/src/audit/application/envelope_factory_impl.rs` | `canonical_envelope_bytes` (signature nulled) + `envelope_hash` = SHA-256(hex) over those bytes |
| `rigorix-oss/engine/src/audit/application/chain.rs` (`83e904ad`/#902) | `verify_chain` semantics: genesis 0, contiguous, `prev_hash` continuity; legacy grandfathered |
| `rigorix-oss/engine/.pi/.../ADR-016-audit-integrity-anchor.md` | The three anchor artifacts' field lists + Ed25519 + "accepts a gap iff covered by a signed checkpoint" |
| `rigorix-oss/engine/src/sequence_policy/domain/history.rs` | `HistoryAction { node, principal, at, effect_key }` (history-slice `actions[]`) |

## Drift found in the issue draft (fix from code)

- The draft lists four envelope fields; the engine also has **`history_policy`**
  (`Option<HistoryPolicy>`, `allow_unanchored`) — added it (schema + verifier).
- The verifier's frozen `AuditEnvelope` was missing `requirement_findings`
  (ADR-015); adding it now makes the frozen copy mirror the engine
  field-for-field, required for chain/canonicalization parity.

## Deliverables

1. `schemas/envelope.json` — additive chain fields (+ `$defs.historyIntegrity`,
   `$defs.historyPolicy`), in engine struct order.
2. `schemas/api/ledger-receipt.json`, `history-slice.json`,
   `compaction-checkpoint.json` — FROZEN anchor artifacts.
3. `schemas/fixtures/integrity/` — engine-signed `chain.json` +
   `broken-chain.json`; Ed25519 anchor fixtures + README.
4. `rust/rigorix-verifier` — chain fields + enums + `requirement_findings`;
   `envelope_hash`; `verify_chain`; `verify_chain_with_checkpoints`; Ed25519
   verification (`ed25519-dalek`).
5. Docs — `schemas/README.md`, `schemas/api/README.md`, contract-sync delta.

## Validation

- [x] `cargo build`
- [x] `cargo test --workspace` — 22 passed, 1 ignored (fixture generator)
- [x] `cargo clippy --all-targets -- -D warnings`
- [x] `cargo fmt --check`
- [x] `cargo audit` — 0 advisories
- [x] Independent Python Ed25519 verify of the anchor fixtures
- [x] all 4 new schemas compile; fixtures validate

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
