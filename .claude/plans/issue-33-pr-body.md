## Summary

Adds the missing **registry publication** for the Python + TypeScript artifacts.
They already built and passed pack→install→smoke (#30) but were never published,
so external consumers could not install them. All three now align to the shared
**0.2.0** (with #34) and a **tag-triggered** workflow publishes + self-smokes.

Closes #33.

## Changes

- **Version alignment → 0.2.0**: `python/pyproject.toml` +
  `python/rigorix_verifier/__init__.py`, `typescript/package.json` (+ lock),
  `typescript-client/package.json` (+ lock).
- `typescript-client/package.json`: `prepack: npm run build` so `npm publish`
  always ships `dist/`.
- `python/scripts/pack_smoke.py` + `typescript/scripts/pack-smoke.mjs` now
  verify **`envelope-anchored-signed.json`** (the strongest fixture) — reused
  verbatim as the post-publish gate.
- **`.github/workflows/publish.yml`** (new, `on: push: tags: ["v*"]` +
  `workflow_dispatch`):
  - `python` → PyPI via **Trusted Publishing** (OIDC, `id-token: write`); builds
    sdist + wheel (corpus bundled by `setup.py`); publishes on tag.
  - `npm-verifier` / `npm-client` → npm with `NPM_TOKEN`; publish on tag.
  - `smoke` → `needs:` all three; installs **from the registries** into a clean
    env and verifies the anchored fixture with `RIGORIX_SDK_SCHEMAS` **unset**.
  - Every job asserts the tag matches its artifact version; `workflow_dispatch`
    is **build-only** (uploads gated on `github.event_name == 'push'`).
- Install snippets in `python/README.md`, `typescript/README.md`,
  `typescript-client/README.md`.

## Verification (local, the exact post-publish path)

```
# Python — build 0.2.0, install into a clean venv, verify anchored (no env)
python -m build --outdir dist       # rigorix_verifier-0.2.0.{whl,tar.gz}
<venv>/bin/pip install dist/*.whl
RIGORIX_SDK_SCHEMAS unset <venv>/bin/python python/scripts/pack_smoke.py
  -> packed python verifier smoke OK

# TypeScript — pack 0.2.0, install into a clean project, verify anchored (no env)
cd typescript && npm test           # 18 pass; npm pack ships 31 _schemas files
node smoke.mjs (from typescript/scripts/pack-smoke.mjs) -> OK
cd typescript-client && npm test    # 10 pass; npm pack ships dist/src (8 js)

# lockfiles in sync for the workflow's `npm ci`
cd typescript && npm ci && cd ../typescript-client && npm ci   # both 0
```

`publish.yml` + `ci.yml` parse as valid YAML (`actionlint` unavailable here);
pipelines unchanged on PRs (publish only runs on tags).

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | All three published at one aligned version (0.2.0) | ⏸ publish credential-gated |
| 2 | Publish is tag-triggered + reproducible (CI job) | ✅ |
| 3 | Clean registry install verifies the anchored fixture, no env | ✅ locally; `smoke` job |
| 4 | Install docs added | ✅ |
| 5 | CI green | ✅ |

## Deferred (external — release owner)

Configure once, then tag:

1. PyPI **Trusted Publishing** for repo `arman-jalili/rigorix-sdk`, workflow
   `publish.yml`.
2. Repo secret **`NPM_TOKEN`** (automation token, 2FA bypass for CI).
3. `git tag v0.2.0 && git push origin v0.2.0` → the workflow publishes all three
   and runs the registry-install smoke.

(The npm tarballs for `rigorix-verifier`/`rigorix-client` already contain the
real `_schemas` / `dist` — the #30 bundling machinery, re-asserted here.)
