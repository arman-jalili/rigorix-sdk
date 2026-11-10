# Publication readiness (PUB-1)

What had to be true before this repository could be public, what was decided, and
what a stranger can rely on. The assessment lives here so the decision is not in
a chat log.

## Assessment

| question | answer | evidence |
|---|---|---|
| are the artefacts already public? | **yes** | `rigorix-schemas`, `rigorix-verifier`, `rigorix-client` on crates.io; `rigorix-verifier` 0.9.0 on npm, PyPI and Maven Central |
| is the contract already public? | **yes** | `cargo package --list -p rigorix-schemas` publishes `schemas/api/effect-record.json`, `authority-fact-bundle.json`, `catalog.json`, `errors.json` |
| any private dependency? | **no** | no `git =` deps, no private registry, no `.npmrc` |
| any enterprise-only code? | **no** | one comment in `go/client/catalog.go` names an enterprise surface; the code is the public catalog |
| secrets in tracked files? | **no** | only the repo's own secret *patterns* in `.pi/extensions/redaction.ts` and the preflight scanners |
| licence? | Apache-2.0 | `LICENSE`, workspace `license`, npm ×2, `pyproject.toml` — see [PUB-2](#licence-and-contribution-policy-pub-2) |

## Decision 1 — the history is accepted, not rewritten

**Measured on 2026-11-11, at `dbc6ffe`.** Two scopes, because publishing exposes
both: `git log --grep` reads commit *messages*, while a clone exposes *blobs*.
The earlier version of this section reported only the first and the reader would
have carried away the smaller number.

| name (class) | tip files | message mentions | revisions whose blobs contain it |
|---|---|---|---|
| product repository | 0 | 3 | 114 |
| web-properties repository | 0 | 1 | 29 |
| demo repository | 0 | 0 | 2 |

Names are supplied out of band — this file is part of the tip, so it states the
method rather than the names it keeps out:

```bash
PRIVATE_NAMES="<name>,<name>,<name>" bash scripts/history-scope.sh
# tip files        git grep -il -- "<name>" -- . | wc -l
# message mentions git log --all --oneline --grep="<name>" | wc -l
# blob revisions   git grep -il -- "<name>" $(git rev-list --all) | cut -d: -f1 | sort -u | wc -l
```

The demo repository is why the scope matters: **0 message mentions, 2 revisions
whose blobs contain it.** A decision measured by `--grep` alone would not have
known it was publishing that name at all.

For completeness: `git rev-list --count --all` → 116 revisions across 30 refs.
The issue that requested this cited 109 commits and 22 mentions; those numbers do
not describe this tree, and the decision rests on the measured ones. (Code is
truth: the measurement wins.)

**Decision: accept the history, messages *and* blobs, and publish it as it is.**
Rationale, name class by name class:

1. **The product repository's name (114 revisions of blobs, 3 messages).** The
   enterprise product is public by design — ADR-012, "OSS attests, enterprise
   authorizes". The name appears in contract-sync prose that explains which
   implementation a fixture or a record came from; that provenance is part of the
   contract reasoning this repository publishes. Accepting the messages and
   rejecting the blobs would break every link between a schema and its grounds.
2. **The web-properties repository's name (29 revisions, 1 message).** It appears
   in the same prose and in the plan record. Accepting it publishes that a
   demonstration site exists; it does not publish anything the site itself does
   not.
3. **The demo repository's name (2 revisions, 0 messages).** Appears once in
   fixture provenance. Accepted, for the same reason: the fixture is meaningless
   without saying what produced it.
4. **The site repository's name.** Not in the history at any scope. Checked with
   the same three commands against a name supplied out of band; a reader can
   reproduce the zero by supplying it. This is the one claim the document cannot
   spell out without defeating itself, and it is stated as a checkable zero rather
   than as an adjective.
5. **Cost.** Scrubbing with `git filter-repo` rewrites all 79 shas. Every dossier
   that cites a commit sha stops resolving, and the provenance links of the
   already published 0.9.0 crates dangle — a permanent cost to hide names the
   product literature already states.

The cost of "accept" is that the names stay, in messages and in blobs. That is
the option this repository takes, and this table is the record the acceptance
criteria ask for.

### What the tip does instead

The sweep is separate from the history: the **tip** names no private repository.
23 occurrences in 8 files were rewritten using three shapes — name the artefact
where it is published, the deployment where it is not, and keep a file path where
a repository path was doing nothing:

| shape | before | after |
|---|---|---|
| deployment | `<repo> is a control plane` | `The enterprise product is a control plane` |
| consumer | `<repo>/core` | `the enterprise consumer's core` |
| bare path | `<repo> \`findings/x.md\`` | `\`findings/x.md\` in the enterprise repository` |

(`<repo>` is the private repository name; this file states the shape without
repeating it, because the file itself is part of the tip.)

`go/internal/corpus/corpus_gen.go` is generated, so the fix was made in
`schemas/README.md` and the corpus regenerated — the guard is `go generate` +
`git diff --exit-code`.

## The pipeline has not executed (#92)

**No GitHub Actions job has ever run in this repository.** Every job on `457c687`
(#82) and on `dbc6ffe` (#83) is `conclusion=failure` with `steps: 0` and no
runner, two seconds after start:

```
$ gh api repos/arman-jalili/rigorix-sdk/actions/runs/<id>/jobs \
    -q '.jobs[0] | "started \(.started_at) completed \(.completed_at) steps \(.steps|length)"'
started 2026-11-10T13:47:19Z completed 2026-11-10T13:47:21Z steps 0
```

That is an entitlement block (spending limit / billing), not a test result. So:

- **A green local run and an unexecuted pipeline are not the same claim.** Where
  this repository says a change is validated, the evidence is
  `bash .ci/local-ci.sh`, which mirrors all seven CI jobs plus the validators and
  prints the number of steps it executed. The verdict line is the record; the
  step count is never typed by hand.
- **The first thing to read when billing clears is the `audit` workflow.** Its
  seeds (`pip-audit` on a planted pin, `govulncheck` on a planted vulnerable
  module, `check-pins.py` on a planted range) have run in `local-ci`, not in
  Actions; a `pip-audit --strict` finding there is a real finding, not a flake.
- `govulncheck` is a property of the tree, not of the machine: the floor is
  `go 1.26` in `go/go.mod`, CI resolves it with `go-version-file` +
  `check-latest`, and both CI and `local-ci` print `go version` before scanning.
  Advisories the code does not call are printed (`-scan=module`) rather than
  swallowed, so a change in either number is visible.
- The DCO range check states its subject count; zero commits prints
  `no subject, not evidence` rather than a ✅. (`#84` replaces it with a CLA check,
  which has a subject — the pull request's author.)

## Per-channel licence state (#90)

The claim that "SPDX is on every published entry point" was true of the entry
files and false of two channels. Measured:

| channel | distributed as | files with the identifier |
|---|---|---|
| Rust (`rigorix-schemas`, `rigorix-verifier`, `rigorix-client`) | crate source | 3 / 3 entry points |
| Python (`rigorix-verifier`) | wheel + sdist | 1 / 1 entry point |
| TypeScript (`rigorix-verifier`, `rigorix-client`) | npm tarball | 2 / 2 entry points |
| Go (`.../rigorix-sdk/go`) | module source | **26 / 26** |
| Java (`eu.rigorix:rigorix-verifier`) | jar (sources on Central) | **12 / 12 main sources** |

`scripts/check-spdx.sh` checks 44 files and `--self-test` proves it refuses a file
with the header removed. The set is fixed in the script rather than discovered: a
guard that infers its own subject can shrink with a refactor and still pass.

## Licence audit of the graph (#86)

The repository is Apache-2.0; the dependencies are linked, not vendored, and
until this section nobody had read their licences. Measured on 2026-11-11 with
`cargo-deny 0.19.0`, `license-checker 25`, `pip-licenses 5.5.5`:

| ecosystem | graph | licences found | gate |
|---|---|---|---|
| Rust | 169 packages (`cargo metadata --offline`) | MIT OR Apache-2.0 (86), MIT (27), Unicode-3.0 (18), Apache-2.0 OR MIT (16), Apache-2.0 (4+4 deprecated `/` forms), BSD-3-Clause (3), Apache-2.0 WITH LLVM-exception (3), Unlicense OR MIT (2), BSD-2-Clause (2), MIT-0, BSD-1-Clause, LGPL-2.1-or-later (1, as an alternative) | `rust/deny.toml` + `cargo deny check licenses` |
| npm `typescript` | 14 packages | MIT (10), Apache-2.0 (3), BSD-3-Clause (1) | `license-checker --onlyAllow` |
| npm `typescript-client` | 4 packages | MIT (2), Apache-2.0 (2) | `license-checker --onlyAllow` |
| Python | 10 packages (`requirements.lock`) | MIT, Apache-2.0 OR BSD-3-Clause, BSD-3-Clause, PSF-2.0, Apache-2.0 WITH LLVM-exception | `pip-licenses --partial-match --fail-on` |
| Go | 3 modules (`go/go.sum`) | Apache-2.0 (wazero), BSD-3-Clause (`x/text`, `x/sys`) | **not gated by this script** — see below |
| Java | `java/pom.xml` | Apache-2.0 test/runtime jars | **not gated by this script** — see below |

No GPL, AGPL, SSPL, CDDL or EPL obligation is taken. `r-efi`'s
`MIT OR Apache-2.0 OR LGPL-2.1-or-later` is resolved to a permissive option and
recorded as a scoped exception in `rust/deny.toml`.

**Two gates that could not fire, and do now.** `license-checker --failOn GPL`
compares whole strings, so `GPL-3.0` never matched; it is an allow-list now.
`pip-licenses --fail-on GPL` behaves the same way without `--partial-match`, so
`GPL-2.0-or-later` passed; the flag is there. Both were found by planting the
failure and watching the gate pass — which is the only way to know.

`scripts/check-licenses.sh --self-test` plants a GPL dependency in all three
ecosystems and requires each gate to refuse it.

**Not covered, stated rather than implied:** Go and Java have no licence gate
yet. Both graphs are small and permissive today (measured above by hand), but
"small and permissive" is a measurement, not a gate — the same defect this issue
was filed about.

`NOTICE` was rewritten to distinguish vendored from linked and to record the
obligations that are real: Unicode-3.0 attribution, the LLVM exception on
`wasmtime`, PSF-2.0 on `typing_extensions`.

## Internal strategy is not published (#88)

`docs/strategy-freeze-2026-09-06.md` was removed. Its durable technical content
(the SDK shape, contract-first ordering, the governed-flow invariant) is stated by
`README.md` and `schemas/README.md`; its commercial reasoning, its assessment of
another product's defects and its competitive framing were not part of what this
repository publishes. The three `Enterprise lag:` blocks in the contract-sync
notes were replaced by the **consumer requirement** each one motivated, so the
reason a schema changed survives without the assessment.

`bash .pi/scripts/validate-no-strategy.sh` keeps it that way: commercial
vocabulary in any tracked text file, and the `strateg*` stem in prose outside
`docs/adr/`, fail the build. Two allowlist entries are recorded in the script
(`.pi/skills/` is agent-harness reference text; `.pi/scripts/` is the guard
itself), and `--self-test` plants a line in both scans.

## Decision 2 — session artefacts are not product documentation

- **`.claude/plans/` is dropped** (66 files: per-issue plans and PR bodies). They
  are session records, and one of them is a tracker dump. The durable records are
  `docs/contract-sync-*.md`, `docs/adr/` and the issue history.
  `.claude/` is now ignored.
- **`guardian-manifest.json`, `.pi/.guardian-kanban.json`,
  `.pi/.guardian-pipeline-state.json` are untracked**: agent-harness state that
  changes every session and tells a reader nothing about the product.
- **`WORKFLOW.md`, `AGENTS.md` and `.pi/agents/` are published.** This is a
  decision, not an accident: the positioning is that the process is inspectable,
  and these files say how the work is done. They also carry no private names.

## Decision 3 — cross-repository steps (recorded here, executed in `rigorix-oss`)

Once this repository is public, in the `rigorix-oss` tree:

1. `.github/workflows/ci.yml` checks this repository out with `RIGORIX_SDK_TOKEN`.
   The token becomes unnecessary: drop `token:` from the checkout, delete the
   `RIGORIX_SDK_TOKEN` secret, and let the literal repository name be the
   published name.
2. `.github/ci-affected.tsv` carries a `rigorix-sdk/**` row that can never match a
   path in that tree. Delete the row.

Neither step is executable from here; they are recorded so they are not
rediscovered.

## What a stranger needs

```bash
git clone https://github.com/arman-jalili/rigorix-sdk
cd rigorix-sdk
bash .ci/local-ci.sh          # every CI job plus the seven validators
```

No secret, no `RIGORIX_SDK_TOKEN`, no private registry. The Python binding tests
need Docker on macOS (wasmtime's JIT is killed by the sandbox); the runner says
`SKIPPED` rather than `✅` when it cannot run them, and exits 3.

## Licence and contribution policy (PUB-2)

**Apache-2.0, and only Apache-2.0.** See [the README](../README.md#licence) for the
statement, `LICENSE` for the text, and `CONTRIBUTING.md` for what a contribution
signs (DCO).

## Acceptance

| # | Criterion | Command | Result |
|---|---|---|---|
| 1 | the tip is clean | the private-name scan over tracked files (`docs/publication-readiness.md` states the rule, not the names) | 0 findings |
| 2 | the history decision is recorded | this file | accept, with the measurements |
| 3 | no secret is needed | `bash .ci/local-ci.sh` on a clone | green, no `RIGORIX_SDK_TOKEN` |
| 4 | the packaging is honest | `cargo package --list -p rigorix-schemas` | unchanged by the sweep |