# Implementation Plan: issue/43

**Branch:** `issue/43`
**Base:** `main` (`56c3e4f`)
**Issue:** #43 — SDK-VALIDATOR-MAINTENANCE
**Created:** 2026-10-13

## Status

- [x] Issues identified
- [x] Implementation plan created
- [x] Code implemented
- [x] False-failure reproduced with a temporary `required-features` target
- [x] Tests passing (`validate-ci.sh`, `validate-tests.sh`)
- [ ] MR created
- [ ] Pipeline green
- [ ] Merged

## Scope

Tooling only (`.pi/scripts`); no schema/contract change. Independent of #44.

## Changes

| File | Change | Reason |
|------|--------|--------|
| `.pi/scripts/languages/rust/validate-tests.sh` | `--test '*'` → `--tests` | latent false failure (exit 101 on `required-features`) |
| `.pi/scripts/languages/rust/validate-integration.sh` | `--test '*'` → `--tests` | same |
| `.pi/scripts/ci/stage_lint.sh` | `case "C.UTF-8"` → `"$LANG"`; `((PASS++))` → `PASS=$((PASS+1))` | locale literal bug; second fix required so the now-active branch doesn't abort under `set -e` |
| `.pi/scripts/coverage.sh` | `[ "C.UTF-8" = "unknown" ]` → `"$LANG"` | locale literal bug |
| `.pi/scripts/install_coverage_tools.sh` | `[ "C.UTF-8" = "unknown" ]` → `"$LANG"` | locale literal bug |
| `docs/validator-single-source.md` | new | records the source-of-truth decision (accept divergence + invariants) |

## Evidence

Temporary target in `rigorix-client` (added, run, reverted):

```
cargo test --test '*'  → error: target `__tmp_required` requires the features: `__tmp_required`   EXIT=101
cargo test --tests     → 0 + 2 + 7 tests pass                                                      EXIT=0
```

Dispatcher activations (run from `rust/` after the `$LANG` fix):

```
stage_lint.sh  → "Linting: Rust", clippy + fmt pass, exit 0
coverage.sh    → "Workspace coverage (cargo llvm-cov)", exit 0
```

## Deterministic gate

`cargo build`, `cargo test --all`, `cargo clippy --all-targets -- -D warnings`,
`cargo fmt --check`, `validate-ci.sh`, `validate-tests.sh` — all pass.

## Follow-up (out of scope, recorded)

`((PASS++))` under `set -e` is also present in `stage_unit.sh`,
`stage_remaining.sh`, `stage_docs_policy.sh`, `stage_static_analysis.sh`. Not
touched here (no locale bug activates them in this repo); filed as a note.
