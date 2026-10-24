## Summary

Closes #54 and #55. Both are the same class: a verification claim that was not
mechanically pinned.

### #54 — rejected fixtures are now pinned to the tests

`effect_record_fixtures_verify` skipped every `rejected-*` file, and seven
hand-written tests named the rejects individually. Nothing tied the fixture
directory to the exercised set, so a new `rejected-*.json` was inert coverage,
and the accepted set was only a `>= 5` count (deletions went unnoticed).

- Introduce explicit `ACCEPTED_EFFECT_FIXTURES` / `REJECTED_EFFECT_FIXTURES`
  tables and assert **set equality** against the on-disk `fixtures/effect/` set.
- Run each rejection at its declared layer: `Schema` (and assert structural also
  rejects), `Structural`, `ReadbackDigestMismatch`, `ReadbackMissing`.
- The seven hand-written tests collapse into the table; the orthogonal-axes
  semantic test stays.

**Seed proof** (the issue's repro):

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

### #55 — the schema dependency is pinned exactly

`rigorix-verifier/Cargo.toml` used `version = "0.7.0"` (a caret range) while
`RELEASING.md` claimed the dependency was exact-versioned. A `0.7.1` schema
patch could change what an already-published verifier accepts without a verifier
release.

- `rigorix-schemas = { version = "=0.7.0", path = "../rigorix-schemas" }`;
  `cargo metadata` confirms `=0.7.0`.
- `RELEASING.md` now states the verifier is exact-pinned (publish order is
  Cargo-enforced) and the client keeps the compatible range because it is a
  protocol client, not a verification trust boundary. Also corrects the stale
  `0.5.0` header to `0.7.0`.

## Files

| File | Change |
|---|---|
| `rust/rigorix-verifier/src/lib.rs` | pinned tables + set-equality rejection test (32 verifier tests) |
| `rust/rigorix-verifier/Cargo.toml` | `=0.7.0` exact pin |
| `rust/RELEASING.md` | exact-pin claim, client range, 0.7.0 header |
| `schemas/fixtures/effect/README.md` | documents the test pin |

No schema or artifact-content change; the #52 contract is untouched.

## Verification

```
cargo metadata: rigorix-schemas -> =0.7.0                  ✅
cargo build / test --all / clippy -D warnings / fmt       ✅
packaged-crate smoke (gate 1 + gate 2)                    ✅
validators: ci/tests/security/operations/canonical/architecture/integration ✅
#54 seed fails as expected and passes after removal       ✅
```

## Acceptance

| # | Criterion | Status |
|---|-----------|--------|
| 54 | Every rejected fixture has a case, every case a fixture | ✅ set equality |
| 54 | New unexercised `rejected-*.json` fails the suite | ✅ seed proven |
| 54 | Deleting an accepted fixture fails the suite | ✅ exact accepted set |
| 55 | Verifier dep is exact (`=0.7.0`) | ✅ |
| 55 | Doc matches the manifest | ✅ |
| 55 | Publish order enforced by Cargo | ✅ |
