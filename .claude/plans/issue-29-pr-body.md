## Summary

Fixes the publish path for the Python and TypeScript verifiers. Both resolved
the corpus from a `_schemas` **symlink** to the repo root, but npm/setuptools do
**not** dereference a symlinked directory into the packaged artifact (cargo
does) — so the packed packages shipped **zero** corpus and `schemasRoot()`
threw at runtime (`npm pack --dry-run | grep -c _schemas/` was `0`).

Now the corpus is **materialised as a real copy at pack/build time**, generated
from the single source of truth (`schemas/`), never committed, with a sync
assertion and pack→install→smoke CI gates.

Closes #29.

## Changes

**TypeScript (`typescript/`)**
- `scripts/bundle-schemas.mjs` — copies `<repo>/schemas` → `typescript/_schemas`
  (real dir); run from npm `prepack` and `build`.
- `scripts/pack-smoke.mjs` — the clean-install smoke test.
- `test/corpus-sync.test.ts` — generated copy must be byte-equal to `schemas/`.
- `package.json` — `bundle`/`prepack`/`build` scripts.
- `_schemas` symlink **removed** (generated + gitignored).

**Python (`python/`)**
- `scripts/bundle_schemas.py` — copies into `rigorix_verifier/_schemas`; no-ops
  when building the wheel from an sdist that already carries the corpus.
- `setup.py` — `build_py`/`sdist` hooks that bundle before packing;
  `MANIFEST.in` ships `scripts/` + `_schemas`.
- `conftest.py` — bundles before the test session.
- `scripts/pack_smoke.py` — the clean-install smoke test.
- `tests/test_corpus_sync.py` — generated copy must be byte-equal to `schemas/`.
- `_schemas` symlink **removed** (generated + gitignored).

**Repo** — `.gitignore` (`_schemas/`, `*.egg-info/`, `python/build/`);
**CI** — pack→install→smoke gates for both packages; `typescript/README.md` +
`python/README.md` document the bundling + `RIGORIX_SDK_SCHEMAS` override.

## Verification

```
# TypeScript
cd typescript && npm test                 # 17 tests
npm pack --dry-run | grep -c _schemas/    # 30 (was 0)
# install the tarball into a clean project, RIGORIX_SDK_SCHEMAS unset, verify -> OK

# Python
cd python && pytest -q                    # 17 tests
python -m build                            # wheel + sdist each carry the corpus
# install wheel -> verify (no env) -> OK;  install sdist -> verify (no env) -> OK

# Rust unchanged
cd rust && cargo test --workspace && cargo clippy --all-targets -- -D warnings
```

Covered by the sync tests: the generated `_schemas` stays byte-equal to the
canonical `schemas/` (drift fails CI).

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `npm pack` ships the corpus; installed tarball verifies with no env | ✅ 30 files + smoke |
| 2 | wheel + sdist ship the corpus; installed verifies with no env | ✅ both smoke |
| 3 | CI runs both pack→install→smoke gates | ✅ |
| 4 | READMEs document bundling + override | ✅ |
| 5 | CI green | ✅ |

## Notes

- The **Rust publish gate** (`cargo package -p rigorix-verifier` /
  `cargo publish --dry-run`) remains deferred: it requires `rigorix-schemas` to
  be on crates.io (not published here). The existing self-containment step
  stays; enable the gate after the first `rigorix-schemas` release.
- Out of scope: the actual `npm publish` / PyPI upload; the Rust crate bundling
  (already correct); the TS client (uses `_schemas` only in a test).
