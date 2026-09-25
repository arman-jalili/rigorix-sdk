# Implementation Plan: issue/29

**Branch:** `issue/29`
**Base:** `main`
**Issue:** #29 — SDK-C6-PACKAGING: bundle the contract corpus in the packed
Python/TS verifiers + pack-time gates

## Classification

Packaging fix. Scope: **Complex**. No verification-semantics change.

## The trap

Both verifiers resolved the corpus from a `_schemas` **symlink** to the repo
root. npm and setuptools do **not** dereference a symlinked directory into the
published artifact (cargo does — that's why #18/#22 works). Verified:
`npm pack --dry-run | grep -c _schemas/ == 0`.

## Fix

Materialise a **real** corpus copy at pack/build time; keep `schemas/` at the
repo root as the single source of truth; commit no duplicate; add a sync
assertion.

- **TypeScript** — `scripts/bundle-schemas.mjs` copies `<repo>/schemas` →
  `typescript/_schemas` (real dir). Run from npm `prepack` and `build`.
- **Python** — `scripts/bundle_schemas.py` copies into
  `rigorix_verifier/_schemas`. Run from the setuptools `build_py`/`sdist` hooks
  (`setup.py`) and from `conftest.py` before tests. The wheel-from-sdist rebuild
  no-ops when the sdist already carries the corpus (and `MANIFEST.in` ships
  `scripts/` + `_schemas`).
- Remove the committed `_schemas` symlinks; gitignore the generated dirs
  (`*.egg-info/`, `python/build/` too).
- Sync tests assert the generated copy is byte-equal to `schemas/`
  (`test/corpus-sync.test.ts`, `tests/test_corpus_sync.py`).

## Pack-time gates (CI)

- **TypeScript**: `npm pack` → install the tarball into a clean temp project →
  `node smoke.mjs` (`verify_signature` on a bundled fixture + `verify_chain`)
  with `RIGORIX_SDK_SCHEMAS` unset.
- **Python**: `python -m build` → install the **wheel** then the **sdist** into
  clean venvs → `scripts/pack_smoke.py` with the env unset.
- **Rust publish gate**: still deferred — `cargo package -p rigorix-verifier`
  needs `rigorix-schemas` on crates.io (not published here); the existing
  self-containment step remains.

## Validation (local)

- [x] `npm test` — 17 tests; `npm pack` ships **30** `_schemas/` files;
      clean-project install + smoke OK with the env unset
- [x] `pytest` — 17 tests; `python -m build` wheel + sdist each carry the corpus;
      clean-venv install + smoke OK (both) with the env unset
- [x] `cargo test --workspace` / `clippy` / `fmt` still green

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `npm pack` ships the corpus; installed tarball verifies with no env | ✅ |
| 2 | wheel + sdist ship the corpus; installed verifies with no env | ✅ |
| 3 | CI runs both pack gates | ✅ |
| 4 | READMEs document bundling + override | ✅ |
| 5 | CI green | ✅ |

## Status

- [x] Implemented
- [x] Local deterministic checks green
- [ ] MR pushed
- [ ] Merged
