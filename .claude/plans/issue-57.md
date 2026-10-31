# Implementation Plan: issue/57

**Branch:** `issue/57`
**Base:** `main` (`00fc015`)
**Issue:** #57 — 0.8.1 admits scope_check in every verifier; Maven/PyPI publishing still blocked
**Severity:** high (release integrity)

## Status

- [x] Verified the code fix + cross-language fixture tests already on main
- [x] Verified published state (npm 0.8.1 with scope_check; Maven 0.8.0; PyPI 0.6.0)
- [x] Fixed the stale PyPI `__version__`
- [x] Guard narrowed to verifier channels + pin consistency
- [x] Self-test seeds the three-behind state and stale `__version__`
- [x] All language suites + validators green
- [ ] MR created
- [ ] Maven/PyPI publish (externally blocked)

## What was already done (on main, not in this PR)

| Commit | Change |
|---|---|
| `aa6f563` | Rust verifier struct + `schemas/envelope.json` admit `scope_check`; crates.io 0.8.1 |
| `8ce4223` | Java/TS/Python canonical skip-none include `scope_check`; engine-signed rich fixtures carry it; npm/Java/Python source → 0.8.1 |
| `00fc015` | Per-language tests assert the shared fixture carries `scope_check` and verify it |

Published check (this session):

- npm `rigorix-verifier@0.8.1` — package contains `scope_check` in `_schemas/envelope.json` and `dist/src/canonical.js`.
- Maven `eu.rigorix:rigorix-verifier` — latest 0.8.0.
- PyPI `rigorix-verifier` — 0.6.0.
- crates.io `rigorix-schemas 0.8.0` — lacks the `scope_check` property, but the envelope schema allows additional properties, so acceptance is unaffected.

## Decisions (review-confirmed)

**Verifier-only lockstep.** The four verifier channels must agree: crates.io verifier, npm verifier,
PyPI, Maven. `rigorix-schemas` and the clients are an independent cadence; their pins must match the
workspace version, but a verifier patch does not force a schema/client release. This keeps the
published Rust 0.8.1 (`=0.8.0` schemas) reproducible and matches #57's in-scope/out-of-scope.

## Changes

| File | Change |
|---|---|
| `python/rigorix_verifier/__init__.py` | `__version__` 0.8.0 → 0.8.1 (pyproject was already 0.8.1) |
| `.pi/scripts/validate-channel-versions.sh` | compare the four verifier channels; report schemas/clients as independent; keep stale-pin failure; self-test seeds Java drift, three-behind npm, stale `__version__`, stale pin, empty root |
| `RELEASING.md` | verifier-only lockstep policy; Maven URL corrected to `eu/rigorix` |

## Verification

```
validate-channel-versions.sh                 ✅ 5 verifier manifests agree on 0.8.1
validate-channel-versions.sh --self-test     ✅ consistent accepted; 5 drifts rejected
rust: test --all (33) / clippy / fmt         ✅
python: pytest (20)                          ✅
typescript: verifier (20) + client (10)      ✅
go: ./...                                    ✅
java: mvn -B -q verify                       ✅
validators: ci/tests/security/operations/canonical/architecture/integration ✅
```

## Remaining (why the issue stays open)

1. **Maven 0.8.1** — source is ready; publish blocked on the GPG key/pinentry and the verified
   `eu.rigorix` namespace.
2. **PyPI 0.8.1** — source is ready; publish blocked on GitHub Actions billing (Trusted Publishing
   is the only path).
3. npm is already 0.8.1; crates.io verifier is 0.8.1.

The guard now fails before publish if any verifier channel is behind, which is the issue's third
acceptance criterion. The issue should be closed when Maven and PyPI resolve 0.8.1.
