# Issue Implementation Groups

**Generated:** 2026-09-24 (updated)
**Open issues:** 2 (#11, #15) — #10 (PR #13) and #12 (PR #14) are merged
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
| 10 | SDK-C1 | high | `docs/adr` + `schemas/api` + `schemas/fixtures/events` + verifier | **DONE** — PR #13 merged |
| 11 | SDK-C4 | medium | `rust/rigorix-client` + `typescript/` | Yes, but large; C1 dependency now satisfied |
| 12 | SDK-AUDIT-A | high | `schemas/envelope.json` + `schemas/api` + `schemas/fixtures/integrity` + verifier | **DONE** — PR #14 merged |
| 15 | SDK-C5 | medium | `schemas/api` + verifier (catalog parity) | **Yes** — enterprise `rigorix.auth.verify` is code truth (`rigorix-enterprise` #208) |

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
