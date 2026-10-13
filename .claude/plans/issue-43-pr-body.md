## Summary

Closes #43. Two defects in the SDK's validator tooling, both measured against the
current tree:

1. **Latent false failure** — `cargo test --test '*'` selects every target
   explicitly, so a target declaring `required-features` that are not enabled makes
   cargo **error (exit 101)** instead of skipping it. Replaced with
   `cargo test --tests` in the two Rust validators.
2. **Implicit divergence from `rigorix-oss`** — the seven
   `languages/rust/validate-*.sh` files share names but differ in content, so
   “`validate-tests` passed” means different things per repo. This is now an
   explicit, recorded compatibility contract rather than an assumption.

Also fixed a third, related defect found while verifying: a hardcoded `C.UTF-8`
locale literal in three dispatchers where `$LANG` was intended. Fixing
`stage_lint.sh` activated a code path that then tripped a `set -e` bug in its
`((PASS++))` counters, so that counter arithmetic was corrected too.

## Changes

| File | Change |
|------|--------|
| `.pi/scripts/languages/rust/validate-tests.sh` | `--test '*'` → `--tests` |
| `.pi/scripts/languages/rust/validate-integration.sh` | `--test '*'` → `--tests` |
| `.pi/scripts/ci/stage_lint.sh` | `case "C.UTF-8"` → `case "$LANG"`; `((PASS++))` → `PASS=$((PASS+1))` |
| `.pi/scripts/coverage.sh` | `[ "C.UTF-8" = "unknown" ]` → `[ "$LANG" = "unknown" ]` |
| `.pi/scripts/install_coverage_tools.sh` | `[ "C.UTF-8" = "unknown" ]` → `[ "$LANG" = "unknown" ]` |
| `docs/validator-single-source.md` | **new** — records the source-of-truth decision |

## Proof of the false failure

A temporary test target was added to `rigorix-client` (feature `__tmp_required`,
target `required-features = ["__tmp_required"]`), exercised, then reverted:

| command | result | exit |
|---|---|---|
| `cargo test --test '*'` | `error: target \`__tmp_required\` requires the features: \`__tmp_required\`` | **101** |
| `cargo test --tests` | real suite runs: `0 + 2 + 7` tests pass, target skipped | **0** |

## Proof the dispatcher fixes activate correctly

Run from `rust/` after the `$LANG` fix:

- `ci/stage_lint.sh` → `Linting: Rust`, `cargo clippy` + `cargo fmt check` pass, exit 0
- `coverage.sh` → `Workspace coverage (cargo llvm-cov)`, exit 0

## Source-of-truth decision (acceptance criterion #3)

**Accept divergence; record an explicit compatibility contract.** The SDK copies
stay canonical for this repo, the OSS copies for OSS. A shared generator is
rejected for now (it would couple two independently released repos and is not
enforceable from one side). `docs/validator-single-source.md` records that
filenames are not a shared interface and lists the invariants both trees must
preserve (never `--test '*'`; detect language, never hardcode a locale value;
keep the summary/exit contract).

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | No rust validator uses `--test '*'` | ✅ `grep` clean |
| 2 | A `required-features` target does not cause a false failure | ✅ reproduced → fixed (table above) |
| 3 | Source-of-truth relationship recorded | ✅ `docs/validator-single-source.md` |
| 4 | `C.UTF-8` message fixed if present | ✅ 3 dispatchers |

## Validation

```
cargo build                                   ✅
cargo test --all                              ✅
cargo clippy --all-targets -- -D warnings     ✅
cargo fmt --check                             ✅
.pi/scripts/validate-ci.sh                    ✅ (5 passed, 0 failed)
.pi/scripts/validate-tests.sh                 ✅ (4 passed, 0 failed)
```

## Out of scope

- Reconciling the intra-repo trees (this repo has no per-crate mirrors).
- `((PASS++))` in `stage_unit.sh` / `stage_remaining.sh` /
  `stage_docs_policy.sh` / `stage_static_analysis.sh` (no locale bug activates
  them here; noted as a follow-up).

## Contract impact

None. No schema, catalog, or client change. Additive/behavioural tooling only —
old verifiers are unaffected.
