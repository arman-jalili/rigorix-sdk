## Summary

**0.2.0 republish** of the SDK crates. `rigorix-schemas` 0.1.0 + `rigorix-verifier`
0.1.0 were published **before** #31/#32 declared the ADR-016 Phase C
`anchor_head`, so the crates.io verifier drops the field when computing canonical
bytes and **cannot verify an anchored envelope**. 0.2.0 is the anchored-verification
release.

Closes #34.

## Changes

- `rust/Cargo.toml` — `[workspace.package] version` **0.1.0 → 0.2.0**
  (schemas, verifier, client all inherit).
- `rust/rigorix-verifier/Cargo.toml` + `rust/rigorix-client/Cargo.toml` —
  `rigorix-schemas` dep → **0.2.0** (the issue names the verifier; the client has
  the same pin, bumped for a coherent workspace). `rust/Cargo.lock` re-resolved.
- `rust/scripts/verify-packaged-crates.sh` + CI step — the packaged
  `rigorix-schemas` `.crate` must contain `schemas/envelope.json` **with**
  `anchor_head` and the anchored fixture; a clean scratch consumer then verifies
  `envelope-anchored-signed.json` byte-exact with `RIGORIX_SDK_SCHEMAS` **unset**.
- `rust/RELEASING.md` — the release runbook: publish **schemas first** (exact
  dep), clean-project post-publish check, `rust-v0.2.0` tag, mandatory 0.x
  consumer bumps (`^0.1` does **not** match 0.2). 0.1.0 is **not** yanked.
- `docs/contract-sync-2026-09-06.md` — release note.

## Verification

```
cd rust
cargo fmt --check && cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace          # 26 verifier tests (+1 ignored); schemas sync holds
./scripts/verify-packaged-crates.sh
  gate 1: packaged rigorix-schemas-0.2.0 carries anchor_head + fixture OK
  gate 2: clean consumer verifies anchored fixture + chain OK
  packaged-crate smoke: PASS
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | 0.2.0 schemas embeds `envelope.json` WITH `anchor_head` (embedded == on-disk) | ✅ sync test + `.crate` grep |
| 2 | Packed 0.2.0 verifies the anchored fixture byte-exact, no env override | ✅ clean-consumer gate |
| 3 | Both published + tagged | ⏸ credential-gated |
| 4 | OSS + enterprise dev-deps bumped to 0.2; their CI green | ⏸ cross-repo tail |
| 5 | CI green | ✅ |

## Deferred (external — see `rust/RELEASING.md`)

`cargo package -p rigorix-verifier` / `cargo publish --dry-run` need
`rigorix-schemas` 0.2.0 on crates.io: cargo resolves the exact-version dep
against the registry even with `--no-verify` (a temporary `[patch.crates-io]`
does not help — verified). So the credential-gated tail is:

1. `cargo publish -p rigorix-schemas` → `cargo publish -p rigorix-verifier`
2. clean-project install + verify (no env override)
3. `git tag rust-v0.2.0 && git push origin rust-v0.2.0`
4. bump `rigorix-oss/server/Cargo.toml` + `rigorix-enterprise/core/Cargo.toml`
   to `rigorix-verifier = "0.2"` and run their CI

The 0.1.0 gate proves the artifact content on this branch; only the registry
round-trip is deferred.
