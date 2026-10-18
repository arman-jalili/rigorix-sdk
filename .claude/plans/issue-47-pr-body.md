## Summary

Closes #47. The frozen envelope schema rejected `history_integrity=anchored_pending`,
a value `rigorix-oss` now emits. This is a **high-severity contract drift**: the
engine labels a record `anchored_pending` when anchored mode is configured but no
head has been verified yet (startup window), and any strict validator against
`envelope-v2.json` reports that record as non-conformant.

Code is truth (`rigorix-oss` `engine/src/audit/domain/envelope.rs` +
`envelope_factory_impl.rs:137,359`):

```rust
pub enum HistoryIntegrity { LocalUnanchored, Anchored, AnchoredPending }
// anchored + head -> Anchored; anchored + no head -> AnchoredPending, anchor_head: None
```

## Changes

| File | Change |
|---|---|
| `schemas/envelope.json` | `$defs.historyIntegrity.enum` += `anchored_pending`; `$defs` + `properties.history_integrity` descriptions state the semantic rule |
| `schemas/api/authority-fact-bundle.json` | `anchorRef.history_integrity` description names all three + the rule |
| `rust/rigorix-verifier/src/lib.rs` | frozen `HistoryIntegrity` enum += `AnchoredPending`; ignored fixture generator; `anchored_pending_fixture_verifies` |
| `schemas/fixtures/envelope/envelope-anchored-pending-signed.json` | **new** signed fixture (`anchored_pending`, no `anchor_head`) |
| `schemas/fixtures/envelope/README.md`, `schemas/README.md` | document the third value + contract-first fixture |
| `docs/contract-sync-2026-10-18-envelope-integrity.md` | **new** contract delta note |
| `docs/contract-sync-2026-09-06.md` | pointer to the new delta |
| `go/internal/corpus/corpus_gen.go`, `_schemas/` copies | regenerated (generated artifacts) |

Additive only: no field, type, or canonical-form change. `apiVersion` unchanged.

## The semantic rule (recorded where consumers read it)

- `local_unanchored` — tamper-evident local cache only (HMAC + local chain), not
  anchor-authenticated.
- `anchored` — anchor-authenticated evidence with a verified head. **Only this
  value asserts authenticity.**
- `anchored_pending` — anchored mode configured, **nothing verified yet**. It must
  never be treated as a weaker `anchored`.

Anchored mode configured is intent; a verified head is evidence.

## Fixture

`envelope-anchored-pending-signed.json` is produced by the ignored
`generate_anchored_pending_fixture` test: derived from the engine-signed
`envelope-anchored-signed.json` by dropping the unverified `anchor_head`, setting
`history_integrity` to `anchored_pending`, and re-signing with the fixed test key
`fixture-hmac-key-2026`. It is contract-first (same precedent as the ADR-017
precondition fixture) until the engine's conformance writer emits that variant.

The new fixture is picked up automatically by every language's
`signed engine fixtures verify byte-exact` test (each iterates
`fixtures/envelope/*.json`).

## Verification

```
cargo test -p rigorix-verifier -p rigorix-client -p rigorix-schemas   ✅ (29 passed)
cargo fmt --check / cargo clippy --all-targets -- -D warnings         ✅
go test ./...                                                         ✅
python -m pytest                                                      ✅ (19 passed)
npm test (typescript verifier)                                        ✅ (19 passed)
npm test (typescript-client)                                          ✅ (10 passed)
mvn -B -q verify (java)                                               ✅
validate-ci / tests / security / operations / canonical               ✅
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `$defs.historyIntegrity` accepts all three values | ✅ |
| 2 | `authority-fact-bundle.json` description names all three | ✅ |
| 3 | A fixture envelope with `anchored_pending` is added and validated | ✅ |
| 4 | Description states only `anchored` asserts authenticity | ✅ |
| 5 | OSS conformance adds an `anchored_pending` case | ⏳ cross-repo (oss #1071) |

## Cross-repo follow-up

`rigorix-oss` conformance should add a case that emits `anchored_pending`
(tracked in oss #1071). The SDK fixture is contract-first until the engine's
conformance writer emits it directly; regenerate it from the engine then.
