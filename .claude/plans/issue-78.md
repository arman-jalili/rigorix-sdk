# #78 · re-vendor the artifact from the v1.14.3 release

Branch: `issue/78`. The release exists and is **not** the build we vendor.

Facts read from the release, not from a workflow file:

```
asset  rigorix_gate_wasi.wasm   1,899,431 B   sha256:ab77bb82…   v1.14.3
tag    v1.14.3 → c8d162e11a5b9c9c50c34d03211e33df33537d48
prev   7414f8df…, 1,896,910 B, a314672c (not a release)
```

Order: download the asset (never a local rebuild — a macOS build of `c8d162e1`
hashes to `0cfacf43…`, pinning a digest no download reproduces), probe it against
the five vectors through `open_unverified`, then move all recordings in one
commit so the guard names nothing.

Recordings moved: both copies, both `PROVENANCE.md` (digest, size, crate,
contract/engine, Obtainability), both source constants, the guard's
`EXPECTED_SIZE`, and the two tests that pinned `contract == 1.14.2`.

Probe result (before touching anything): contract/engine `1.14.3`,
`gate_evaluation: true`, five vectors reproduce with `seeded-0001` diverging as
recorded — the artifact moved, the decisions did not. `runtime_version()` is
`50.0.1`, unchanged: the runtime did not move either.

Gate: `bash .ci/local-ci.sh` → the verdict line, 35 steps.
