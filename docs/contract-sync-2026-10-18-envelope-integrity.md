# Contract Sync — Delta (2026-10-18): envelope `anchored_pending` (#47)

**Status:** Applied contract delta (SDK issue #47, high severity).
**Scope:** `schemas/envelope.json` `$defs.historyIntegrity`, the Rust verifier's
frozen enum copy, `schemas/api/authority-fact-bundle.json` description, and one
conformance fixture.
**Base:** the 2026-09-06 contract-sync design + the 2026-10-13 catalog delta.

## What changed

| Artifact | Change |
|---|---|
| `schemas/envelope.json` | `$defs.historyIntegrity.enum` gains `anchored_pending`; both the `$defs` and the `properties.history_integrity` descriptions state the semantic rule (only `anchored` asserts authenticity). |
| `schemas/api/authority-fact-bundle.json` | `$defs.anchorRef.history_integrity` description names all three values and the rule. |
| `rust/rigorix-verifier/src/lib.rs` | Frozen `HistoryIntegrity` enum gains `AnchoredPending` (mirrors the engine struct). |
| `schemas/fixtures/envelope/envelope-anchored-pending-signed.json` | **New** signed fixture: `history_integrity=anchored_pending`, no `anchor_head`. |
| `schemas/fixtures/envelope/README.md`, `schemas/README.md` | Document the third value + the contract-first fixture. |

Additive only: the wire format gains a value the engine already emits; no field,
type, or canonical-form change. `apiVersion` is unchanged.

## Why (code is truth)

`rigorix-oss` `engine/src/audit/domain/envelope.rs` now has:

```rust
pub enum HistoryIntegrity { LocalUnanchored, Anchored, AnchoredPending }
```

and `engine/src/audit/application/envelope_factory_impl.rs` emits
`AnchoredPending` (with `anchor_head: None`) when anchored mode is configured but
no verified head exists yet (`:137`, `:359`). With `rename_all = "snake_case"`
that is the wire value `anchored_pending`, which the frozen SDK enum rejected.

The ordering rule is contract-first: a new wire value lands here, then in the
producers. OSS #1071 shipped the producer first; this delta closes the gap.

## The semantic rule (recorded where consumers read it)

- `local_unanchored` — tamper-evident local cache only (HMAC + local chain), not
  anchor-authenticated.
- `anchored` — anchor-authenticated evidence with a verified head. **Only this
  value asserts authenticity.**
- `anchored_pending` — anchored mode configured, **nothing verified yet**
  (startup window). It must never be treated as a weaker `anchored`.

Anchored mode configured is intent; a verified head is evidence.

## Verification

- `rust/rigorix-verifier`: `anchored_pending_fixture_verifies` — the fixture
  parses to `HistoryIntegrity::AnchoredPending`, is HMAC-valid byte-exact, is
  schema-valid, and tampering with the label is detected (it is signed).
- The generic `engine_signed_fixtures_verify_byte_exact` iterates every
  `fixtures/envelope/*.json`, so the new fixture is covered without a special
  case.
- Python/TypeScript verify the fixture byte-exact and validate it against
  `envelope.json`; Java/Go verify it byte-exact through their canonical field
  lists (all four iterate the envelope fixture directory).

## Follow-up (cross-repo)

`rigorix-oss` conformance should add a case that emits `anchored_pending`
(tracked in oss #1071). The SDK fixture is contract-first (signed by the
reference verifier with the fixed test key) until the engine's conformance
writer emits that variant directly; regenerate it from the engine then.
