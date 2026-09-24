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
| 12 | SDK-AUDIT-A | high | `schemas/envelope.json` + `schemas/api` + verifier | **No — BLOCKED** |

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

## Group: Blocked (do not start)

**Issue:** #12 SDK-AUDIT-A — Envelope integrity contract

**Blocker:** ADR-016 is Accepted in rigorix-oss, but the engine
`AuditEnvelope` struct does **not** yet carry `producer_id` / `sequence` /
`prev_hash` / `history_integrity` (verified: `grep` over
`rigorix-oss/engine/src` returns zero hits). Per `AGENTS.md` rule 1
("Code is truth") the SDK schemas must mirror the engine struct; implementing
now would invent field names. The issue's own dependency list names
"OSS Phase A (engine is code truth — the struct gains the fields)". Re-triage
when that lands.

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
