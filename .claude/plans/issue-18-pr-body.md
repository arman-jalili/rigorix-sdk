## Summary

Makes the canonical contracts a **first-class, distributable artifact**. Today
`rigorix-verifier` reads `schemas/` from `CARGO_MANIFEST_DIR/../../schemas` —
outside its crate root — so `cargo package -p rigorix-verifier` ships **zero**
schemas and every schema-dependent entry point (`verify_signature`,
`verify_catalog_subset`, `all_schemas_compile`, `catalog_integrity`,
`verify_chain`) fails in a published crate.

This adds **`rigorix-schemas`** (issue option B): a near-dependency-free crate
that embeds `schemas/**` (schemas **and** `fixtures/**`) at build time and
exposes it by name. One copy, consumed by the Rust verifier, the future
Python/TS verifiers (SDK-C6), and both servers — no vendoring, no drift.

Closes #18.

## Changes

**`rust/rigorix-schemas/`** (new workspace member)
- `build.rs` — walks the corpus and emits `$OUT_DIR/embedded.rs` with
  `FILES: &[(&str, &str)]`, `NAMES: &[&str]`, `IDS: &[(&str, &str)]` via
  `include_str!`. The `$id` map is parsed with a `serde_json`
  **build-dependency** → **zero runtime dependencies**.
- `src/lib.rs` — `schema(rel_path)`, `schema_names()`, `fixture(rel_path)`,
  `schema_by_id(id)`, `schema_ids()`, and the raw `FILES` table.
- Sync test `embedded_corpus_matches_disk` — walks the on-disk corpus and fails
  on any divergence (both directions), asserts `>= 25` files, and asserts the
  ADR-016 integrity fixtures are embedded.
- `README.md`; `schemas` is a symlink → `../../schemas`.

**`rust/Cargo.toml`** — adds the member.

**`.github/workflows/ci.yml`** — adds `cargo package -p rigorix-schemas` to the
gate.

## Packaging constraint (why the symlink)

`cargo package` only ships files **inside** the package root:
`include = ["../../schemas/**"]` is silently ignored (verified empirically).
`schemas/` inside the crate is therefore a **symlink** to the repo-root single
source of truth, which `cargo package` **dereferences** into the published
crate. `build.rs` walks the crate-local path, so the identical code works
in-repo (symlink) and in the package (real dir). No duplicate copy is committed,
and the packaged crate has no path/env dependency on the repo.

## Verification

```
cd rust
cargo test --workspace                 # rigorix-schemas 2 + doctest; verifier 24 (+1 ignored)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo package -p rigorix-schemas       # 37 files (30 under schemas/); verify build OK
cargo audit                            # 0 advisories
```

`cargo package --list` shows all 30 `schemas/**` files, and the packaged crate
compiles standalone (build.rs embeds them from the dereferenced directory).

## Acceptance criteria

| # | Criterion | Where |
|---|-----------|-------|
| 1 | Every `schemas/**` file embedded and retrievable | `embedded_corpus_matches_disk` + `exposes_schemas_fixtures_and_ids` |
| 2 | Sync test fails on embedded-vs-disk divergence | `embedded_corpus_matches_disk` |
| 3 | `cargo package` succeeds; packaged crate builds standalone | CI `cargo package`, local run |
| 4 | `$id -> path` map exposed | `schema_by_id` / `schema_ids` |
| 5 | CI green | CI |

## Out of scope

- Any schema **content** change (packaging only).
- Publishing `rigorix-verifier` (tracked as #19).
- Python/TypeScript verifiers (tracked as #21).
