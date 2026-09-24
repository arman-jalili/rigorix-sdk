# Issue Implementation Groups

**Generated:** 2026-09-24
**Total open issues:** 3 (#10, #11, #12)
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
| 10 | SDK-C1 | high | `docs/adr` + `schemas/api` + `schemas/fixtures/events` + verifier | **Yes** — self-contained spec; engine `ExecutionEvent` + OSS `server/src/events.rs` exist as code truth |
| 11 | SDK-C4 | medium | `rust/rigorix-client` + `typescript/` | Yes, but large; lists C1 as an optional dependency for event-stream parity |
| 12 | SDK-AUDIT-A | high | `schemas/envelope.json` + `schemas/api` + `schemas/fixtures/integrity` + verifier | **Yes** — ADR-016 Phase A landed (`rigorix-oss` #902, `83e904ad`): engine struct now carries the chain fields |

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

## Backlog (deferred, not blocked)

**Issue:** #11 SDK-C4 — Typed SDK clients (Rust + TypeScript)

**Defer reason:** it consumes C1 (`events.json`) for push-stream parity and is
substantially larger (new Rust crate + TS package + two CI jobs). Run after #10
merges.

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
