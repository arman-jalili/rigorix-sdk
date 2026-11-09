## What this batch does

Three issues, one component family, ordered so each step creates the fact the
next one enforces: **#74** makes the two vendored copies one fact, **#72** makes
both loaders enforce the digest that guard pins, **#73** makes the local runner
honest about the suite that proves both.

### #74 · one artifact, one fact

`scripts/check-vendored-artifact.sh` compares the four recordings of one digest
(Go copy, Python copy, both `PROVENANCE.md`, both source constants) and fails
naming the file that drifted. Wired into the CI `verifier` job and `local-ci`.

Both provenance files drop the stale `SDL-3`/`SDL-4` split and gain
**Obtainability**: `v1.14.2` has no asset and `package-wasi` never ran, so the
artifact is built from the recorded commit — and a rebuild is byte-identical, so
the digest is a function of the commit.

Probes (run, then restored):

```
flip 1 byte in go/gate/testdata/…  → ❌ names the Go copy + both digests, exit 1
rewrite PROVENANCE sha256          → ❌ names the line, exit 1
```

### #72 · refuse a modified artifact at load, in both languages

**Corrected premise (code is truth).** The issue says "Python refuses a digest
mismatch at load". It did not: `loader.py` validated only the import/export
sets, and the digest was checked in `binding_test.py:184`. Neither language
checked at load. So this adds the check to both — which is what acceptance
criterion 4 ("both READMEs state a load-time check") requires.

- Go: `*gate.ArtifactDigestError` (expected/actual digest **and** size,
  `errors.Is(err, gate.ErrArtifactDigestMismatch)`); `Open` verifies before
  compiling; `OpenBytes` → `OpenUnverified`.
- Python: `ArtifactDigestMismatch` + `loader.verify_artifact`; `Gate.open`
  verifies; `Gate.open_unverified(artifact=…)` is the opt-out.
- Both READMEs carry the same sentence, naming the check rather than the test.

### #73 · a skipped suite is not a green step

`run()` now parses pytest's summary. The binding suite is its **own** step,
because a whole-suite check never fires — the other Python tests still pass, so
the pre-fix log read `49 passed, 14 skipped` and exited 0.

```
docker hidden, no --allow-skips  → ❌ "executed 0 tests (14 skipped)", reason quoted, exit 1
docker hidden, --allow-skips     → ⏭ SKIPPED, summary lists the step, exit 3
docker present                   → ✅ 49 passed, 1 skipped, exit 0
```

Two host-branch defects fell out of actually exercising it: a missing
`LOCAL_CI_LOG_DIR` failed every step, and the host smoke used `python` plus a
system-wide `build` that macOS does not have (it now builds in a venv).

## Validation

GitHub Actions minutes are exhausted, so the gate is `bash .ci/local-ci.sh`
(mirrors all seven jobs + the seven `.pi` validators). **29/29 green:**

```
artifact: both vendored copies agree        ✅
rust: fmt · clippy · test --workspace       ✅  (+ package, packaged smoke, self-containment, no engine dep)
python: pytest + wheel/sdist (linux docker) ✅  49 passed, 1 skipped
ts-verifier: npm ci · test · browser · pack ✅  (real Chrome conformance)
ts-client: npm ci · test                    ✅
go: corpus · vet · test · CGO_ENABLED=0     ✅
java: mvn verify                            ✅
publish-helper: syntax + classification     ✅
validators ×7 (ci, tests, security, operations, canonical, architecture, integration) ✅
LOCAL CI: GREEN — exit 0
```

Exit codes are now meaningful: `0` green, `1` failed, `3` green-but-skipped.

Closes #74. Closes #72. Closes #73.