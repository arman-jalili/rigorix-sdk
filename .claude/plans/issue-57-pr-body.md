## Summary

Refs #57 — **not closed**, because Maven and PyPI publishing remain externally blocked.

The `scope_check` code fix and cross-language fixture tests already landed on `main` (`aa6f563`,
`8ce4223`, `00fc015`), and npm `rigorix-verifier@0.8.1` is published with the field. This PR
completes the source and guard side:

- Fix the stale PyPI `__version__` (0.8.0 → 0.8.1; `pyproject.toml` was already 0.8.1).
- Make `validate-channel-versions.sh` lock the **four verifier channels** (crates.io verifier, npm
  verifier, PyPI, Maven), report `rigorix-schemas`/clients as independent cadence, and still fail
  on stale intra-workspace pins.
- Add self-test seeds for the #57 three-behind state (npm at 0.8.0) and a stale `__version__`.
- Update `RELEASING.md` to the verifier-only lockstep and correct the Maven URL to `eu/rigorix`.

## Current published state (verified)

| Channel | Published | `scope_check` |
|---|---|---|
| crates.io `rigorix-verifier` | **0.8.1** | yes (signature/chain; `rigorix-schemas 0.8.0` allows unknown fields) |
| npm `rigorix-verifier` | **0.8.1** | yes (`_schemas` + canonical skip-none in the package) |
| Maven `eu.rigorix:rigorix-verifier` | 0.8.0 | no |
| PyPI `rigorix-verifier` | 0.6.0 | no |

Maven is blocked on the GPG key/pinentry and namespace; PyPI on GitHub Actions billing (OIDC only).
This PR cannot publish either.

## Why verifier-only lockstep

The published Rust 0.8.1 exact-pins `rigorix-schemas = "=0.8.0"`; the schema crate allows additional
envelope properties, so 0.8.1 accepts `scope_check` without a schema republish. Locking the verifier
to the workspace/schema/client versions would force a new Rust release for every verifier patch and
break the reproducibility of the already-published 0.8.1. The clients are an independent cadence
(`RELEASING.md`), but their `rigorix-schemas` pins are still checked against the workspace version.

## Verification

```
validate-channel-versions.sh                 ✅ 5 verifier manifests agree on 0.8.1
validate-channel-versions.sh --self-test     ✅ consistent accepted; 5 drifts rejected
  seeds: Java drift, three-behind npm, stale __version__, stale pin, empty root
rust: test --all (33) / clippy -D warnings / fmt ✅
python: pytest (20)                          ✅
typescript: verifier (20) + client (10)      ✅
go: ./...                                    ✅
java: mvn -B -q verify                       ✅
validators: ci/tests/security/operations/canonical/architecture/integration ✅
```

## Remaining for #57

1. Publish **Maven 0.8.1** (GPG/pinentry + verified namespace).
2. Publish **PyPI 0.8.1** once Actions billing is restored.
3. Then verify each resolves (`npm view`, `pip index versions`, Maven metadata) before closing.

The guard now fails before publish when any verifier channel is behind, which is the issue's third
acceptance criterion.
