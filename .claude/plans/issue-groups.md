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
| 19 | SDK-VERIFIER-PUBLISH | high | `rust/rigorix-verifier` (self-contained publish) | Depends on #18 (this batch) |
| 20 | SDK-CATALOG-AUDIT | medium | `schemas/api/catalog.json` (audit methods) | Needs the server code as truth (verify) |
| 21 | SDK-C6 | medium | `python/` + `typescript/` verifiers | Depends on #18 for a consumable corpus |

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
