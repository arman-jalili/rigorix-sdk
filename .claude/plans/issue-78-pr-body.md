## The release exists and is not the build we shipped

Read from the release page, not a workflow file:

```
v1.14.3  rigorix_gate_wasi.wasm   1,899,431 B   sha256:ab77bb82…
tag      v1.14.3 → c8d162e11a5b9c9c50c34d03211e33df33537d48
shipped  7414f8df…, 1,896,910 B, built from a314672c (never a release)
```

The old recordings were mutually consistent, which is why nothing here could
notice: `check-vendored-artifact.sh` compares them to each other, not to the
release. Four batches of engine code landed between `a314672c` and the tag.

## What changed

- Both copies replaced by the **downloaded** asset — not a local rebuild: a
  macOS build of `c8d162e1` hashes to `0cfacf43…`, pinning a digest no download
  reproduces.
- Every recording moved in one commit: both `PROVENANCE.md`, both source
  constants, the guard's `EXPECTED_SIZE`, and the two tests that pinned
  `contract == "1.14.2"`.
- `Obtainability` now names the tag, the asset, the digest and the commit the tag
  peels to — and the reason a local build is not the answer.

## Verified before vendoring

Probed through `open_unverified` so the digest check could not mask a decision
change:

```
seeded-0001        contract=1.14.3  engine=1.14.3  gate=True diverge   OK
vec-0001           contract=1.14.3  reproduce OK
vec-0002           contract=1.14.3  reproduce OK
vec-0003           contract=1.14.3  reproduce OK
vec-fixture-0001   contract=1.14.3  reproduce OK
```

The artifact moved; the decisions and the runtime (`50.0.1`) did not.

## Acceptance

| # | Criterion | Result |
|---|---|---|
| 1 | copies are the release | all three hash `ab77bb82…`, 1,899,431 B |
| 2 | recordings agree | `✅ one artifact: ab77bb82… (1899431 B)` |
| 3 | the gate still decides | Python 15 passed; Go `TestConformance` + `CGO_ENABLED=0` pass |
| 4 | obtainability is true | names `v1.14.3`, the asset, `ab77bb82…`, `c8d162e1` |

## Gate

`bash .ci/local-ci.sh` (Go 1.26.10 on PATH) → **GREEN — 35 step(s) executed**,
exit 0. Actions minutes are still exhausted; the count is the runner's verdict
line.

Closes #78.
