# Publication readiness (PUB-1)

What had to be true before this repository could be public, what was decided, and
what a stranger can rely on. The assessment lives here so the decision is not in
a chat log.

## Assessment

| question | answer | evidence |
|---|---|---|
| are the artefacts already public? | **yes** | `rigorix-schemas` and `rigorix-verifier` on crates.io; `rigorix-verifier` on npm, PyPI, Maven Central and the Go module proxy — the version is stated once, below |

<!-- published: crates=0.10.0 pypi=0.10.0 npm=0.10.0 maven=0.10.0 go=0.10.0 -->
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

**Both reasons are now recorded, because there were two.** For `ci.yml` it was the
entitlement block (spending limit / billing) — Actions answered `steps: 0` in two
seconds, which is not a test result. For `audit.yml` there was a second reason on top
of it: the file did not parse, so even a funded run could not have loaded it.

```
$ python3 - <<'PY'
import subprocess, yaml
for rev in ('9fc7141','738cf93','3a91849','0d33a58','634277f','54b4bcd'):
    s = subprocess.run(['git','show',f'{rev}:.github/workflows/audit.yml'],
                       capture_output=True, text=True).stdout
    try: yaml.safe_load(s); print(rev, 'parses')
    except Exception: print(rev, 'does not parse')
PY
9fc7141 does not parse      # the secret scan (#87) and licence gate (#86) were wired here
738cf93 does not parse
3a91849 does not parse
0d33a58 does not parse
634277f does not parse
54b4bcd parses
```

The cause was `run: "$(cmd)" args` — a quoted scalar followed by junk, added with the
govulncheck step. Four steps were unloadable for five merges, including the secret
scan and the licence gate. An incomplete reason is how a dead workflow survives, so
both are stated. `scripts/check-workflows.sh` is what prevents a recurrence: it parses
every workflow file, refuses the exact unloadable shape by name, and runs in `ci.yml`
and in `local-ci`.

**The block is gone.** The repository became public on 2026-11-11, which removed the
entitlement block, and both workflows now execute:

| workflow | run | result |
|---|---|---|
| `Audit` | `main` @ `f4dbf8f` | **success** — all six jobs, including `--verify-upstream` (the vendored copy equals the release asset) |
| `CI` | `main` @ `3b4fa85` | **success** — all seven jobs |
| `Audit` | `main` @ `3b4fa85` | **success** — the govulncheck policy's first execution anywhere |

The first funded run found two defects the local runner could not see, both now fixed:
three repo-root steps inherited `working-directory: rust` (`exit 127`), and a
SHA-pinned `dtolnay/rust-toolchain` lost the ref that named its toolchain
(`'toolchain' is a required input`).

So:

- **A green local run and an unexecuted pipeline are not the same claim.** Where
  this repository says a change is validated, the evidence is
  `bash .ci/local-ci.sh`, which mirrors all seven CI jobs plus the validators and
  prints the number of steps it executed. The verdict line is the record; the
  step count is never typed by hand.
- **The first thing to read when billing clears is the `audit` workflow.** Its
  seeds (`pip-audit` on a planted pin, `govulncheck` on a planted vulnerable
  module, `check-pins.py` on a planted range) have run in `local-ci`, not in
  Actions; a `pip-audit --strict` finding there is a real finding, not a flake.
