## Summary

Closes #50. The post-publish smoke job retried `12 × 20s = 4 minutes` and treated
every failure as "not yet available". npm propagation has been observed past 4
minutes, so the gate failed a **successful** `v0.6.0` release; re-running only the
smoke job passed minutes later. It also could not tell "not visible yet" from
"visible but broken" — so a real post-publish defect would have been retried and
then reported as a generic failure.

## Fix

A tested helper, `.github/scripts/wait-for-registry.sh`, now drives both install
steps:

| Situation | Exit | Outcome |
|---|---|---|
| install succeeds | 0 | verified |
| failure matches a propagation/transient signature | retry | wait, then re-run |
| failure is anything else (`EINTEGRITY`, wheel build error, …) | 2 | **visible but broken** — fail fast |
| still not visible after the window | 3 | **propagation timeout — published, smoke unverified** |

- **Window:** 15 minutes (45 × 20s), covering observed npm latency; the smoke job
  timeout is raised 20 → 40 min for two windows plus setup.
- **Retryable:** PyPI `No matching distribution found` / 404 / 503 / timeouts;
  npm `ETARGET` / `E404` / `No matching version found` / timeouts.
- **Distinct give-up:** exit 3 with a titled `::error::` annotation and a step
  summary stating *artifacts published, smoke unverified* — explicitly not a bad
  artifact. It is still a failing step (not advisory).
- `--no-cache-dir` (pip) and `--prefer-online` (npm) avoid stale negative caches.

## Never re-publishes

The smoke job has **no publish step** (checkout/setup + install + fixture checks
only), and the helper runs only the command it is given. Re-running the smoke job
alone installs and verifies; it cannot push.

## Files

| File | Change |
|---|---|
| `.github/scripts/wait-for-registry.sh` | **new** helper |
| `.github/workflows/publish.yml` | smoke job uses the helper; timeout 40 min |
| `.github/workflows/ci.yml` | **new** `publish-helper` job (syntax + classification self-test) |
| `rust/RELEASING.md` | smoke semantics + re-run guidance |

The new CI job matters because the smoke only runs on a tag — without it, a broken
helper would surface at the next release.

## Verification

```
bash -n .github/scripts/wait-for-registry.sh    ✅
success                                         ✅ exit 0
visible-but-broken (EINTEGRITY)                  ✅ exit 2 (no retry)
not-visible → timeout                            ✅ exit 3
not-visible ×1 → success                         ✅ exit 0
YAML parse (ci.yml, publish.yml)                 ✅
validate-ci / tests / security / operations      ✅
```

The `publish-helper` CI job runs the same four classification cases on every PR.

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Retry window covers observed npm propagation latency | ✅ 15 min |
| 2 | "Not yet visible" vs "visible but broken" distinguished | ✅ |
| 3 | Give-up reports propagation-timeout distinctly | ✅ exit 3 + annotation/summary |
| 4 | Never triggers a re-publish | ✅ smoke has no publish step |
