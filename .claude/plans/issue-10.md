# Implementation Plan: issue/10

**Branch:** `issue/10`
**Base:** `main`
**Issue:** #10 — SDK-C1: Specify the SSE push channel (`GET /events`) — reconnect,
Last-Event-ID, event payloads

## Classification

Spec/contract slice. Scope: **Complex** (new schema + fixtures + ADR + verifier
integrity test). No production runtime code; the only Rust change is the
protocol-only verifier's schema/integrity tests.

## Code truth (grounded — not the issue prose)

| Source | What it fixes |
|---|---|
| `rigorix-oss/server/src/events.rs` (#894) | `EventKind` = `approval_required` / `run_progress` / `policy_changed`; `ServerEvent { id: u64, event: EventKind, data: Value }`; monotonic id from 1; `Last-Event-ID` header *or* `?last_event_id=`; bounded replay ring (256); bounded broadcast (64); 15 s keep-alive; lagged receiver drops |
| `rigorix-oss/engine/src/event_system/domain/event.rs` | 24 `ExecutionEvent` variants + `event_type_name()` (the ADR-0001 doc comment "11 variants" is stale) |
| `rigorix-oss/server/src/version.rs` | already advertises `api/events.json` in the schema set |
| `schemas/envelope.json` `$id` `https://rigorix.dev/schemas/envelope-v2.json` | `$defs.executionEventRef` is the event-ref shape to **reuse** (`event_type`, `summary`, `occurred_at`, `status`, optional `correlation_id`, optional `payload`) |
| `schemas/api/catalog.json` `transport.push` | already lists the three event names; gains a schema ref |

## Drift found in the issue draft (fix from code)

- Issue hint says `run_progress` ← "PlanningStarted/…/ExecutionCancelled" and
  `policy_changed` ← `ScopeViolationRecorded` etc. — correct, but the engine
  enum has **24** variants (not the 11 in the stale doc comment): the 5
  audit/telemetry variants (`audit_envelope_delivered|queued|dropped|created`,
  `circuit_breaker_state_changed`) are host telemetry, **not** run-lifecycle
  push. The ADR mapping table classifies them explicitly as not-pushed so none
  is "silently dropped" (issue acceptance criterion 4).
- Approval: the engine has no pending-approval event; the only approval
  evidence ref is `ApprovalRecorded` (`approval_recorded`) plus
  `IntentMismatchDetected` (re-approval). Both map to `approval_required`.

## Deliverables

1. **`docs/adr/ADR-0002-sse-push-channel.md`** (Accepted) — endpoint, framing,
   reconnect + `Last-Event-ID`, replay window + gap→resync rule, heartbeat/retry,
   ordering, backpressure, per-session auth + D5 invariant, poll fallback, and
   the normative `ExecutionEvent` → SSE-name mapping table.
2. **`schemas/api/events.json`** — the three payloads as a `oneOf` discriminated
   union on the SSE `event:` name; `data` `$ref`s `envelope.json#/$defs/executionEventRef`
   (no second envelope dialect) and constrains `event_type` to the mapped engine
   names.
3. **`schemas/fixtures/events/{run-progress,approval-required,policy-changed}.json`**
   — one per event, each validates against `events.json`.
4. **`schemas/api/catalog.json`** — `transport.push.schema = "api/events.json"`;
   **`schemas/api/catalog.schema.json`** allows it.
5. **`schemas/README.md`** + **`schemas/api/README.md`** row updates.
6. **`docs/contract-sync-2026-09-06.md`** — ADR-0002 delta note.
7. **`rust/rigorix-verifier/src/lib.rs`** — register the envelope resource so
   cross-file `$ref`s resolve offline; `all_schemas_compile` covers `api/events.json`;
   new `events_fixtures_validate`; extend `catalog_integrity` to resolve
   `push.schema` and match `push.events` to the schema's variant consts.

## Implementation order

1. `schemas/api/events.json` (+ catalog + catalog.schema).
2. fixtures.
3. ADR-0002.
4. verifier tests.
5. README + contract-sync delta.

## Validation

- [ ] `cargo build` (rust/)
- [ ] `cargo test --workspace` green
- [ ] `cargo clippy --all-targets -- -D warnings`
- [ ] `cargo fmt --check`
- [ ] `cargo audit` (0 advisories)
- [ ] `events.json` compiles; all 3 fixtures validate; catalog push ref resolves

## Out of scope

- Servers (C2 OSS / C3 enterprise) implementing the spec.
- MCP Streamable HTTP; resurrecting the legacy MCP SSE endpoint (GAP-A-10).
- Changing the frozen SSE event-name set.
