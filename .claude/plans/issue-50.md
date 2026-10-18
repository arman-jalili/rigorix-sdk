# Implementation Plan: issue/50

**Branch:** `issue/50`
**Base:** `main` (`7c0a6c4`, SDK 0.5.0 shipped; v0.6.0 release failed the smoke gate)
**Issue:** #50 — publish smoke retry budget too tight for npm propagation
**Severity:** low (release-pipeline reliability, not a release defect)

## Status

- [x] Root cause confirmed (4-min window; no visibility/broken distinction)
- [x] Tested retry helper added
- [x] `publish.yml` smoke job wired to it (15-min window, 40-min job timeout)
- [x] CI self-test job added
- [x] Release doc updated
- [ ] MR created
- [ ] Merged

## Root cause

`publish.yml`'s smoke job retried `12 × 20s = 4 minutes` for both PyPI and npm,
and treated every failure as "not yet available". On the `v0.6.0` release the
packages were live minutes later; re-running only the smoke job passed. A red
release on a non-defect invites blind re-runs, which can mask a real defect.

## Changes

| File | Change |
|---|---|
| `.github/scripts/wait-for-registry.sh` | **new** helper: 15-min default window (45 × 20s), per-ecosystem retryable signatures, fail-fast on visible-but-broken, distinct give-up outcome |
| `.github/workflows/publish.yml` | smoke job uses the helper for PyPI + npm; job timeout 20 → 40 min (two windows + setup); `--no-cache-dir` / `--prefer-online` |
| `.github/workflows/ci.yml` | **new** `publish-helper` job: `bash -n` + classification self-test (success / broken / timeout / retry-then-success) |
| `rust/RELEASING.md` | note the smoke semantics + "re-run the smoke job, it never re-publishes" |

## Behavior (the contract the helper enforces)

| Situation | Exit | Outcome |
|---|---|---|
| install succeeds | 0 | verified |
| failure matches a propagation/transient signature | retry | wait, then re-run |
| failure is anything else (e.g. `EINTEGRITY`, wheel build error) | 2 | **visible but broken** — fail fast |
| still not visible after the window | 3 | **propagation timeout — published, smoke unverified** |

Retryable signatures:
- PyPI: `No matching distribution found`, `Could not find a version that satisfies`, 404/503, timeouts/resets/DNS.
- npm: `ETARGET`, `No matching version found`, `E404`, timeouts/resets/DNS.

Exit codes 2/3 are distinct; each writes a titled GitHub annotation and a step
summary, so the release state is unambiguous (a timeout is not a bad artifact).

## Never re-publishes

- The `smoke` job has no publish step (only checkout/setup + installs + fixture checks).
- The helper executes only the command it is given; it contains no publish verb.
- Re-running the `smoke` job alone therefore installs and verifies; it cannot push.

## Local verification

```
bash -n .github/scripts/wait-for-registry.sh                      ✅
success                                                           ✅ exit 0
visible-but-broken (EINTEGRITY)                                    ✅ exit 2 (no retry)
not-visible → timeout (max attempts 1)                             ✅ exit 3
not-visible ×1 → success (retry loop)                              ✅ exit 0
YAML parse (ci.yml, publish.yml)                                   ✅
validate-ci / tests / security / operations                        ✅
```

## Acceptance criteria (#50)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Retry window covers observed npm propagation latency | ✅ 15 min (45 × 20s) |
| 2 | "Not yet visible" vs "visible but broken" distinguished | ✅ signatures + exit 2 |
| 3 | Give-up reports propagation-timeout distinctly | ✅ exit 3, titled annotation + summary |
| 4 | Never triggers a re-publish (re-running the job does not re-push) | ✅ smoke has no publish step |
