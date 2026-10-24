# Implementation Plan: feature/verifier-integrity-54-55

**Branch:** `feature/verifier-integrity-54-55`
**Base:** `main` (`be204aa`, SDK 0.7.0)
**Issues:** #54, #55
**Group:** component batch (both pin a verification claim mechanically)

## Status

- [x] #54: rejected/accepted fixture sets pinned to a test table
- [x] #54: seed (`rejected-zzz-probe.json`) fails for the right reason
- [x] #55: `rigorix-schemas = "=0.7.0"` in the verifier manifest
- [x] #55: RELEASING.md claim corrected (verifier exact; client range)
- [x] Rust gate + packaged-crate smoke + all validators green
- [ ] MR created
- [ ] Merged

## #54 — rejected fixtures were not pinned to the tests

**Root cause:** `effect_record_fixtures_verify` skipped every `rejected-*` file,
and seven hand-written tests named the rejects one by one. Nothing tied the
fixture directory to the exercised set, so a new `rejected-*.json` was inert
coverage; the accepted set was only a `>= 5` count, so deletions went unnoticed.

**Fix:**

- `ACCEPTED_EFFECT_FIXTURES` and `REJECTED_EFFECT_FIXTURES` are explicit tables.
- `effect_record_fixtures_verify` asserts the accepted set equals the directory
  and verifies each entry.
- `effect_record_rejected_fixtures_are_pinned_and_rejected` asserts the rejected
  set equals the directory, then runs each case at its declared layer:
  `Schema` (also assert the structural verifier rejects), `Structural`,
  `ReadbackDigestMismatch`, `ReadbackMissing`.
- The seven hand-written tests collapse into this table; the orthogonal-axes
  semantic test stays.

**Seed proof:**

```
$ cp rejected-terminal-without-evidence.json rejected-zzz-probe.json
$ cargo test ... effect_record_rejected_fixtures_are_pinned_and_rejected
assertion `left == right` failed: every rejected fixture must have a case ...
  left:  [..., "rejected-zzz-probe.json"]
  right: [...]
test result: FAILED
$ rm rejected-zzz-probe.json && cargo test ...
test result: ok
```

## #55 — the verifier's schema dependency was a caret range

**Root cause:** `rigorix-verifier/Cargo.toml` had
`rigorix-schemas = { version = "0.7.0", ... }`, i.e. `>=0.7.0, <0.8.0`, while
`RELEASING.md` claimed the dependency was exact-versioned. A `0.7.1` schema
patch could change what an already-published verifier accepts with no verifier
release.

**Fix:**

- Pin `rigorix-schemas = { version = "=0.7.0", path = "../rigorix-schemas" }`.
- `cargo metadata` confirms the requirement is `=0.7.0`.
- `RELEASING.md`: state that the **verifier** is exact-pinned and publish order
  is now Cargo-enforced; the client keeps the compatible range because it is not
  a verification trust boundary. Also correct the stale `0.5.0` header to
  `0.7.0` (marker tag `rust-v0.7.0`, CI tag `v0.7.0`).

## Verification

```
cargo metadata: rigorix-schemas -> =0.7.0                  ✅
cargo build / test --all (32 verifier) / clippy -D warnings / fmt ✅
packaged-crate smoke (gate 1 + gate 2)                    ✅
validators: ci/tests/security/operations/canonical/architecture/integration ✅
#54 seed: fails on unexercised fixture, passes after removal ✅
```

## Acceptance

| # | Criterion | Status |
|---|-----------|--------|
| 54 | Every rejected fixture has a declared case; every case has a fixture | ✅ set equality |
| 54 | A new unexercised `rejected-*.json` fails the suite | ✅ seed proven |
| 54 | Deleting an accepted fixture fails the suite | ✅ exact accepted set |
| 55 | Verifier dep is exact (`=0.7.0`) | ✅ |
| 55 | Doc matches the manifest | ✅ |
| 55 | Publish order is enforced by Cargo, not remembered | ✅ |

## Notes

- No schema/content change: the artifact contract from #52 is untouched.
- `rigorix-client` intentionally keeps the compatible range (`0.7.0`); pinning it
  would couple an independently versioned protocol client to every schema patch.
