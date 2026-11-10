# Contributing

## Licence of a contribution

This project is **Apache-2.0** ([LICENSE](LICENSE), [NOTICE](NOTICE)). By
contributing you agree that your contribution is licensed under the same terms.

## Contributor Licence Agreement

Every contribution is made under the [Contributor Licence Agreement](docs/CLA.md)
(version 1.0). You keep copyright; you grant the project a copyright licence, a
patent licence, and the right to relicense the contribution under any licence the
project adopts.

**A pull request whose author has not signed cannot be merged.** Signing happens on
the pull request itself: the CLA bot comments once and waits for your confirmation,
and the signature record (account, agreement version, date) is what the required
check reads.

### Why a CLA and not a `Signed-off-by` trailer

The project previously used a DCO sign-off. A sign-off records that you had the
right to submit the work, and it grants nothing else — so it preserves no ability
to change the project's licence, which is the one thing a licence agreement exists
to preserve. Version 1.0 of the CLA is the replacement, and the DCO check is gone
with it: two gates enforcing different agreements is worse than one gate.

### Until the bot is live

The repository is private on a free plan, where GitHub does not offer branch
protection or required status checks (both return `403 Upgrade to GitHub Pro or
make this repository public`). The bot can be installed while private, but the
check cannot be made required until the visibility change. In that window the
maintainer asks for the signature on the pull request and records it before
merging; the required check is applied in the same operation that makes the
repository public, by the operator — never after it. This paragraph exists so the
gap is a known state with an owner, not a hole.

## Before you write code

```bash
bash .ci/local-ci.sh          # all seven CI jobs plus the seven validators
```

That is the same gate CI runs. Two notes for a macOS machine:

- the Python binding tests run in Linux Docker (`wasmtime`'s JIT is killed by the
  macOS sandbox); without Docker the step reports `SKIPPED` and the runner exits
  `3`, which is not a pass;
- `govulncheck` reports the standard library of the toolchain that builds, so the
  audit job needs the newest patch of the Go floor in `go/go.mod`.

## Rules this repository holds itself to

1. **Code is truth.** Schema and contract shapes are derived from the upstream
   Rust types, never invented. If a document and the code disagree, the code wins
   and the document is corrected in the same pull request.
2. **Contract changes are decisions.** A change to `schemas/` is not an edit; it
   is a decision with a delta note under `docs/` and a drift check on both sides.
3. **Generated files are regenerated, never hand-edited.** The Go corpus
   (`cd go && go generate ./...`), the Python `_schemas/` bundle and the
   TypeScript browser corpus are produced by their scripts.
4. **Governed flows only.** No SDK may expose a direct-execute path.
5. **A guard has been shown to bite, or it is a claim.** Tests for a guard plant
   the failure it exists for; a seed that did not run is not evidence.

## Scope

Bug reports, contract discrepancies, and portability fixes are always welcome.
For a change to a frozen schema or the API catalog, open an issue first: those
are additive-only within a major version, and the delta note is part of the
change.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Report a security issue privately
per [SECURITY.md](SECURITY.md), never in a public issue.

## A note on headers

Published entry points carry `SPDX-License-Identifier: Apache-2.0` so a file
copied out of its repository keeps its terms. New source files should start with
that line; a missing line in an older file is not a licence ambiguity — the
repository licence governs.