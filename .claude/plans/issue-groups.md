# Issue Implementation Groups

**Generated:** 2026-09-25 (updated)
**Open issues:** 5 (#11, #18, #19, #20, #21) — #10/#12/#15 merged
**Fetched from:** `gh issue list --state open` → `.claude/plans/issues-fetched.json`

---

## Grouping Strategy

Issues are grouped by:
1. **Component** — Same module/files affected
2. **Priority** — Critical > High > Medium > Low
3. **Dependency** — Blocking relationships

---

## Triage

| # | ID | Priority | Component | Buildable now? |
|---|----|----------|-----------|----------------|
| 10 | SDK-C1 | high | SSE push spec | **DONE** — PR #13 |
| 11 | SDK-C4 | medium | `rust/rigorix-client` + `typescript/` | Yes; C1 done |
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
