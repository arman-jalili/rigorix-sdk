# Validator source-of-truth relationship (`rigorix-sdk` ↔ `rigorix-oss`)

**Status:** Decided — 2026-10-13 (issue #43)
**Counterpart:** `rigorix-oss` `ISSUE-VALIDATOR-SINGLE-SOURCE`
(`docs/issues/validator-single-source.md` there).

## Problem

Seven files share identical names in the two repos:

```
.pi/scripts/languages/rust/validate-{architecture,canonical,ci,integration,tests,security,operations}.sh
```

They have been edited independently and **all seven differ**. Neither repo is
uniformly newer (this repo already uses `cargo llvm-cov` while still carrying the
`--test '*'` defect; OSS has the inverse mixture in places). Because the
filenames and the command names are identical, “`validate-tests` passed” does
**not** mean the same thing in the two repos. That is the actual defect: an
implicit interface.

## Decision

**Accept divergence; record an explicit compatibility contract.** The SDK keeps
its own copies as canonical *for this repo*; the OSS copies are canonical *for
OSS*. A shared source (one repo generates the other) is rejected for now because
it would couple two independently released repos and cannot be enforced from
either side alone unilaterally.

The relationship is now explicit rather than assumed:

1. **Filenames are not a shared interface.** Passing `validate-tests.sh` in one
   repo implies nothing about the other.
2. **Shared invariants.** Any future edit to a `languages/rust/validate-*.sh`
   in either repo must preserve these invariants, which the two trees agree on
   in intent even where the bytes differ:
   - Select test targets with `cargo test --tests` (or `--lib` / `--doc` /
     `--test <name>`), **never** `cargo test --test '*'`. `--test '*'` selects
     every target explicitly, so a target declaring `required-features` that are
     not enabled makes cargo **error** (exit 101) instead of skipping it.
   - Detect the project language from the working tree; never hardcode a locale
     value where a `$LANG` variable was intended.
   - Keep the pass/fail summary contract (`Summary` + non-zero exit on failure).
3. **Deltas are recorded, not silent.** A change here that should be mirrored in
   OSS gets a note in the PR body; the OSS counterpart issue tracks the other
   direction. This mirrors `AGENTS.md` rule 2 (contract changes are decisions).

## Rationale

The issue explicitly allowed either a shared source or a recorded divergence.
Recorded divergence is chosen because it is the only option enforceable from
within this repo and it removes the false assumption without adding cross-repo
build coupling. Revisit only if a shared generator is introduced in both repos
in the same change.

## Change log

- 2026-10-13 (#43): accept divergence; record invariants; fix `--test '*'` in
  `validate-tests.sh` / `validate-integration.sh`; fix the hardcoded `C.UTF-8`
  literal in `coverage.sh`, `install_coverage_tools.sh`, `ci/stage_lint.sh`.