- `govulncheck` applies a policy, not just a tool (#112), because a floor cannot chase
  an advisory published yesterday. A finding whose fix is **inside the declared
  minor** (or is a module version) is actionable: the step fails and names the version
  to put in `go/go.mod`. A finding fixed only in a **later minor** is reported with
  the version it would need and does not fail — raising a language minor is a
  decision, not a patch. Both numbers are printed either way, an unparseable failure
  fails closed, and the Monday run carries the stale-floor watch
  (`python3 scripts/govulncheck.py --check-floor`), which reports and opens nothing.
  `scripts/govulncheck.py` owns the step for `audit.yml` and `local-ci`, so the two
  cannot drift.
- The floor names a **patch**: `go 1.26.11` in `go/go.mod`. It previously said `go 1.26`, which is a minimum
  language version — it admitted 1.26.3, whose standard library carries 17
  advisories, so the gate failed on a host the tree called in-policy (`#98`). CI
  resolves the floor with `go-version-file` + `check-latest`; both CI and
  `local-ci` print `go version` before scanning, and `scripts/check-pins.py`
  refuses a floor without a patch component. Advisories the code does not call are
  printed (`-scan=module`) rather than swallowed, so a change in either number is
  visible.
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

`scripts/check-agreement.sh` fails when a tracked Markdown file states a
contribution agreement other than the one `docs/CLA.md` declares — the canonical
name is read from that document, not written into the script, so the guard follows
the agreement. Ten lines in `CONTRIBUTING.md`, `docs/CLA.md` and this document are
allow-listed with a reason each: they exist to name what was replaced.

`scripts/check-spdx.sh` checks 44 files and `--self-test` proves it refuses a file
with the header removed. The set is fixed in the script rather than discovered: a
guard that infers its own subject can shrink with a refactor and still pass.

## Five channels, and a release that leaves no document false (#119, #120, #121)

The 0.10.0 run published to four coordinates and the gate never asked about the fifth.
Three things were wrong with the *gate's* idea of the release, and all three are now
measured rather than assumed.

### The channel set is five (#120)

`ALL_CHANNELS="crates pypi npm maven go"`, one definition, both loops and `--channels`
derived from it — so a sixth channel cannot be added to one and forgotten in the other.
Go is read from the proxy's own metadata like every other channel:

```
✅ go serves 0.10.0 — gate/ present, wasm ab77bb82…
✅ published: crates,pypi,npm,maven,go serve(s) 0.10.0
```

The `gate/` count and the wasm digest come from the **zip the proxy serves**, and the
expected digest is read from `go/gate/testdata/PROVENANCE.md` — one copy of the fact,
not a second literal in the gate.

Two asymmetries are stated instead of hidden:

* **Preflight does not ask Go**, because `go/v<version>` is served the moment the tag
  is pushed: the question "is it unpublished" has no answer there. It prints
  `unpublished on crates, pypi, npm, maven (go: tag-driven, verified after upload)`.
* **A Go 404 is not an answer.** The proxy returns the same 404 for "no such version"
  and "cannot fetch", so it is reported as `unverified`, naming the coordinate. A
  registry that lists versions still answers 404 as "not published here".

A run that was asked about a subset is not a green total: it names each channel it did
not verify **with the observable that would settle it**, and exits 3.

```
⚠ 4 of 5 verified; 1 not verified (crates: cargo publish)
```

### The checks can be re-run (#121)

A `workflow_dispatch` used to *skip* both post-release checks and *run* the uploads —
so the defects the first release found had to be fixed blind, and a dispatch could not
reach them anyway: the preflight ran, and at that tree it fails by design, because
0.10.0 is published.

| job | push | dispatch |
|---|---|---|
| `preflight` | runs | **skipped** — its subject is a version about to be uploaded |
| `python`, `npm-verifier`, `npm-client`, `maven` | run | **skipped** — a dispatch must never re-upload an immutable version |
| `smoke`, `verify-published` | run | **run**, on `inputs.tag` (default: the newest `v*`) |

The checks no longer inherit `needs:` from jobs a dispatch skips — a job whose needs
are skipped is skipped too, which is how they became unreachable.

### A release's definition of done contains a document (#119)

Four files said the registries served 0.9.0 while every one of them served 0.10.0.
Nothing failed, because nothing compared a document's claim with the registry's answer.

Each document now states a published version **once**, on a machine-readable line next
to the claim:

```
<!-- published: pypi=0.10.0 npm=0.10.0 maven=0.10.0 go=0.10.0 crates=0.10.0 -->
```

and the prose says "the published version". `--verify-docs` reads every marker in
every tracked `.md`, asks each channel what it serves **now** (`registry_latest`, not
`registry_has`: an old version is still served forever, so only the latest can see a
stale claim), and fails with the file, the line and both versions:

```
❌ python/README.md:58 says 0.9.0 for pypi, but pypi serves 0.10.0
```

No network is exit 3 — "not compared", never a green line. `local-ci` reports a step
that exits 3 as `⏭ NOT COMPARED` and counts it, so the gate's own verdict says so.

## The 0.10.0 release: what published, and the two defects it found (2026-11-11)

`v0.10.0` was pushed at `56ad028` after the tag fix (#116), and the workflow ran to
completion for the first time in this repository's history.

| job | result |
|---|---|
| 🔒 release identity (preflight) | **success** — `✅ tag: v0.10.0 is annotated (remote: f69d9c47 -> 56ad0283)` |
| 🐍 PyPI | **success** — `rigorix-verifier 0.10.0` |
| 🟦 npm `rigorix-verifier` | **success** — `0.10.0` |
| 🟦 npm `rigorix-client` | success (no-op: independent cadence, already at 0.8.0) |
| ☕ Maven Central | **success** — `eu.rigorix:rigorix-verifier 0.10.0` |
| 🔎 registry install + smoke | **failure** — `rigorix-client@0.10.0` does not exist (see below) |
| 🔎 every channel serves what the README documents | **failure** — `crates does not serve 0.10.0` (see below) |

**The artifact is published and verifiable.** `bash scripts/check-release.sh
--verify-published --channels pypi,npm,maven` passes, including the surface check:

```
✅ PyPI wheel: carries binding/ and the vendored artifact
```

That is `#102`'s acceptance, measured against the registry: `pip install
rigorix-verifier==0.10.0` now yields `rigorix_verifier.binding` and the vendored
`rigorix_gate_wasi.wasm`.

**Two defects the run found, and neither was the artifact:**

1. **The smoke asked for a version that will never exist.** It installed
   `rigorix-client@"$tag"`, but the client has its own cadence and its own `client-v`
   tag prefix, so on a `v0.10.0` push it published nothing and `0.10.0` is not a client
   version. It now installs the client at the version this tree declares.
2. **The verification waited for a channel no job publishes.** crates.io is published
   by hand (`cargo publish`, marker tag `rust-vX`, which triggers nothing —
   `rust/RELEASING.md`), so `--verify-published` demanding it could only ever fail.
   The job now verifies the channels the workflow publishes
   (`--channels pypi,npm,maven`), names the one it did not verify, and prints the
   manual commands for crates instead of pretending to gate them.

**Crates — since resolved:** the manual step was performed after that run, and
crates.io now serves `0.10.0` for `rigorix-schemas` and `rigorix-verifier`
(`max_stable_version`: `0.10.0`). All five channels serve 0.10.0.

**Outstanding at the time of that run, and not claimed then:** crates.io did not serve `0.10.0`.

```bash
cargo publish -p rigorix-schemas --token "$CRATES_TOKEN"
cargo publish -p rigorix-verifier --token "$CRATES_TOKEN"
bash scripts/check-release.sh --verify-published --channels crates
```

It needs the crates token, which is not available here. The three other channels have
spent `0.10.0`, so this is a remaining step of the same release, not a new version.

## The preflight's subject is the remote's advertisement (#116)

The release preflight could not pass inside the workflow that runs it, and it refused
twice on a tag that was correctly annotated:

```
✅ manifests: one version, 0.10.0
❌ tag v0.10.0 is lightweight — an annotated tag carries the tagger and the message …
```

The remote says otherwise:

```
$ git ls-remote --tags origin | grep 'v0.10.0$\|v0.10.0\^{}'
e626544d…  refs/tags/v0.10.0
ada4d6d3…  refs/tags/v0.10.0^{}
```

`actions/checkout` fetches the tag's **commit** into `refs/tags/<tag>` with `--no-tags`,
so in the runner `git cat-file -t refs/tags/v0.10.0` is `commit`. Reproduced locally
on a fresh clone — the annotation is only ever absent when the ref was created from
the commit:

```
$ git clone --no-tags --depth 1 … /tmp/shape && cd /tmp/shape
$ git fetch --no-tags origin +ada4d6d3…:refs/tags/v0.10.0
$ git cat-file -t refs/tags/v0.10.0
commit
```

Same class as #114: **the shape the workflow produces was never part of the subject**,
because `.ci/local-ci.sh` runs against the refs the author pushed.

Three changes follow, and one of them is about the message:

| | before | now |
|---|---|---|
| the verdict's source | the local ref | the **remote's advertisement**; the local object is the fallback when the remote says nothing, and the verdict names which answered |
| a ref pointing at a commit | reported as `lightweight` | reported as *a harness rewrite* when the remote holds the annotation (passes), and as that when it does not |
| an unreadable object | reported as `lightweight` | reported as *unreadable*, with the command to inspect it |

The misattribution is what cost two runs: `2>/dev/null` collapsed "the ref points at a
commit" and "the object cannot be read" into one sentence that told the releaser to
recreate a tag that was already right.

`git ls-remote --tags <remote>` with **no pattern** prints the tag object and its
peeled commit for an annotated tag, and one line for a lightweight one. With an
explicit pattern git prints no peel line at all, so the pattern form cannot answer the
question — measured, which is why the script reads the full list.

`publish.yml` also restores the ref (`git fetch --force --no-tags origin
+refs/tags/<tag>:refs/tags/<tag>`) as belt and braces for anything else reading the
local ref; the verdict does not depend on it. `scripts/check-tag-shape.sh` builds the
runner's shape offline and runs as a `local-ci` step, so the class can be seen locally:
the rewritten ref passes naming the remote, and a genuinely lightweight tag on the
fixture remote is refused as `lightweight on the remote`.

Nothing was published during either failure — no channel took a byte — so `0.10.0` is
unspent and the tag did not need to be re-pushed.

## The in-process gate is in the tree and on no channel (#102) — history, superseded

Measured against the registries at the time of that issue, not the tree. **These rows
are history**: 0.10.0 has since been published on all five channels (see the 0.10.0
section above), and the table is kept because it is the evidence the release was
designed against.

| coordinate | serves | carries the in-process gate |
|---|---|---|
| PyPI `rigorix-verifier` | 0.9.0 | **no** — wheel has 0 `binding/` entries, and its METADATA declares no `wasmtime` |
| crates.io `rigorix-verifier` | 0.9.0 | no |
| npm `rigorix-verifier` | 0.9.0 | no (and does not claim one) |
| Maven `eu.rigorix:rigorix-verifier` | 0.9.0 | no (and does not claim one) |
| Go `go/v0.9.0` | — | **no** — 0 `go/gate/` entries at the tag, 12 at `HEAD` |

The tree is bumped to **0.10.0** across the five manifests (`rust/Cargo.toml`,
`python/pyproject.toml`, `typescript/package.json`, `java/pom.xml`, and the two
intra-workspace pins), because the contents moved and a version must mean released
content — `check-release.sh` refuse-and-name is what makes that a rule rather than a
habit. `typescript-client` stays at 0.8.0: independent cadence, recorded in
`validate-channel-versions.sh`.

Bumping the tree also narrowed the dependency audit: `pip-audit --strict` refuses to
audit a package it cannot resolve on PyPI, and 0.10.0 is by design unpublished, so
`--strict` over an editable install reported *"Dependency not found on PyPI and could
not be audited: rigorix-verifier (0.10.0)"* — a fact about the release, not an
advisory. The audit's subject is now `requirements.lock` (the same graph the licence
audit reads), and `python/scripts/audit.sh` owns the step so `.ci/local-ci.sh` and
`audit.yml` cannot drift apart. It also retries **once** when pip-audit's own
resolver environment fails to bootstrap (`Failed to upgrade pip`) — a network
failure, matched by its own words — and never retries a finding.

Both READMEs now state the coordinate instead of the tree: `python/README.md` has a
`Status` table (published 0.9.0 = verifier only; tree 0.10.0 = with the gate) and the
one-line checkout install that does work today; `go/README.md` shows the two
`git ls-tree` commands that make the difference visible.

**Blocked, and stated as blocked:** publishing 0.10.0 needs a tag push and the
`Publish` workflow, and Actions minutes are exhausted. The exact steps, in order,
when billing clears:

```bash
# 1. the gate's own evidence, offline
bash .ci/local-ci.sh
# 2. the three tags, locally — a release is tagged before it is published
git tag -a v0.10.0      -m "0.10.0" && \
git tag -a go/v0.10.0   -m "0.10.0" && \
git tag -a rust-v0.10.0 -m "0.10.0"
# 3. the release identity: the tags exist and agree, nothing serves the version
bash scripts/check-release.sh --tag v0.10.0
# 4. publish (five channels; Go and the Rust crates by tag)
git push --tags
# 5. after the uploads, from the registries
bash scripts/check-release.sh --verify-published --tag v0.10.0
```

The order is the gate's, not a preference: `check-release.sh` reads
`refs/tags/$TAG`, peels it to a commit and compares the manifests **at that commit**
— so step 3 cannot pass before step 2. `#110` found the version that skipped step 2
entirely: it compared `$TAG` (defaulted to `v$version`) with `v$version`, which
cannot fail, and printed ✅ on a tree with no tag anywhere.

Measured today: step 2 exits **0** (`0.10.0` is unpublished on all four channels —
a 404 from crates.io is an answer, not a read failure, and the script treats it that
way), and step 4 exits **1**, naming `binding/` as missing, until the release lands.
The acceptance rows in `#102` that need `pip download …==0.10.0` are therefore **not
satisfied**, and are not reported as if they were.

## What each coordinate serves, read rather than assumed (#103)

`publish.yml` asserted one thing about a release: the tag matches the manifest. Two
properties a release needs were asserted nowhere, and both have failed here:

- **whether the version is new.** A second registry rejecting it, after the first has
  taken it, is discovered by hand and late.
- **whether the registry serves what the tree documents.** That is how
  `rigorix-verifier` 0.9.0 reached PyPI without `binding/` and the vendored artifact
  while every local gate was green: the pack gate builds from the tree.

`scripts/check-release.sh` has two modes — `preflight` (before the first upload: one
version across the four manifests, the tag agrees, no channel serves it yet) and
`--verify-published` (after the last upload: every channel serves it, and the PyPI
wheel carries the surface the README names). `publish.yml` runs the first in a
`preflight` job that every upload job `needs`, and the second in `verify-published`
after the uploads. Neither is `continue-on-error`.

**Measured 2026-11-11** with `bash scripts/check-release.sh --verify-published`:

| coordinate | version served | surface |
|---|---|---|
| crates.io `rigorix-verifier` | 0.9.0 | verifier only |
| PyPI `rigorix-verifier` | 0.9.0 | **no `binding/`, no vendored artifact** |
| npm `rigorix-verifier` | 0.9.0 | verifier only |
| npm `rigorix-client` | 0.8.0 | independent cadence (not part of a verifier release) |
| Maven `eu.rigorix:rigorix-verifier` | 0.9.0 | verifier only |
| Go `github.com/arman-jalili/rigorix-sdk/go` | no `go/v0.9.0` with `gate/` | tag-only coordinate |

So the tree **cannot be published as it stands**: `preflight` exits 1 naming all four
channels, and the verification exits 1 on the PyPI surface. That is the point — the
check would have caught what shipped. The release that fixes it is `#102`.

Re-measure with:

```bash
bash scripts/check-release.sh --verify-published
bash scripts/check-release.sh             # preflight: exits 0 only for a new version
```

## A pin is a digest, in the workflows too (#105)

The two wasm engines were pinned exactly and refused a range with a sentence; the
workflows were not. Every action ran a tag or a branch — `actions/checkout@v4`,
`dtolnay/rust-toolchain@stable`, and `pypa/gh-action-pypi-publish@release/v1`, the
one holding the PyPI token — and the secret scanner was pinned to
`zricethezav/gitleaks:v8.30.1`, a **tag** under a comment claiming that "a scan that
changes rules when the image moves cannot be quoted in a report a month later".

Now, in `publish.yml` first:

| what | was | now |
|---|---|---|
| actions | `@v4`, `@v5`, `@stable`, `@release/v1` | 40-hex commit + `# vX.Y.Z` on the line |
| secret scanner | `gitleaks:v8.30.1` | `gitleaks@sha256:c00b6bd0…` with `# v8.30.1` |
| run output | the image name | `▶ scanner: <digest>  (v8.30.1)` |

**Recorded exception, and the trap in it:** `dtolnay/rust-toolchain` has no version
tag that follows its `stable` branch, so the pin is the commit behind the moving `v1`
tag — `683b588c…` `# v1`. That action reads its toolchain from the **ref**
(`@stable`, `@1.85.0`), so pinning it to a commit removes the only thing that said
which toolchain to install: CI failed the step with `'toolchain' is a required
input`. The pin stays and the toolchain moves into `with: toolchain: stable`, which
is the documented form for a pinned ref. A SHA pin is not always a drop-in
substitution for a tag — the failure mode is silent until the step first runs.

`scripts/check-pins.py` gained both subjects, and they are reported in one run so a
fix cannot satisfy one and miss the other:

```
$ # planted: actions/checkout@v4  and  gitleaks:v8.30.1
❌ .github/workflows/ci.yml:24: uses: actions/checkout@v4 is not a commit SHA — a tag or branch can move; pin the 40-hex commit and put the version in a comment
❌ scripts/check-secrets.sh: GITLEAKS_IMAGE is zricethezav/gitleaks:v8.30.1 — a tag can be moved, and then the same command runs a different scanner (pin @sha256:<digest>, tag in the comment)
→ exit 1
```

A SHA without a version comment is a third defect and fails on its own wording: the
SHA says what runs, the comment says what it is. `--self-test` covers the tag, the
uncommented SHA, the tag-pinned scanner and the minor Go floor; the `local-ci` seed
plants the action and the scanner in a temporary copy and requires each to be named.

## What the artifact guard checks, and where (#104)

`scripts/check-vendored-artifact.sh` had four checks and all four were internal:
the copies agree, both `PROVENANCE.md` files agree with their copy, both source
constants agree. **All five recordings can move together to a value no download
reproduces** — which is the state `#78` found, and the guard passed on it.

| mode | what it proves | where it runs | when |
|---|---|---|---|
| default | the five recordings agree with each other | `ci.yml`, `local-ci` | every change |
| `--self-test` | four planted drifts are each rejected by file name | `audit.yml`, `local-ci` | every change |
| `--verify-upstream` | the vendored bytes are the **release asset** | `audit.yml`, `local-ci --verify-upstream` | weekly, or on request |

`--verify-upstream` reads the `**source:** owner/repo, tag vX` line from
`PROVENANCE.md`, asks the release API for that asset's `digest` and `size`, and
compares them to the vendored copy. It is the only check in this repository that
leaves the machine, so it is **not** in `ci.yml`: a pull request must not depend on
a release API. Without `gh` or network it exits **2** and says `not verified` —
never 0. `local-ci` without the flag prints
`⏭ the release asset was not compared (pass --verify-upstream …)` and does not
count a step that did not run.

Measured 2026-11-11: `--verify-upstream` → exit 0, `arman-jalili/rigorix-oss`
`v1.14.3` publishing `ab77bb82…` (1,899,431 B), equal to the vendored copy. With
all five recordings moved to `1d82f852…` the default mode still passes and
`--verify-upstream` fails naming both digests — the `#78` defect, caught.

## A workflow that could not load (#104, found in passing)

Wiring the artifact job into `audit.yml` produced a YAML error — and it predated
the change: **`audit.yml` had not parsed since the govulncheck edit**, four merges
earlier.

```yaml
run: "$(go env GOPATH)/bin/govulncheck" ./...      # a quoted scalar, then junk
```

Nothing caught it. Actions never loaded the file (billing), no local step parsed
YAML, and the text read as if the step worked. A workflow that cannot load gates
nothing, so:

- both lines are block scalars now;
- `scripts/check-workflows.sh` parses every workflow file, `--self-test` plants the
  exact unloadable shape and requires the refusal to name the file, and an empty
  workflows directory is a refusal (`no subject, not evidence`), not a pass;
- it runs in `ci.yml` and in `local-ci`.

## Tracker sweep (#89)

Issue and pull-request bodies are published with the repository, and `git grep`
cannot see them, so the tree's guard said nothing about them. Measured
2026-11-11 over **45 issues and 50 pull requests**, titles and bodies:

| class | pattern | before | after |
|---|---|---|---|
| private repository name | supplied out of band to the script | 16 items | **0** |
| commercial vocabulary | the words the guard lists | 6 items | **0** |
| internal hostname | `*.internal` | 1 item | **0** |

**16 items were edited** (14 issues, 2 pull requests), mechanically: a repository
name became "the enterprise consumer", "the web-properties repository" or "the
demo deployment" where it described provenance; a demo hostname became "the public
demo"; positioning ("Python is where the buyers' engineers are") kept its
technical reason and lost the framing. The three issues this sweep was filed for
(`#80`, `#59`, `#64`) were among them, and `#80`'s own remediation note carried
**stale measurements** — it reported 27 files and 22 commits where the tree has
23 occurrences and 4 commits, and 0 files now. Corrected in the body.

The sweep's own remediation issues quoted the names they removed (`#88`, `#89`,
`#91`); they were rewritten to describe the classes, because a document that names
what it keeps out is the leak it reports.

```bash
PRIVATE_NAMES="<name>,<name>,<name>" bash scripts/tracker-sweep.sh
```

The names are supplied out of band, for the same reason the history measurement
takes them that way: the repository records the method, not the names.

**Recorded, not re-triaged:** an earlier pass reported pull request `#71` as a hit
on `ExportArtifactSet`. It is an API name, not a keyword; the re-run does not
match it, and it needs no edit.

The rule is stated where a contributor meets it: `CONTRIBUTING.md` → "Issue and
pull-request bodies are published documents".

## Contribution gate: a CLA, and what cannot be switched on yet (#84)

**Decision: a Contributor Licence Agreement, not a DCO sign-off.** Version 1.0 is
in [`docs/CLA.md`](CLA.md); it grants the copyright licence, the patent licence,
and the right to relicense under any licence the project adopts — the last of
which a `Signed-off-by` trailer cannot grant. The DCO check is removed with it
(`scripts/check-dco.sh` deleted, the `dco` job removed, the runner step removed),
because two gates enforcing different agreements is worse than one gate.

**Measured, and it constrains the sequencing:**

```
$ gh api repos/arman-jalili/rigorix-sdk/branches/main/protection
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":403}
$ gh api repos/arman-jalili/rigorix-sdk/rulesets
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":403}
$ gh api repos/arman-jalili/rigorix-sdk --jq .private
true
```

So **no branch protection exists today, on any branch, for any check** — nothing
blocks a merge, including CI. The CLA bot can be installed while the repository
is private, but its check cannot be *required* until the repository is public
(protection is free on public repositories) or the account has Pro.

**The three operator steps, in this order, none of them executable from this
repository's code:**

1. Install the CLA bot (CLA Assistant or equivalent) on this repository and
   exercise it on a test pull request — an unsigned author must show the check
   failing.
2. Confirm the bot's check passes for a signed author.
3. In the same operation that makes the repository public, add the bot's check to
   the required list for `main`. Not after: the first external pull request can
   arrive within hours of an announcement.

Until step 3, the maintainer asks for the signature on the pull request and
records it before merging. That is a manual gate with an owner, not an absent one,
and it is the only honest statement available while the API returns 403.

**Acceptance status:** the in-repository half is done (`docs/CLA.md`,
`CONTRIBUTING.md`, the DCO removed, the checklist item replaced). The
"unsigned pull request cannot be merged" criterion is **not** satisfied yet, and
cannot be, until the bot is installed and the check is required — recorded here
rather than reported as complete.

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
statement, `LICENSE` for the text, `docs/CLA.md` for the agreement, and
`CONTRIBUTING.md` for what signing it means.

## Acceptance

| # | Criterion | Command | Result |
|---|---|---|---|
| 1 | the tip is clean | the private-name scan over tracked files (`docs/publication-readiness.md` states the rule, not the names) | 0 findings |
| 2 | the history decision is recorded | this file | accept, with the measurements |
| 3 | no secret is needed | `bash .ci/local-ci.sh` on a clone, `RIGORIX_SDK_TOKEN` unset, Docker available | `toolchain: go version go1.26.11 darwin/arm64`; `LOCAL CI: GREEN — 44 step(s) executed`; exit `0`; one step skipped-by-choice (`--verify-upstream` not requested) |
| 4 | the packaging is honest | `cargo package --list -p rigorix-schemas` | unchanged by the sweep |