# Contributing

## Licence of a contribution

This project is **Apache-2.0** ([LICENSE](LICENSE), [NOTICE](NOTICE)). By
contributing you agree that your contribution is licensed under the same terms.

## Developer Certificate of Origin (DCO), not a CLA

Every commit must carry a sign-off:

```bash
git commit -s -m "fix(scope): what changed and why"
```

That appends the trailer

```
Signed-off-by: Your Name <you@example.com>
```

using the name and email in your `user.name` / `user.email`. The trailer
certifies the [Developer Certificate of Origin 1.1](https://developercertificate.org/):
that you wrote the change, or have the right to submit it under this licence.

**Why DCO and not a CLA:** a CLA would give this project a relicensing option it
does not want, and the DCO is the lower-friction instrument for a
specification-adjacent project. The check is mechanical, so nothing depends on
anyone remembering to ask.

CI enforces it: `scripts/check-dco.sh` checks every commit in a pull request and
refuses one without the trailer, naming the commit. Run it locally:

```bash
bash scripts/check-dco.sh --self-test        # proves the check can refuse
bash scripts/check-dco.sh origin/main..HEAD  # your branch
```

Commits made before this policy have no trailer; they are accepted as history and
are not rewritten. The policy applies to commits from its introduction onward.

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