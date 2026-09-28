# Implementation Plan: issue/33

**Branch:** `issue/33` (base `issue/34` — shared 0.2.0)
**Issue:** #33 — SDK-PUBLISH-PY-TS: publish the Python + TypeScript verifiers to
PyPI + npm

## Classification

Release / CI. Scope **Moderate**. External registry push is credential-gated.

## Approach

The artifacts already build + pack→install→smoke (#30). Only registry
publication is missing. We implement a **tag-triggered publish workflow**, align
all three artifacts to the shared **0.2.0**, strengthen the pack-smoke to the
anchored fixture, and document install. The actual `pip`/`npm` upload is
executed by the release owner (secrets), and a `workflow_dispatch` dry run
builds without uploading.

## Changes

- Versions → **0.2.0** (folded in with #34):
  `python/pyproject.toml` + `python/rigorix_verifier/__init__.py`,
  `typescript/package.json` (+ lock), `typescript-client/package.json`
  (+ lock).
- `typescript-client` gains `prepack: npm run build` so `npm publish` always
  ships `dist/`.
- `python/scripts/pack_smoke.py` + `typescript/scripts/pack-smoke.mjs` now
  verify `envelope-anchored-signed.json` (stronger, and the post-publish gate).
- `.github/workflows/publish.yml` (new):
  - `python` → PyPI Trusted Publishing (OIDC, `id-token: write`), builds
    sdist + wheel, publishes on tag.
  - `npm-verifier` / `npm-client` → npm with `NPM_TOKEN`, publish on tag.
  - `smoke` → after publish, installs from the registries in a clean env and
    verifies the anchored fixture with `RIGORIX_SDK_SCHEMAS` unset.
  - Each job asserts the tag matches its artifact version; `workflow_dispatch`
    is build-only (no upload).
- Install snippets in the three READMEs.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | All three artifacts published at one aligned version (0.2.0) | ⏸ workflow ready; publish credential-gated |
| 2 | Publish is tag-triggered + reproducible (CI job) | ✅ `publish.yml` |
| 3 | Clean install from the registry verifies the anchored fixture, no env | ✅ locally (wheel/tarball); registry step in `smoke` |
| 4 | Install docs added | ✅ |
| 5 | CI green | ✅ |

## Deferred (external)

`git tag v0.2.0 && git push origin v0.2.0` after configuring PyPI Trusted
Publishing + the `NPM_TOKEN` secret. The workflow then publishes and self-smokes.

## Status

- [x] Implemented (local)
- [x] Local checks green (Py build+smoke, npm pack+smoke, pytest, node)
- [ ] Registry publish (credential-gated)
- [ ] MR pushed / merged
