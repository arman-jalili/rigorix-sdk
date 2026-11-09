# Issue Implementation Groups

**Generated:** 2026-11-07 (updated)
**Open issues:** 4 (#63, #64, #65, #66)
**Fetched from:** `gh issue list --state open` → `.claude/plans/issues-fetched.json`

---

## Series: protocol clients (2026-11-07)

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 63 | Go protocol client | high | `go/client` | `issue/63` | — |
| 64 | Python protocol client | high | `python/rigorix_verifier/client` | `issue/64` | — |
| 65 | Python in-process gate | high | `python/rigorix_verifier/binding` | `issue/65` | — (WASI-1 resolved 2026-11-08) |
| 66 | Go in-process gate | medium | `go/gate` | `issue/66` | — (#63 merged) |

### Groups

- **#63 + #64 — NOT batched.** Different modules and languages, no shared files.
  Batching would couple a brand-new Python package to the Go completion and make
  one CI failure block both. The grouping rule for a component batch is "same
  module"; these are `go/client` vs `python/rigorix_verifier/client`. Land
  #63 first (it already has a base), then #64.
- **#65 + #66 — ready, not batched.** The WASI-1 blocker is resolved:
  `rigorix-oss` builds `rigorix_gate_wasi.wasm` from `wasi/ci/build.sh`, and
  `node wasi/ci/run-conformance.mjs` reproduces all five vectors through
  `node:wasi` (four recorded + one recorded divergence).
  - artifact sha256: `7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c`
  - size: 1,896,910 bytes; contract/engine `1.14.2`; `gate_evaluation: true`
  - **contract correction:** the artifact imports **six** `wasi_snapshot_preview1`
    prologue functions (`random_get`, `environ_get`, `environ_sizes_get`,
    `clock_time_get`, `fd_write`, `proc_exit`), not zero. The embedder answers
    each with a constant, counts `clock_time_get` / `random_get` / `fd_write`,
    and refuses any other import at load. The binding tests assert the counters
    stay zero across the vectors.
  - #66's SDL-1 dependency is satisfied by #63 (`e11ef99`).

### Surface correction (code is truth)

The issue YAML says "the same eight methods the TS client exposes" and lists
`executeStep`. The current TS client exposes **18** typed methods, and
`executeStep` is not in the frozen catalog and is forbidden by ADR-0001 D10
(governed flows only). The plans mirror the 18 real methods; every one of the
issue's named eight is included.

---

**Open issues:** 2 (#57, #59) — #43/#44/#47/#50/#52/#54/#55 merged
**Fetched from:** `gh issue list --state open` → `.claude/plans/issues-fetched.json`

---

## Series: browser verifier (2026-11-06)

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 59 | browser entry for the verifier | high | `typescript` verifier | `issue/59` | — |

### Group: browser entry (single) — actionable

`rigorix-verifier@0.9.0` cannot be imported by a page (every entry reaches for a
Node built-in). Adds `rigorix-verifier/browser` with WebCrypto, a generated schema
corpus, a `node:` build guard, and a real-Chrome cross-entry conformance test.
Blocks rigorix-gtm #33.

---

## Series: scope_check release integrity (2026-10-30)

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 57 | scope_check every verifier + channel guard | high | release / verifier | `issue/57` | Maven GPG/pinentry; PyPI Actions billing |

### Group: scope_check release integrity (single) — partially actionable

The code fix (`aa6f563`, `8ce4223`, `00fc015`) and npm 0.8.1 are already live. This PR fixes the
stale PyPI `__version__` and narrows the channel guard to the four verifier channels, with self-test
seeds for the three-behind state. Maven (0.8.0) and PyPI (0.6.0) publishes remain blocked, so the
issue stays open until both resolve 0.8.1.

---

## Series: verifier integrity (2026-10-25)

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 54 | rejected fixtures pinned to tests | high | `rust/rigorix-verifier` tests | `feature/verifier-integrity-54-55` | — |
| 55 | exact `rigorix-schemas` pin | high | `rust/rigorix-verifier/Cargo.toml`, `rust/RELEASING.md` | same | — |

### Group: verifier integrity (component batch, 2 issues) — actionable

Both issues are the same class: a verification claim that is not mechanically
pinned. #54 pins the rejected-fixture set to the tests; #55 pins the schema
dependency so a patch cannot change acceptance under an unchanged verifier.

**Order:** #54 (test table + set equality) → #55 (manifest pin + doc correction).

---

## Series: effect-commitment contract (2026-10-24)

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 52 | effect-record artifact + verifier | critical (release-trailing) | `schemas/api/effect-record.json`, `rust/rigorix-verifier` | `issue/52` | OSS 1.11.0 tag for the 0.7.0 *release* (contract unblocked) |

### Group: effect-commitment contract (single) — actionable

**Branch:** `issue/52`
**Decisions (review-confirmed):**
1. Artifact = frozen wire `EffectRecordResponse` + sibling `settlement`
   (`ObservedOutcome` + raw readback bytes + optional resolver).
2. `levels` describes the producing deployment on two independent axes
   (`durability` l1/l2, `settlement` none/l3) — not a per-record label.

**Deliverables:** schema + 12 fixtures (5 accepted, 7 rejected), typed mirror,
`verify_effect_record` + `verify_settlement_evidence`, contract-sync note.
The 0.7.0 publish waits for OSS 1.11.0 to be tagged.

---

## Series: release-pipeline reliability (2026-10-18)

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 50 | registry smoke retry | low | `.github/workflows/publish.yml` | `issue/50` | — |

### Group: registry smoke retry (single) — actionable

**Branch:** `issue/50`
**Issue:** 1
- #50: the publish smoke's 4-minute retry budget sits inside npm's normal
  propagation window and failed a successful v0.6.0 release; it also cannot
  distinguish "not visible yet" from "visible but broken".

**Approach:** a tested helper (`.github/scripts/wait-for-registry.sh`) — 15-minute
window, retry only propagation signatures, fail fast on a real defect, and report
give-up as a distinct **propagation timeout**. The smoke job contains no publish
step, so re-running it cannot re-push. A `publish-helper` CI job guards the
classification contract.

---

## Series: envelope integrity contract (2026-10-18)

Single high-severity contract fix (schema-vs-engine drift). Not groupable: one
schema surface (`schemas/envelope.json`) + the verifier's frozen enum copy.

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 47 | envelope `historyIntegrity` | high | `schemas/envelope.json` + rust verifier enum | `issue/47` | — |

### Group: `anchored_pending` (single) — actionable

**Branch:** `issue/47`
**Issue:** 1
- #47: the frozen envelope schema rejects `history_integrity=anchored_pending`,
  which rigorix-oss now emits (anchored mode, no verified head).

**Verified facts (code is truth, 2026-10-18):**
- `rigorix-oss` `engine/src/audit/domain/envelope.rs`: `HistoryIntegrity` has
  `AnchoredPending`; `envelope_factory_impl.rs:137,359` emits it with
  `anchor_head: None`.
- `schemas/envelope.json` `$defs.historyIntegrity` allowed only two values; the
  Rust verifier's frozen `HistoryIntegrity` enum also had only two.
- Fix is additive; only `anchored` asserts anchor-authenticated evidence.

---

## Series: validator integrity + catalog projection (2026-10-13)

Two independent singles. They share no files and have no ordering dependency,
but they are **not** one PR: #43 touches only `.pi/scripts` (tooling), #44 touches
`schemas/` + the three client trees (a frozen contract). Per `AGENTS.md` rule 2,
#44 is a contract change and is **decision-gated by the issue itself** — the
surface question (`MCP tool` vs `CLI-only`) must be answered before any edit.

| # | ID | Priority | Component | Branch | Blocked by |
|---|----|----------|-----------|--------|-----------|
| 43 | SDK-VALIDATOR-MAINTENANCE | medium | `.pi/scripts/languages/rust/*` + dispatchers | `issue/43` | — (actionable now) |
| 44 | SDK-CATALOG-PROJECTION-METHOD | medium | `schemas/api/catalog.json` + rust/ts/go clients | `issue/44` | **surface decision** (issue gate) |

**Order:** #43 first (independent, no decision needed). #44 only if the surface
decision is "MCP tool"; if "CLI-only", close #44 without code.

### Group: Validator maintenance (single) — actionable

**Branch:** `issue/43`
**Issue:** 1
- #43 SDK-VALIDATOR-MAINTENANCE: `cargo test --test '*'` latent false failure +
  OSS divergence + hardcoded `C.UTF-8` locale in dispatchers

**Why not grouped:** tooling-only, single component owner (`.pi/scripts`).

**Verified facts (code is truth, 2026-10-13):**
- `.pi/scripts/languages/rust/validate-tests.sh:70` and
  `validate-integration.sh:45` still use `cargo test --test '*'`.
- No `required-features` target exists in `rust/**/Cargo.toml` today — the
  failure is latent, exactly as the issue states.
- The `C.UTF-8` literal is present in three dispatchers:
  `.pi/scripts/coverage.sh:47`, `.pi/scripts/install_coverage_tools.sh:32`,
  `.pi/scripts/ci/stage_lint.sh:33` (`[ "C.UTF-8" = "unknown" ]` /
  `case "C.UTF-8" in`) — `$LANG` was substituted by a locale value.

### Group: Catalog projection method (single) — decision-gated

**Branch:** `issue/44` (only if approved)
**Issue:** 1
- #44 SDK-CATALOG-PROJECTION-METHOD: add the authority-fact projection to the
  frozen catalog (23 → 24 methods), regenerate copies/embeddings, update clients
  + go drift test, cut a minor release

**Gate:** the issue says *"Do not implement this issue until that question is
answered"* — is an MCP tool the right surface, or is the projection CLI-only?
A "CLI-only" answer means #44 is closed, not implemented.

**Decision (2026-10-13):** proceed with the MCP/catalog method. Contract shape:
`rigorix.audit.authorityFacts` (query, `session`, tool `rigorix_audit_authority_facts`),
result is the standalone `api/authority-fact-bundle.json` (`$id` addressed;
`envelopes[]` `$ref`s the one canonical `envelope.json`). Recorded in
`docs/contract-sync-2026-10-13.md`; plan in `.claude/plans/issue-44.md`.

---

## Historical series (SDK distribution, 2026-09/10 — merged)

## Series: SDK distribution (D-1 / D-2) — 2026-09-25

**Batch:** 3 issues, dependency-ordered **#34 → #33 → #35** (one PR per issue,
`issue/{N}`, base `main`; publish steps gated on registry credentials).

| # | ID | Priority | Component | Blocked by |
|---|----|----------|-----------|-----------|
| 34 | SDK-CRATES-0.2.0 | high | `rust/` version bump + packed-crate proof + consumer bumps | → `issue/34` (in progress) |
| 33 | SDK-PUBLISH-PY-TS | medium | publish jobs + version alignment + README | → `issue/33` (in progress; base `issue/34`) |
| 35 | SDK-CLIENTS-JAVA-GO | low | `java/` + `go/` verifiers + clients | #34 (schemas publish) |

**Why one series:** all three are the D-1/D-2 distribution epic and share the
0.2.0 version. They are **not** one PR: each has distinct layers (`rust/` vs
ci/packaging vs new `java/`+`go/` trees) and distinct external risk (crates.io,
PyPI/npm). Dependency order is strict: #34 publishes `rigorix-schemas 0.2.0`
**first** (the verifier dep is exact-versioned); #33 folds its artifact versions
into the same 0.2.0; #35 consumes the published corpus.

**Non-local tail (needs credentials / other repos) — implemented, documented,
CI-gated here, then executed by the release owner:**
- `cargo publish -p rigorix-schemas` → then `-p rigorix-verifier` (crates.io token).
- PyPI Trusted Publishing / `PYPI_TOKEN`; npm `NPM_TOKEN`.
- `rigorix-oss` + `rigorix-enterprise` consumer bumps (`^0.1` does **not** match
  `0.2`) — separate-repo PRs.

**Readiness (each read against `main` @ `4efbc32`):**
- #34: buildable now — bump, `cargo package`, unpack → verify the anchored
  fixture with no env; publish + cross-repo bumps are the gated tail.
- #33: buildable now — tag-triggered job + post-publish smoke reusing
  `pack_smoke.py` / `pack-smoke.mjs`; alignment waits on #34.
- #35: buildable now — new `java/` + `go/` trees; large; every catalog method +
  every fixture.

---

## Triage

| # | ID | Priority | Component | Buildable now? |
|---|----|----------|-----------|----------------|
| 10 | SDK-C1 | high | SSE push spec | **DONE** — PR #13 |
| 11 | SDK-C4 | medium | `rust/rigorix-client` + `typescript-client/` | **In progress** — Rust PR #26; TS client `issue/11-ts` (follow-up) |
| 12 | SDK-AUDIT-A | high | envelope chain + anchor artifacts | **DONE** — PR #14 |
| 15 | SDK-C5 | medium | catalog parity (`rigorix.auth.verify`) | **DONE** — PR #16 |
| 18 | SDK-SCHEMAS-PUBLISH | high | `rust/rigorix-schemas` (new crate) + CI | **Yes** — packaging only |
| 19 | SDK-VERIFIER-PUBLISH | high | `rust/rigorix-verifier` (self-contained publish) | **Yes** — stacked on #18 (`issue/19`); package/publish gate after `rigorix-schemas` release |
| 20 | SDK-CATALOG-AUDIT | high | `schemas/api/catalog.json` (audit methods) | **In progress** — `issue/20`, stacked on #19 |
| 21 | SDK-C6 | medium | `python/` + `typescript/` verifiers | **In progress** — `issue/21`, stacked on #20 |

---

## Group: SSE push channel (single)

**Branch:** `issue/10`
**Issues:** 1
- #10 SDK-C1: Specify the SSE push channel (`GET /events`) — reconnect, Last-Event-ID, event payloads

**Why not grouped:** it is a spec/contract slice with a single component owner
(`schemas/api` + `docs/adr`); #11 depends on it, not the reverse.

**Dependency position:** first. #11's event-stream binding consumes
`schemas/api/events.json`.

---

## Group: Audit integrity (single) — unblocked 2026-09-24

**Branch:** `issue/12`
**Issue:** 1
- #12 SDK-AUDIT-A: Envelope integrity contract — chain fields + receipt /
  history-slice / compaction schemas + verifier chain support

**Previously blocked:** ADR-016 Phase A has now landed in `rigorix-oss`
(`83e904ad`, #902) — `AuditEnvelope` carries `producer_id` / `sequence` /
`prev_hash` / `history_integrity` / **`history_policy`**. Per `AGENTS.md` rule 1
the schemas mirror the engine struct field-for-field, and the verifier's frozen
copy now does too.

---

## Group: Catalog parity (single)

**Branch:** `issue/15`
**Issue:** 1
- #15 SDK-C5: Catalog parity — declare `rigorix.auth.verify` + catalog-subset
  conformance guard

**Decision:** **declare** (option a). `rigorix-enterprise` #206/#208 registers
`rigorix.auth.verify` (query / session / no MCP tool) dispatching to JWKS claim
verification (`core/src/execution_api/application/catalog.rs:74,182`). It is
distinct from `rigorix.auth.status` (local session status), so the SDK owns the
call and declares it in the closed `rigorix.*` namespace (ADR-0001 D3).

---

## Group: Schemas publish (single)

**Branch:** `issue/18`
**Issue:** 1
- #18 SDK-SCHEMAS-PUBLISH: publish `rigorix-schemas` — the canonical contracts
  as a consumable crate

**Approach:** new build-time-embedding crate (issue option B). `schemas/` at the
repo root stays canonical; `rust/rigorix-schemas/schemas` is a symlink that
`cargo package` dereferences so the published crate is self-contained.
Unblocks **#19** (publish `rigorix-verifier`) and **#21** (Python/TS verifiers,
which consume the same corpus).

---

## Group: Verifier publish (single, stacked)

**Branch:** `issue/19` (base `issue/18`)
**Issue:** 1
- #19 SDK-VERIFIER-PUBLISH: publish `rigorix-verifier` (self-contained)

**Approach:** depend on `rigorix-schemas` and resolve contracts
`RIGORIX_SDK_SCHEMAS` → embedded → error (no repo path); publish metadata +
README + self-containment CI. The actual `cargo package`/`publish` gate
activates once `rigorix-schemas` is on crates.io (the issue's prerequisite).

---

## Group: Catalog audit methods (single, stacked)

**Branch:** `issue/20` (base `issue/19`)
**Issue:** 1
- #20 SDK-CATALOG-AUDIT: declare `rigorix.audit.head` / `.history` / `.overdue`

**Code truth:** rigorix-enterprise PR #210 (ADR-016 Phase B ledger).
`audit.history` reuses the frozen `api/history-slice.json`; the closed-namespace
subset test now covers the enterprise 13-method set.

---

## Group: Multi-language verifiers (single, stacked)

**Branch:** `issue/21` (base `issue/20`)
**Issue:** 1
- #21 SDK-C6: Python + TypeScript verifiers (Strategy A parity)

**Approach:** independent re-implementations, byte-exact against the committed
engine fixtures (canonical field order + sorted maps + lossless numbers).
Python (pytest) + TypeScript (`node --test`) CI jobs added.

---

## Group: Typed clients (split, stacked)

**Branch:** `issue/11` (base `issue/21`)
**Issue:** 1
- #11 SDK-C4: typed SDK clients — **Rust client now**, TypeScript follow-up

**Approach:** protocol-only `rigorix-client` (framing, transport seam, error
taxonomy, catalog binding + drift test, no engine dep, governed flows only).
- `issue/11` → Rust client (PR #26, base `issue/21`).
- `issue/11-ts` → TypeScript client in `typescript-client/` (base `issue/11`;
  `typescript/` is the #21 verifier package).

---

## Group: ADR-016 Phase C contract (single)

**Branch:** `issue/31`
**Issue:** 1
- #31 SDK-CATALOG-ANCHOR-HEAD: declare envelope `anchor_head` (ADR-016 Phase C)
  in `envelope.json` + all three verifiers at the exact engine position

**Approach:** additive `anchor_head` in `schemas/envelope.json` after
`history_policy` / before `approval_events`; frozen struct field in the Rust
verifier; skip-none set in Python/TS; an engine-produced anchored fixture; and
focused regression tests in all three. Contract follows rigorix-oss
`issue/899` (PR #908, code is truth).

---

## Group: ADR-017 consequence gating (single, contract-first)

**Branch:** `issue/39`
**Issue:** 1
- #39 freeze precondition config + envelope `precondition_findings` (ADR-017)

**Approach:** contract-first per D-011/D-012 (the engine has no ADR-017 code).
`policy.json` gains `preconditions[]` + `gating` + `require_companion_step`;
`envelope.json` gains additive `precondition_findings[]` (after
`requirement_findings`, before `decision_context_ref`); `errors.json` gains the
non-retryable denial taxonomy. A contract-first signed fixture is verified
byte-exact in all five verifiers. `catalog.json` unchanged (23 methods).

---

## Backlog (deferred, not blocked)

**Issue:** #11 SDK-C4 — Typed SDK clients (Rust + TypeScript)

**Defer reason:** it consumes C1 (`events.json`) for push-stream parity and is
substantially larger (new Rust crate + TS package + two CI jobs). C1 is now
merged (PR #13), so it is ready to start when scheduled.

---

## Deterministic gate (every batch)

```bash
cd rust
cargo build
cargo test --workspace
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo audit
```

---

# Round 2 — artifact trust (issues #69, #72, #73, #74)

Fetched 2026-11-08: four issues, one component family, **shared files**
(`.ci/local-ci.sh`, `go/gate/`, both `PROVENANCE.md`, both READMEs).

| Batch | Issues | Branch | Note |
|---|---|---|---|
| A | #74, #72, #73 | `feature/artifact-trust-72-74` | one artifact, one fact; both languages check at load; local-ci stops calling a skipped suite green |
| B | #69 | `issue/69` | runtime pins + advisory scanning; needs a Go-toolchain decision (see below) |

**Why A is a batch and B is not:** A's issues edit the same files — #74 creates the
guard, #72 makes both loaders enforce the digest that guard pins, #73 makes the
local runner honest about the suite that proves both. B changes dependency policy
and needs a toolchain-floor decision, so it cannot block A.

**Correction (code is truth, AGENTS.md §1).** #72 states "Python refuses a digest
mismatch at load". It does not: `loader.py` validates only the import/export
sets, and the digest is checked by `binding_test.py:184`. Neither language checks
at load today. Batch A therefore adds the load-time check to **both** — that is
what criterion 4 ("both READMEs state a load-time check") requires.

**Blocked-by-nobody note for #74:** re-vendoring is blocked on an OSS release, and
stays out of scope; the provenance records obtainability instead.
