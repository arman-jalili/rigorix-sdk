## Summary

Makes `rigorix-verifier` distributable: it now resolves the contracts from the
embedded `rigorix-schemas` corpus (#18) instead of a repo-relative path, so a
packaged/published verifier is self-contained and engine-free (D-1).

Closes #19. **Stacked on #18** (base branch `issue/18`) — `rigorix-schemas` must
exist first.

## Changes

**`rust/rigorix-verifier/Cargo.toml`**
- depends on `rigorix-schemas` (data-only; preserves protocol-only/no-engine);
- publish metadata: `readme`, `authors`, `keywords`, `categories`,
  `documentation`, `rust-version`, `include`. License kept **Apache-2.0**
  (repo-wide consistency; the issue allowed either).

**`rust/rigorix-verifier/src/lib.rs`**
- `schema_path` → `schema_text`, resolving **`RIGORIX_SDK_SCHEMAS` (override) →
  embedded `rigorix-schemas` → clear error**. The `CARGO_MANIFEST_DIR/../../schemas`
  fallback is gone.
- All schema/fixture test reads go through the same resolution
  (`fixture_text` / `fixture_json_names`), so the suite passes in the packaged
  crate with the override unset; added `embedded_corpus_smoke` (signature +
  catalog subset + chain via the embedded corpus).

**`rust/rigorix-verifier/README.md`** — new (purpose, resolution order, usage,
packaging).

**`.github/workflows/ci.yml`** — explicit verifier self-containment step
(embedded corpus, `RIGORIX_SDK_SCHEMAS` unset); keeps the `rigorix-schemas`
package gate.

## Publish gate (honest note)

`cargo package -p rigorix-verifier` / `cargo publish --dry-run` require
`rigorix-schemas` to be **on crates.io** — the issue's own prerequisite
("publish that crate first"). Cargo refuses to package a crate whose registry
dependency is missing (verified: no `--no-verify`/`[patch]` workaround).
So this PR ships the resolution + metadata + self-containment proof; the
package/publish commands run unchanged once `rigorix-schemas` is released. Per
your "no merge / no publish" instruction, nothing is published here.

## Verification

```
cd rust
cargo test --workspace                 # rigorix-schemas 2 + verifier 25 (+1 ignored)
RIGORIX_SDK_SCHEMAS=$PWD/../schemas cargo test -p rigorix-verifier --lib   # override path
unset RIGORIX_SDK_SCHEMAS; cargo test -p rigorix-verifier --lib            # embedded path
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo package -p rigorix-schemas       # verify build OK
```

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Resolution: env override → embedded (no `../../schemas`) | ✅ unit + helpers |
| 2 | `cargo test` green with the env unset (embedded) | ✅ 25 tests |
| 3 | package → unpack → build → smoke, no env | ⏳ blocked on `rigorix-schemas` publish (prerequisite) |
| 4 | `cargo publish --dry-run` + full metadata | metadata ✅; dry-run ⏳ same gate |
| 5 | Published + tagged | ⏳ release step (not in this PR) |

## Out of scope

- Verification-semantics changes; schemas.
- Python/TS verifiers (#21) and consumers' adoption (OSS/enterprise guards).
