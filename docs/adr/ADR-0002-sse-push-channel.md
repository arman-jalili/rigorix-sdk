# ADR-0002 — SSE push channel (`GET /events`)

- **Status:** Accepted (freeze) — 2026-09-24
- **Context:** rigorix-sdk, SDK-C1; closes ADR-0001 D8 "Open items"
- **Supersedes:** none
- **Related:** `docs/adr/ADR-0001-native-api-catalog.md` (D1 transport, D4 auth
  levels, D5 identity invariant, D8 push channel, D10 non-goals); rigorix-oss
  `server/src/events.rs` (#888 OSS-C2, #894) and
  `engine/src/event_system/domain/event.rs`

## Context

ADR-0001 D1/D8 fixed the push **transport** (`GET /events`, SSE) and the
**event-name set** (`approval_required`, `run_progress`, `policy_changed`) but
explicitly deferred reconnect / `Last-Event-ID` semantics and the exact
payloads "to the server implementations". Two servers will be built against
this surface — OSS `rigorix-server` (C2) and the enterprise Execution API (C3).
Without one spec they will diverge on the first reconnect.

The OSS reference host already landed an implementation
(`rigorix-oss/server/src/events.rs`, #894) *ahead* of this spec. This ADR
freezes what that implementation established as code truth (monotonic u64 ids,
`Last-Event-ID` header or `?last_event_id=` query, a bounded replay ring, a
bounded live broadcast, a 15 s keep-alive), states the parts the implementation
still owes (per-session scoping, `retry:` hint, gap→resync), and gives the
payload shape a machine-checkable schema (`schemas/api/events.json`).

This ADR is **spec-only**. It does not implement either server's HTTP layer.

## Decision

### D1 — Endpoint and framing

- `GET /events`, response `Content-Type: text/event-stream`, `Cache-Control:
  no-cache`, `Connection: keep-alive`.
- Frames follow the SSE grammar:
  - `id: <u64>` — the monotonic stream id (see D3).
  - `event: <name>` — exactly one of `approval_required`, `run_progress`,
    `policy_changed`.
  - `data: <json>` — one JSON object: an `envelope.json` event ref (see D2). One
    line; the server MUST NOT emit raw newlines inside the JSON.
  - a blank line terminates the frame.
- The server SHOULD send a `retry: 3000` hint before the first frame (client
  reconnect backoff in ms).
- The server sends `: keep-alive` comment frames on an interval (OSS default
  15 s) so proxies do not idle-close. Comment frames are not events and carry
  no id.

### D2 — Payloads (one envelope dialect)

The three payloads are a discriminated union on the SSE `event:` name, defined
in `schemas/api/events.json`. Each `data` **reuses**
`envelope.json` `$defs.executionEventRef` (`event_type`, `summary`,
`occurred_at`, `status`, optional `correlation_id`, optional `payload`) — there
is no second envelope dialect, and `event_type`/`status` are never redefined.

`events.json` also carries the normative `x-engine-event-mapping` table (D9).
The logical event a client reconstructs is
`{ id: u64, event: <name>, data: <envelope event ref> }`, mirroring the OSS
`ServerEvent` struct.

### D3 — Stream id and `Last-Event-ID` reconnect

- The **id** is a monotonic `u64`, assigned per server stream at publish time,
  starting at 1. Within a stream, ids are strictly increasing; there is no
  global order across runs (D5).
- On connect a client MAY send `Last-Event-ID: <id>` (header) or
  `?last_event_id=<id>` (query). The header wins if both are present.
- The server retains a **bounded replay ring** (OSS default 256 events). On
  connect it replays retained events with `id > Last-Event-ID`, then continues
  live. It subscribes to the live channel **before** reading the ring so no
  event can slip between replay and live.
- **Gap detection / no silent gap.** The server replays only what it still
  retains. If the requested id is old enough to have been evicted, the first
  replayed id is **greater than `Last-Event-ID + 1`** — a detectable
  discontinuity. On observing it, the client MUST resync via
  `rigorix.audit.read` (the signed trail is authoritative) rather than accept a
  hole. An omitted `Last-Event-ID` replays the retained window (server-defined;
  OSS replays all retained).
- A client that has caught up (no replay) keeps the live stream.

### D4 — Ordering

Within one `execution_id`, events follow engine emission order. Across runs,
no global order is promised and clients MUST NOT assume one. Ids order the
stream, not the runs.

### D5 — Backpressure

- The live fan-out per subscriber is **bounded** (OSS default 64). A slow
  consumer lags and **drops** missed events; it never stalls execution. This
  mirrors the `AuditEnvelopeDropped` philosophy: the engine's progress is not
  hostage to a slow reader.
- A lagged client reconnects with `Last-Event-ID` and replays from the ring
  (D3). If the gap is already evicted, it resyncs via `rigorix.audit.read`.
- The server MUST bound the ring and the per-subscriber buffer; unbounded
  buffering is forbidden.

### D6 — Auth and per-session scoping

- `/events` is **`session`** auth (ADR-0001 D4). An unauthenticated request is
  rejected before the stream opens with HTTP `401` (or `403` for an
  authenticated-but-insufficient session) and an `api/errors.json` error object
  as the body (`data.type` `not_authenticated` / `insufficient_scope`).
- Events are scoped to the **attested session** (ADR-0001 D5). The stream MUST
  NOT leak another session's runs; identity is session-derived and is never
  taken from the request. The server tests this by filtering the fan-out on the
  attested subject — not by trusting a client-supplied id.
- Auth is enforced when the stream is opened. A session that expires
  mid-stream terminates the connection; the client re-authenticates and
  reconnects with `Last-Event-ID`.
- Stream errors are SSE-framed/connection-level, **not** JSON-RPC. The three
  frozen event names are the only `event:` values; the server does not add a
  fourth error event name within `apiVersion` 1.x (additive-only).

### D7 — Poll fallback

A client that cannot hold a stream polls the authoritative signed trail with
`rigorix.audit.read` (`session` auth). The push channel is a latency
optimization over that surface, never the sole source of record.

### D8 — Normative engine `ExecutionEvent` → SSE name mapping

The engine emits 24 `ExecutionEvent` variants
(`engine/src/event_system/domain/event.rs`, `event_type_name()`). Every
run-relevant variant is assigned; the rest are explicitly host telemetry and
are **not pushed** (not silently dropped). This table is mirrored
machine-readably in `events.json` `x-engine-event-mapping`.

| Engine `event_type` | SSE `event:` |
|---|---|
| `planning_started` | `run_progress` |
| `planning_completed` | `run_progress` |
| `node_started` | `run_progress` |
| `node_completed` | `run_progress` |
| `node_failed` | `run_progress` |
| `node_retrying` | `run_progress` |
| `tool_executed` | `run_progress` |
| `execution_completed` | `run_progress` |
| `execution_failed` | `run_progress` |
| `execution_cancelled` | `run_progress` |
| `budget_warning` | `run_progress` |
| `approval_recorded` | `approval_required` |
| `intent_mismatch_detected` | `approval_required` |
| `sequence_rule_matched` | `policy_changed` |
| `sequence_policy_denied` | `policy_changed` |
| `sequence_policy_config_error` | `policy_changed` |
| `requirement_unmet` | `policy_changed` |
| `requirement_promoted` | `policy_changed` |
| `scope_violation_recorded` | `policy_changed` |
| `audit_envelope_delivered` | — (host telemetry, not pushed) |
| `audit_envelope_queued` | — (host telemetry, not pushed) |
| `audit_envelope_dropped` | — (host telemetry, not pushed) |
| `audit_envelope_created` | — (host telemetry, not pushed) |
| `circuit_breaker_state_changed` | — (host telemetry, not pushed) |

Notes:
- The pending-approval **pause** is server state (the run result's
  `pending_approval_steps`), not an engine event; the OSS `EventHub` is not yet
  wired to the engine bus, so today an `approval_required` push is
  server-synthesized. When wired, `approval_recorded` /
  `intent_mismatch_detected` carry the approval-lifecycle push.
- A new engine variant that is run-relevant MUST be assigned here in the same
  contract change (ADR-0001 D3 additive rule).

### D9 — Non-goals (frozen)

- Implementing either server's HTTP layer (C2 / C3 own that).
- MCP Streamable HTTP (an adapter over this surface, later).
- Resurrecting the legacy MCP SSE endpoint (GAP-A-10) — stays removed.
- Changing the frozen event-name set: additive-only within the `apiVersion`
  major; a new name is a contract change.

## Consequences

- C2 and C3 implement one push contract; the conformance corpus is
  `schemas/api/events.json` + `schemas/fixtures/events/*.json` + the
  `rigorix-verifier` integrity test.
- Clients (C4) can bind the event stream against a frozen schema and resync
  deterministically.
- `catalog.json` `transport.push.schema` points at `api/events.json`; the
  catalog integrity test resolves it.

## Open items (tracked, not blocking the freeze)

- **OSS conformance gap:** `rigorix-oss/server/src/events.rs` currently does not
  enforce per-session scoping or emit the `retry:` hint; both are C2 follow-ups
  against this spec (its module note already flags "when C1 lands, only the
  payload schema validation is added").
- **Engine wiring:** publishing live engine events from the event bus into the
  `EventHub` is a C2 follow-up.
- The enterprise Execution API (C3) adds policy-bundle version-change pushes to
  `policy_changed`.
