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

**Measured on 2026-11-10, at `457c687`:**

- `git rev-list --count HEAD` → **79** commits
- commits naming a non-public sibling → **4** (`rigorix-enterprise` ×3,
  `rigorix-gtm` ×1), measured with `git log --all --grep=`
- the site repository's name → **absent from the history entirely**

The issue that requested this (*PUB-1*) cited 109 commits and 22 mentions. Those
numbers do not describe this tree; the ones above do, and they are the ones the
decision rests on. (Code is truth: the measurement wins.)

**Decision: accept the history and publish it as it is.** Rationale:

1. The mention is a *product* name, and the enterprise product is public by
   design — ADR-012, "OSS attests, enterprise authorizes". A name the product
   literature states is not a secret.
2. Scrubbing avec `git filter-repo` rewrites all 79 shas. Every dossier that
   cites a commit sha stops resolving, and the provenance links of the already
   published 0.9.0 crates dangle — a permanent cost for a name that is already
   public.
3. The conditional in the issue — *if the site repository's name must stay
   unpublished* — does not fire: that name is not in the history.

The cost of "accept" is that the names stay. That is the option this repository
takes, and this paragraph is the record the acceptance criteria ask for.

### What the tip does instead

The sweep is separate from the history: the **tip** names no private repository.
23 occurrences in 8 files were rewritten using three shapes — name the artefact
where it is published, the deployment where it is not, and keep a file path where
a repository path was doing nothing:

| shape | before | after |
|---|---|---|
| deployment | `rigorix-enterprise is a control plane` | `The enterprise product is a control plane` |
| consumer | `rigorix-enterprise/core` | `the enterprise consumer's core` |
| bare path | `rigorix-enterprise \`findings/x.md\`` | `\`findings/x.md\` in the enterprise repository` |

`go/internal/corpus/corpus_gen.go` is generated, so the fix was made in
`schemas/README.md` and the corpus regenerated — the guard is `go generate` +
`git diff --exit-code`.

## Decision 2 — session artefacts are not product documentation

- **`.claude/plans/` is dropped** (66 files: per-issue plans and PR bodies). They
  are session records, and one of them is a tracker dump. The durable records are
  `docs/contract-sync-*.md`, `docs/strategy-freeze-*.md` and the issue history.
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
| 1 | the tip is clean | `git grep -l 'rigorix-enterprise\|rigorix-gtm\|cost-demo'` (excluding `.claude/`) | 0 findings |
| 2 | the history decision is recorded | this file | accept, with the measurements |
| 3 | no secret is needed | `bash .ci/local-ci.sh` on a clone | green, no `RIGORIX_SDK_TOKEN` |
| 4 | the packaging is honest | `cargo package --list -p rigorix-schemas` | unchanged by the sweep |