# rigorix-sdk schemas — single source of truth

Contract-first schemas for Rigorix audit, identity, and policy surfaces.
Grounded in rigorix-oss Rust types (code is truth) and reconciled with
rigorix-enterprise consumers via contract-sync milestone 1 (delta maps).
Contract changes are DECISIONS (see AGENTS.md + docs/strategy-freeze).

## Catalog

| Schema | Status | Grounds (code is truth) | Notes |
|---|---|---|---|
| `envelope.json` | **v1** (2026-09-07) | rigorix-oss `engine/src/audit/domain/envelope.rs`, `identity/domain/claim.rs` | Full reconciliation vs v0 draft: EventStatus serde-exact values (Success/Failure/Skipped/Cancelled — no rename_all), `decision_context_ref` corrected (string ref, not object), all `$defs` completed. Canonicalization contract for HMAC documented in the schema description. |
| `claims.json` | **v1** (2026-09-07) | rigorix-oss `engine/src/identity/domain/claim.rs` | IdentityClaim (full, root) + IdentityRef (redacted, `$defs`) — serde-stable, Options always serialized as null (no skips on IdentityClaim). Raw JWT claim sets are an extension slot (enterprise delta map). |
| `policy.json` | **v1** (2026-09-07) | rigorix-oss `engine/src/sequence_policy/domain/rule.rs` + `config.rs`, `configuration/domain/config.rs` | SequenceRule/StepPredicate/ParamPredicate/HistoryPredicate/RuleAction semantics; SafetyCaps + root-config surface for cross-tool alignment. Enterprise policy-bundle exports must emit rule semantics in this shape. |
| `api/method-catalog.md` | sketch | rigorix.* JSON-RPC catalog (strategy D-3) | Pre-ADR-008; not yet authoritative. |

## Conformance fixtures (milestone 1)

`fixtures/` is the home for real run artifacts (signed envelopes produced by
real engine runs with fixed keys) — produced by the rigorix-oss conformance
session (F-20260907-01), verified against `envelope.json` and byte-exact
HMAC-verifiable by `rigorix-verifier` from any language.

## Verifier

`../rust/rigorix-verifier` — protocol-only Rust crate (no rigorix-engine dep):
HMAC-SHA256 integrity over the documented canonical form + JSON Schema
conformance. Frozen struct copies of the envelope contract.

## Validation

```bash
# schemas are valid JSON; verifier tests exercise schema + HMAC semantics
cd rust && cargo test
```
