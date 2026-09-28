# Implementation Plan: issue/34

**Branch:** `issue/34`
**Base:** `main`
**Issue:** #34 — SDK-CRATES-0.2.0: republish `rigorix-schemas` + `rigorix-verifier`
(0.1.0 predates `anchor_head`)

## Classification

Release. Scope **Moderate**. Local + cross-repo + registry.

## Why

`rigorix-schemas` 0.1.0 + `rigorix-verifier` 0.1.0 were published **before**
#31/#32 added the ADR-016 Phase C `anchor_head`. The crates.io verifier drops
the field when canonicalizing, so it **cannot verify an anchored envelope** —
wrong for its core purpose. Republish as 0.2.0.

## Changes

- `rust/Cargo.toml` — `[workspace.package] version` 0.1.0 → **0.2.0**
  (`rigorix-schemas`, `rigorix-verifier`, `rigorix-client` all inherit it).
- `rust/rigorix-verifier/Cargo.toml` + `rust/rigorix-client/Cargo.toml` —
  `rigorix-schemas` dep → 0.2.0 (the issue names only the verifier; the client
  has the same pin, so it is bumped too for a coherent workspace).
- `rust/Cargo.lock` — re-resolved.
- `rust/scripts/verify-packaged-crates.sh` (new) + CI step — prove the packaged
  `rigorix-schemas` `.crate` carries `anchor_head` + the anchored fixture, and a
  clean scratch consumer verifies it with `RIGORIX_SDK_SCHEMAS` unset.
- `rust/RELEASING.md` (new) — publish order (schemas first), clean-project
  check, tag, and the mandatory 0.x consumer bumps.
- `docs/contract-sync-2026-09-06.md` — release delta note.

## Why `cargo package -p rigorix-verifier` is still deferred

Cargo resolves the verifier's exact-version `rigorix-schemas = "0.2.0"` dep
against the **registry** during packaging — even with `--no-verify` (a temporary
`[patch.crates-io]` does not help; verified). It becomes runnable immediately
after `cargo publish -p rigorix-schemas` lands. The gate proves the same
artifact content via the workspace source + the packaged schemas `.crate`.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 0.2.0 schemas embeds `envelope.json` WITH `anchor_head` (embedded == on-disk) | ✅ sync test + packaged `.crate` grep |
| 2 | Packed 0.2.0 verifies `envelope-anchored-signed.json` byte-exact, no env | ✅ clean-consumer gate (source; verifier `.crate` post-publish) |
| 3 | Both published + tagged | ⏸ credential-gated (`RELEASING.md`) |
| 4 | OSS + enterprise dev-deps bumped to 0.2; their CI green | ⏸ cross-repo tail |
| 5 | CI green | ✅ |

## Status

- [x] Implemented (local)
- [x] Local checks green
- [x] MR pushed
- [ ] Merged
- [ ] Published + tagged + consumers bumped (deferred)
