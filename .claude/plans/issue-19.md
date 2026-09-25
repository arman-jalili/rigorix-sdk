# Implementation Plan: issue/19

**Branch:** `issue/19` (stacked on `issue/18`)
**Base:** `issue/18` → `main` after #18 merges
**Issue:** #19 — SDK-VERIFIER-PUBLISH: publish `rigorix-verifier` as a
self-contained, consumable crate

## Classification

Packaging + consumption. Scope: **Complex** (resolution rewrite + metadata +
CI). No verification-semantics change.

## Problem

`rigorix-verifier` read contracts from `CARGO_MANIFEST_DIR/../../schemas`, so a
`cargo package`d/published verifier shipped zero schemas and every schema entry
point failed. It also lacked a README and full publish metadata.

## Code truth / dependency

- `rigorix-schemas` (#18, this stack) — the embedded corpus.
- No verification semantics change; no `rigorix-engine` dependency (D-1).

## Deliverables

1. `rust/rigorix-verifier/Cargo.toml` — add
   `rigorix-schemas = { version = "0.1.0", path = "../rigorix-schemas" }`; publish
   metadata (README, authors, keywords, categories, docs.rs, MSRV, include).
   License decision: keep **Apache-2.0** (repo-wide/workspace consistency; the
   issue allowed either).
2. `rust/rigorix-verifier/src/lib.rs` — resolution is
   `RIGORIX_SDK_SCHEMAS` (override) → embedded `rigorix-schemas` → clear error.
   `schema_path` replaced by `schema_text`; no `../../schemas` fallback.
   Fixture/schema tests read through the same resolution (helpers
   `fixture_text` / `fixture_json_names`), so `cargo test` passes in the packaged
   crate with no env override. New `embedded_corpus_smoke` test.
3. `rust/rigorix-verifier/README.md` — new.
4. `.github/workflows/ci.yml` — an explicit verifier self-containment step
   (embedded corpus, override unset).

## Publish gate (honest constraint)

Publishing a crate with a registry dependency requires that dependency to be on
crates.io. `cargo package -p rigorix-verifier` / `cargo publish --dry-run`
therefore cannot pass until `rigorix-schemas` is published — the issue's **own
stated prerequisite** ("publish that crate first"). The PR ships the code,
metadata, and the self-containment proof; the package/publish commands activate
immediately after the first `rigorix-schemas` release. Not published here (the
user's "no merge / no publish" instruction).

## Validation

- [x] `cargo test --workspace` — rig. schemas 2 + verifier 25 (+1 ignored)
- [x] env-override run (`RIGORIX_SDK_SCHEMAS`) — 25 green
- [x] no-env run (embedded corpus) — 25 green
- [x] `cargo clippy --all-targets -- -D warnings`; `cargo fmt --check`
- [x] `cargo package -p rigorix-schemas` — verify build OK
- [ ] `cargo package -p rigorix-verifier` / `cargo publish --dry-run` — after
      `rigorix-schemas` is published

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
- [ ] Published (blocked on `rigorix-schemas` release)
