# #69 · pin and audit the two gate runtimes

Branch: `issue/69`. Decided at the gate: **raise the Go floor to 1.26**, CI reads
`go-version-file` + `check-latest` so the stdlib is always the newest patch.

Order: manifests (pins, floor) → pin guard → audit workflow → runtime reporting →
ownership policy → local-ci mirrors audit.yml → READMEs.

Evidence:
- `scripts/check-pins.py`: pass; planted `wasmtime>=20.0` fails quoting line 19.
- `pip-audit --strict`: clean; planted `pyyaml==5.1` → exit 1, PYSEC-2020-176.
- `govulncheck ./...` (Go 1.26.10): clean; planted x/text v0.14.0 → exit 3, GO-2026-6629.
- `binding.runtime_version()` == `50.0.1`, asserted equal to the pyproject pin.
- local CI: the verdict prints the count it executed — `35 step(s) executed`
  (all), 28 (`--jobs-only`), 7 (`--validators-only`).
- the three seeds now run in `local-ci` too, and each asserts *why* it failed
  (the range named, PYSEC id, exit 3 naming the planted module), because a seed
  that fails for the wrong reason proves nothing.
