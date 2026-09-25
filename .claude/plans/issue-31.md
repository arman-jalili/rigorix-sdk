# Implementation Plan: issue/31

**Branch:** `issue/31`
**Base:** `main`
**Issue:** #31 — SDK-CATALOG-ANCHOR-HEAD: declare envelope `anchor_head`
(ADR-016 Phase C) in `envelope.json` + all three verifiers

## Classification

Contract change (additive), scope **Complex**. Three verifiers + fixture + docs.

## The gap

rigorix-oss PR #908 (`issue/899`, **open**) binds a new **signed** envelope
field `anchor_head` — the verified anchor ledger head a decision was decided
against — immediately after `history_policy`, before `approval_events`. It was
absent from the frozen contract, so the Rust/Python/TS verifiers **dropped it**
when computing canonical bytes: an engine-signed **anchored** envelope's HMAC
never reproduced out-of-band. `envelope.json` has no
`additionalProperties:false`, so schema validation silently tolerated it.

Regression evidence (before the fix):
```
verify_signature(envelope-anchored-signed.json) -> SignatureMismatch
  expected a28fca21…4ba07d45, got c946f1d5…d9ed3f9
```

## Changes

- `schemas/envelope.json` — additive `anchor_head` (string|null, pattern
  `^[0-9a-f]{64}$`) inserted at the engine's exact property position:
  `history_policy → anchor_head → approval_events`.
- `rust/rigorix-verifier` — `AuditEnvelope.anchor_head: Option<String>` at the
  same struct position, same serde skip-if-none; focused regression test.
- `python/rigorix_verifier/canonical.py` + `typescript/src/canonical.ts` —
  `anchor_head` added to the skip-if-none set (field order already comes from
  `envelope.json`).
- `schemas/fixtures/envelope/envelope-anchored-signed.json` — **engine-produced**
  anchored envelope (real anchored factory, key `fixture-hmac-key-2026`,
  `history_integrity=anchored`, non-null head, non-empty `approval_events`).
- Parity tests assert the anchored fixture verifies byte-exact and is
  tamper-detected; legacy/`local_unanchored` fixtures still verify.
- Delta note in `docs/contract-sync-2026-09-06.md`.

## Fixture provenance (code is truth)

Generated from a throwaway worktree of rigorix-oss `origin/issue/899` (the
Phase C branch) via an ignored conformance generator:
```bash
RIGORIX_FIXTURE_OUT=<dir> cargo test -p rigorix-engine --features conformance \
  --test conformance write_anchored_signed_fixture -- --ignored
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `anchor_head` declared in `envelope.json`; schema-lint passes | ✅ |
| 2 | All three verifiers place it after `history_policy`, before `approval_events` | ✅ |
| 3 | Engine-signed anchored fixture verifies byte-exact (all 3); local fixtures unchanged | ✅ |
| 4 | Regression test proves the drop is fixed | ✅ |
| 5 | CI green (Rust · pytest · node · pack) | ✅ |

## Status

- [x] Implemented
- [x] Local checks green (Rust 26, Python 18, TS 18; fmt/clippy; pack gates)
- [ ] MR pushed
- [ ] Merged
