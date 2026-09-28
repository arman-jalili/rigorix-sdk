# Issue Implementation Groups

**Generated:** 2026-09-25 (updated)
**Open issues:** 3 (#33, #34, #35) — #10/#12/#15/#18–#21/#11/#29/#31 merged
**Fetched from:** `gh issue list --state open` → `.claude/plans/issues-fetched.json`

---

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
