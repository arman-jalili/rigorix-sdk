## What this does

The gate moved the decision into a `.wasm` and, by doing so, added a dependency
the project never had: **a wasm engine inside the customer's process** —
`wasmtime` (Python) and `wazero` (Go). Both are now pinned, scanned and owned.

### Exact pins, guarded by a script

```
wasmtime==50.0.1                  (python/pyproject.toml)
github.com/tetratelabs/wazero v1.12.0   (go/go.mod)
```

`scripts/check-pins.py` fails on a range, quoting the line:

```
$ sed -i 's/"wasmtime==50.0.1"/"wasmtime>=20.0"/'
$ python3 scripts/check-pins.py
❌ python/pyproject.toml:19: wasmtime must be pinned exactly (==X.Y.Z), not a range
    wasmtime>=20.0
exit=1
```

It also refuses a provenance that names a different runtime than the manifest.
**Scope decision:** the exact-pin rule covers the two wasm engines — the versions
recorded in `PROVENANCE.md` and reported at run time. `jsonschema` and
`cryptography` keep compatible ranges: they are audited, but pinning a library
exactly fights its consumers and they are not what an incident report quotes.

### Advisories fail the build

`.github/workflows/audit.yml` runs on every PR, on `main`, and weekly
(advisories arrive after a merge):

- `pip-audit --strict` on the environment the wheel runs in
- `govulncheck ./...` at symbol level

Each job proves its own guard with a planted advisory, so a silently inert gate
fails CI too. Verified locally:

```
pip-audit -r pyyaml==5.1        → exit 1, PYSEC-2020-176 named
govulncheck -scan=module        → exit 3, GO-2026-6629 named (planted x/text v0.14.0)
pip-audit --strict (clean env)  → "No known vulnerabilities found"
govulncheck ./... (Go 1.26.10)  → "No vulnerabilities found"
```

### Go floor 1.22 → 1.26 (decision)

A strict `govulncheck` cannot be green on the old floor: the fixed
`golang.org/x/text` releases require Go 1.25, and the local 1.26.3 stdlib had 17
reachable advisories. Per your call, `go.mod` now declares `go 1.26` and CI reads
it with `check-latest`, so the build always uses the newest patch; with 1.26.10
and `x/text v0.41.0` the scan is clean today.

### Provenance and ownership

- `binding.runtime_version()` reports the installed engine (`importlib.metadata`;
  the module has no `__version__`), and a test asserts it equals the pin — the
  manifest is the fact, not a copy of it.
- The packaged `PROVENANCE.md` gains a **Runtime** section: artifact digest,
  contract version, engine version are the three numbers a support case quotes.
- **`SECURITY.md`** (new): who answers a wasmtime/wazero advisory (the maintainer
  on call), how fast (within the ecosystem's disclosure window), and what ships
  (a patch release the same day a fixed runtime exists, naming the runtime).

## Validation

GitHub Actions minutes are exhausted, so the gate is `.ci/local-ci.sh`, which now
mirrors `audit.yml` as well. The runner prints how many steps it executed; the
count below is copied from its verdict line, not typed by hand (it reads
`35 step(s) executed`, exit 0), with Go 1.26.10 on PATH:

```
artifact guard ✅ · rust (fmt, clippy, test, package, smoke, self-containment, no-engine) ✅
python (linux docker) ✅ 50 passed, 1 skipped · ts-verifier (incl. real Chrome) ✅ · ts-client ✅
go (corpus, vet, test, CGO_ENABLED=0) ✅ · java ✅ · publish-helper ✅
audit: pins ✅ · pip-audit ✅ · govulncheck ✅ · the three seeds fire ✅
validators ×7 ✅      LOCAL CI: GREEN — 35 step(s) executed
```

The seeds are part of the runner (`--jobs-only` prints 28, `--validators-only`
prints 7), so the planted range, the planted advisory and the planted vulnerable
module are executed evidence on any machine with Docker and Go — not a claim
about a workflow that has not started.

Closes #69.