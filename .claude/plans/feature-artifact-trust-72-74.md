# Batch A — artifact trust (#74, #72, #73)

Branch: `feature/artifact-trust-72-74`. Order: **#74 → #72 → #73**, because the
guard creates the single fact the loaders then enforce, and the local runner is
made honest about the suite that proves both.

## #74 · the two copies are one fact

- `scripts/check-vendored-artifact.sh` (new): both copies exist, are byte-identical
  and hash to the digest recorded in both `PROVENANCE.md` files and in both
  source constants (`loader.ARTIFACT_SHA256`, `gate.artifactSHA256`); sizes agree.
  A failure names the file that drifted and both digests.
- Both `PROVENANCE.md`: drop the stale `SDL-3` / `SDL-4` split for one identifier,
  and add **Obtainability** — no published asset today, build from the commit;
  the line becomes the release URL when `v1.14.3` ships (digest unchanged).
- Wire the guard into the CI `verifier` job and `local-ci`.

## #72 · a modified artifact is refused at load, in both languages

Corrected premise: **neither** language checked the digest at load; Python's check
lives in a test. So both gain it:

- Go: `artifact.go` with `artifactSHA256`, `artifactSize`, `ErrArtifactDigestMismatch`
  and `*ArtifactDigestError` (expected/actual digest + size). `Open` verifies before
  compiling; `OpenBytes` → `OpenUnverified`, documented as the opt-out.
- Python: `loader.verify_artifact(raw)` names both digests; `Gate.open` verifies the
  vendored bytes; caller bytes go through `Gate.open_unverified(...)`.
- Both READMEs carry the same sentence, naming the check rather than the test.

## #73 · a skipped suite is not a green step

- `run()` parses pytest's summary line. A suite that reports `N skipped` with zero
  passed/failed is **not** evidence: it fails the step, naming the suite and the
  skip reason (`-rs` puts the reason in the log).
- `--allow-skips`: the step prints `⏭`/`SKIPPED` in the summary and never `✅`;
  the run exits **3** (green except skips) so a caller cannot mistake it for full
  evidence. Exit codes: 0 green, 1 red, 3 green-with-skips.
- The #74 guard becomes a step, so the runner exercises the new fact.

## Gate

`bash .ci/local-ci.sh` (all 7 jobs + 7 validators) and, for this batch specifically:

```bash
bash scripts/check-vendored-artifact.sh
cd go && go test ./gate/... && CGO_ENABLED=0 go test ./gate/...
python3 -m pytest -q python/tests/binding_test.py     # 12 skipped on Darwin → red unless Docker
bash .ci/local-ci.sh --jobs-only                       # docker present → binding runs
```