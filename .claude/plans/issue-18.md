# Implementation Plan: issue/18

**Branch:** `issue/18`
**Base:** `main` (`974460d`)
**Issue:** #18 — SDK-SCHEMAS-PUBLISH: publish `rigorix-schemas`, the canonical
contracts as a consumable crate

## Classification

Packaging (no schema content change). Scope: **Complex** (new published crate +
build-time embedding + CI gate).

## Problem

`rigorix-verifier` reads the contracts from `CARGO_MANIFEST_DIR/../../schemas` —
outside its crate root — so `cargo package -p rigorix-verifier` ships **zero**
schemas and every schema-dependent entry point fails in a published crate.

## Approach (issue option B)

Publish a companion `rigorix-schemas` crate that embeds `schemas/**` at build
time and exposes it by name. `schemas/` at the repo root stays canonical; no
duplicate copy is committed.

## Packaging constraint (resolved)

`cargo package` only ships files **inside** the package root; `include = ["../../schemas/**"]`
is silently ignored (verified empirically). Solution: `rust/rigorix-schemas/schemas`
is a **symlink** to `../../schemas`. `cargo package` dereferences it into the
published crate (verified: 30 schema files in the package; the packaged crate
builds standalone). `build.rs` walks the crate-local `schemas/` path, so the
same code works in-repo (via the symlink) and in the package.

## Deliverables

1. `rust/rigorix-schemas/{Cargo.toml, build.rs, src/lib.rs, README.md, schemas -> ../../schemas}`.
2. `build.rs` — walks the corpus, emits `FILES`/`NAMES`/`IDS` into `$OUT_DIR`
   via `include_str!`; `IDS` parsed with a `serde_json` build-dependency (zero
   runtime deps).
3. `src/lib.rs` — `schema`, `schema_names`, `fixture`, `schema_by_id`,
   `schema_ids`; sync test (embedded == on-disk, byte-equal, >= 25 files,
   integrity fixtures present).
4. `rust/Cargo.toml` — workspace member.
5. `.github/workflows/ci.yml` — add `cargo package -p rigorix-schemas`.

## Validation

- [x] `cargo build/test -p rigorix-schemas` — 2 tests + 1 doctest
- [x] `cargo test --workspace` — green
- [x] `cargo clippy --all-targets -- -D warnings`
- [x] `cargo fmt --check`
- [x] `cargo package -p rigorix-schemas` — 37 files (30 under `schemas/`), verify build OK
- [x] `cargo audit`

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
