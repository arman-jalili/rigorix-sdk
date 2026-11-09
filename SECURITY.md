# Security policy

## Report a vulnerability

Use a **private GitHub security advisory** on this repository
(`Security → Report a vulnerability`). Do not open a public issue: the report
needs to reach a person before it reaches a reader.

Include the artifact digest (`7414f8df…`), the `contract` version and the wasm
runtime version — the three numbers a decision depends on. `rigorix_verifier.binding.runtime_version()`
reports the third; both `PROVENANCE.md` files record the first.

## The runtimes this SDK now owns

The in-process gate executes a `.wasm` artifact inside a wasm engine we do not
write: **`wasmtime`** (Python) and **`wazero`** (Go). Both are pinned exactly, so
"the runtime version" is a fact rather than a range, and both are scanned for
known advisories on every pull request and weekly
(`.github/workflows/audit.yml`: `pip-audit --strict`, `govulncheck ./...`).

**Who answers, and how fast:** the SDK maintainer on call answers a `wasmtime` or
`wazero` advisory within that ecosystem's disclosure window (the GHSA or RUSTSEC
publication date), and ships a patch release on the same day a fixed runtime
version exists. The advisory text names the runtime and the pinned version it
moves from, and the release notes name the artifact digest, contract version and
runtime version it moves to. "We will look at it" is not a policy; a date is.

`pip-audit` and `govulncheck` fail the build on a *known* advisory. Unknown ones
are the reason the runtimes are pinned and the ownership sentence exists.